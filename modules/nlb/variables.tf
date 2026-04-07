variable "public_subnet_id" {
  description = "Public subnet ID where the NLB is placed"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for target groups"
  type        = string
}

variable "worker_instance_ids" {
  description = "Worker node instance IDs to register as NLB targets"
  type        = list(string)
}
