# Root variables — all hardcoded values in scripts and modules are driven from here.

variable "core" {
  description = "Global AWS and cluster settings"
  type = object({
    aws_region   = string
    cluster_name = string
  })
  default = {
    aws_region   = "us-east-1"
    cluster_name = "kubeadm-cluster"
  }
}

# ── Networking ─────────────────────────────────────────────────────────────────
variable "vpc" {
  description = "VPC and subnet CIDR configuration"
  type = object({
    vpc_cidr              = string
    public_subnet_cidr    = string
    private_subnet_cidr   = string
    public_subnet_2_cidr  = string
    private_subnet_2_cidr = string
  })
  default = {
    vpc_cidr              = "10.0.0.0/16"
    public_subnet_cidr    = "10.0.1.0/24"
    private_subnet_cidr   = "10.0.10.0/24"
    public_subnet_2_cidr  = "10.0.2.0/24"
    private_subnet_2_cidr = "10.0.11.0/24"
  }
}

# ── Compute ────────────────────────────────────────────────────────────────────

variable "compute" {
  description = "Kubernetes node and cluster configuration"
  type = object({
    control_plane_instance_type = string
    worker_instance_type        = string
    worker_count                = number
    control_plane_private_ip    = string
    control_plane_name          = string
    worker_name                 = string
    volume_size                 = number
    k8s_version                 = string
    ccm_version                 = string
    pod_subnet_cidr             = string

  })
  default = {
    control_plane_instance_type = "t3.medium"
    worker_instance_type        = "t3.medium"
    worker_count                = 1
    control_plane_private_ip    = "10.0.10.100"
    control_plane_name          = "K8s-Control-Plane"
    worker_name                 = "K8s-Worker"
    volume_size                 = 20
    k8s_version                 = "1.31"
    ccm_version                 = "v1.31.1"
    pod_subnet_cidr             = "192.168.0.0/16"
  }
}

# ── Admin ──────────────────────────────────────────────────────────────────────

variable "admin" {
  description = "Admin kubectl management instance configuration"
  type = object({
    instance_type     = string
    admin_name        = string
    terraform_version = string
  })
  default = {
    instance_type     = "t3.micro"
    admin_name        = "K8s-Admin"
    terraform_version = "1.10.5"
  }
}

# ── GitOps / ArgoCD ────────────────────────────────────────────────────────────

variable "gitops" {
  description = "GitOps repository and ArgoCD application configuration"
  type = object({
    github_repo   = string
    repo_url      = string
    branch        = string
    path          = string
    app_namespace = string
  })
  default = {
    github_repo   = "syedibrahim-dev/kubeadm"
    repo_url      = "https://github.com/syedibrahim-dev/kubeadm-gitops.git"
    branch        = "main"
    path          = "k8s-app/overlays/production"
    app_namespace = "test-app"
  }
}

# ── Automation ─────────────────────────────────────────────────────────────────

variable "automation" {
  description = "Automation toggles for setup and deployment"
  type = object({
    enable_auto_setup  = bool
    enable_auto_deploy = bool
  })
  default = {
    enable_auto_setup  = true
    enable_auto_deploy = true
  }
}

variable "deploy_argocd" {
  description = "Stage 2 gate — set to true only when running from the admin EC2 inside the VPC. The K8s API (10.x.x.x:6443) is unreachable from outside."
  type        = bool
  default     = false
}

variable "stage2" {
  description = "Stage 2 ArgoCD configuration — Helm chart versions and ALB settings"
  type = object({
    helm = optional(object({
      nginx_chart_version  = string
      argocd_chart_version = string
      timeout_seconds      = number
      }), {
      nginx_chart_version  = "4.10.1"
      argocd_chart_version = "7.7.11"
      timeout_seconds      = 900
    })
    alb_settings = optional(object({
      listener_port          = number
      target_port            = number
      ingress_cidrs          = list(string)
      health_check_path      = string
      health_check_interval  = number
      healthy_threshold      = number
      unhealthy_threshold    = number
      health_check_matcher   = string
      listener_rule_priority = number
      }), {
      listener_port          = 80
      target_port            = 80
      ingress_cidrs          = ["0.0.0.0/0"]
      health_check_path      = "/"
      health_check_interval  = 15
      healthy_threshold      = 2
      unhealthy_threshold    = 2
      health_check_matcher   = "200-404"
      listener_rule_priority = 1
    })
  })
  default = {}
}
