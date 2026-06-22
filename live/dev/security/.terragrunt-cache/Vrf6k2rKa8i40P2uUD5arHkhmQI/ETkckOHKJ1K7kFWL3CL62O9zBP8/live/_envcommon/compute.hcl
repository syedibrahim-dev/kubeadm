terraform {
  source = "${get_repo_root()}//modules/compute"
}

inputs = {
  ccm_version     = "v1.31.1"
  pod_subnet_cidr = "192.168.0.0/16"
  worker_name     = "K8s-Worker"
}
