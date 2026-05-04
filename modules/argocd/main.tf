# ─────────────────────────────────────────────────────────────────────────────
# DATA SOURCES — discover Stage 1 infrastructure via tags.
# This makes module.argocd self-contained: no dependency on module.vpc outputs,
# so -target=module.argocd[0] on the admin EC2 works without Stage 1 state.
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
# NOTE: AWS Load Balancer Controller (LBC) code is commented out below.
# ALB and NLB are now managed by modules/loadbalancer (pure Terraform).
# Uncomment the LBC blocks if you want to switch back to LBC-managed load
# balancers — you would also need to restore the LBC IAM policy in the
# compute module and revert nginx to LoadBalancer type with NLB annotations.
# ─────────────────────────────────────────────────────────────────────────────

# Pre-install cleanup — removes partial releases and stale resources from any
# previous failed attempt so a fresh deploy always starts from a clean state.
# NOTE: helm is not installed on the admin EC2 — kubectl is used instead.
resource "null_resource" "pre_install_cleanup" {
  provisioner "local-exec" {
    environment = {
      KUBECONFIG = "/home/ubuntu/.kube/config"
    }
    command = <<-EOT
      echo "Cleaning up stale resources from any previous attempt..."

      # Remove stale LBC resources if present from older deploys that had LBC enabled.
      # LBC is not in the current Terraform code so it will not be re-installed.
      kubectl delete deployment aws-load-balancer-controller -n kube-system --ignore-not-found 2>/dev/null || true
      kubectl delete validatingwebhookconfiguration aws-load-balancer-webhook --ignore-not-found 2>/dev/null || true

      # Delete namespaces so Helm installs always start from a clean slate.
      kubectl delete namespace ingress-nginx --ignore-not-found 2>/dev/null || true
      kubectl delete namespace argocd --ignore-not-found 2>/dev/null || true

      # Wait for namespaces to be fully terminated before Helm re-creates them.
      echo "Waiting for namespaces to terminate..."
      kubectl wait --for=delete namespace/ingress-nginx --timeout=60s 2>/dev/null || true
      kubectl wait --for=delete namespace/argocd --timeout=60s 2>/dev/null || true

      echo "Cleanup complete."
    EOT
  }

  depends_on = [var.cluster_ready]
}

# ── LBC: commented out ────────────────────────────────────────────────────────
# data "aws_vpc" "cluster" {
#   tags = {
#     "kubernetes.io/cluster/${var.cluster_name}" = "owned"
#   }
# }
#
# resource "helm_release" "aws_lbc" {
#   name             = "aws-load-balancer-controller"
#   repository       = "https://aws.github.io/eks-charts"
#   chart            = "aws-load-balancer-controller"
#   namespace        = "kube-system"
#   version          = "1.8.1"
#   timeout          = 600
#   wait             = true
#   values = [
#     yamlencode({
#       clusterName  = var.cluster_name
#       region       = var.aws_region
#       vpcId        = data.aws_vpc.cluster.id
#       serviceAccount = { create = true, name = "aws-load-balancer-controller" }
#       enableShield = false
#       enableWaf    = false
#       enableWafv2  = false
#     })
#   ]
#   depends_on = [var.cluster_ready, null_resource.pre_install_cleanup]
# }
#
# resource "null_resource" "wait_for_lbc_webhook" {
#   provisioner "local-exec" {
#     environment = { KUBECONFIG = "/home/ubuntu/.kube/config" }
#     command     = <<-EOT
#       echo "Waiting for LBC webhook endpoint to be ready..."
#       for i in $(seq 1 36); do
#         ENDPOINT=$(kubectl get endpoints aws-load-balancer-webhook-service \
#           -n kube-system -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)
#         if echo "$ENDPOINT" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
#           echo "LBC webhook is ready at $ENDPOINT"
#           exit 0
#         fi
#         echo "Not ready yet, attempt $i/36..."
#         sleep 5
#       done
#       echo "ERROR: LBC webhook endpoint never became ready"
#       exit 1
#     EOT
#   }
#   depends_on = [helm_release.aws_lbc]
# }
# ─────────────────────────────────────────────────────────────────────────────

