variable "vpc_id" {
  description = "VPC ID — required by AWS Load Balancer Controller"
  type        = string
}

variable "aws_region" {
  description = "AWS region — required by AWS Load Balancer Controller"
  type        = string
}

variable "cluster_name" {
  description = "Kubernetes cluster name — required by AWS Load Balancer Controller"
  type        = string
  default     = "kubeadm-cluster"
}

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

variable "gitops_path" {
  description = "Path inside the GitOps repository that ArgoCD watches"
  type        = string
  default     = "k8s-app/overlays/production"
}
