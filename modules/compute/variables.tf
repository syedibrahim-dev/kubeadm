# Compute Module Variables

variable "ami_id" {
  description = "AMI ID for K8s nodes"
  type        = string
}

variable "control_plane_instance_type" {
  description = "Instance type for control plane"
  type        = string
}

variable "worker_instance_type" {
  description = "Instance type for worker node"
  type        = string
}

variable "worker_count" {
  description = "Number of worker nodes to create"
  type        = number
  default     = 1
}

variable "private_subnet_id" {
  description = "Private subnet ID where K8s nodes will be deployed"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for K8s nodes"
  type        = string
}

variable "control_plane_private_ip" {
  description = "Fixed private IP for control plane"
  type        = string
}

variable "control_plane_name" {
  description = "Name tag for control plane instance"
  type        = string
}

variable "worker_name" {
  description = "Name tag for worker instance"
  type        = string
}

variable "enable_auto_setup" {
  description = "Enable automatic Kubernetes setup via user_data scripts"
  type        = bool
  default     = true
}

variable "aws_region" {
  description = "AWS region for SSM Parameter Store"
  type        = string
}

variable "nat_gateway_id" {
  description = "NAT Gateway ID for explicit dependency - ensures NAT is ready before instances start"
  type        = string
}
