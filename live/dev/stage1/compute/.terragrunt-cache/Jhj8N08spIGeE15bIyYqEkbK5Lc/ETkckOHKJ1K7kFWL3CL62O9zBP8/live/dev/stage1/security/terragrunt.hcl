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
  source = "${get_repo_root()}//modules/security"
}

# ── Dependency ────────────────────────────────────────────────────────────────
# Reads vpc's remote state to extract vpc_id. No terraform_remote_state data
# source in any .tf file — Terragrunt resolves this at the wrapper level.
# mock_outputs allow `terragrunt plan` to run on a cold start with no real state.
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
