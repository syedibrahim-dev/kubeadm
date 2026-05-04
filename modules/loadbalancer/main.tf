# Loadbalancer Module
#
# ── ARCHITECTURE NOTE ────────────────────────────────────────────────────────
# All load balancer resources have moved to modules/argocd (Stage 2).
# Reason: the internal NLB is now CCM-provisioned (nginx service type=LoadBalancer)
# and its private IPs are unknown at plan time (Stage 1). The external ALB and
# its target registration (pointing at NLB IPs) must happen AFTER CCM provisions
# the NLB — which only happens after nginx is deployed (Stage 2).
#
# CCM flow:
#   nginx helm release (type=LoadBalancer) → CCM provisions internal NLB
#   → null_resource.wait_for_nlb → ALB created → null_resource.register_nlb_targets
#
# All resources below are intentionally commented out.
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────
# ROUTE53 — commented out (requires registered domain)
# ─────────────────────────────────────────────────────────

# resource "aws_route53_zone" "public" { ... }
# resource "aws_route53_record" "app" { ... }
# resource "aws_route53_record" "api" { ... }
# resource "aws_route53_zone" "internal" { ... }
# resource "aws_route53_record" "argocd" { ... }

# ─────────────────────────────────────────────────────────
# SECURITY GROUP — moved to modules/argocd
# ─────────────────────────────────────────────────────────

# resource "aws_security_group" "alb_sg" { ... }

# ─────────────────────────────────────────────────────────
# INTERNAL NLB — now CCM-provisioned (not Terraform-managed)
# CCM creates this when nginx service type=LoadBalancer is applied.
# ─────────────────────────────────────────────────────────

# resource "aws_lb" "internal_nlb" { ... }
# resource "aws_lb_target_group" "nlb_nginx" { ... }
# resource "aws_lb_target_group_attachment" "nlb_worker" { ... }
# resource "aws_lb_listener" "nlb_http" { ... }

# ─────────────────────────────────────────────────────────
# EXTERNAL ALB — moved to modules/argocd
# ─────────────────────────────────────────────────────────

# resource "aws_lb" "external_alb" { ... }
# resource "aws_lb_target_group" "alb_nlb" { ... }
# resource "aws_lb_target_group_attachment" "alb_nlb_az1" { ... }
# resource "aws_lb_target_group_attachment" "alb_nlb_az2" { ... }
# resource "aws_lb_listener" "alb_http" { ... }
# resource "aws_lb_listener_rule" "block_argocd_path" { ... }
