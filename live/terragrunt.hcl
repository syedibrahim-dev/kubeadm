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

remote_state {
  backend = "s3"
  config = {
    bucket         = "kubeadm-tfstate-${local.aws_account_id}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    encrypt        = true
    dynamodb_table = "kubeadm-tfstate-locks"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}
