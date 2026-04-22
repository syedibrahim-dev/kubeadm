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

variable "availability_zone" {
  description = "Primary availability zone (K8s nodes live here)"
  type        = string
}

variable "availability_zone_2" {
  description = "Second availability zone — ALB requires subnets in at least 2 AZs"
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
