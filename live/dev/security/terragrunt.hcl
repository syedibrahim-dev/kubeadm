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
  path           = "${get_repo_root()}/_envcommon/security.hcl"
  expose         = true
  merge_strategy = "deep"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id = "vpc-00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  vpc_id       = dependency.vpc.outputs.vpc_id
  vpc_cidr     = include.env.locals.vpc_cidr
  cluster_name = include.env.locals.cluster_name

  tags = {
    Project     = include.env.locals.cluster_name
    Environment = include.env.locals.environment
    ManagedBy   = "terragrunt"
  }
}
