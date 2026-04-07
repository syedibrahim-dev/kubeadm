# AWS Provider Configuration

provider "aws" {
  region = var.aws_region
}

provider "null" {}

# Helm and Kubernetes providers use dynamically fetched kubeconfig
# During destroy, if kubeconfig doesn't exist, use dummy config to avoid errors
locals {
  kubeconfig_path = fileexists("${path.root}/.terraform/kubeconfig") ? "${path.root}/.terraform/kubeconfig" : "${path.root}/.terraform/dummy-kubeconfig"
}

provider "helm" {
  kubernetes {
    config_path = local.kubeconfig_path
  }
}

provider "kubernetes" {
  config_path = local.kubeconfig_path
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
  }
}
