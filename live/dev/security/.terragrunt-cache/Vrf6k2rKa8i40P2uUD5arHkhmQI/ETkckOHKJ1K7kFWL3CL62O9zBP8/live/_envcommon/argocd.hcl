terraform {
  source = "${get_repo_root()}//modules/argocd"
}

locals {
  # pathexpand resolves ~ to the home dir of the user running Terragrunt.
  # On the admin EC2 (ubuntu user) this becomes /home/ubuntu/.kube/config.
  kubeconfig_path = pathexpand("~/.kube/config")
}

