# Loadbalancer Module Variables

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_id" {
  description = "First public subnet ID (AZ1) — for external ALB"
  type        = string
}

variable "public_subnet_2_id" {
  description = "Second public subnet ID (AZ2) — ALB requires 2 AZs"
  type        = string
}

variable "private_subnet_id" {
  description = "First private subnet ID (AZ1) — for internal NLB"
  type        = string
}

variable "private_subnet_2_id" {
  description = "Second private subnet ID (AZ2) — NLB requires 2 AZs"
  type        = string
}

variable "worker_instance_ids" {
  description = "Worker node EC2 instance IDs — registered in NLB target group"
  type        = list(string)
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
}

variable "nlb_private_ip_az1" {
  description = "Fixed private IP for NLB in AZ1 — must be within private subnet CIDR (10.0.10.0/24)"
  type        = string
  default     = "10.0.10.50"
}

variable "nlb_private_ip_az2" {
  description = "Fixed private IP for NLB in AZ2 — must be within private subnet CIDR (10.0.11.0/24)"
  type        = string
  default     = "10.0.11.50"
}

variable "vpc_cidr" {
  description = "VPC CIDR — used for ALB security group egress to NLB"
  type        = string
}

variable "domain_name" {
  description = "Base domain — public zone hosts app/api, private zone hosts argocd.internal"
  type        = string
}
