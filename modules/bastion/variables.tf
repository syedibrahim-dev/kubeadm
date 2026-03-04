# Bastion Module Variables

variable "ami_id" {
  description = "AMI ID for bastion instance"
  type        = string
}

variable "instance_type" {
  description = "Instance type for bastion"
  type        = string
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "subnet_id" {
  description = "Public subnet ID where bastion will be deployed"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for bastion"
  type        = string
}
