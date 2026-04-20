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
