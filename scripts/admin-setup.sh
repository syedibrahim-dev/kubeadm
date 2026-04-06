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
apt-get install -y apt-transport-https ca-certificates curl gpg awscli

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
# DOWNLOAD k8s-app FROM S3
# ==========================================
echo "Downloading k8s-app from S3 bucket: ${s3_bucket_name}..."
mkdir -p /home/ubuntu/k8s-app

if aws s3 ls s3://${s3_bucket_name}/k8s-app/ --region ${aws_region} > /dev/null 2>&1; then
    aws s3 sync s3://${s3_bucket_name}/k8s-app/ /home/ubuntu/k8s-app/ \
        --region ${aws_region} --delete
    chown -R ubuntu:ubuntu /home/ubuntu/k8s-app
    # Make deploy script executable if present
    [ -f /home/ubuntu/k8s-app/deploy.sh ] && chmod +x /home/ubuntu/k8s-app/deploy.sh
    echo "k8s-app downloaded successfully to /home/ubuntu/k8s-app/"
else
    echo "WARNING: No k8s-app found in S3 yet. Run upload-app.sh from your local machine first."
    echo "  aws s3 sync ./k8s-app/ s3://${s3_bucket_name}/k8s-app/ --region ${aws_region}"
fi

# Create a marker file to indicate setup is complete
echo "Setup completed at $(date)" > /home/ubuntu/admin-setup-complete.txt

# ==========================================
# AUTOMATIC APPLICATION DEPLOYMENT
# ==========================================
%{ if enable_auto_deploy }
echo ""
echo "=========================================="
echo "AUTOMATIC DEPLOYMENT ENABLED"
echo "=========================================="

# Check if k8s-app was downloaded successfully
if [ -f /home/ubuntu/k8s-app/deploy.sh ]; then
    
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
        
        echo "Waiting for nodes... ($ready_nodes/$expected_nodes ready, ${elapsed}s elapsed)"
        sleep 15
        elapsed=$((elapsed + 15))
    done
    
    # Run deploy.sh
    echo ""
    echo "Running deploy.sh..."
    cd /home/ubuntu/k8s-app
    
    # Run as ubuntu user but with root's kubeconfig (already set up)
    if /home/ubuntu/k8s-app/deploy.sh >> /var/log/k8s-deploy.log 2>&1; then
        echo "Deployment completed successfully!"
        echo "Deployment completed at $(date)" >> /home/ubuntu/admin-setup-complete.txt
    else
        echo "WARNING: deploy.sh exited with error. Check /var/log/k8s-deploy.log"
        echo "You can retry manually: cd /home/ubuntu/k8s-app && ./deploy.sh"
    fi
else
    echo "WARNING: /home/ubuntu/k8s-app/deploy.sh not found. Skipping auto-deploy."
    echo "Make sure k8s-app is uploaded to S3 first."
fi
%{ else }
echo ""
echo "Auto-deploy disabled. To deploy manually:"
echo "  cd /home/ubuntu/k8s-app && ./deploy.sh"
%{ endif }

echo ""
echo "Admin instance setup completed successfully!"