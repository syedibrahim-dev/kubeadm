provider "aws" {
  region = var.aws_region
}

# Helm, Kubernetes, and kubectl providers all use the same kubeconfig.
# During Stage 1 (laptop) the file doesn't exist yet — fall back to a dummy
# path so provider init doesn't error before the cluster is created.
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

provider "kubectl" {
  config_path      = local.kubeconfig_path
  load_config_file = fileexists(local.kubeconfig_path)
}

terraform {
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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}
