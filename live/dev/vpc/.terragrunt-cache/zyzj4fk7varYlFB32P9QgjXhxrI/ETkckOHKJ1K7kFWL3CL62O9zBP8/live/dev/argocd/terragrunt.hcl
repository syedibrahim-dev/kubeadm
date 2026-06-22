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
  path           = "${get_repo_root()}/live/_envcommon/argocd.hcl"
  expose         = true
  merge_strategy = "deep"
}

dependency "admin" {
  config_path = "../admin"

  mock_outputs = {
    admin_instance_id = "i-00000000000000000"
    admin_private_ip  = "10.0.10.50"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "apply", "destroy"]
}

dependency "compute" {
  config_path = "../compute"

  mock_outputs = {
    control_plane_private_ip = "10.0.10.100"
    worker_count             = 1
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "apply", "destroy"]
}
# Overwrites the root-generated provider.tf with a combined block covering all
# five providers. Terraform forbids required_providers in more than one
# terraform{} block — merging here avoids that.
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
  kubeconfig_path = include.envcommon.locals.kubeconfig_path

  helm = {
    nginx_chart_version  = "4.10.1"
    argocd_chart_version = "7.7.11"
    timeout_seconds      = 900
  }

  gitops = {
    repo_url      = "https://github.com/syedibrahim-dev/kubeadm-gitops.git"
    branch        = "main"
    path          = "k8s-app/overlays/production"
    app_namespace = "test-app"
  }

  alb_settings = {
    listener_port          = 80
    target_port            = 80
    ingress_cidrs          = ["0.0.0.0/0"]
    health_check_path      = "/"
    health_check_interval  = 15
    healthy_threshold      = 2
    unhealthy_threshold    = 2
    health_check_matcher   = "200-404"
    listener_rule_priority = 1
  }

  tags = {
    Project     = include.env.locals.cluster_name
    Environment = include.env.locals.environment
    ManagedBy   = "terragrunt"
  }
}
