variable "cluster_ready" {
  description = "Dependency to ensure cluster is ready before deploying ArgoCD"
  type        = any
  default     = null
}

variable "gitops_repo_url" {
  description = "GitOps repository URL for ArgoCD to watch"
  type        = string
  default     = "https://github.com/syedibrahim-dev/kubeadm-gitops.git"
}

variable "gitops_branch" {
  description = "Branch to watch in GitOps repository"
  type        = string
  default     = "main"
}

variable "app_namespace" {
  description = "Namespace where application will be deployed"
  type        = string
  default     = "test-app"
}
