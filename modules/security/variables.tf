# Security Module Variables

variable "vpc_id" {
  description = "VPC ID where security groups will be created"
  type        = string
}

variable "cluster_name" {
  description = "Kubernetes cluster name — used in AWS resource tags"
  type        = string
}
