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

include "envcommon" {
  path           = "${get_repo_root()}/_envcommon/admin.hcl"
  expose         = true
  merge_strategy = "deep"
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
    admin_sg_id = "sg-11111111111111111"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "compute" {
  config_path = "../compute"

  mock_outputs = {
    control_plane_id         = "i-00000000000000000"
    control_plane_private_ip = "10.0.10.100"
    worker_id                = ["i-00000000000000001"]
    worker_private_ip        = ["10.0.10.101"]
    worker_count             = 1
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  aws_region               = include.root.locals.aws_region
  control_plane_name       = include.env.locals.control_plane_name
  k8s_version              = include.env.locals.k8s_version
  enable_auto_setup        = include.env.locals.enable_auto_setup
  private_subnet_id        = dependency.vpc.outputs.private_subnet_id
  nat_gateway_id           = dependency.vpc.outputs.nat_gateway_id
  security_group_id        = dependency.security.outputs.admin_sg_id
  control_plane_private_ip = dependency.compute.outputs.control_plane_private_ip
  worker_count             = dependency.compute.outputs.worker_count
  instance_type            = "t3.micro"
  terraform_version        = "1.10.5"
  terragrunt_version       = "0.75.10"
  enable_auto_deploy       = true
  github_repo              = "syedibrahim-dev/kubeadm"

  tags = {
    Project     = include.env.locals.cluster_name
    Environment = include.env.locals.environment
    ManagedBy   = "terragrunt"
  }
}
