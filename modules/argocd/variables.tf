# ArgoCD Module Variables

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "Kubernetes cluster name — used in data source tag filters"
  type        = string
  default     = "kubeadm-cluster"
}

variable "cluster_ready" {
  description = "Dependency token — set to admin module output to sequence Stage 2 after cluster is up"
  type        = any
  default     = null
}

variable "vpc_cidr" {
  description = "VPC CIDR block — used in nginx whitelist-source-range to restrict ArgoCD to VPC-only access"
  type        = string
  default     = "10.0.0.0/16"
}

variable "namespaces" {
  description = "Namespaces for nginx ingress and ArgoCD"
  type = object({
    nginx  = string
    argocd = string
  })
  default = {
    nginx  = "ingress-nginx"
    argocd = "argocd"
  }
}

variable "resource_names" {
  description = "Resource names for ArgoCD and external ALB resources"
  type = object({
    nginx_release      = string
    argocd_release     = string
    argocd_application = string
    argocd_ingress     = string
    alb_security_group = string
    external_alb       = string
    alb_target_group   = string
  })
  default = {
    nginx_release      = "ingress-nginx"
    argocd_release     = "argocd"
    argocd_application = "k8s-app"
    argocd_ingress     = "argocd-server-ingress"
    alb_security_group = "k8s-external-alb-sg"
    external_alb       = "k8s-external-alb"
    alb_target_group   = "k8s-alb-nlb-tg"
  }
}

variable "argocd_root_path" {
  description = "Base path for ArgoCD UI and ingress routing"
  type        = string
  default     = "/argocd"
}

variable "helm_timeout_seconds" {
  description = "Timeout for Helm releases in seconds"
  type        = number
  default     = 600
}

variable "alb_settings" {
  description = "External ALB listener and health check settings"
  type = object({
    listener_port          = number
    target_port            = number
    ingress_cidrs          = list(string)
    health_check_path      = string
    health_check_interval  = number
    healthy_threshold      = number
    unhealthy_threshold    = number
    health_check_matcher   = string
    listener_rule_priority = number
  })
  default = {
    listener_port          = 80
    target_port            = 80
    ingress_cidrs          = ["0.0.0.0/0"]
    health_check_path      = "/"
    health_check_interval  = 15
    healthy_threshold      = 2
    unhealthy_threshold    = 2
    health_check_matcher   = "200-404"
    listener_rule_priority = 1
  }
}

# ── NLB pinned IPs ────────────────────────────────────────────────────────────
# CCM uses these IPs when provisioning the internal NLB, so they are known at
# plan time and can be registered as ALB targets via pure Terraform (no CLI).
# Choose unused IPs from each private subnet CIDR.

variable "nlb_ip_az1" {
  description = "Pinned private IP for the NLB in AZ1 private subnet (10.0.10.0/24)"
  type        = string
  default     = "10.0.10.50"
}

variable "nlb_ip_az2" {
  description = "Pinned private IP for the NLB in AZ2 private subnet (10.0.11.0/24)"
  type        = string
  default     = "10.0.11.50"
}

# ── Helm chart versions ───────────────────────────────────────────────────────

variable "nginx_chart_version" {
  description = "ingress-nginx Helm chart version"
  type        = string
  default     = "4.10.1"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version"
  type        = string
  default     = "7.7.11"
}

# ── GitOps / Application ──────────────────────────────────────────────────────

variable "gitops_repo_url" {
  description = "GitOps repository URL for ArgoCD to watch"
  type        = string
  default     = "https://github.com/syedibrahim-dev/kubeadm-gitops.git"
}

variable "gitops_branch" {
  description = "Branch in the GitOps repository for ArgoCD to track"
  type        = string
  default     = "main"
}

variable "app_namespace" {
  description = "Kubernetes namespace where the application will be deployed"
  type        = string
  default     = "test-app"
}

variable "gitops_path" {
  description = "Path inside the GitOps repository that ArgoCD watches"
  type        = string
  default     = "k8s-app/overlays/production"
}
