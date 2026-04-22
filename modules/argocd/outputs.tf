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

output "internal_alb_hostname" {
  description = "Internal ALB DNS — VPC-only, serves ArgoCD"
  value       = try(data.kubernetes_ingress_v1.argocd.status[0].load_balancer[0].ingress[0].hostname, "ALB not ready yet")
}

output "argocd_admin_password" {
  description = "ArgoCD initial admin password"
  value       = try(data.kubernetes_secret.argocd_admin_password.data["password"], "Secret not found")
  sensitive   = true
}
