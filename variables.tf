# Root variables — all hardcoded values in scripts and modules are driven from here.

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Kubernetes cluster name — used in AWS resource tags and CCM configuration"
  type        = string
  default     = "kubeadm-cluster"
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

variable "enable_auto_setup" {
  description = "Run Kubernetes setup scripts automatically via cloud-init on first boot"
  type        = bool
  default     = true
}

variable "enable_auto_deploy" {
  description = "Automatically deploy ArgoCD (Stage 2) after cluster is ready"
  type        = bool
  default     = true
}

variable "deploy_argocd" {
  description = "Stage 2 gate — set to true only when running from the admin EC2 inside the VPC. The K8s API (10.x.x.x:6443) is unreachable from outside."
  type        = bool
  default     = false
}
