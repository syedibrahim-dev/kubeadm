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

variable "vpc_id" {
  description = "VPC ID — for ALB security group"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR — for ALB security group egress rule"
  type        = string
}

variable "public_subnet_id" {
  description = "First public subnet ID (AZ1) — for external ALB"
  type        = string
}

variable "public_subnet_2_id" {
  description = "Second public subnet ID (AZ2) — ALB requires 2 AZs"
  type        = string
}

variable "private_subnet_id" {
  description = "First private subnet ID (AZ1) — CCM places NLB here"
  type        = string
}

variable "private_subnet_2_id" {
  description = "Second private subnet ID (AZ2) — CCM places NLB here"
  type        = string
}

# ── Route53 approach (commented out) ──
# variable "domain_name" {
#   description = "Base domain — ArgoCD nginx Ingress uses argocd.internal.<domain>"
#   type        = string
#   default     = "kubeadm-demo.com"
# }
