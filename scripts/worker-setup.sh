#!/bin/bash
# Kubernetes Worker Node Setup Script
# This script runs automatically via cloud-init on instance launch

set -e

# Log output to a file for debugging
exec > >(tee /var/log/k8s-setup.log)
exec 2>&1

echo "Starting Kubernetes worker node setup..."

# Wait for NAT Gateway and internet connectivity
echo "Waiting for NAT Gateway and internet connectivity..."
max_attempts=60
attempt=0

# First, wait for network interface to be fully up
sleep 5

# Test both ping and actual package repository connectivity
while [ $attempt -lt $max_attempts ]; do
    attempt=$((attempt + 1))
    
    # Test 1: Ping Google DNS
    if ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; then
        # Test 2: Try to reach Ubuntu repos
        if curl -s --max-time 5 http://archive.ubuntu.com/ubuntu/ > /dev/null 2>&1; then
            echo "Internet connectivity established!"
            break
        fi
    fi
    
    if [ $attempt -ge $max_attempts ]; then
        echo "ERROR: No internet connectivity after $max_attempts attempts (10 minutes)"
        echo "Please check: NAT Gateway status, Route Tables, Security Groups"
        exit 1
    fi
    
    echo "Waiting for internet... attempt $attempt/$max_attempts"
    sleep 10
done

# Update and install prerequisites
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg conntrack awscli jq

# Add Kubernetes repository
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' > /etc/apt/sources.list.d/kubernetes.list

# Install kubeadm, kubelet, kubectl
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load kernel modules
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# Configure sysctl
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# Install and configure containerd
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# Create a marker file to indicate installation is complete
echo "Installation completed at $(date)" > /home/ubuntu/k8s-installation-complete.txt
chown ubuntu:ubuntu /home/ubuntu/k8s-installation-complete.txt

# Wait for control plane to be ready (max 10 minutes)
echo "Waiting for control plane to be ready..."
CONTROL_PLANE_IP="${control_plane_ip}"
MAX_RETRIES=60
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$CONTROL_PLANE_IP/6443" 2>/dev/null; then
    echo "Control plane is ready!"
    sleep 30  # Additional wait for cluster initialization
    break
  fi
  echo "Waiting for control plane... ($RETRY_COUNT/$MAX_RETRIES)"
  sleep 10
  RETRY_COUNT=$((RETRY_COUNT + 1))
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "ERROR: Control plane is not ready after waiting."
  exit 1
fi

# Retrieve join command from SSM Parameter Store
echo "Retrieving join command from SSM Parameter Store..."
MAX_SSM_RETRIES=30
SSM_RETRY_COUNT=0
JOIN_COMMAND=""

while [ $SSM_RETRY_COUNT -lt $MAX_SSM_RETRIES ]; do
  JOIN_COMMAND=$(aws ssm get-parameter \
    --name "/k8s/${control_plane_name}/join-command" \
    --with-decryption \
    --region "${aws_region}" \
    --query "Parameter.Value" \
    --output text 2>/dev/null)
  
  if [ -n "$JOIN_COMMAND" ] && [ "$JOIN_COMMAND" != "None" ]; then
    echo "Successfully retrieved join command from SSM!"
    break
  fi
  
  echo "Waiting for join command in SSM... ($SSM_RETRY_COUNT/$MAX_SSM_RETRIES)"
  sleep 10
  SSM_RETRY_COUNT=$((SSM_RETRY_COUNT + 1))
done

if [ -z "$JOIN_COMMAND" ] || [ "$JOIN_COMMAND" == "None" ]; then
  echo "ERROR: Failed to retrieve join command from SSM Parameter Store."
  echo "The control plane may not have finished initialization yet."
  exit 1
fi

# Construct the full private DNS FQDN that CCM uses to match nodes to EC2 instances.
# AWS CCM searches DescribeInstances with filter private-dns-name=<node-name> (exact match).
# The EC2 private DNS is always ip-X-X-X-X.ec2.internal (us-east-1) or
# ip-X-X-X-X.REGION.compute.internal (all other regions).
# We build it explicitly so we're not dependent on what local-hostname returns.
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
SHORT_HOSTNAME="ip-$(echo $PRIVATE_IP | tr '.' '-')"
if [ "$REGION" = "us-east-1" ]; then
    PRIVATE_DNS="$${SHORT_HOSTNAME}.ec2.internal"
else
    PRIVATE_DNS="$${SHORT_HOSTNAME}.$${REGION}.compute.internal"
fi
echo "Worker private DNS (constructed): $PRIVATE_DNS"

# Configure kubelet with external cloud provider and correct hostname
echo "KUBELET_EXTRA_ARGS=\"--cloud-provider=external --hostname-override=$PRIVATE_DNS\"" > /etc/default/kubelet
systemctl daemon-reload

# Parse token, API endpoint, and CA hash from the raw join command
# so we can build a kubeadm join config with the correct node name.
API_ENDPOINT=$(echo "$JOIN_COMMAND" | grep -oP '(?<=join )\S+')
TOKEN=$(echo "$JOIN_COMMAND" | grep -oP '(?<=--token )\S+')
CA_HASH=$(echo "$JOIN_COMMAND" | grep -oP '(?<=--discovery-token-ca-cert-hash )\S+')

if [ -z "$API_ENDPOINT" ] || [ -z "$TOKEN" ] || [ -z "$CA_HASH" ]; then
  echo "ERROR: Failed to parse join command. Raw value:"
  echo "$JOIN_COMMAND"
  exit 1
fi

cat > /tmp/kubeadm-join-config.yaml << EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
nodeRegistration:
  name: "$PRIVATE_DNS"
  kubeletExtraArgs:
    cloud-provider: external
    hostname-override: "$PRIVATE_DNS"
discovery:
  bootstrapToken:
    apiServerEndpoint: $API_ENDPOINT
    token: $TOKEN
    caCertHashes:
      - $CA_HASH
EOF

# Execute the join command
echo "Joining the Kubernetes cluster as $PRIVATE_DNS..."
kubeadm join --config /tmp/kubeadm-join-config.yaml

echo "Successfully joined the Kubernetes cluster!"
echo "Worker node setup completed at $(date)" > /home/ubuntu/k8s-cluster-join-complete.txt
chown ubuntu:ubuntu /home/ubuntu/k8s-cluster-join-complete.txt
echo "To join this node, SSH to the control plane, get the join command:"
echo "  cat /home/ubuntu/join-command.sh"
echo "Then SSH to this worker and run that command."

# Create a helper script for manual join
cat > /home/ubuntu/join-cluster.sh <<'JOINSCRIPT'
#!/bin/bash
echo "This worker is ready to join the cluster."
echo "Steps to join:"
echo "1. SSH to control plane: ${control_plane_ip}"
echo "2. Get join command: cat /home/ubuntu/join-command.sh"
echo "3. Copy that command and run it on this worker with sudo"
JOINSCRIPT
chmod +x /home/ubuntu/join-cluster.sh
chown ubuntu:ubuntu /home/ubuntu/join-cluster.sh

echo "Worker node setup completed!"
