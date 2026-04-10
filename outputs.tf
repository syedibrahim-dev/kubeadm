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

# ArgoCD Information (only available after admin instance deploys it)
# These outputs will be visible when running terraform on the admin instance
# output "argocd_namespace" {
#   description = "Namespace where ArgoCD is deployed"
#   value       = module.argocd.argocd_namespace
# }
# 
# output "argocd_application" {
#   description = "ArgoCD application name managing the k8s-app"
#   value       = module.argocd.argocd_application_name
# }

output "app_url_command" {
  description = "Command to get the NLB DNS name provisioned by AWS CCM for ingress-nginx"
  value       = "kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "argocd_access_info" {
  description = "How to access ArgoCD after deployment"
  value       = <<-EOT

    ═══════════════════════════════════════════════════════════
    ARGOCD ACCESS (After Auto-Deployment)
    ═══════════════════════════════════════════════════════════

    ArgoCD is an admin tool — access it via port-forward from the admin EC2.

    1. Connect to admin EC2:
       aws ssm start-session --target ${module.admin.admin_instance_id}

    2. Port-forward ArgoCD (run on admin EC2):
       kubectl port-forward svc/argocd-server -n argocd 8080:80

    3. In a second SSM session, use SSM port forwarding to reach it locally:
       aws ssm start-session --target ${module.admin.admin_instance_id} \
         --document-name AWS-StartPortForwardingSession \
         --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
       Then open: http://localhost:8080

    4. Get ArgoCD admin password:
       kubectl -n argocd get secret argocd-initial-admin-secret \
         -o jsonpath='{.data.password}' | base64 -d

    5. Check application sync status:
       kubectl get application k8s-app -n argocd

    ═══════════════════════════════════════════════════════════
    APP ACCESS (via CCM-provisioned NLB)
    ═══════════════════════════════════════════════════════════

    Get the NLB DNS name (available ~2 min after ingress-nginx deploys):
      kubectl get svc -n ingress-nginx ingress-nginx-controller \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
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
        kubectl create deployment nginx --image=nginx
      
      Or use sudo directly:
        sudo kubectl get nodes
        sudo kubectl get pods -A

    Monitor admin setup logs:
      sudo tail -f /var/log/admin-setup.log

    ═══════════════════════════════════════════════════════════
    DEPLOY YOUR APPLICATION
    ═══════════════════════════════════════════════════════════

    The cluster is set up with automatic deployment!
    
    - ArgoCD is automatically installed
    - Application manifests are synced from: ${var.github_repo}
    - GitOps pipeline updates image tags in kubeadm-gitops repo
    
    To manually re-deploy (if needed):
      ${format("aws ssm start-session --target %s --region %s", module.admin.admin_id, var.aws_region)}
      cd ~/k8s-app && bash deploy.sh

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

