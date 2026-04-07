# NLB Module - Public-facing Network Load Balancer
# Exposes ingress-nginx (port 80) and ArgoCD (port 8080) without port-forwarding.
# Sits in the public subnet; targets worker nodes in the private subnet.

resource "aws_lb" "k8s_nlb" {
  name               = "k8s-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [var.public_subnet_id]

  tags = {
    Name = "k8s-nlb"
  }
}

# ── App target group: ingress-nginx fixed NodePort 30080 ──────────────────────
resource "aws_lb_target_group" "app" {
  name     = "k8s-app-tg"
  port     = 30080
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    protocol            = "TCP"
    port                = 30080
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.k8s_nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_target_group_attachment" "app_workers" {
  count            = length(var.worker_instance_ids)
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = var.worker_instance_ids[count.index]
  port             = 30080
}

# ── ArgoCD target group: ArgoCD server fixed NodePort 30082 ───────────────────
resource "aws_lb_target_group" "argocd" {
  name     = "k8s-argocd-tg"
  port     = 30082
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    protocol            = "TCP"
    port                = 30082
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }
}

resource "aws_lb_listener" "argocd" {
  load_balancer_arn = aws_lb.k8s_nlb.arn
  port              = 8080
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.argocd.arn
  }
}

resource "aws_lb_target_group_attachment" "argocd_workers" {
  count            = length(var.worker_instance_ids)
  target_group_arn = aws_lb_target_group.argocd.arn
  target_id        = var.worker_instance_ids[count.index]
  port             = 30082
}
