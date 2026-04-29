# Loadbalancer Module
# Owns all AWS load balancer resources — terraform destroy cleans everything up.
# No AWS Load Balancer Controller (LBC) involved — pure Terraform.
#
# Active approach: nip.io (free, no domain registration needed)
#   - App/API: path-based routing via nginx, accessed at ALB DNS directly
#   - ArgoCD: host-based via argocd.<nlb-private-ip>.nip.io (resolves to NLB private IP)
#
# Commented approach: Route53 + real domain
#   - Uncomment Route53 blocks and host-based ALB listener rules below
#   - Set domain_name in tfvars to your registered domain

# ─────────────────────────────────────────────────────────
# ROUTE53 — commented out (requires registered domain + $0.50/month per zone)
# Uncomment this entire section when using a real domain.
# ─────────────────────────────────────────────────────────

# resource "aws_route53_zone" "public" {
#   name = var.domain_name
#   tags = { Name = "k8s-public-zone" }
# }
#
# resource "aws_route53_record" "app" {
#   zone_id = aws_route53_zone.public.zone_id
#   name    = "app.${var.domain_name}"
#   type    = "A"
#   alias {
#     name                   = aws_lb.external_alb.dns_name
#     zone_id                = aws_lb.external_alb.zone_id
#     evaluate_target_health = true
#   }
# }
#
# resource "aws_route53_record" "api" {
#   zone_id = aws_route53_zone.public.zone_id
#   name    = "api.${var.domain_name}"
#   type    = "A"
#   alias {
#     name                   = aws_lb.external_alb.dns_name
#     zone_id                = aws_lb.external_alb.zone_id
#     evaluate_target_health = true
#   }
# }
#
# resource "aws_route53_zone" "internal" {
#   name = "internal.${var.domain_name}"
#   vpc { vpc_id = var.vpc_id }
#   tags = { Name = "k8s-internal-zone" }
# }
#
# resource "aws_route53_record" "argocd" {
#   zone_id = aws_route53_zone.internal.zone_id
#   name    = "argocd.internal.${var.domain_name}"
#   type    = "A"
#   alias {
#     name                   = aws_lb.internal_nlb.dns_name
#     zone_id                = aws_lb.internal_nlb.zone_id
#     evaluate_target_health = true
#   }
# }

# ─────────────────────────────────────────────────────────
# SECURITY GROUP — External ALB
# ─────────────────────────────────────────────────────────

resource "aws_security_group" "alb_sg" {
  name        = "k8s-external-alb-sg"
  description = "Security group for internet-facing ALB"
  vpc_id      = var.vpc_id

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
    cidr_blocks = [var.vpc_cidr]
    description = "Forward to internal NLB within VPC"
  }

  tags = {
    Name = "k8s-external-alb-sg"
  }
}

# ─────────────────────────────────────────────────────────
# INTERNAL NLB
# Fixed private IPs per AZ — stable, known at apply time.
# Used to form nip.io hostname: argocd.<nlb-ip>.nip.io
# ─────────────────────────────────────────────────────────

resource "aws_lb" "internal_nlb" {
  name               = "k8s-internal-nlb"
  internal           = true
  load_balancer_type = "network"

  subnet_mapping {
    subnet_id            = var.private_subnet_id
    private_ipv4_address = var.nlb_private_ip_az1
  }

  subnet_mapping {
    subnet_id            = var.private_subnet_2_id
    private_ipv4_address = var.nlb_private_ip_az2
  }

  tags = {
    Name = "k8s-internal-nlb"
  }
}

# NLB target group — worker EC2 instances on NodePort 30080 (nginx)
resource "aws_lb_target_group" "nlb_nginx" {
  name        = "k8s-nlb-nginx-tg"
  port        = 30080
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = "30080"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = {
    Name = "k8s-nlb-nginx-tg"
  }
}

# Register each worker node in the NLB target group
resource "aws_lb_target_group_attachment" "nlb_worker" {
  count            = var.worker_count
  target_group_arn = aws_lb_target_group.nlb_nginx.arn
  target_id        = var.worker_instance_ids[count.index]
  port             = 30080
}

# NLB listener — TCP :80 → nginx NodePort target group
resource "aws_lb_listener" "nlb_http" {
  load_balancer_arn = aws_lb.internal_nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb_nginx.arn
  }
}

# ─────────────────────────────────────────────────────────
# EXTERNAL ALB
# ─────────────────────────────────────────────────────────

resource "aws_lb" "external_alb" {
  name               = "k8s-external-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [var.public_subnet_id, var.public_subnet_2_id]

  tags = {
    Name = "k8s-external-alb"
  }
}

# ALB target group — NLB private IPs (type: ip)
# ALB forwards HTTP to NLB; NLB forwards TCP to nginx NodePort 30080
resource "aws_lb_target_group" "alb_nlb" {
  name        = "k8s-alb-nlb-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
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

  tags = {
    Name = "k8s-alb-nlb-tg"
  }
}

# Register both NLB fixed private IPs in the ALB target group (one per AZ).
# depends_on = [aws_lb.internal_nlb] is required: ALB IP target groups require
# the IP to be an active ENI. The NLB claims its fixed private IPs as ENIs only
# after it finishes provisioning. Without this dependency, the attachment runs in
# parallel with NLB creation and AWS rejects the IP as "not within a VPC subnet".
resource "aws_lb_target_group_attachment" "alb_nlb_az1" {
  target_group_arn = aws_lb_target_group.alb_nlb.arn
  target_id        = var.nlb_private_ip_az1
  port             = 80
  depends_on       = [aws_lb.internal_nlb]
}

resource "aws_lb_target_group_attachment" "alb_nlb_az2" {
  target_group_arn = aws_lb_target_group.alb_nlb.arn
  target_id        = var.nlb_private_ip_az2
  port             = 80
  depends_on       = [aws_lb.internal_nlb]
}

# ALB listener — nip.io approach (active)
# Default action: forward all traffic to NLB.
# nginx handles all routing internally (path-based for apps, host-based for ArgoCD).
# ArgoCD isolation is maintained by:
#   1. NLB is internal — internet cannot reach it directly
#   2. The block_argocd rule below — any request with argocd.* Host header is rejected
resource "aws_lb_listener" "alb_http" {
  load_balancer_arn = aws_lb.external_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_nlb.arn
  }
}

# Block any request to ALB with an argocd.* Host header.
# Even though the NLB is internal (internet unreachable), this adds an explicit
# AWS-level guard — the ALB rejects it before it ever touches the NLB or nginx.
resource "aws_lb_listener_rule" "block_argocd" {
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
    host_header {
      values = ["argocd.*"]
    }
  }
}

# ── Route53 approach: host-based ALB listener rules (commented out) ──────────
# Uncomment when Route53 is enabled — these replace the default-forward approach
# with explicit host-allow rules (everything else gets 404 by default).
#
# Note: also change the alb_http listener default_action to fixed-response 404
# when using this approach.
#
# resource "aws_lb_listener_rule" "app" {
#   listener_arn = aws_lb_listener.alb_http.arn
#   priority     = 10
#   action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.alb_nlb.arn
#   }
#   condition {
#     host_header { values = ["app.${var.domain_name}"] }
#   }
# }
#
# resource "aws_lb_listener_rule" "api" {
#   listener_arn = aws_lb_listener.alb_http.arn
#   priority     = 20
#   action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.alb_nlb.arn
#   }
#   condition {
#     host_header { values = ["api.${var.domain_name}"] }
#   }
# }
# ─────────────────────────────────────────────────────────────────────────────
