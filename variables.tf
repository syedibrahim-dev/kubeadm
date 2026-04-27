# Variables for Kubernetes Cluster Infrastructure - Modular Structure

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Kubernetes cluster name — used in AWS resource tags and LBC configuration"
  type        = string
  default     = "kubeadm-cluster"
}

# VPC Configuration
variable "vpc" {
  description = "VPC and network configuration"
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

# Compute Configuration
variable "compute" {
  description = "Kubernetes nodes configuration"
  type = object({
    control_plane_instance_type = string
    worker_instance_type        = string
    worker_count                = number
    control_plane_private_ip    = string
    control_plane_name          = string
    worker_name                 = string
    volume_size                 = number
  })
  default = {
    control_plane_instance_type = "t3.medium"
    worker_instance_type        = "t3.medium"
    worker_count                = 1
    control_plane_private_ip    = "10.0.10.100"
    control_plane_name          = "K8s-Control-Plane"
    worker_name                 = "K8s-Worker"
    volume_size                 = 20
  }
}

# Admin Instance Configuration
variable "admin" {
  description = "Admin kubectl management instance configuration"
  type = object({
    instance_type = string
    admin_name    = string
  })
  default = {
    instance_type = "t3.micro"
    admin_name    = "K8s-Admin"
  }
}

# Automation Configuration
variable "enable_auto_setup" {
  description = "Enable automatic Kubernetes installation and setup via user_data scripts"
  type        = bool
  default     = true
}

variable "enable_auto_deploy" {
  description = "Enable automatic deployment of ArgoCD and applications after cluster is ready"
  type        = bool
  default     = true
}

variable "deploy_argocd" {
  description = "Stage 2 gate: set to true only when running from the admin EC2 inside the VPC. Never set true locally — the K8s API server is unreachable from outside the VPC."
  type        = bool
  default     = false
}

variable "github_repo" {
  description = "GitHub repository for bootstrap files (format: owner/repo)"
  type        = string
  default     = "syedibrahim-dev/kubeadm"
}

# GitOps Configuration
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

variable "gitops_path" {
  description = "Path inside the GitOps repository that ArgoCD watches"
  type        = string
  default     = "k8s-app/overlays/production"
}

variable "app_namespace" {
  description = "Namespace where application will be deployed"
  type        = string
  default     = "test-app"
}
