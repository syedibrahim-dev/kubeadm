#!/bin/bash
# Admin Instance Setup Script
# This script runs automatically via cloud-init on instance launch

set -e

# Log output to a file for debugging
exec > >(tee /var/log/admin-setup.log)
exec 2>&1

echo "Starting Admin instance setup..."

# Wait for internet connectivity (NAT Gateway to be ready)
echo "Waiting for internet connectivity..."
max_attempts=30
attempt=0
while ! ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ $attempt -ge $max_attempts ]; then
        echo "ERROR: No internet connectivity after $max_attempts attempts (5 minutes)"
        exit 1
    fi
    echo "Waiting for internet... attempt $attempt/$max_attempts"
    sleep 10
done
echo "Internet connectivity established!"

# Update and install prerequisites
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg awscli unzip git

# Install Terraform (Terragrunt delegates to it internally)
echo "Installing Terraform ${terraform_version}..."
wget -q https://releases.hashicorp.com/terraform/${terraform_version}/terraform_${terraform_version}_linux_amd64.zip
unzip -q terraform_${terraform_version}_linux_amd64.zip -d /usr/local/bin/
rm terraform_${terraform_version}_linux_amd64.zip
chmod +x /usr/local/bin/terraform
terraform --version

# Install Terragrunt (Stage 2 orchestration — wraps Terraform)
echo "Installing Terragrunt ${terragrunt_version}..."
wget -q https://github.com/gruntwork-io/terragrunt/releases/download/v${terragrunt_version}/terragrunt_linux_amd64 -O /usr/local/bin/terragrunt
chmod +x /usr/local/bin/terragrunt
terragrunt --version

# Add Kubernetes repository
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${k8s_version}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${k8s_version}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list

# Install kubectl only (no kubelet or kubeadm needed)
apt-get update
apt-get install -y kubectl
apt-mark hold kubectl

# ==========================================
# BULLETPROOF KUBECONFIG & API WAIT LOOP
# ==========================================
echo "Waiting for valid Kubeconfig and API Server readiness..."
max_attempts=60
attempt=0

while true; do
    attempt=$((attempt + 1))
    
    # 1. Fetch the latest parameter on every loop
    if aws ssm get-parameter --name "/k8s/${control_plane_name}/kubeconfig" \
        --with-decryption --query 'Parameter.Value' --output text \
        --region "${aws_region}" > /tmp/kubeconfig.b64 2>/dev/null; then
        
        # 2. Decode it
        if base64 -d /tmp/kubeconfig.b64 > /tmp/kubeconfig 2>/dev/null; then
            
            # 3. THE CRITICAL FIX: Test the config against the live API server
            if kubectl --kubeconfig=/tmp/kubeconfig cluster-info > /dev/null 2>&1; then
                echo "Success! API Server is ready and Kubeconfig is fresh!"
                rm -f /tmp/kubeconfig.b64
                break
            else
                echo "Found kubeconfig, but API rejected it (likely stale). Waiting for Control Plane to upload new keys..."
            fi
        fi
    fi
    
    if [ $attempt -ge $max_attempts ]; then
        echo "ERROR: Could not get a working connection after $max_attempts attempts."
        exit 1
    fi
    
    sleep 10
done

# ==========================================
# APPLY CONFIGURATION TO USERS
# ==========================================
echo "Distributing valid kubeconfig to local users..."

# Configure for ubuntu
mkdir -p /home/ubuntu/.kube
cp /tmp/kubeconfig /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube
chmod 600 /home/ubuntu/.kube/config

# Configure for root
mkdir -p /root/.kube
cp /tmp/kubeconfig /root/.kube/config
chmod 600 /root/.kube/config

# Configure for ssm-user (the default SSM user)
mkdir -p /home/ssm-user/.kube
cp /tmp/kubeconfig /home/ssm-user/.kube/config
chown -R ssm-user:ssm-user /home/ssm-user/.kube 2>/dev/null || true
chmod 600 /home/ssm-user/.kube/config

rm -f /tmp/kubeconfig

# ==========================================
# CLONE k8s-app FROM GITHUB
# ==========================================
echo "Cloning kubeadm repository for bootstrap files..."
cd /home/ubuntu

# Install git if not present
apt-get install -y git >/dev/null 2>&1

# Clone the repository (only k8s-app directory)
if git clone --depth 1 --filter=blob:none --sparse https://github.com/${github_repo}.git; then
    cd kubeadm
    git sparse-checkout set k8s-app
    
    # Move k8s-app to ubuntu home and cleanup
    mv k8s-app /home/ubuntu/
    cd /home/ubuntu
    rm -rf kubeadm
    
    chown -R ubuntu:ubuntu /home/ubuntu/k8s-app
    chmod +x /home/ubuntu/k8s-app/deploy.sh
    echo "k8s-app cloned successfully from GitHub"
