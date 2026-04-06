# Zero-Trust Private Kubernetes Cluster on AWS with Admin Gateway

## Overview

This Terraform project deploys a **fully automated, zero-trust Kubernetes cluster** in AWS with:
- **No SSH keys** - eliminated completely
- **No open port 22** - zero inbound network access
- **No bastion host** - cost-effective and secure
- **AWS SSM access only** - IAM-auditable terminal access
- **Dedicated Admin instance** - centralized kubectl gateway with pre-configured access
- **Network-enforced security** - Control plane API only accessible from Admin instance via security groups
- **Automated worker join** - workers join cluster automatically via SSM Parameter Store
- **CI/CD pipeline** - GitHub Actions with SonarQube, Hadolint, Trivy, OWASP ZAP, DefectDojo
- **GitOps deployment** - ArgoCD with separate GitOps repository (industry best practice)
- **DefectDojo integration** - centralized security findings dashboard

## Architecture Design

### Zero-Trust Security Model
- All EC2 instances in **private subnets only** (no public IPs anywhere)
- **No internet-facing resources** (no bastion, no load balancers)
- **No inbound ports open** - not even SSH port 22
- **Admin instance as mandatory gateway** - only instance allowed to access Kubernetes API (port 6443)
- **Security group enforcement** - AWS firewall rules prevent any other instance from reaching control plane
- Access via **AWS Systems Manager (SSM)** with IAM authentication
- All access attempts logged in **CloudTrail** for auditing

### How It Works
1. **IAM Roles**: All EC2 instances have `AmazonSSMManagedInstanceCore` policy attached
2. **SSM Agent**: Pre-installed on Ubuntu AMI, establishes outbound-only connection to AWS
3. **Admin Gateway**: Dedicated private EC2 instance with kubectl pre-configured
4. **Security Groups**: Control plane only accepts port 6443 connections from Admin instance's security group
5. **Emergency Access**: Use `aws ssm start-session` for terminal access (no SSH needed)
6. **Daily Operations**: Connect to Admin instance via SSM, run kubectl commands directly
7. **Automated Join**: Control plane stores join command in SSM Parameter Store (base64 encoded), workers automatically retrieve and execute it

## GitOps Architecture

This project follows **industry-standard GitOps practices** with ArgoCD and a separate GitOps repository:

```
┌─────────────────────────────────────────────────────────────────────┐
│                           INTERNET                                   │
│                              │                                       │
│    ┌─────────────────────────┴─────────────────────────┐            │
│    │                      GitHub                        │            │
│    │                                                    │            │
│    │   ┌─────────────────┐      ┌───────────────────┐  │            │
│    │   │    kubeadm      │      │  kubeadm-gitops   │  │            │
│    │   │   (this repo)   │      │  (manifest repo)  │  │            │
│    │   │                 │      │                   │  │            │
│    │   │ • App source    │      │ • K8s manifests   │  │            │
│    │   │ • Dockerfiles   │      │ • Deployment YAML │  │            │
│    │   │ • CI/CD config  │      │ • Service configs │  │            │
│    │   │ • Terraform     │      │                   │  │            │
│    │   └────────┬────────┘      └─────────┬─────────┘  │            │
│    │            │                         │            │            │
│    └────────────┼─────────────────────────┼────────────┘            │
│                 │                         │                          │
│                 │ CI/CD pushes            │ ArgoCD pulls             │
│                 │ image tags              │ manifests                │
│                 │                         │                          │
│                 ▼                         ▼                          │
│    ┌────────────────────────────────────────────────────┐           │
│    │                  NAT Gateway                        │           │
│    │              (outbound only)                        │           │
│    └────────────────────────┬───────────────────────────┘           │
│                             │                                        │
│    ┌────────────────────────▼───────────────────────────┐           │
│    │           Private Kubernetes Cluster                │           │
│    │                                                     │           │
│    │   ┌─────────────┐    ┌──────────────────────────┐  │           │
│    │   │   ArgoCD    │───▶│     Application Pods     │  │           │
│    │   │  (GitOps)   │    │  • Go Backend            │  │           │
│    │   │             │    │  • React Frontend        │  │           │
│    │   │ Watches:    │    │  • MongoDB               │  │           │
│    │   │ kubeadm-    │    └──────────────────────────┘  │           │
│    │   │ gitops repo │                                  │           │
│    │   └─────────────┘                                  │           │
│    │                                                     │           │
│    │   ✅ Zero inbound access                           │           │
│    │   ✅ Pull-based GitOps (ArgoCD pulls, never push)  │           │
│    │   ✅ Git as single source of truth                 │           │
│    │   ✅ Automatic sync on manifest changes            │           │
│    │                                                     │           │
│    └─────────────────────────────────────────────────────┘           │
└──────────────────────────────────────────────────────────────────────┘
```