# nginx ingress controller — single controller for all HTTP routing.
# type=LoadBalancer: CCM (AWS cloud provider) watches this service and provisions
# an internal NLB automatically in the private subnets. NodePort is assigned
# dynamically — we don't manage it. Security group allows the full 30000-32767 range.
# nginx routes based on URL path:
#   /        → app pods (ClusterIP) — defined in GitOps repo Ingress resources
#   /argocd  → argocd-server (ClusterIP)
resource "helm_release" "nginx_ingress" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.10.1"
  timeout          = 600
  wait             = true

  values = [
    yamlencode({
      controller = {
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type"     = "nlb"
            "service.beta.kubernetes.io/aws-load-balancer-internal" = "true"
            "service.beta.kubernetes.io/aws-load-balancer-subnets"  = join(",", sort(data.aws_subnets.private.ids))
          }
        }
      }
    })
  ]

  # ── NodePort approach (commented out) ──
  # values = [
  #   yamlencode({
  #     controller = {
  #       service = {
  #         type = "NodePort"
  #         nodePorts = { http = 30080, https = 30443 }
  #       }
  #     }
  #   })
  # ]

  depends_on = [var.cluster_ready, null_resource.pre_install_cleanup]
}

# ArgoCD — ClusterIP service, accessed via internal NLB → nginx → /argocd path.
# server.rootpath strips /argocd from all asset URLs so the UI loads correctly.
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.11"
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
          # server.insecure: skip TLS since nginx terminates TLS (no cert yet)
          "server.insecure" = true
          # nginx Ingress rewrites /argocd → / before proxying, so no rootpath needed.
          # ArgoCD serves at / inside the pod.
        }
      }
    })
  ]

  depends_on = [var.cluster_ready, null_resource.pre_install_cleanup]
  # ── LBC approach dependency (commented out) ──
  # depends_on = [var.cluster_ready, null_resource.pre_install_cleanup, null_resource.wait_for_lbc_webhook]
}

data "kubernetes_secret" "argocd_admin_password" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = "argocd"
  }
  depends_on = [helm_release.argocd]
}

# Applies:
#   1. ArgoCD Application CR — tells ArgoCD to sync from the GitOps repo
#   2. ArgoCD nginx Ingress  — routes /argocd → argocd-server (ClusterIP)
#
# Note: external-alb-ingress is no longer applied here.
# The external ALB is now a Terraform resource in modules/loadbalancer.
resource "null_resource" "argocd_application" {
  triggers = {
    gitops_repo_url = var.gitops_repo_url
    gitops_branch   = var.gitops_branch
    app_namespace   = var.app_namespace
    gitops_path     = var.gitops_path
  }

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = "/home/ubuntu/.kube/config"
    }

    command = <<-EOT
      echo "Waiting for ArgoCD server to be ready..."
      kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
      echo "Waiting for nginx ingress controller to be ready..."
      kubectl wait --for=condition=available --timeout=300s \
        deployment/ingress-nginx-controller -n ingress-nginx
      echo "Applying ArgoCD Application CR and nginx Ingress..."
      kubectl apply -f - <<'EOF'
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
      ---
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: argocd-server-ingress
        namespace: argocd
        annotations:
          # Rewrite /argocd → / before proxying to argocd-server.
          # Matches both /argocd and /argocd/ due to trailing slash handling.
          nginx.ingress.kubernetes.io/rewrite-target: /
          # Restrict to VPC CIDR — ArgoCD is internal-only.
          # Reachable via SSM tunnel to NLB (10.0.10.50:80) only.
          nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/16"
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
      # ── Host-based approach (nip.io) — commented out ──
      # Requires modifying /etc/hosts on laptop to resolve argocd.<nlb-ip>.nip.io
      # to 127.0.0.1 when using SSM port-forward tunnel.
      # - host: argocd.$${nlb_private_ip}.nip.io
      #   http:
      #     paths:
      #     - path: /
      #       pathType: Prefix
      #       backend:
      #         service:
      #           name: argocd-server
      #           port:
      #             number: 80
      # ── Route53 approach (commented out) ──
      # - host: argocd.internal.$${var.domain_name}
      #   http:
      #     paths:
      #     - path: /
      #       pathType: Prefix
      #       backend:
      #         service:
      #           name: argocd-server
      #           port:
      #             number: 80
      EOF
    EOT
  }

  depends_on = [helm_release.argocd, helm_release.nginx_ingress]
}

# ── LBC approach: data sources for dynamic ALB/NLB hostnames (commented out) ──
# data "kubernetes_ingress_v1" "external_alb" {
#   metadata { name = "external-alb-ingress", namespace = "ingress-nginx" }
#   depends_on = [null_resource.argocd_application]
# }
#
# data "kubernetes_service" "nginx_nlb" {
#   metadata { name = "ingress-nginx-controller", namespace = "ingress-nginx" }
#   depends_on = [helm_release.nginx_ingress]
# }

