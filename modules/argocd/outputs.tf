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
  value       = kubernetes_manifest.argocd_application.manifest.metadata.name
}

output "ingress_nginx_namespace" {
  description = "Namespace where Ingress NGINX is deployed"
  value       = helm_release.ingress_nginx.namespace
}
