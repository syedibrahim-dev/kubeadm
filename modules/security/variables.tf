# Security Module Variables

variable "vpc_id" {
  description = "VPC ID where security groups will be created"
  type        = string
}

variable "cluster_name" {
  description = "Kubernetes cluster name — used in AWS resource tags"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block — restricts nginx NodePort ingress to VPC-internal traffic only"
  type        = string
}
