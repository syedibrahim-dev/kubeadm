# VPC Module Variables

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
}

variable "public_subnet_2_cidr" {
  description = "CIDR block for second public subnet (AZ2, ALB use only)"
  type        = string
}

variable "private_subnet_2_cidr" {
  description = "CIDR block for second private subnet (AZ2, ALB use only)"
  type        = string
}

variable "cluster_name" {
  description = "Kubernetes cluster name — used in AWS resource tags"
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources (merged with resource-specific tags)"
  type        = map(string)
  default     = {}
}
