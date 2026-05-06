
# Core Configuration
core = {
  aws_region   = "us-east-1"
  cluster_name = "kubeadm-cluster"
}

# VPC Configuration
vpc = {
  vpc_cidr              = "10.0.0.0/16"
  public_subnet_cidr    = "10.0.1.0/24"
  private_subnet_cidr   = "10.0.10.0/24"
  public_subnet_2_cidr  = "10.0.2.0/24"
  private_subnet_2_cidr = "10.0.11.0/24"
}

# Compute Configuration
compute = {
  control_plane_instance_type = "t3.medium"
  worker_instance_type        = "t3.medium"
  worker_count                = 1
  control_plane_private_ip    = "10.0.10.100"
  control_plane_name          = "K8s-Control-Plane"
  worker_name                 = "K8s-Worker"
  volume_size                 = 20
  k8s_version                 = "1.31"
  ccm_version                 = "v1.31.1"
  pod_subnet_cidr             = "192.168.0.0/16"
}

# Admin Instance Configuration
admin = {
  instance_type     = "t3.micro"
  admin_name        = "K8s-Admin"
  terraform_version = "1.10.5"
}

# Automation Configuration
automation = {
  enable_auto_setup  = true
  enable_auto_deploy = true
}

# Stage 2 Configuration
stage2 = {
  deploy_argocd = false
}
