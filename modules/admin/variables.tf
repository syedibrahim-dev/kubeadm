# Admin Module Variables

variable "ami_id" {
  description = "AMI ID for the admin instance"
  type        = string
}

variable "instance_type" {
  description = "Instance type for admin"
  type        = string
}

variable "private_subnet_id" {
  description = "Private subnet ID for admin instance"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for admin instance"
  type        = string
}

variable "admin_name" {
  description = "Name tag for admin instance"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "control_plane_name" {
  description = "Control plane name for Parameter Store path"
  type        = string
}

variable "control_plane_private_ip" {
  description = "Control plane private IP for kubectl access"
  type        = string
}

variable "enable_auto_setup" {
  description = "Enable automatic kubectl configuration"
  type        = bool
}

variable "enable_auto_deploy" {
  description = "Enable automatic deployment of ArgoCD and applications"
  type        = bool
  default     = false
}

variable "nat_gateway_id" {
  description = "NAT Gateway ID for dependency"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name where k8s-app is stored for automated download"
  type        = string
}

variable "worker_count" {
  description = "Number of worker nodes to wait for before deploying"
  type        = number
  default     = 1
}