### Why Separate Repositories?

| Aspect | Benefit |
|--------|---------|
| **Security** | Code repo keeps branch protection; GitOps repo allows automated pushes |
| **Separation of Concerns** | Application code ≠ Deployment configuration |
| **Audit Trail** | Every deployment is a Git commit with full history |
| **Disaster Recovery** | Cluster dies? Repo is safe. New cluster syncs automatically |
| **Multi-Cluster** | Same GitOps repo can deploy to dev/staging/prod clusters |

### Repository Structure

**This Repository (`kubeadm`):**
```
├── k8s-app/backend/      # Go application source
├── k8s-app/frontend/     # React application source
├── .github/workflows/    # CI/CD pipeline
├── modules/              # Terraform infrastructure
└── ...
```

**GitOps Repository (`kubeadm-gitops`):**
```
└── k8s-app/k8s/
    ├── 01-namespace.yaml
    ├── 02-mongodb-hostpath.yaml
    ├── 03-go-backend.yaml
    ├── 04-react-frontend.yaml
    └── 04-ingress.yaml
```

### Deployment Flow

```
1. Developer pushes code to kubeadm repo
                    ↓
2. GitHub Actions runs CI/CD pipeline:
   • SonarQube SAST scan
   • Hadolint Dockerfile lint
   • Docker build & push to Docker Hub
   • Trivy vulnerability scan
   • OWASP ZAP DAST scan
   • DefectDojo report upload
                    ↓
3. Pipeline updates image tags in kubeadm-gitops repo
                    ↓
4. ArgoCD detects changes (watches kubeadm-gitops)
                    ↓
5. ArgoCD syncs cluster automatically (rolling update)
                    ↓
6. Zero-downtime deployment complete! ✅
```

## Project Structure

```
.
├── main.tf                      # Module orchestration (purely module calls, no hardcoded logic)
├── providers.tf                 # AWS + null provider configuration
├── data.tf                      # Data sources (availability zones, AMI, account ID)
├── variables.tf                 # Root-level variable definitions
├── outputs.tf                   # Root-level outputs
├── modules/                     # Reusable modules
│   ├── vpc/                     # VPC, subnets, NAT, routing
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── security/                # Security groups (admin + k8s nodes)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── admin/                   # Admin kubectl gateway instance
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── compute/                 # K8s nodes with IAM roles for SSM
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── scripts/                     # Automation scripts (run via cloud-init)
│   ├── control-plane-setup.sh  # Auto-install K8s on control plane
│   ├── worker-setup.sh          # Auto-install K8s on workers
│   └── admin-setup.sh           # Auto-configure kubectl + bootstrap k8s-app from Git
├── k8s-app/                     # Application source + admin bootstrap scripts
│   ├── deploy.sh                # Deploy script (run on admin instance)
│   ├── backend/                 # Go REST API (multi-stage → ~20MB distroless)
│   │   ├── main.go
│   │   ├── go.mod
│   │   └── Dockerfile
│   ├── frontend/                # React SPA (4-stage → ~15MB nginx:alpine)
│   │   ├── src/
│   │   ├── index.html
│   │   ├── package.json
│   │   ├── vite.config.js
│   │   ├── nginx.conf
│   │   └── Dockerfile
│   └── argocd/
│       └── argocd-app.yaml      # ArgoCD application manifest (points to kubeadm-gitops)
├── config/
│   └── terraform.tfvars        # Configuration values
├── .github/
│   └── workflows/
│       └── ci-cd.yml            # CI/CD pipeline (Hadolint + Semgrep + Trivy + ZAP + DefectDojo)
├── defectdojo/
│   └── docker-compose.yml      # Self-hosted DefectDojo (security findings dashboard)
└── README.md                    # This file
```


