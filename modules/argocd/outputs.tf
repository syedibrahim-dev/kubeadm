output "argocd_namespace" {
  description = "Namespace where ArgoCD is deployed"
  value       = helm_release.argocd.namespace
}

output "argocd_release_name" {
  description = "Helm release name for ArgoCD"
  value       = helm_release.argocd.name
}

output "argocd_application_name" {
  description = "Name of the ArgoCD application managing the k8s-app"
  value       = "k8s-app"
}

output "argocd_admin_password" {
  description = "ArgoCD initial admin password"
  value       = try(data.kubernetes_secret.argocd_admin_password.data["password"], "Secret not found")
  sensitive   = true
}

# ── LBC approach: ALB/NLB hostnames from K8s data sources (commented out) ──
# output "external_alb_hostname" {
#   description = "External ALB DNS — internet-facing, routes all traffic via nginx ingress"
#   value       = try(data.kubernetes_ingress_v1.external_alb.status[0].load_balancer[0].ingress[0].hostname, "ALB not ready yet")
# }
#
# output "internal_nlb_hostname" {
#   description = "Internal NLB DNS — VPC-only, access ArgoCD at <hostname>/argocd via SSM tunnel"
#   value       = try(data.kubernetes_service.nginx_nlb.status[0].load_balancer[0].ingress[0].hostname, "NLB not ready yet")
# }
