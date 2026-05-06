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

variable "argocd_root_path" {
  description = "Base path for ArgoCD UI and ingress routing"
  type        = string
  default     = "/argocd"
}

# ── Namespaces ─────────────────────────────────────────────────────────────────

variable "namespaces" {
  description = "Kubernetes namespaces for nginx ingress and ArgoCD"
  type = object({
    nginx  = string
    argocd = string
  })
  default = {
    nginx  = "ingress-nginx"
    argocd = "argocd"
  }
}

# ── Resource names ─────────────────────────────────────────────────────────────

variable "resource_names" {
  description = "Resource names for Helm releases, K8s objects, and AWS ALB resources"
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

# ── Helm ───────────────────────────────────────────────────────────────────────

variable "helm" {
  description = "Helm chart versions and install timeout. timeout_seconds covers image pulls + NLB provisioning — keep >= 900."
  type = object({
    nginx_chart_version  = string
    argocd_chart_version = string
    timeout_seconds      = number
  })
}

# ── NLB pinned IPs ─────────────────────────────────────────────────────────────
# CCM uses these IPs when provisioning the internal NLB, so they are known at
# plan time and can be registered as ALB targets via pure Terraform (no CLI).
# Choose unused IPs from each private subnet CIDR.

variable "nlb" {
  description = "Pinned private IPs for the CCM-provisioned internal NLB, one per AZ"
  type = object({
    ip_az1 = string
    ip_az2 = string
  })
}

# ── GitOps / Application ───────────────────────────────────────────────────────

variable "gitops" {
  description = "GitOps repository and ArgoCD application configuration"
  type = object({
    repo_url      = string
    branch        = string
    path          = string
    app_namespace = string
  })
  default = {
    repo_url      = "https://github.com/syedibrahim-dev/kubeadm-gitops.git"
    branch        = "main"
    path          = "k8s-app/overlays/production"
    app_namespace = "test-app"
  }
}

# ── ALB settings ───────────────────────────────────────────────────────────────

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
}