## Configuration

Edit `config/terraform.tfvars` to customize. Variables are organized into logical groups:

**VPC Configuration:**
```hcl
vpc = {
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidr  = "10.0.1.0/24"  # Used for NAT Gateway only
  private_subnet_cidr = "10.0.10.0/24"
}
```

**Compute Configuration:**
```hcl
compute = {
  control_plane_instance_type = "t3.medium"
  worker_instance_type        = "t3.medium"
  worker_count                = 2           
  control_plane_private_ip    = "10.0.10.100"
  control_plane_name          = "K8s-Control-Plane"
  worker_name                 = "K8s-Worker"
}
```

**Admin Instance Configuration:**
```hcl
admin = {
  instance_type = "t3.micro"
  admin_name    = "K8s-Admin"
}
```

**Note:** No SSH keys or bastion configuration needed!


## Usage

### Initialize Terraform

```bash
terraform init
```

### Plan the deployment

```bash
terraform plan -var-file="config/terraform.tfvars"
```

### Apply the configuration

```bash
terraform apply -var-file="config/terraform.tfvars"
```
### Destroy the infrastructure

```bash
terraform destroy -var-file="config/terraform.tfvars"
```

## Deploying the Application

The `k8s-app/` folder contains a **React + Go + MongoDB** stack demonstrating multi-stage Docker builds:
- **Go backend**: `golang:1.22-alpine` → `distroless/static-debian12` (~800MB → ~20MB)
- **React frontend**: `node:18` → `nginx:alpine` (~1.25GB → ~15MB) — 4-stage build
- **MongoDB**: `mongo:7.0` with hostPath persistence

Routing via nginx ingress: `/ → react-frontend:80`, `/api → go-backend:8080`

### Step 1 — Build and push Docker images (local machine, once)

```bash
# Go backend
docker build --platform linux/amd64 -t <YOUR_DOCKERHUB_USER>/go-backend:latest ./k8s-app/backend
docker push <YOUR_DOCKERHUB_USER>/go-backend:latest

# React frontend (multi-stage — builds through all 4 stages, final image is ~15MB)
docker build --platform linux/amd64 -t <YOUR_DOCKERHUB_USER>/node-frontend:latest ./k8s-app/frontend
docker push <YOUR_DOCKERHUB_USER>/node-frontend:latest
```

Then update the image names in the manifests:
- `kubeadm-gitops/k8s-app/k8s/03-go-backend.yaml` → `image: <YOUR_DOCKERHUB_USER>/go-backend:latest`
- `kubeadm-gitops/k8s-app/k8s/04-react-frontend.yaml` → `image: <YOUR_DOCKERHUB_USER>/node-frontend:latest`

#### Frontend multi-stage size comparison

The frontend Dockerfile has 4 named stages. Use `--target` to stop at any stage and compare sizes:

```bash
# Stage 3 — node:18 + node_modules + source + dist (~1.25 GB)
docker build --target builder    -t frontend:bloated   ./k8s-app/frontend

# Stage 4 — nginx:alpine + compiled dist only (~15 MB)
docker build --target production -t frontend:optimised ./k8s-app/frontend

docker images | grep frontend
```

### Step 2 — Apply infrastructure (Git bootstrap is automatic)

```bash
terraform apply -var-file="config/terraform.tfvars"
```

Terraform will:
1. Create all infrastructure (VPC, EC2, IAM roles, security groups, NAT)
2. Bootstrap admin instance with kubectl + kubeconfig via SSM
3. Clone `${github_repo}` with sparse checkout (`k8s-app/`) on admin instance
4. Run `k8s-app/deploy.sh` to install ArgoCD and register the GitOps app

