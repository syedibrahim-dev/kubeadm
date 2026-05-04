# VPC Module - Creates networking infrastructure
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr              = var.vpc.vpc_cidr
  public_subnet_cidr    = var.vpc.public_subnet_cidr
  private_subnet_cidr   = var.vpc.private_subnet_cidr
  availability_zone     = data.aws_availability_zones.available.names[0]
  public_subnet_2_cidr  = var.vpc.public_subnet_2_cidr
  private_subnet_2_cidr = var.vpc.private_subnet_2_cidr
  availability_zone_2   = data.aws_availability_zones.available.names[1]
  cluster_name          = var.cluster_name
}

# Security Module - Creates security groups
module "security" {
  source = "./modules/security"

  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc.vpc_cidr
  cluster_name = var.cluster_name
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
  cluster_name                = var.cluster_name
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

# Loadbalancer Module — intentionally empty.
# Internal NLB is now CCM-provisioned (nginx service type=LoadBalancer in Stage 2).
# External ALB is created by module "argocd" after CCM provisions the NLB.
# module "loadbalancer" { ... }  # commented out — all resources moved to modules/argocd

# ArgoCD Module - Stage 2: runs automatically on the admin EC2 instance (inside VPC)
# deploy_argocd defaults to false so this is skipped during local Stage 1 apply.
# admin-setup.sh re-runs terraform with -var="deploy_argocd=true" from inside the VPC
# where the K8s API server (10.0.x.x:6443) is reachable.
# Stage 2 also creates the external ALB (after CCM provisions the internal NLB).
module "argocd" {
  count  = var.deploy_argocd ? 1 : 0
  source = "./modules/argocd"

  gitops_repo_url = var.gitops_repo_url
  gitops_branch   = var.gitops_branch
  gitops_path     = var.gitops_path
  app_namespace   = var.app_namespace
  aws_region      = var.aws_region
  cluster_name    = var.cluster_name
  # vpc_id, subnets etc. are discovered via data sources inside the module
  # ── Route53 approach (commented out) ──
  # domain_name   = var.domain_name
}

# Pre-destroy: pause ArgoCD sync before EC2s are terminated so it doesn't
# fight the destroy by reconciling resources during teardown.
# ALB and NLB are now in Terraform state (modules/loadbalancer) so they are
# deleted automatically by terraform destroy — no manual cleanup needed.
resource "null_resource" "pre_destroy_cleanup" {
  triggers = {
    admin_instance_id = module.admin.admin_instance_id
    aws_region        = var.aws_region
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Pre-destroy: pausing ArgoCD sync..."
      aws ssm send-command \
        --instance-ids "${self.triggers.admin_instance_id}" \
        --document-name "AWS-RunShellScript" \
        --parameters '{"commands":["kubectl patch app k8s-app -n argocd -p \"{\\\"spec\\\":{\\\"syncPolicy\\\":null}}\" --type=merge 2>/dev/null || true"]}' \
        --region "${self.triggers.aws_region}" \
        --output text 2>/dev/null || true

      echo "Pre-destroy: deleting ingress-nginx namespace so CCM cleans up the NLB before nodes are destroyed..."
      COMMAND_ID=$(aws ssm send-command \
        --instance-ids "${self.triggers.admin_instance_id}" \
        --document-name "AWS-RunShellScript" \
        --parameters '{"commands":["kubectl delete namespace ingress-nginx --ignore-not-found --timeout=180s 2>/dev/null || true"]}' \
        --region "${self.triggers.aws_region}" \
        --query "Command.CommandId" \
        --output text 2>/dev/null)

      if [ -n "$COMMAND_ID" ]; then
        echo "Waiting for NLB deletion to complete (SSM command: $COMMAND_ID)..."
        aws ssm wait command-executed \
          --command-id "$COMMAND_ID" \
          --instance-id "${self.triggers.admin_instance_id}" \
          --region "${self.triggers.aws_region}" 2>/dev/null || true
        echo "NLB cleanup complete."
      fi

      echo "Pre-destroy cleanup done."
    EOT
  }

  depends_on = [module.admin, module.compute]
}
