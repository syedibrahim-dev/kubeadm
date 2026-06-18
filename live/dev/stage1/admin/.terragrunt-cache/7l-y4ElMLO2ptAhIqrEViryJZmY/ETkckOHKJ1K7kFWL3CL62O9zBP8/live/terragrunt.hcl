# ─────────────────────────────────────────────────────────────────────────────
# ROOT terragrunt.hcl
#
# This file is the single source of truth for:
#   1. The state backend (local for learning, S3 for production)
#   2. The AWS provider (generated into every child's .terragrunt-cache directory)
#   3. Global inputs silently merged into every child unit
#
# ZERO BLAST-RADIUS: path_relative_to_include() produces a unique state path
# per unit. A destroy in one unit cannot affect any other unit's state.
# Local state lands at state/<path>/terraform.tfstate:
#   state/dev/stage1/vpc/terraform.tfstate
#   state/dev/stage1/security/terraform.tfstate
#   state/dev/stage1/compute/terraform.tfstate
#   state/dev/stage1/admin/terraform.tfstate
#   state/dev/stage2/argocd/terraform.tfstate

locals {
  account_vars = read_terragrunt_config("${get_repo_root()}/live/account.hcl")

  aws_account_id = local.account_vars.locals.aws_account_id
  aws_region     = local.account_vars.locals.aws_region
}

# ── Provider ──────────────────────────────────────────────────────────────────
# Generated into provider.tf inside every child's .terragrunt-cache directory.
# Stage 2 (argocd) adds helm/kubernetes/kubectl providers on top via its own
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
# Bootstrap S3 once before switching:
#   aws s3 mb s3://<account-id>-terraform-state-us-east-1 --region us-east-1
#   aws s3api put-bucket-versioning --bucket <account-id>-terraform-state-us-east-1 --versioning-configuration Status=Enabled
#   aws dynamodb create-table --table-name terraform-locks \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --key-schema AttributeName=LockID,KeyType=HASH \
#     --billing-mode PAY_PER_REQUEST --region us-east-1

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
