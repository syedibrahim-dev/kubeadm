# ─────────────────────────────────────────────────────────────────────────────
# DATA SOURCES — discover Stage 1 infrastructure via tags.
# Self-contained: no dependency on module.vpc outputs, so
# -target=module.argocd[0] on the admin EC2 works without Stage 1 state.
# ─────────────────────────────────────────────────────────────────────────────

data "aws_vpc" "cluster" {
  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "tag:kubernetes.io/role/elb"
    values = ["1"]
  }
  filter {
    name   = "tag:kubernetes.io/cluster/${var.cluster_name}"
    values = ["owned"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "tag:kubernetes.io/role/internal-elb"
    values = ["1"]
  }
  filter {
    name   = "tag:kubernetes.io/cluster/${var.cluster_name}"
    values = ["owned"]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# PRE-INSTALL CLEANUP
# Deletes stale namespaces from any previous failed attempt so Helm installs
# always start from a clean slate.
# ─────────────────────────────────────────────────────────────────────────────

resource "null_resource" "pre_install_cleanup" {
  provisioner "local-exec" {
    environment = { KUBECONFIG = "/home/ubuntu/.kube/config" }
    command     = <<-EOT
      echo "Cleaning up stale namespaces from any previous failed attempt..."
      kubectl delete namespace ingress-nginx --ignore-not-found 2>/dev/null || true
      kubectl delete namespace argocd --ignore-not-found 2>/dev/null || true
      echo "Waiting for namespaces to fully terminate..."
      kubectl wait --for=delete namespace/ingress-nginx --timeout=60s 2>/dev/null || true
      kubectl wait --for=delete namespace/argocd --timeout=60s 2>/dev/null || true
      echo "Cleanup complete."
    EOT
  }

  depends_on = [var.cluster_ready]
}

# ─────────────────────────────────────────────────────────────────────────────
# NGINX INGRESS CONTROLLER
# type=LoadBalancer: CCM watches this service and provisions an internal NLB
# in the private subnets using the pinned IPs from var.nlb_ip_az1/az2.
# Because the IPs are known at plan time, ALB target registration is pure
# Terraform — no polling null_resource or CLI discovery needed.
# ─────────────────────────────────────────────────────────────────────────────

resource "helm_release" "nginx_ingress" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = var.nginx_chart_version
  timeout          = 600
  wait             = true

  values = [
    yamlencode({
      controller = {
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type"                   = "nlb"
            "service.beta.kubernetes.io/aws-load-balancer-internal"               = "true"
            "service.beta.kubernetes.io/aws-load-balancer-subnets"                = join(",", sort(data.aws_subnets.private.ids))
            "service.beta.kubernetes.io/aws-load-balancer-private-ipv4-addresses" = "${var.nlb_ip_az1},${var.nlb_ip_az2}"
          }
        }
      }
    })
  ]

  depends_on = [var.cluster_ready, null_resource.pre_install_cleanup]
}

# ─────────────────────────────────────────────────────────────────────────────
# ARGOCD
# ClusterIP service — not internet-facing.
# Accessed via SSM port-forward tunnel → internal NLB → nginx → /argocd.
# server.rootpath=/argocd: ArgoCD sets <base href="/argocd/"> in the UI HTML
# so React Router uses /argocd as the basename and asset URLs are correctly
# prefixed — prevents the blank page caused by assets loading from /.
# ─────────────────────────────────────────────────────────────────────────────

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = var.argocd_chart_version
  timeout          = 600
  wait             = true

  values = [
    yamlencode({
      server = {
        service = {
          type = "ClusterIP"
        }
      }
      configs = {
        params = {
          "server.insecure"  = true       # nginx terminates TLS; no cert on ArgoCD pod
          "server.rootpath"  = "/argocd"  # sets <base href="/argocd/"> in UI HTML
        }
      }
    })
  ]

  depends_on = [var.cluster_ready, null_resource.pre_install_cleanup]
}

data "kubernetes_secret" "argocd_admin_password" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = "argocd"
  }
  depends_on = [helm_release.argocd]
}

