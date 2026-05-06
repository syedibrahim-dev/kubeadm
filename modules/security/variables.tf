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

variable "admin_security_group_name" {
  description = "Name for the admin instance security group"
  type        = string
  default     = "k8s-admin-sg"
}

variable "nodes_security_group_name" {
  description = "Name for the Kubernetes nodes security group"
  type        = string
  default     = "k8s-nodes-sg"
}

variable "k8s_api_port" {
  description = "Kubernetes API server port — allowed from the admin instance"
  type        = number
  default     = 6443
}

variable "nodeport_range" {
  description = "NodePort range allowed from within the VPC"
  type = object({
    from_port = number
    to_port   = number
  })
  default = {
    from_port = 30000
    to_port   = 32767
  }
}

variable "egress_cidr_blocks" {
  description = "CIDR blocks allowed for outbound traffic"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