If auto-deploy is disabled, deploy manually from the admin instance:

```bash
aws ssm start-session --target <ADMIN_INSTANCE_ID> --region us-east-1
sudo su - ubuntu
cd ~/k8s-app && bash deploy.sh
```

### Step 3 — Deploy on the admin instance

```bash
# Connect to admin instance
aws ssm start-session --target <ADMIN_INSTANCE_ID> --region us-east-1

# Switch to ubuntu (kubeconfig + k8s-app are here)
sudo su - ubuntu

# Deploy the full stack
cd ~/k8s-app && bash deploy.sh
```

`deploy.sh` installs nginx ingress + ArgoCD, registers the `k8s-app` ArgoCD application, and waits for workload readiness after initial sync.

## Outputs

After applying, Terraform outputs:
- **Admin instance ID** (primary access point for kubectl)
- Control plane and worker instance IDs (for emergency troubleshooting)
- Private IPs of all instances
- SSM Session Manager commands
- Complete setup instructions
- Security architecture summary

## Prerequisites

1. **AWS CLI** installed locally: `aws --version`
2. **Terraform >= 1.3** installed: `terraform --version`
   - Providers used: `hashicorp/aws ~> 6.0`, `hashicorp/null ~> 3.0`
3. **Docker** installed locally (for building images): `docker --version`
4. **Session Manager Plugin** installed:
   - Instructions: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
5. **IAM Permissions** to use SSM:
   - `ssm:StartSession`
   - `ssm:TerminateSession`
   - `ec2:DescribeInstances`

## Access Pattern (Admin Gateway)

### Primary Access - kubectl via Admin Instance

**This is your main way to interact with the cluster:**

**Step 1:** Connect to Admin Instance via SSM
```bash
aws ssm start-session --target <ADMIN_INSTANCE_ID> --region us-east-1
```

**Step 2:** Switch to ubuntu user (kubeconfig pre-configured)
```bash
sudo su - ubuntu
```

**Step 3:** Run kubectl commands
```bash
kubectl get nodes
kubectl get pods -A
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort
kubectl get svc
```

**Why this approach?**
- kubectl already configured and ready to use
- kubeconfig automatically retrieved from Parameter Store during setup
- Network security enforced - only Admin instance can reach control plane API
- No port forwarding complexity
- No local kubeconfig management

### Emergency Terminal Access (Troubleshooting Only)

**Access Control Plane directly:**
```bash
aws ssm start-session --target <CONTROL_PLANE_INSTANCE_ID> --region us-east-1
```

**Monitor setup logs:**
```bash
sudo tail -f /var/log/k8s-setup.log
```

**Check cluster status:**
```bash
sudo kubectl get nodes
sudo kubectl get pods -A
```

**Access Worker Node directly:**
```bash
aws ssm start-session --target <WORKER_INSTANCE_ID> --region us-east-1
```

**Note:** Direct access to control plane/workers is for troubleshooting only. Normal operations should go through Admin instance.

## Kubernetes Setup

**Fully Automated Process (~10-15 minutes):**

**Control Plane (5-8 minutes):**
1. Kubernetes packages installed (kubeadm, kubelet, kubectl, containerd)
2. System configured (swap disabled, kernel modules, sysctl)
3. Control plane initialized with Calico CNI
4. kubectl configured for ubuntu user
5. Join command generated and stored in AWS SSM Parameter Store (base64 encoded)
6. Kubeconfig stored in AWS SSM Parameter Store (base64 encoded)

**Admin Instance (2-3 minutes):**
1. kubectl installed
2. Waits for kubeconfig to be available in Parameter Store
3. Retrieves and decodes kubeconfig
4. Configures kubectl for ubuntu, root, and ssm-user
5. Waits for control plane API to be fully ready
6. Tests connectivity and displays cluster status

**Workers (3-5 minutes):**
1. Kubernetes packages installed
2. System configured
3. **Automatically retrieve join command from SSM Parameter Store**
4. **Automatically join the cluster**

