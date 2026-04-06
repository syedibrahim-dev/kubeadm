# Variables for Kubernetes Cluster Infrastructure - Modular Structure

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

# VPC Configuration
variable "vpc" {
  description = "VPC and network configuration"
  type = object({
    vpc_cidr            = string
    public_subnet_cidr  = string
    private_subnet_cidr = string
  })
  default = {
    vpc_cidr            = "10.0.0.0/16"
    public_subnet_cidr  = "10.0.1.0/24"
    private_subnet_cidr = "10.0.10.0/24"
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
