# VPC Module - Creates networking infrastructure
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr            = var.vpc.vpc_cidr
  public_subnet_cidr  = var.vpc.public_subnet_cidr
  private_subnet_cidr = var.vpc.private_subnet_cidr
  availability_zone   = data.aws_availability_zones.available.names[0]
}

# Security Module - Creates security groups
module "security" {
  source = "./modules/security"

  vpc_id = module.vpc.vpc_id
}

# Compute Module - Creates Kubernetes nodes (MUST be created before admin)
module "compute" {
  source = "./modules/compute"

  ami_id                      = data.aws_ami.ubuntu.id
  control_plane_instance_type = var.compute.control_plane_instance_type
  worker_instance_type        = var.compute.worker_instance_type
  worker_count                = var.compute.worker_count
  private_subnet_id           = module.vpc.private_subnet_id
  security_group_id           = module.security.k8s_nodes_sg_id
  control_plane_private_ip    = var.compute.control_plane_private_ip
  control_plane_name          = var.compute.control_plane_name
  worker_name                 = var.compute.worker_name
  volume_size                 = var.compute.volume_size
  enable_auto_setup           = var.enable_auto_setup
  aws_region                  = var.aws_region
  nat_gateway_id              = module.vpc.nat_gateway_id
}

# Admin Module - Creates private kubectl management instance (depends on control plane)
module "admin" {
  source = "./modules/admin"

  ami_id                   = data.aws_ami.ubuntu.id
  instance_type            = var.admin.instance_type
  private_subnet_id        = module.vpc.private_subnet_id
  security_group_id        = module.security.admin_sg_id
  admin_name               = var.admin.admin_name
  aws_region               = var.aws_region
  control_plane_name       = var.compute.control_plane_name
  control_plane_private_ip = var.compute.control_plane_private_ip
  enable_auto_setup        = var.enable_auto_setup
  enable_auto_deploy       = var.enable_auto_deploy
  nat_gateway_id           = module.vpc.nat_gateway_id
  worker_count             = var.compute.worker_count
  github_repo              = var.github_repo
}