# ─────────────────────────────────────────────────────────
# EXTERNAL ALB (Stage 2 — created after CCM provisions NLB)
# CCM watches the nginx LoadBalancer service and provisions an internal NLB.
# We wait for the NLB hostname, then create the external ALB and wire it up.
# ─────────────────────────────────────────────────────────

# Block until CCM assigns a hostname to the nginx LoadBalancer service.
# CCM provisions the NLB asynchronously after the helm release completes.
resource "null_resource" "wait_for_nlb" {
  provisioner "local-exec" {
    environment = { KUBECONFIG = "/home/ubuntu/.kube/config" }
    command = <<-EOT
      echo "Waiting for CCM to provision internal NLB for nginx ingress..."
      for i in $(seq 1 60); do
        HOSTNAME=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
          -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
        if [ -n "$HOSTNAME" ]; then
          echo "NLB provisioned: $HOSTNAME"
          exit 0
        fi
        echo "Waiting for NLB hostname... ($i/60)"
        sleep 10
      done
      echo "ERROR: NLB hostname not assigned after 600s"
      exit 1
    EOT
  }
  depends_on = [helm_release.nginx_ingress]
}

# External ALB security group — accepts HTTP from internet, egresses to VPC only
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

# External ALB — internet-facing, routes all traffic via nginx ingress (ALB → NLB → nginx → pods)
resource "aws_lb" "external_alb" {
  name               = "k8s-external-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = sort(data.aws_subnets.public.ids)

  tags = { Name = "k8s-external-alb" }

  # Wait for NLB to be provisioned before creating ALB (ordering clarity — ALB
  # target registration depends on NLB IPs which are discovered after this wait)
  depends_on = [null_resource.wait_for_nlb]
}

# ALB target group — type:ip, targets the CCM-provisioned NLB's private IPs.
# IPs are registered by null_resource.register_nlb_targets below.
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

# ALB listener — forwards all HTTP traffic to NLB target group
resource "aws_lb_listener" "alb_http" {
  load_balancer_arn = aws_lb.external_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_nlb.arn
  }
}

# Block /argocd* at the internet-facing ALB — ArgoCD is VPC-internal only.
# Access ArgoCD via SSM port-forward tunnel to NLB hostname:80, not through ALB.
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

# Discover CCM NLB private IPs and register them in the ALB target group.
# CCM provisions the NLB dynamically — IPs are unknown at plan time, so we
# use AWS CLI after provisioning instead of a Terraform data source.
# Primary method: AvailabilityZones[].LoadBalancerAddresses[].PrivateIPv4Address
# Fallback: ENI description filter (ELB net/<name>/<id>)
resource "null_resource" "register_nlb_targets" {
  triggers = {
    alb_tg_arn = aws_lb_target_group.alb_nlb.arn
  }

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = "/home/ubuntu/.kube/config"
      AWS_REGION = var.aws_region
      TG_ARN     = aws_lb_target_group.alb_nlb.arn
    }
    command = <<-EOT
      echo "Discovering CCM-provisioned NLB..."
      NLB_DNS=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
      echo "NLB DNS: $NLB_DNS"

      NLB_ARN=$(aws elbv2 describe-load-balancers \
        --region "$AWS_REGION" \
        --query "LoadBalancers[?DNSName=='$NLB_DNS'].LoadBalancerArn" \
        --output text)
      echo "NLB ARN: $NLB_ARN"

      # Primary: private IPs from describe-load-balancers (works for internal NLBs)
      NLB_IPS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$NLB_ARN" \
        --region "$AWS_REGION" \
        --query "LoadBalancers[0].AvailabilityZones[*].LoadBalancerAddresses[*].PrivateIPv4Address" \
        --output text)

      if [ -z "$NLB_IPS" ]; then
        echo "Primary method returned no IPs, trying ENI fallback..."
        LB_ID=$(echo "$NLB_ARN" | awk -F'loadbalancer/' '{print $2}')
        NLB_IPS=$(aws ec2 describe-network-interfaces \
          --region "$AWS_REGION" \
          --filters "Name=description,Values=ELB $LB_ID" \
          --query "NetworkInterfaces[*].PrivateIpAddress" \
          --output text)
      fi

      echo "NLB private IPs: $NLB_IPS"
      for IP in $NLB_IPS; do
        echo "Registering $IP in ALB target group..."
        aws elbv2 register-targets \
          --region "$AWS_REGION" \
          --target-group-arn "$TG_ARN" \
          --targets Id=$IP,Port=80
      done
      echo "NLB target registration complete."
    EOT
  }

  depends_on = [aws_lb_target_group.alb_nlb, null_resource.wait_for_nlb]
}
