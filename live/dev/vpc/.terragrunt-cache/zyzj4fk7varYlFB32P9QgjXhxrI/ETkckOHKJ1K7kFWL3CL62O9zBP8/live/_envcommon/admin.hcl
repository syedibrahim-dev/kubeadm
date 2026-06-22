terraform {
  source = "${get_repo_root()}//modules/admin"
}

inputs = {
  admin_name = "K8s-Admin"
}
