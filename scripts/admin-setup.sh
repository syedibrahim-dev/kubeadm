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

# Install Terraform for ArgoCD deployment
echo "Installing Terraform..."
wget -q https://releases.hashicorp.com/terraform/1.10.5/terraform_1.10.5_linux_amd64.zip
unzip -q terraform_1.10.5_linux_amd64.zip -d /usr/local/bin/
rm terraform_1.10.5_linux_amd64.zip
chmod +x /usr/local/bin/terraform
terraform --version

# Add Kubernetes repository
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' > /etc/apt/sources.list.d/kubernetes.list

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
# Helper script to deploy ArgoCD using Terraform (Stage 2)
# Run this after the cluster is fully ready

set -e

echo "Deploying ArgoCD via Terraform (Stage 2)..."
cd /home/ubuntu/kubeadm-infra

# Copy kubeconfig so Helm/Kubernetes providers can reach the API server
mkdir -p .terraform
cp ~/.kube/config .terraform/kubeconfig
chown -R ubuntu:ubuntu .terraform
chmod 600 .terraform/kubeconfig

# Initialize Terraform and deploy only the ArgoCD module
terraform init
terraform apply -var="deploy_argocd=true" -target='module.argocd[0]' -auto-approve

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

# Wait for all worker nodes to be Ready
echo "Waiting for ${worker_count} worker node(s) to be Ready..."
expected_nodes=$((${worker_count} + 1))  # workers + control plane
max_wait=600  # 10 minutes max
elapsed=0

while true; do
    ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo "0")
    
    if [ "$ready_nodes" -ge "$expected_nodes" ]; then
        echo "All $expected_nodes nodes are Ready!"
        kubectl get nodes
        break
    fi
    
    if [ $elapsed -ge $max_wait ]; then
        echo "WARNING: Timeout waiting for nodes. Current ready: $ready_nodes, expected: $expected_nodes"
        echo "Proceeding with deployment anyway..."
        break
    fi
    
    echo "Waiting for nodes... ($ready_nodes/$expected_nodes ready, $${elapsed}s elapsed)"
    sleep 15
    elapsed=$((elapsed + 15))
done

# Wait for AWS CCM to initialize all nodes (removes uninitialized taint)
# Until CCM clears this taint, Helm pre-install hook pods cannot be scheduled.
echo "Waiting for AWS CCM to initialize all nodes..."
ccm_wait=300
ccm_elapsed=0
while kubectl get nodes -o json 2>/dev/null | grep -q "node.cloudprovider.kubernetes.io/uninitialized"; do
    if [ $ccm_elapsed -ge $ccm_wait ]; then
        echo "WARNING: CCM initialization timed out after $${ccm_wait}s. Proceeding anyway..."
        break
    fi

    # Print diagnostics every 30s so we know what's blocking
    if [ $(( ccm_elapsed % 30 )) -eq 0 ]; then
        echo "--- CCM pod status ---"
        kubectl get pods -n kube-system -l k8s-app=aws-cloud-controller-manager 2>/dev/null || true
        CCM_POD=$(kubectl get pods -n kube-system -l k8s-app=aws-cloud-controller-manager \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
        if [ -n "$CCM_POD" ]; then
            echo "--- CCM pod events ---"
            kubectl describe pod -n kube-system "$CCM_POD" 2>/dev/null | grep -A 20 "^Events:" || true
            echo "--- CCM logs ---"
            kubectl logs -n kube-system "$CCM_POD" --tail=15 2>/dev/null || true
        fi
        echo "--- Node taints ---"
        kubectl get nodes -o custom-columns="NAME:.metadata.name,TAINTS:.spec.taints" 2>/dev/null || true
        echo "---"
    fi

    echo "Waiting for CCM to clear uninitialized taint... ($${ccm_elapsed}s elapsed)"
    sleep 15
    ccm_elapsed=$((ccm_elapsed + 15))
done
echo "All nodes initialized by CCM. Ready for Helm deployments."

# Run ArgoCD Terraform deployment (Stage 2 — inside VPC, can reach API server)
echo ""
echo "Deploying ArgoCD via Terraform (Stage 2)..."
cd /home/ubuntu/kubeadm-infra

# Copy kubeconfig to ubuntu user's home (Terraform runs as ubuntu)
mkdir -p /home/ubuntu/.kube
cp /root/.kube/config /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube

# Copy kubeconfig into Terraform's path so Helm/Kubernetes providers can connect
# (API server is at 10.x.x.x:6443 — only reachable from inside the VPC)
mkdir -p /home/ubuntu/kubeadm-infra/.terraform
cp /root/.kube/config /home/ubuntu/kubeadm-infra/.terraform/kubeconfig
chown -R ubuntu:ubuntu /home/ubuntu/kubeadm-infra/.terraform
chmod 600 /home/ubuntu/kubeadm-infra/.terraform/kubeconfig

# Run as ubuntu user
if su - ubuntu -c "cd /home/ubuntu/kubeadm-infra && terraform init && terraform apply -var='deploy_argocd=true' -target='module.argocd[0]' -auto-approve" >> /var/log/argocd-deploy.log 2>&1; then
    echo "ArgoCD deployment completed successfully!"
    echo "ArgoCD deployed at $(date)" >> /home/ubuntu/admin-setup-complete.txt
    
    # Show access instructions
    echo ""
    echo "=========================================="
    echo "ArgoCD Access Information"
    echo "=========================================="
    echo "Get admin password:"
    echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    echo ""
    echo "Check application status:"
    echo "  kubectl get application k8s-app -n argocd"
else
    echo "WARNING: ArgoCD deployment failed. Check /var/log/argocd-deploy.log"
    echo "You can retry manually: /home/ubuntu/deploy-argocd.sh"
fi
%{ else }
echo ""
echo "Auto-deploy disabled. To deploy ArgoCD manually:"
echo "  /home/ubuntu/deploy-argocd.sh"
%{ endif }

echo ""
echo "Admin instance setup completed successfully!"