output "external_alb_dns" {
  description = "External ALB DNS — use directly in browser or as nip.io base"
  value       = aws_lb.external_alb.dns_name
}

output "internal_nlb_dns" {
  description = "Internal NLB DNS — VPC-only, used for SSM tunnel to ArgoCD"
  value       = aws_lb.internal_nlb.dns_name
}

output "nlb_private_ip_az1" {
  description = "Fixed private IP of NLB in AZ1 — forms argocd.<ip>.nip.io hostname"
  value       = var.nlb_private_ip_az1
}

output "argocd_nip_host" {
  description = "nip.io hostname for ArgoCD — resolves to NLB private IP from anywhere in VPC"
  value       = "argocd.${var.nlb_private_ip_az1}.nip.io"
}

output "alb_sg_id" {
  description = "External ALB security group ID"
  value       = aws_security_group.alb_sg.id
}

# ── Route53 approach outputs (commented out) ─────────────────────────────────
# output "app_url" {
#   value = "http://app.${var.domain_name}"
# }
# output "api_url" {
#   value = "http://api.${var.domain_name}"
# }
# output "argocd_internal_url" {
#   value = "http://argocd.internal.${var.domain_name}"
# }
# output "public_zone_nameservers" {
#   description = "Point your domain registrar to these nameservers"
#   value       = aws_route53_zone.public.name_servers
# }
# ─────────────────────────────────────────────────────────────────────────────
