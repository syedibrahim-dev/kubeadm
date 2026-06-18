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

# get_repo_root()// copies the ENTIRE repo into the Terragrunt cache and sets
# the working directory to modules/vpc. This keeps scripts/ accessible at
# path.module/../../scripts/ inside the modules (two levels up from any module).
terraform {
  source = "${get_repo_root()}//modules/vpc"
}

inputs = {
  cluster_name          = include.env.locals.cluster_name
  vpc_cidr              = include.env.locals.vpc_cidr
  public_subnet_cidr    = include.env.locals.public_subnet_cidr
  private_subnet_cidr   = include.env.locals.private_subnet_cidr
  public_subnet_2_cidr  = include.env.locals.public_subnet_2_cidr
  private_subnet_2_cidr = include.env.locals.private_subnet_2_cidr

  tags = {
    Project     = include.env.locals.cluster_name
    Environment = include.env.locals.environment
    ManagedBy   = "terragrunt"
  }
}
