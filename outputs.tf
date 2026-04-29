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

output "external_alb_dns" {
  description = "External ALB DNS — open directly in browser for app access"
  value       = module.loadbalancer.external_alb_dns
}

output "argocd_nip_host" {
  description = "ArgoCD nip.io hostname — use as SSM tunnel target host"
  value       = module.loadbalancer.argocd_nip_host
}

# ── Route53 approach outputs (commented out) ──────────────────────────────────
# output "public_zone_nameservers" {
#   description = "Point your domain registrar to these nameservers"
#   value       = module.loadbalancer.public_zone_nameservers
# }

output "argocd_admin_password" {
  description = "ArgoCD initial admin password"
  value       = var.deploy_argocd ? module.argocd[0].argocd_admin_password : "Available after Stage 2 (deploy_argocd=true)"
  sensitive   = true
}

output "argocd_access_info" {
  description = "How to access ArgoCD via SSM tunnel to internal NLB"
  value       = <<-EOT

    ═══════════════════════════════════════════════════════════
    ARGOCD ACCESS (via SSM tunnel to internal NLB → nginx)
    ═══════════════════════════════════════════════════════════

    ArgoCD sits behind an internal NLB — not reachable from the internet.
    nginx ingress routes /argocd → argocd-server pod (ClusterIP).

    Step 1 — On your laptop, open an SSM port-forward tunnel to the internal NLB:
      aws ssm start-session --target ${module.admin.admin_instance_id} \
        --document-name AWS-StartPortForwardingSessionToRemoteHost \
        --parameters '{"host":["${module.loadbalancer.argocd_nip_host}"],"portNumber":["80"],"localPortNumber":["8080"]}'

    Step 2 — Open ArgoCD in browser:
      http://localhost:8080

    Step 3 — Get ArgoCD admin password (run on admin EC2):
      kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' | base64 -d

    ═══════════════════════════════════════════════════════════
    APP ACCESS (external ALB, internet-facing)
    ═══════════════════════════════════════════════════════════

    App URL:  http://${module.loadbalancer.external_alb_dns}/
    (nip.io alt): get ALB IP with: dig +short ${module.loadbalancer.external_alb_dns}
                  then open: http://app.<ALB-IP>.nip.io

    ── Route53 approach (when domain is registered) ──────────
    App URL:  http://app.<your-domain>
    API URL:  http://api.<your-domain>
    Nameservers: terraform output public_zone_nameservers
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
