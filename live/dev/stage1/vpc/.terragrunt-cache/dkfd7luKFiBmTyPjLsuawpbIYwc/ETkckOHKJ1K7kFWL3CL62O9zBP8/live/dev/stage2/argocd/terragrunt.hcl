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
  source = "${get_repo_root()}//modules/argocd"
}

locals {
  # Kubeconfig is written to ~/.kube/config by admin-setup.sh for all users.
  # pathexpand() resolves ~ at apply time on the machine running Terragrunt
  # (i.e., the ubuntu user on the admin EC2 for Stage 2).
  kubeconfig_path = pathexpand("~/.kube/config")

  # ── GitOps ─────────────────────────────────────────────────────────────────
  repo_url      = "https://github.com/syedibrahim-dev/kubeadm-gitops.git"
  branch        = "main"
  gitops_path   = "k8s-app/overlays/production"
  app_namespace = "test-app"

  # ── Helm ───────────────────────────────────────────────────────────────────
  nginx_chart_version  = "4.10.1"
  argocd_chart_version = "7.7.11"
  helm_timeout_seconds = 900

  # ── ALB ────────────────────────────────────────────────────────────────────
  alb_listener_port          = 80
  alb_target_port            = 80
  alb_ingress_cidrs          = ["0.0.0.0/0"]
  alb_health_check_path      = "/"
  alb_health_check_interval  = 15
  alb_healthy_threshold      = 2
  alb_unhealthy_threshold    = 2
  alb_health_check_matcher   = "200-404"
  alb_listener_rule_priority = 1
}

# ── Cross-stage dependencies ──────────────────────────────────────────────────
# Depending on admin (which itself depends on compute → security → vpc) ensures
# the full Stage 1 stack is up before any Helm release is attempted.
dependency "admin" {
  config_path = "../../stage1/admin"

  mock_outputs = {
    admin_instance_id = "i-00000000000000000"
    admin_private_ip  = "10.0.10.50"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Explicit compute dependency for outputs consumed below
dependency "compute" {
  config_path = "../../stage1/compute"

  mock_outputs = {
    control_plane_private_ip = "10.0.10.100"
    worker_count             = 1
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# ── Stage 2 provider override ─────────────────────────────────────────────────
# The root generate block writes provider.tf with only the aws provider.
# This block overwrites that same file (if_exists = "overwrite_terragrunt")
# with a combined version covering all five providers in a SINGLE
# required_providers block. Terraform forbids required_providers appearing in
# more than one terraform{} block across a module — merging here avoids that.
generate "provider_all" {
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
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}

provider "aws" {
  region = "${include.root.locals.aws_region}"
}

provider "helm" {
  kubernetes {
    config_path = "${local.kubeconfig_path}"
  }
}

provider "kubernetes" {
  config_path = "${local.kubeconfig_path}"
}

provider "kubectl" {
  config_path      = "${local.kubeconfig_path}"
  load_config_file = true
}
EOF
}

inputs = {
  aws_region      = include.root.locals.aws_region
  cluster_name    = include.env.locals.cluster_name
  vpc_cidr        = include.env.locals.vpc_cidr
  kubeconfig_path = local.kubeconfig_path

  # Helm chart versions and timeout — composed into the object the module expects
  helm = {
    nginx_chart_version  = local.nginx_chart_version
    argocd_chart_version = local.argocd_chart_version
    timeout_seconds      = local.helm_timeout_seconds
  }

  # GitOps — composed into the object the module expects
  gitops = {
    repo_url      = local.repo_url
    branch        = local.branch
    path          = local.gitops_path
    app_namespace = local.app_namespace
  }

  # ALB — composed into the object the module expects
  alb_settings = {
    listener_port          = local.alb_listener_port
    target_port            = local.alb_target_port
    ingress_cidrs          = local.alb_ingress_cidrs
    health_check_path      = local.alb_health_check_path
    health_check_interval  = local.alb_health_check_interval
    healthy_threshold      = local.alb_healthy_threshold
    unhealthy_threshold    = local.alb_unhealthy_threshold
    health_check_matcher   = local.alb_health_check_matcher
    listener_rule_priority = local.alb_listener_rule_priority
  }

  tags = {
    Project     = include.env.locals.cluster_name
    Environment = include.env.locals.environment
    ManagedBy   = "terragrunt"
  }
}
