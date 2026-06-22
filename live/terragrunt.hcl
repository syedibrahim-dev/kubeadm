# ─────────────────────────────────────────────────────────────────────────────
# ROOT terragrunt.hcl
# ZERO BLAST-RADIUS: path_relative_to_include() produces a unique state path
# per unit. A destroy in one unit cannot affect any other unit's state.
# Local state lands at state/<path>/terraform.tfstate:

locals {
  account_vars = read_terragrunt_config("${get_repo_root()}/live/account.hcl")

  aws_account_id = local.account_vars.locals.aws_account_id
  aws_region     = local.account_vars.locals.aws_region
}

# ── Provider ──────────────────────────────────────────────────────────────────
# Generated into provider.tf inside every child's .terragrunt-cache directory.
# generate block — Terraform merges required_providers across .tf files.
generate "provider_aws" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "${local.aws_region}"
}
EOF
}

# ── Remote State ──────────────────────────────────────────────────────────────
# LEARNING MODE: local backend — state files land in state/ at the repo root.
# Each unit gets its own isolated .tfstate file via path_relative_to_include(),
# which is what makes dependency {} blocks work (they can find sibling state).
#
# To switch to S3 for production, replace this block with:
#
#   remote_state {
#     backend = "s3"
#     config = {
#       encrypt        = true
#       bucket         = "${local.aws_account_id}-terraform-state-${local.aws_region}"
#       key            = "${path_relative_to_include()}/terraform.tfstate"
#       region         = local.aws_region
#       dynamodb_table = "terraform-locks"
#     }
#     generate = {
#       path      = "backend.tf"
#       if_exists = "overwrite_terragrunt"
#     }
#   }
#

remote_state {
  backend = "local"
  config = {
    path = "${get_repo_root()}/state/${path_relative_to_include()}/terraform.tfstate"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}
