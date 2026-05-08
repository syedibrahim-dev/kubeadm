# Admin Module Variables

variable "ami_id" {
  description = "AMI ID for the admin instance"
  type        = string
}

variable "instance_type" {
  description = "Instance type for the admin instance"
  type        = string
}

variable "private_subnet_id" {
  description = "Private subnet ID for the admin instance"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for the admin instance"
  type        = string
}

variable "admin_name" {
  description = "Name tag for the admin instance"
  type        = string
}

variable "aws_region" {
  description = "AWS region — used for SSM and Terraform provider config"
  type        = string
}

variable "control_plane_name" {
  description = "Control plane name — used for SSM Parameter Store paths"
  type        = string
}

variable "control_plane_private_ip" {
  description = "Control plane private IP — used in helper scripts"
  type        = string
}

variable "enable_auto_setup" {
  description = "Run setup script automatically via cloud-init on first boot"
  type        = bool
}

variable "enable_auto_deploy" {
  description = "Automatically run Stage 2 (ArgoCD deployment) after cluster is ready"
  type        = bool
  default     = false
}

variable "nat_gateway_id" {
  description = "NAT Gateway ID — explicit dependency ensures NAT is ready before instance boots"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository for bootstrap files (format: owner/repo)"
  type        = string
}

variable "worker_count" {
  description = "Number of worker nodes to wait for before running Stage 2"
  type        = number
  default     = 1
}

variable "k8s_version" {
  description = "Kubernetes version to install kubectl (e.g. '1.31')"
  type        = string
}

variable "terraform_version" {
  description = "Terraform version to install for Stage 2 deployment (e.g. '1.10.5')"
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources (merged with resource-specific tags)"
  type        = map(string)
  default     = {}
}
