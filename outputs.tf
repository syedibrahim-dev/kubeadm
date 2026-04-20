# Outputs for Private Kubernetes Cluster - Admin Instance Access

# Admin Instance Information
output "admin_instance_id" {
  description = "Admin instance ID for SSM access"
  value       = module.admin.admin_instance_id
}

output "admin_private_ip" {
  description = "Admin instance private IP"
  value       = module.admin.admin_private_ip
}

# Primary Access Command
output "admin_access_command" {
  description = "AWS SSM command to access Admin kubectl management instance"
  value       = "aws ssm start-session --target ${module.admin.admin_instance_id} --region ${var.aws_region}"
}

# Private IPs of K8s Nodes
output "control_plane_private_ip" {
  description = "Private IP of the control plane"
  value       = module.compute.control_plane_private_ip
}

output "control_plane_id" {
  description = "Control plane instance ID for emergency SSM access"
  value       = module.compute.control_plane_id
}

output "worker_private_ips" {
  description = "Private IPs of worker nodes"
  value       = module.compute.worker_private_ip
}

output "worker_ids" {
  description = "Worker instance IDs for emergency SSM access"
  value       = module.compute.worker_id
}

output "worker_count" {
  description = "Number of worker nodes"
  value       = module.compute.worker_count
}

output "public_nlb_hostname" {
  description = "Public NLB DNS for app traffic"
  value       = var.deploy_argocd ? module.argocd[0].public_nlb_hostname : "Available after Stage 2 (deploy_argocd=true)"
}

output "internal_nlb_hostname" {
  description = "Internal NLB DNS for ArgoCD (VPC-only)"
  value       = var.deploy_argocd ? module.argocd[0].internal_nlb_hostname : "Available after Stage 2 (deploy_argocd=true)"
}

output "argocd_admin_password" {
  description = "ArgoCD initial admin password"
  value       = var.deploy_argocd ? module.argocd[0].argocd_admin_password : "Available after Stage 2 (deploy_argocd=true)"
  sensitive   = true
}

output "argocd_access_info" {
  description = "How to access ArgoCD via SSM bastion tunnel"
  value       = <<-EOT

    ═══════════════════════════════════════════════════════════
    ARGOCD ACCESS (via SSM bastion tunnel)
    ═══════════════════════════════════════════════════════════

    ArgoCD is on an internal NLB — not reachable from the internet.
    Use the admin EC2 as a bastion to tunnel through.

    Step 1 — Get the internal NLB DNS (run on admin EC2):
      INTERNAL_NLB=$(kubectl get svc -n ingress-nginx-internal \
        ingress-nginx-internal-controller \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
      echo $INTERNAL_NLB

    Step 2 — On your laptop, open an SSM tunnel to the internal NLB:
      aws ssm start-session --target ${module.admin.admin_instance_id} \
        --document-name AWS-StartPortForwardingSessionToRemoteHost \
        --parameters '{"host":["<internal-NLB-DNS>"],"portNumber":["80"],"localPortNumber":["8080"]}'

    Step 3 — Open in browser:
      http://localhost:8080

    Step 4 — Get ArgoCD admin password (run on admin EC2):
      kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' | base64 -d

    ═══════════════════════════════════════════════════════════
    APP ACCESS (public NLB, internet-facing)
    ═══════════════════════════════════════════════════════════

    Get the public NLB DNS name (available ~2 min after ingress-nginx deploys):
      kubectl get svc -n ingress-nginx ingress-nginx-controller \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

    App URL: http://<public-NLB-DNS>/
  EOT
}

output "setup_instructions" {
  description = "Quick setup instructions"
  value = (var.enable_auto_setup ? <<-EOT

    ═══════════════════════════════════════════════════════════
    CLUSTER INFORMATION
    ═══════════════════════════════════════════════════════════

    Admin Instance ID: ${module.admin.admin_instance_id}
    Admin Instance IP: ${module.admin.admin_private_ip}

    Control Plane ID: ${module.compute.control_plane_id}
    Control Plane IP: ${module.compute.control_plane_private_ip}

    Worker Count: ${module.compute.worker_count}
    Worker IPs: ${join(", ", module.compute.worker_private_ip)}

    ═══════════════════════════════════════════════════════════
    PRIMARY ACCESS - ADMIN INSTANCE (kubectl pre-configured)
    ═══════════════════════════════════════════════════════════

    Prerequisites:
    - AWS CLI installed locally
    - Session Manager plugin: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
    - Proper IAM permissions for SSM

    Connect to Admin Instance:
      ${format("aws ssm start-session --target %s --region %s", module.admin.admin_instance_id, var.aws_region)}

    Run kubectl commands (kubeconfig already configured):

      Switch to ubuntu user (recommended):
        sudo su - ubuntu
        kubectl get nodes
        kubectl get pods -A

      Or use sudo directly:
        sudo kubectl get nodes
        sudo kubectl get pods -A

    Monitor admin setup logs:
      sudo tail -f /var/log/admin-setup.log

    ═══════════════════════════════════════════════════════════
    EMERGENCY DIRECT ACCESS TO NODES (via SSM)
    ═══════════════════════════════════════════════════════════

    Access Control Plane (for troubleshooting):
      ${format("aws ssm start-session --target %s --region %s", module.compute.control_plane_id, var.aws_region)}

    Monitor control plane setup logs:
      sudo tail -f /var/log/k8s-setup.log

    Access Worker Nodes (for troubleshooting):
      ${join("\n      ", [for id in module.compute.worker_id : format("aws ssm start-session --target %s --region %s", id, var.aws_region)])}

  EOT
    : <<-EOT
  EOT
  )
}