# ─────────────────────────────────────────────────────────────────────────────
# ARGOCD APPLICATION CR
# Tells ArgoCD which GitOps repo/path/branch to sync from.
# kubectl_manifest replaces null_resource + local-exec: helm_release.argocd
# with wait=true already ensures the CRD and server are ready before this runs.
# ─────────────────────────────────────────────────────────────────────────────

resource "kubectl_manifest" "argocd_application" {
  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: k8s-app
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: ${var.gitops_repo_url}
        targetRevision: ${var.gitops_branch}
        path: ${var.gitops_path}
      destination:
        server: https://kubernetes.default.svc
        namespace: ${var.app_namespace}
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
  YAML

  depends_on = [helm_release.argocd]
}

# ─────────────────────────────────────────────────────────────────────────────
# ARGOCD NGINX INGRESS
# Routes /argocd → argocd-server (ClusterIP).
# No rewrite: server.rootpath=/argocd means ArgoCD handles the /argocd prefix
# itself. Rewriting to / causes 404 because ArgoCD only serves at /argocd.
# whitelist-source-range restricts to VPC CIDR — ArgoCD is internal-only.
# The external ALB also blocks /argocd* at the listener rule level (layer 1).
# ─────────────────────────────────────────────────────────────────────────────

resource "kubectl_manifest" "argocd_ingress" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: argocd-server-ingress
      namespace: argocd
      annotations:
        nginx.ingress.kubernetes.io/whitelist-source-range: "${var.vpc_cidr}"
    spec:
      ingressClassName: nginx
      rules:
        - http:
            paths:
              - path: /argocd
                pathType: Prefix
                backend:
                  service:
                    name: argocd-server
                    port:
                      number: 80
  YAML

  depends_on = [helm_release.argocd, helm_release.nginx_ingress]
}

# ─────────────────────────────────────────────────────────────────────────────
# EXTERNAL ALB
# Internet-facing entry point. Forwards to the CCM-provisioned internal NLB
# via IP targets. NLB IPs are pinned (var.nlb_ip_az1/az2) so registration is
# pure Terraform — no CLI discovery, no polling null_resource.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "alb_sg" {
  name        = "k8s-external-alb-sg"
  description = "Security group for internet-facing ALB"
  vpc_id      = data.aws_vpc.cluster.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from internet"
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.cluster.cidr_block]
    description = "Forward to internal NLB within VPC"
  }

  tags = { Name = "k8s-external-alb-sg" }
}

resource "aws_lb" "external_alb" {
  name               = "k8s-external-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = sort(data.aws_subnets.public.ids)

  tags = { Name = "k8s-external-alb" }

  depends_on = [helm_release.nginx_ingress]
}

resource "aws_lb_target_group" "alb_nlb" {
  name        = "k8s-alb-nlb-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.cluster.id
  target_type = "ip"

  health_check {
    protocol            = "HTTP"
    path                = "/"
    port                = "80"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 15
    matcher             = "200-404"
  }

  tags = { Name = "k8s-alb-nlb-tg" }
}

resource "aws_lb_listener" "alb_http" {
  load_balancer_arn = aws_lb.external_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_nlb.arn
  }
}

# Block /argocd* at the ALB — first isolation layer.
# nginx whitelist-source-range is the second layer.
resource "aws_lb_listener_rule" "block_argocd_path" {
  listener_arn = aws_lb_listener.alb_http.arn
  priority     = 1

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

  condition {
    path_pattern {
      values = ["/argocd", "/argocd/*"]
    }
  }
}

# Register the NLB's pinned private IPs as ALB targets.
# IPs are known at plan time so this is pure Terraform — no CLI needed.
# ALB health checks will show unhealthy briefly until CCM finishes provisioning
# the NLB with these IPs, then go healthy automatically.
resource "aws_lb_target_group_attachment" "nlb_ips" {
  for_each = toset([var.nlb_ip_az1, var.nlb_ip_az2])

  target_group_arn = aws_lb_target_group.alb_nlb.arn
  target_id        = each.value
  port             = 80

  depends_on = [aws_lb_target_group.alb_nlb, helm_release.nginx_ingress]
}
