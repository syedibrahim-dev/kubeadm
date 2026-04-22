#!/bin/bash
# Kubernetes Control Plane Setup Script
# This script runs automatically via cloud-init on instance launch

set -e

# Log output to a file for debugging
exec > >(tee /var/log/k8s-setup.log)
exec 2>&1

echo "Starting Kubernetes control plane setup..."

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
apt-get install -y apt-transport-https ca-certificates curl gpg conntrack awscli

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

# Wait for system to be ready
sleep 10

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
echo "Control plane private DNS (constructed): $PRIVATE_DNS"

# Configure kubelet with external cloud provider and correct hostname
echo "KUBELET_EXTRA_ARGS=\"--cloud-provider=external --hostname-override=$PRIVATE_DNS\"" > /etc/default/kubelet
systemctl daemon-reload

# Initialize Kubernetes cluster with external cloud provider
CONTROL_PLANE_IP="${control_plane_ip}"
cat > /tmp/kubeadm-init-config.yaml << EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
controlPlaneEndpoint: "$CONTROL_PLANE_IP"
networking:
  podSubnet: "192.168.0.0/16"
apiServer:
  extraArgs:
    cloud-provider: external
  certSANs:
    - "127.0.0.1"
    - "localhost"
    - "$CONTROL_PLANE_IP"
controllerManager:
  extraArgs:
    cloud-provider: external
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  name: "$PRIVATE_DNS"
  kubeletExtraArgs:
    cloud-provider: external
    hostname-override: "$PRIVATE_DNS"
EOF

kubeadm init --config /tmp/kubeadm-init-config.yaml

# Configure kubectl for ubuntu user
mkdir -p /home/ubuntu/.kube
cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube

# Configure kubectl for root
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config

# Install Calico CNI
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Deploy AWS Cloud Controller Manager
# CCM handles node lifecycle only: removes node.cloudprovider.kubernetes.io/uninitialized
# taint, sets node labels (zone/region), and manages routes.
# Load balancer provisioning is handled by AWS Load Balancer Controller (deployed in Stage 2).
# Must deploy CCM before workers join so the uninitialized taint is removed promptly.
# Key: tolerations must include node.cloudprovider.kubernetes.io/uninitialized
# so CCM itself can start even when nodes have that taint (chicken-and-egg fix).
echo "Deploying AWS Cloud Controller Manager..."
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f - <<'EOF'
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cloud-controller-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: system:cloud-controller-manager
rules:
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["create", "patch", "update"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["*"]
  - apiGroups: [""]
    resources: ["nodes/status"]
    verbs: ["patch"]
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["list", "patch", "update", "watch"]
  - apiGroups: [""]
    resources: ["services/status"]
    verbs: ["patch", "update"]
  - apiGroups: [""]
    resources: ["serviceaccounts"]
    verbs: ["create", "get", "list", "watch", "update"]
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "update", "watch"]
  - apiGroups: [""]
    resources: ["endpoints"]
    verbs: ["create", "get", "list", "watch", "update"]
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["create", "get", "list", "watch", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:cloud-controller-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:cloud-controller-manager
subjects:
  - kind: ServiceAccount
    name: cloud-controller-manager
    namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: system:cloud-controller-manager:extension-apiserver-authentication-reader
  namespace: kube-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: extension-apiserver-authentication-reader
subjects:
  - kind: ServiceAccount
    name: cloud-controller-manager
    namespace: kube-system
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: aws-cloud-controller-manager
  namespace: kube-system
  labels:
    k8s-app: aws-cloud-controller-manager
spec:
  selector:
    matchLabels:
      k8s-app: aws-cloud-controller-manager
  template:
    metadata:
      labels:
        k8s-app: aws-cloud-controller-manager
    spec:
      nodeSelector:
        node-role.kubernetes.io/control-plane: ""
      tolerations:
        - key: node.cloudprovider.kubernetes.io/uninitialized
          value: "true"
          effect: NoSchedule
        - key: node-role.kubernetes.io/control-plane
          effect: NoSchedule
      hostNetwork: true
      serviceAccountName: cloud-controller-manager
      priorityClassName: system-cluster-critical
      containers:
        - name: aws-cloud-controller-manager
          image: registry.k8s.io/provider-aws/cloud-controller-manager:v1.31.1
          args:
            - --v=2
            - --cloud-provider=aws
            - --cluster-name=kubeadm-cluster
            - --configure-cloud-routes=false
          resources:
            requests:
              cpu: 200m
              memory: 128Mi
EOF

echo "AWS CCM deployed. Waiting for it to start..."
kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout status daemonset/aws-cloud-controller-manager -n kube-system --timeout=120s || true

# Generate join command and save it
kubeadm token create --print-join-command > /home/ubuntu/join-command.sh
chmod +x /home/ubuntu/join-command.sh
chown ubuntu:ubuntu /home/ubuntu/join-command.sh

# Store join command in AWS SSM Parameter Store for workers to retrieve
echo "Storing join command in SSM Parameter Store..."
JOIN_COMMAND=$(cat /home/ubuntu/join-command.sh)
aws ssm put-parameter \
  --name "/k8s/${control_plane_name}/join-command" \
  --value "$JOIN_COMMAND" \
  --type "SecureString" \
  --overwrite \
  --region "${aws_region}" || echo "Warning: Failed to store join command in SSM"

# Store kubeconfig in AWS SSM Parameter Store for local kubectl access
# Use file-based base64 encoding to prevent corruption
echo "Storing kubeconfig in SSM Parameter Store..."
base64 -w 0 /etc/kubernetes/admin.conf > /tmp/kubeconfig.b64
KUBECONFIG_BASE64=$(cat /tmp/kubeconfig.b64)
rm -f /tmp/kubeconfig.b64

aws ssm put-parameter \
  --name "/k8s/${control_plane_name}/kubeconfig" \
  --value "$KUBECONFIG_BASE64" \
  --type "SecureString" \
  --tier "Advanced" \
  --overwrite \
  --region "${aws_region}" || echo "Warning: Failed to store kubeconfig in SSM"

echo "Kubeconfig stored successfully (size: $${#KUBECONFIG_BASE64} bytes base64 encoded)"

# Wait a moment for Parameter Store to propagate
echo "Waiting for Parameter Store propagation..."
sleep 5

# Create a marker file to indicate setup is complete
echo "Setup completed at $(date)" > /home/ubuntu/k8s-setup-complete.txt

echo "Control plane setup completed successfully!"
echo "Join command stored in SSM Parameter Store: /k8s/${control_plane_name}/join-command"
echo "Kubeconfig stored in SSM Parameter Store: /k8s/${control_plane_name}/kubeconfig"
