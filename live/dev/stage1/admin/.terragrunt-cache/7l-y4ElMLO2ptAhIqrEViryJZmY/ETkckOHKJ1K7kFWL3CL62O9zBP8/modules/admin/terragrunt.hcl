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
  source = "${get_repo_root()}//modules/admin"
}

locals {
  admin_instance_type = "t3.micro"
  admin_name          = "K8s-Admin"
  terraform_version   = "1.10.5"
  terragrunt_version  = "0.75.10"
  enable_auto_deploy  = true
  github_repo         = "syedibrahim-dev/kubeadm"
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
  cluster_name      = include.env.locals.cluster_name
  aws_region        = include.root.locals.aws_region
  private_subnet_id = dependency.vpc.outputs.private_subnet_id
  nat_gateway_id    = dependency.vpc.outputs.nat_gateway_id

  # admin/variables.tf names this security_group_id (not admin_sg_id)
  security_group_id = dependency.security.outputs.admin_sg_id

  # Explicit dependency on compute — admin-setup.sh waits for the cluster
  # to be up before bootstrapping kubectl and triggering Stage 2.
  # These values are passed to the admin-setup.sh template.
  control_plane_private_ip = dependency.compute.outputs.control_plane_private_ip
  worker_count             = dependency.compute.outputs.worker_count

  instance_type      = local.admin_instance_type
  admin_name         = local.admin_name
  terraform_version  = local.terraform_version
  terragrunt_version = local.terragrunt_version
  enable_auto_setup  = include.env.locals.enable_auto_setup
  enable_auto_deploy = local.enable_auto_deploy
  github_repo        = local.github_repo
  control_plane_name = include.env.locals.control_plane_name
  k8s_version        = include.env.locals.k8s_version

  tags = {
    Project     = include.env.locals.cluster_name
    Environment = include.env.locals.environment
    ManagedBy   = "terragrunt"
  }
}
