terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    helm = {
      source = "hashicorp/helm"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    kubectl = {
      source = "gavinbunney/kubectl"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# NGINX INGRESS CONTROLLER
# type=LoadBalancer: CCM watches this service and provisions an internal NLB
# in the private subnets using the pinned IPs from var.nlb_ip_az1/az2.
# Because the IPs are known at plan time, ALB target registration is pure
# Terraform — no polling null_resource or CLI discovery needed.
# ─────────────────────────────────────────────────────────────────────────────

resource "helm_release" "nginx_ingress" {
  name             = var.resource_names.nginx_release
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = var.namespaces.nginx
  create_namespace = true
  version          = var.nginx_chart_version
  timeout          = var.helm_timeout_seconds
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

  depends_on = [var.cluster_ready]
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
  name             = var.resource_names.argocd_release
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = var.namespaces.argocd
  create_namespace = true
  version          = var.argocd_chart_version
  timeout          = var.helm_timeout_seconds
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
          "server.insecure" = true                 # nginx terminates TLS; no cert on ArgoCD pod
          "server.rootpath" = var.argocd_root_path # sets <base href="/argocd/"> in UI HTML
        }
      }
    })
  ]

  depends_on = [var.cluster_ready]
}

# ─────────────────────────────────────────────────────────────────────────────
# EXTERNAL ALB
# Internet-facing entry point. Forwards to the CCM-provisioned internal NLB
# via IP targets. NLB IPs are pinned (var.nlb_ip_az1/az2) so registration is
# pure Terraform — no CLI discovery, no polling null_resource.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "alb_sg" {
  name        = var.resource_names.alb_security_group
  description = "Security group for internet-facing ALB"
  vpc_id      = data.aws_vpc.cluster.id

  ingress {
    from_port   = var.alb_settings.listener_port
    to_port     = var.alb_settings.listener_port
    protocol    = "tcp"
    cidr_blocks = var.alb_settings.ingress_cidrs
    description = "Allow ALB listener traffic from internet"
  }

  egress {
    from_port   = var.alb_settings.target_port
    to_port     = var.alb_settings.target_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.cluster.cidr_block]
    description = "Forward to internal NLB within VPC"
  }

  tags = { Name = var.resource_names.alb_security_group }
}

resource "aws_lb" "external_alb" {
  name               = var.resource_names.external_alb
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = sort(data.aws_subnets.public.ids)

  tags = { Name = var.resource_names.external_alb }

  depends_on = [helm_release.nginx_ingress]
}

resource "aws_lb_target_group" "alb_nlb" {
  name        = var.resource_names.alb_target_group
  port        = var.alb_settings.target_port
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.cluster.id
  target_type = "ip"

  health_check {
    protocol            = "HTTP"
    path                = var.alb_settings.health_check_path
    port                = tostring(var.alb_settings.target_port)
    healthy_threshold   = var.alb_settings.healthy_threshold
    unhealthy_threshold = var.alb_settings.unhealthy_threshold
    interval            = var.alb_settings.health_check_interval
    matcher             = var.alb_settings.health_check_matcher
  }

  tags = { Name = var.resource_names.alb_target_group }
}

resource "aws_lb_listener" "alb_http" {
  load_balancer_arn = aws_lb.external_alb.arn
  port              = var.alb_settings.listener_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_nlb.arn
  }
}

# Block /argocd* at the ALB — first isolation layer.
# nginx whitelist-source-range is the second layer (manifests.tf).
resource "aws_lb_listener_rule" "block_argocd_path" {
  listener_arn = aws_lb_listener.alb_http.arn
  priority     = var.alb_settings.listener_rule_priority

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
      values = [var.argocd_root_path, "${var.argocd_root_path}/*"]
    }
  }
}

# Register the NLB's pinned private IPs as ALB targets.
# IPs are known at plan time so this is pure Terraform — no CLI needed.
resource "aws_lb_target_group_attachment" "nlb_ips" {
  for_each = toset([var.nlb_ip_az1, var.nlb_ip_az2])

  target_group_arn = aws_lb_target_group.alb_nlb.arn
  target_id        = each.value
  port             = var.alb_settings.target_port

  depends_on = [aws_lb_target_group.alb_nlb, helm_release.nginx_ingress]
}