else
    echo "ERROR: Failed to clone repository. Check network and repo access."
    exit 1
fi

# Clone infrastructure repository for ArgoCD Terraform deployment
echo "Cloning infrastructure repository..."
cd /home/ubuntu
if [ ! -d "kubeadm-infra" ]; then
    git clone https://github.com/${github_repo}.git kubeadm-infra
    chown -R ubuntu:ubuntu /home/ubuntu/kubeadm-infra
    echo "Infrastructure repository cloned to /home/ubuntu/kubeadm-infra"
else
    echo "Infrastructure repository already exists at /home/ubuntu/kubeadm-infra"
fi

# Create helper script for ArgoCD deployment
cat > /home/ubuntu/deploy-argocd.sh << 'DEPLOY_SCRIPT'
#!/bin/bash
# Helper script to deploy ArgoCD using Terragrunt (Stage 2)
# Run this after the cluster is fully ready

set -e

echo "Deploying ArgoCD via Terragrunt (Stage 2)..."
STAGE2_DIR="/home/ubuntu/kubeadm-infra/live/dev/argocd"

# ── Wait for all nodes to be Ready ──────────────────────────────────────────
echo "Checking node readiness before deploying..."
max_wait=300
elapsed=0
while true; do
  not_ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready" | wc -l || echo "99")
  total=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
  if [ "$total" -gt 0 ] && [ "$not_ready" -eq 0 ]; then
    echo "All $total nodes are Ready."
    break
  fi
  if [ $elapsed -ge $max_wait ]; then
    echo "WARNING: Timed out waiting for nodes. Proceeding anyway..."
    break
  fi
  echo "Waiting for nodes... ($elapsed/$max_wait s)"
  sleep 15
  elapsed=$((elapsed + 15))
done

# ── Wait for CCM to clear the uninitialized taint ───────────────────────────
# Until CCM removes this taint, Helm pre-install hook pods cannot be scheduled
# and helm_release.nginx_ingress will time out and roll back.
echo "Waiting for AWS CCM to initialize all nodes..."
ccm_elapsed=0
while kubectl get nodes -o json 2>/dev/null | grep -q "node.cloudprovider.kubernetes.io/uninitialized"; do
  if [ $ccm_elapsed -ge 300 ]; then
    echo "WARNING: CCM taint wait timed out after 300s. Proceeding anyway..."
    break
  fi
  echo "CCM still initializing nodes... ($ccm_elapsed/300s)"
  sleep 15
  ccm_elapsed=$((ccm_elapsed + 15))
done
echo "All nodes initialized. Proceeding with Terragrunt deployment."

# Kubeconfig is already at ~/.kube/config — Terragrunt reads it via pathexpand()
# in live/dev/stage2/argocd/terragrunt.hcl. No manual copy needed.
cd "$STAGE2_DIR"
terragrunt apply --non-interactive -auto-approve

echo ""
echo "ArgoCD deployment complete!"
echo ""
echo "Get ArgoCD admin password:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "Check ArgoCD application status:"
echo "  kubectl get application k8s-app -n argocd"
echo ""
DEPLOY_SCRIPT

chmod +x /home/ubuntu/deploy-argocd.sh
chown ubuntu:ubuntu /home/ubuntu/deploy-argocd.sh

# Create a marker file to indicate setup is complete
echo "Setup completed at $(date)" > /home/ubuntu/admin-setup-complete.txt

# ==========================================
# AUTOMATIC ARGOCD DEPLOYMENT
# ==========================================
%{ if enable_auto_deploy }
echo ""
echo "=========================================="
echo "AUTOMATIC ARGOCD DEPLOYMENT ENABLED"
echo "=========================================="
echo "Handing off to deploy-argocd.sh..."

# deploy-argocd.sh already handles:
#   1. Wait for all nodes Ready
#   2. Wait for CCM to clear the uninitialized taint
#   3. terragrunt apply for live/dev/stage2/argocd
# Run it as ubuntu so Terragrunt resolves ~ to /home/ubuntu/.kube/config
if su - ubuntu -c "bash /home/ubuntu/deploy-argocd.sh"; then
    echo "ArgoCD deployed at $(date)" >> /home/ubuntu/admin-setup-complete.txt
else
    echo "WARNING: ArgoCD deployment failed."
    echo "Logs: /var/log/admin-setup.log"
    echo "Retry anytime: su - ubuntu -c 'bash /home/ubuntu/deploy-argocd.sh'"
fi
%{ else }
echo ""
echo "Auto-deploy disabled. To deploy ArgoCD manually:"
echo "  su - ubuntu -c 'bash /home/ubuntu/deploy-argocd.sh'"
%{ endif }

echo ""
echo "Admin instance setup completed successfully!"
