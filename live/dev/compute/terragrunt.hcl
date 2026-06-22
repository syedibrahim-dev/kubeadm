include "root" {
  path           = find_in_parent_folders()
  expose         = true
  merge_strategy = "deep"
}

include "env" {
  path           = find_in_parent_folders("env.hcl")
  expose         = true
  merge_strategy = "no_merge"
}

terraform {
  source = "${get_repo_root()}//modules/compute"
}

locals {
  control_plane_instance_type = "t3.medium"
  worker_instance_type        = "t3.medium"
  worker_count                = 1
  control_plane_private_ip    = "10.0.10.100"
  worker_name                 = "K8s-Worker"
  volume_size                 = 20
  ccm_version                 = "v1.31.1"
  pod_subnet_cidr             = "192.168.0.0/16"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    private_subnet_id = "subnet-00000000000000000"
    nat_gateway_id    = "nat-00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "security" {
  config_path = "../security"

  mock_outputs = {
    k8s_nodes_sg_id = "sg-00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  cluster_name      = include.env.locals.cluster_name
  aws_region        = include.root.locals.aws_region
  private_subnet_id = dependency.vpc.outputs.private_subnet_id
  nat_gateway_id    = dependency.vpc.outputs.nat_gateway_id

  # compute/variables.tf names this security_group_id (not k8s_nodes_sg_id)
  security_group_id = dependency.security.outputs.k8s_nodes_sg_id

  control_plane_instance_type = local.control_plane_instance_type
  worker_instance_type        = local.worker_instance_type
  worker_count                = local.worker_count
  control_plane_private_ip    = local.control_plane_private_ip
  control_plane_name          = include.env.locals.control_plane_name
  worker_name                 = local.worker_name
  volume_size                 = local.volume_size
  k8s_version                 = include.env.locals.k8s_version
  ccm_version                 = local.ccm_version
  pod_subnet_cidr             = local.pod_subnet_cidr
  enable_auto_setup           = include.env.locals.enable_auto_setup

  tags = {
    Project     = include.env.locals.cluster_name
    Environment = include.env.locals.environment
    ManagedBy   = "terragrunt"
  }
}
