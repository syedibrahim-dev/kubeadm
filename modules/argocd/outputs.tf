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

output "ingress_nginx_namespace" {
  description = "Namespace where public Ingress NGINX is deployed"
  value       = helm_release.ingress_nginx.namespace
}

output "ingress_nginx_internal_namespace" {
  description = "Namespace where internal Ingress NGINX is deployed"
  value       = helm_release.ingress_nginx_internal.namespace
}

output "public_nlb_hostname" {
  description = "Public NLB DNS — internet-facing, serves app traffic"
  value       = try(data.kubernetes_service.ingress_nginx_public.status[0].load_balancer[0].ingress[0].hostname, "NLB not ready yet")
}

output "internal_nlb_hostname" {
  description = "Internal NLB DNS — VPC-only, serves ArgoCD"
  value       = try(data.kubernetes_service.ingress_nginx_internal.status[0].load_balancer[0].ingress[0].hostname, "NLB not ready yet")
}

output "argocd_admin_password" {
  description = "ArgoCD initial admin password"
  value       = try(data.kubernetes_secret.argocd_admin_password.data["password"], "Secret not found")
  sensitive   = true
}