**What's Different from Traditional Setup:**
- No manual `kubeadm join` commands needed
- No copying join tokens between machines
- No SSH between control plane and workers
- No manual kubeconfig copying to admin instance
- Everything automated via AWS SSM Parameter Store with base64 encoding for data integrity

**Monitoring the automated setup:**

1. Connect to admin instance via SSM (recommended):
   ```bash
   aws ssm start-session --target <ADMIN_INSTANCE_ID> --region us-east-1
   ```

2. Watch the admin setup progress:
   ```bash
   sudo tail -f /var/log/admin-setup.log
   ```

3. Once complete, switch to ubuntu and use kubectl:
   ```bash
   sudo su - ubuntu
   kubectl get nodes
   kubectl get pods -A
   ```

4. Monitor control plane (if needed):
   ```bash
   aws ssm start-session --target <CONTROL_PLANE_ID> --region us-east-1
   sudo tail -f /var/log/k8s-setup.log
   ```

5. Monitor worker join progress:
   ```bash
   aws ssm start-session --target <WORKER_ID> --region us-east-1
   sudo tail -f /var/log/k8s-setup.log
   ```

## Architecture Benefits

### Security
- **Zero inbound ports** - not even SSH port 22 is open
- **No SSH keys to manage** - eliminates key rotation, storage, and compromise risks
- **IAM-based access control** - leverage AWS IAM for authentication and authorization
- **CloudTrail auditing** - all SSM sessions logged for compliance
- **TLS encrypted sessions** - SSM uses TLS 1.2+ with AWS managed certificates
- **Network-enforced access control** - Security groups prevent direct control plane access
- **Mandatory gateway pattern** - Admin instance is the only path to Kubernetes API
- **Defense in depth** - Multiple security layers (IAM + SSM + Security Groups + Private networking)

### Operational
- **No bastion maintenance** - no patching, no monitoring, minimal overhead
- **Simple kubectl workflow** - kubectl just works on admin instance, no port forwarding needed
- **Fully automated** - from infrastructure to cluster setup to worker join to admin configuration
- **Reproducible** - infrastructure as code with zero manual steps
- **Centralized management** - Single admin instance for all kubectl operations
- **Base64 encoding** - Prevents kubeconfig corruption during Parameter Store storage/retrieval

### Cost
- **Minimal overhead** - Only one t3.micro admin instance (~$7/month)
- **No bastion Elastic IP** - no charge for public IP (~$3.60/month savings vs traditional bastion)
- **Pay only for what you use** - SSM sessions cost nothing extra
- **Efficient design** - Admin instance also serves as troubleshooting gateway

## Security Architecture Deep Dive

### Network-Enforced Access Control

The admin gateway pattern enforces security at the **network layer** via AWS Security Groups:

**Admin Instance Security Group (`admin_sg`):**
```
Inbound:  NONE (access via SSM only)
Outbound: ALL (can reach internet, control plane API, SSM endpoints)
```

**Kubernetes Nodes Security Group (`k8s_nodes_sg`):**
```
Inbound:
  - Port 6443 (Kubernetes API) from admin_sg ONLY
  - All ports from self (inter-node communication)
Outbound: ALL
```

## CI/CD Pipeline

The project includes a **GitHub Actions pipeline** (`.github/workflows/ci-cd.yml`) that runs on every push to `main` and on pull requests.

### Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CI/CD Pipeline Flow                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐  │
│  │   Step   │   │   Step   │   │   Step   │   │   Step   │   │   Step   │  │
│  │    1     │──▶│    2     │──▶│    3     │──▶│    4     │──▶│    5     │  │
│  │          │   │          │   │          │   │          │   │          │  │
│  │ SonarQube│   │ Hadolint │   │  Docker  │   │  Trivy   │   │  Docker  │  │
│  │   SAST   │   │   Lint   │   │  Build   │   │   Scan   │   │   Push   │  │
│  └──────────┘   └──────────┘   └──────────┘   └──────────┘   └──────────┘  │
│                                                                    │         │
│                                                                    ▼         │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐◀──────────────────────┘         │
│  │   Step   │   │   Step   │   │   Step   │                                 │
│  │    8     │◀──│    7     │◀──│    6     │                                 │
│  │          │   │          │   │          │                                 │
│  │  GitOps  │   │ DefectDojo   │ OWASP ZAP│                                 │
│  │  Deploy  │   │  Upload  │   │   DAST   │                                 │
│  └────┬─────┘   └──────────┘   └──────────┘                                 │
│       │                                                                      │
│       ▼                                                                      │
│  ┌─────────────────────────────────────┐                                    │
│  │  Push updated image tags to         │                                    │
│  │  kubeadm-gitops repository          │──────▶ ArgoCD auto-syncs cluster  │
│  └─────────────────────────────────────┘                                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Pipeline Jobs

