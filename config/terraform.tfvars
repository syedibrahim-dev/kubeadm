
# AWS Configuration
aws_region = "us-east-1"  

# VPC Configuration
vpc = {
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidr  = "10.0.1.0/24"
  private_subnet_cidr = "10.0.10.0/24"
}

# Compute Configuration
compute = {
  control_plane_instance_type = "t3.small"  
  worker_instance_type        = "t3.small"  
  worker_count                = 1
  control_plane_private_ip    = "10.0.10.100"
  control_plane_name          = "K8s-Control-Plane"
  worker_name                 = "K8s-Worker"
}

# Admin Instance Configuration
admin = {
  instance_type = "t3.micro"
  admin_name    = "K8s-Admin"
}

# Automation Configuration
enable_auto_setup = true
