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

# ArgoCD Module - Stage 2: runs automatically on the admin EC2 instance (inside VPC)
# deploy_argocd defaults to false so this is skipped during local Stage 1 apply.
# admin-setup.sh re-runs terraform with -var="deploy_argocd=true" from inside the VPC
# where the K8s API server (10.0.x.x:6443) is reachable.
module "argocd" {
  count  = var.deploy_argocd ? 1 : 0
  source = "./modules/argocd"

  gitops_repo_url = var.gitops_repo_url
  gitops_branch   = var.gitops_branch
  gitops_path     = var.gitops_path
  app_namespace   = var.app_namespace
}

# Pre-destroy cleanup — fires automatically on terraform destroy BEFORE EC2s are terminated.
# CCM creates NLBs outside Terraform state so Terraform can't delete them directly.
# This sends an SSM command to the admin EC2 to delete the LoadBalancer services,
# which triggers CCM to delete the NLBs. Without this, VPC/subnet destruction
# hangs indefinitely because AWS won't delete a subnet with an NLB still attached.
resource "null_resource" "pre_destroy_nlb_cleanup" {
  triggers = {
    admin_instance_id = module.admin.admin_instance_id
    aws_region        = var.aws_region
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Pre-destroy: deleting LoadBalancer services so CCM can remove NLBs..."
      COMMAND_ID=$(aws ssm send-command \
        --instance-ids "${self.triggers.admin_instance_id}" \
        --document-name "AWS-RunShellScript" \
        --parameters '{"commands":["kubectl delete svc -n ingress-nginx ingress-nginx-controller --ignore-not-found=true","kubectl delete svc -n ingress-nginx-internal ingress-nginx-internal-controller --ignore-not-found=true"]}' \
        --region "${self.triggers.aws_region}" \
        --query "Command.CommandId" \
        --output text 2>/dev/null) || true

      if [ -n "$COMMAND_ID" ] && [ "$COMMAND_ID" != "None" ]; then
        echo "SSM command sent ($COMMAND_ID). Waiting 60s for CCM to delete NLBs..."
        sleep 60
      else
        echo "Could not reach admin EC2 via SSM — skipping NLB cleanup."
      fi
      echo "Pre-destroy cleanup done."
    EOT
  }

  depends_on = [module.admin, module.compute]
}