| Step | Tool | Type | What it does |
|------|------|------|--------------|
| 1 | **SonarQube** | SAST | Static analysis of Go + React source code |
| 2 | **Hadolint** | Dockerfile Lint | Checks Dockerfiles for bad practices |
| 3 | **Docker Build** | Build | Builds multi-stage images, saves as artifacts |
| 4 | **Trivy** | Image Scan | Scans container images for CVEs |
| 5 | **Docker Push** | Push | Pushes SHA-tagged images to Docker Hub |
| 6 | **OWASP ZAP** | DAST | Live baseline scan against running frontend |
| 7 | **DefectDojo** | Upload | Pushes all scan reports to DefectDojo |
| 8 | **GitOps Deploy** | Deploy | Updates image tags in `kubeadm-gitops` repo |

### Required GitHub Secrets

Go to **Settings → Secrets and variables → Actions** in your GitHub repo:

| Secret | Description |
|--------|-------------|
| `SONAR_TOKEN` | SonarQube/SonarCloud authentication token |
| `SONAR_HOST_URL` | SonarQube URL (e.g., `https://sonarcloud.io`) |
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token ([create one here](https://hub.docker.com/settings/security)) |
| `DEFECTDOJO_URL` | DefectDojo base URL (e.g., `http://your-server:8080`) |
| `DEFECTDOJO_API_KEY` | DefectDojo API key (get from DefectDojo → API v2 Key) |

> **Note:** The GitOps deploy step uses `GITHUB_TOKEN` (automatically provided) to push to `kubeadm-gitops`.

## DefectDojo Setup

DefectDojo is a self-hosted security findings dashboard that aggregates all scan results in one place.

### Start DefectDojo

```bash
docker compose -f defectdojo/docker-compose.yml up -d
```

Wait ~2 minutes for initialization, then access:
- **URL:** http://localhost:8080
- **Login:** `admin` / `admin` (change after first login)

### Get the API Key

1. Log in to DefectDojo
2. Navigate to **API v2 Key** (top-right user menu, or http://localhost:8080/api/key-v2)
3. Copy the token
4. Add it as `DEFECTDOJO_API_KEY` in your GitHub Secrets

### How Findings Appear

All scan results are uploaded under:
- **Product:** `k8s-app`
- **Engagement:** `CI/CD Pipeline`

Each pipeline run creates individual test entries:
- `Hadolint Backend - <commit SHA>`
- `Hadolint Frontend - <commit SHA>`
- `Semgrep Backend SAST - <commit SHA>`
- `Semgrep Frontend SAST - <commit SHA>`
- `Trivy Backend Image - <commit SHA>`
- `Trivy Frontend Image - <commit SHA>`
- `Trivy K8s Config - <commit SHA>`
- `OWASP ZAP DAST - <commit SHA>`

### Stop DefectDojo

```bash
# Stop (preserves data)
docker compose -f defectdojo/docker-compose.yml down

# Full reset (deletes all data)
docker compose -f defectdojo/docker-compose.yml down -v
```



## ArgoCD Setup

ArgoCD is deployed inside the cluster and manages all application deployments via GitOps.

### Installation (via deploy.sh)

ArgoCD is automatically installed when you run the deploy script on the Admin instance:

```bash
# Connect to Admin instance
aws ssm start-session --target <ADMIN_INSTANCE_ID> --region us-east-1

# Switch to ubuntu user
sudo su - ubuntu

# Run deploy script (installs NGINX Ingress + ArgoCD + registers app)
./k8s-app/deploy.sh
```

### ArgoCD Application Configuration

ArgoCD watches the `kubeadm-gitops` repository:

```yaml
# k8s-app/argocd/argocd-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: k8s-app
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/syedibrahim-dev/kubeadm-gitops.git
    targetRevision: main
    path: k8s-app/k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: test-app
  syncPolicy:
    automated:
      prune: true      # Delete resources removed from Git
      selfHeal: true   # Revert manual changes back to Git state
```

### Access ArgoCD Dashboard

```bash
# On Admin instance, port-forward the ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8443:443 &

# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Then use SSM port forwarding from your local machine
aws ssm start-session --target <ADMIN_INSTANCE_ID> \
  --document-name AWS-StartPortForwardingSession \
  --parameters 'portNumber=8443,localPortNumber=8443'

# Access: https://localhost:8443
# Login: admin / <password from above>
```

### Verify GitOps Sync

```bash
# Check ArgoCD application status
kubectl get application k8s-app -n argocd

# View sync status
kubectl get application k8s-app -n argocd -o jsonpath='{.status.sync.status}'

# View which repo ArgoCD is watching
kubectl get application k8s-app -n argocd -o jsonpath='{.spec.source.repoURL}'
# Should output: https://github.com/syedibrahim-dev/kubeadm-gitops.git
```

### Manual Sync (if needed)

```bash
# Force a sync
kubectl patch application k8s-app -n argocd --type=merge \
  -p '{"operation":{"initiatedBy":{"username":"manual"},"sync":{"revision":"main"}}}'

# Or use ArgoCD CLI
argocd app sync k8s-app
```

## Setting Up the GitOps Repository

If you're setting up from scratch, create the `kubeadm-gitops` repository:

### 1. Create Repository on GitHub

```bash
# Go to https://github.com/new
# Name: kubeadm-gitops
# Visibility: Public (or Private with appropriate access)
# Do NOT add README (we'll push content)
```

### 2. Initialize with Manifests

```bash
# Clone the empty repo
git clone https://github.com/<YOUR_USERNAME>/kubeadm-gitops.git
cd kubeadm-gitops

# Create directory structure
mkdir -p k8s-app/k8s

# Copy manifests from this repo
cp ~/kubeadm/k8s-app/k8s/*.yaml k8s-app/k8s/

# Create README
cat > README.md << 'README'
# kubeadm-gitops

GitOps repository for Kubernetes deployments. Managed by ArgoCD.

## Structure

```
k8s-app/k8s/
├── 01-namespace.yaml
├── 02-mongodb-hostpath.yaml
├── 03-go-backend.yaml
├── 04-react-frontend.yaml
└── 04-ingress.yaml
```

## How It Works

1. CI/CD pipeline in `kubeadm` builds and tests the application
2. On successful merge to `main`, pipeline updates image tags here
3. ArgoCD detects changes and syncs the cluster automatically
README

# Commit and push
git add .
git commit -m "Initial commit: Add Kubernetes manifests"
git push origin main
```

### 3. Ensure No Branch Protection

**Important:** The `kubeadm-gitops` repository should NOT have branch protection on `main`. This allows the CI/CD pipeline to push updated image tags automatically.

Go to: `https://github.com/<YOUR_USERNAME>/kubeadm-gitops/settings/branches`
- Ensure no protection rules are set on `main`

## Troubleshooting

### ArgoCD can't reach GitHub

If ArgoCD fails to sync, verify outbound connectivity:

```bash
# On a pod in the cluster
kubectl run test --rm -it --image=alpine -- wget -qO- https://github.com
```

Your NAT Gateway should allow outbound HTTPS traffic.

### Image tags not updating

Check the CI/CD pipeline logs in GitHub Actions. Common issues:
- Missing `GITHUB_TOKEN` permissions
- Branch protection on `kubeadm-gitops` (should be disabled)
- Incorrect repository name in workflow

### ArgoCD sync stuck

```bash
# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Force refresh
kubectl patch application k8s-app -n argocd --type=merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```
