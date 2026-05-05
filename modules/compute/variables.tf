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
  description = "Instance type for worker nodes"
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
  description = "Fixed private IP for the control plane node"
  type        = string
}

variable "control_plane_name" {
  description = "Name tag for the control plane instance"
  type        = string
}

variable "worker_name" {
  description = "Name tag prefix for worker instances"
  type        = string
}

variable "volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 20
}

variable "root_volume_type" {
  description = "Root EBS volume type"
  type        = string
  default     = "gp3"
}

variable "enable_auto_setup" {
  description = "Run Kubernetes setup scripts via cloud-init on first boot"
  type        = bool
  default     = true
}

variable "aws_region" {
  description = "AWS region — used for SSM Parameter Store paths"
  type        = string
}

variable "cluster_name" {
  description = "Kubernetes cluster name — used in AWS resource tags and CCM args"
  type        = string
}

variable "k8s_version" {
  description = "Kubernetes version to install (e.g. '1.31')"
  type        = string
}

variable "pod_subnet_cidr" {
  description = "CIDR block for the Kubernetes pod network (Calico + kubeadm podSubnet)"
  type        = string
}

variable "ccm_version" {
  description = "AWS Cloud Controller Manager image version (e.g. 'v1.31.1')"
  type        = string
}

variable "nat_gateway_id" {
  description = "NAT Gateway ID — explicit dependency ensures NAT is ready before instances boot"
  type        = string
}
