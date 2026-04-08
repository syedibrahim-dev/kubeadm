# Private Kubernetes Cluster on AWS — DevSecOps

A fully automated, private Kubernetes cluster on AWS provisioned with Terraform and kubeadm. Features GitOps deployment via ArgoCD, a public-facing NLB for zero-friction access, and a security-focused CI/CD pipeline.

---

## Architecture

```
                        Internet
                            │
              ┌─────────────▼──────────────┐
              │   Network Load Balancer     │
              │   (public subnet)           │
              │   :80  → app               │
              │   :8080 → ArgoCD UI        │
              └─────────────┬──────────────┘
                            │
              ┌─────────────▼──────────────────────────────┐
              │           Private Subnet                    │
              │                                            │
              │  ┌─────────────┐   ┌────────────────────┐  │
              │  │   Admin EC2 │   │  K8s Worker Node   │  │
              │  │  (kubectl)  │   │  ingress-nginx :30080  │
              │  │             │   │  ArgoCD      :30082 │  │
              │  └──────┬──────┘   └────────────────────┘  │
              │         │                                   │
              │  ┌──────▼──────────────────────────────┐   │
              │  │        K8s Control Plane             │   │
              │  │        (10.0.10.100:6443)            │   │
              │  └──────────────────────────────────────┘   │
              │                                            │
              └────────────────────────────────────────────┘
                            │
              ┌─────────────▼──────────────┐
              │       NAT Gateway          │
              │   (outbound only)          │
              └────────────────────────────┘
```

- All EC2 instances are in a **private subnet** — no public IPs anywhere
- Access to instances is via **AWS SSM Session Manager** only (no SSH, no bastion)
- The Kubernetes API server is **only reachable from the admin EC2** (enforced by security groups)
- The NLB in the public subnet exposes the app and ArgoCD without port-forwarding

---

## How It Works

### Two-Stage Terraform

The cluster is private, so the Kubernetes API is unreachable from your laptop. Terraform deployment is split into two stages:

**Stage 1 — run locally:**
```bash
terraform apply
```
Creates: VPC, subnets, NAT gateway, security groups, EC2 instances (control plane, workers, admin).

**Stage 2 — runs automatically on the admin EC2 (cloud-init):**

`admin-setup.sh` runs on first boot and:
1. Waits for the control plane to finish bootstrapping
2. Fetches the kubeconfig from AWS SSM Parameter Store
3. Copies it into the Terraform working directory
4. Runs `terraform apply -var="deploy_argocd=true" -target='module.argocd[0]'`

Since the admin EC2 is **inside the VPC**, it can reach `10.0.10.100:6443` — so Helm and the Kubernetes provider work correctly.

### Kubernetes Bootstrap

All cluster setup is fully automated via `user_data` scripts:

| Component | Script | What it does |
|-----------|--------|--------------|
| Control Plane | `control-plane-setup.sh` | `kubeadm init`, installs Calico CNI, uploads kubeconfig + join command to SSM Parameter Store |
| Workers | `worker-setup.sh` | Fetches join command from SSM, runs `kubeadm join` automatically |
| Admin | `admin-setup.sh` | Installs kubectl, fetches kubeconfig from SSM, deploys ArgoCD via Terraform |

### GitOps Deployment

Two repositories:

| Repo | Purpose |
|------|---------|
| `kubeadm` (this repo) | App source code, Dockerfiles, CI/CD pipeline, Terraform infrastructure |
| `kubeadm-gitops` | Kubernetes manifests watched by ArgoCD |

```
Developer pushes to kubeadm
         │
         ▼
GitHub Actions CI/CD pipeline
  → builds & scans images
  → pushes images to Docker Hub
  → updates image tags in kubeadm-gitops
         │
         ▼
ArgoCD detects manifest changes
  → auto-syncs cluster (rolling update)
```

---

## Project Structure

```
kubeadm/
├── main.tf                        # Root module — wires all modules together
├── variables.tf                   # All input variables
├── providers.tf                   # AWS, Helm, Kubernetes, Null providers
├── outputs.tf                     # Outputs (NLB DNS, instance IDs, access info)
├── data.tf                        # Data sources (AMI, AZs)
├── config/
│   └── terraform.tfvars           # Variable values
│
├── modules/
│   ├── vpc/                       # VPC, public/private subnets, NAT gateway
│   ├── security/                  # Security groups for K8s nodes and admin
│   ├── compute/                   # EC2: control plane + workers (IAM, user_data)
│   ├── admin/                     # Admin EC2 (kubectl gateway, runs Stage 2)
│   ├── nlb/                       # Public NLB → ingress-nginx + ArgoCD NodePorts
│   └── argocd/                    # ArgoCD + ingress-nginx via Helm (Stage 2 only)
│
├── scripts/
│   ├── control-plane-setup.sh     # kubeadm init, uploads kubeconfig to SSM
│   ├── worker-setup.sh            # kubeadm join via SSM Parameter Store
│   └── admin-setup.sh             # kubectl setup + auto Stage 2 Terraform deploy
│
├── k8s-app/
│   ├── backend/                   # Go REST API (CRUD + health), MongoDB
│   └── frontend/                  # React + Vite, served by nginx:alpine
│
├── defectdojo/
│   └── docker-compose.yml         # Self-hosted security findings dashboard
│
└── .github/workflows/
    └── ci-cd.yml                  # 8-step CI/CD pipeline
```

---

## Prerequisites

- **AWS CLI** with credentials configured
- **Terraform >= 1.3**
- **Session Manager Plugin** — [install guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
- IAM permissions: `ssm:StartSession`, `ec2:DescribeInstances`, and standard Terraform permissions

---

## Usage

### Deploy

```bash
terraform init
terraform apply
```

Terraform prints the NLB DNS and access URLs when complete:

```
app_url    = "http://k8s-nlb-xxxx.elb.amazonaws.com"
argocd_url = "http://k8s-nlb-xxxx.elb.amazonaws.com:8080"
```

Monitor automated setup progress (allow 10-15 minutes):

```bash
# Connect to admin instance
aws ssm start-session --target <admin_instance_id> --region us-east-1

# Watch Stage 1 bootstrap (kubeconfig fetch, kubectl setup)
sudo tail -f /var/log/admin-setup.log

# Watch Stage 2 (ArgoCD Terraform deployment)
sudo tail -f /var/log/argocd-deploy.log
```

### Access ArgoCD

No port-forwarding needed — the NLB exposes ArgoCD directly:

```
http://<nlb_dns>:8080
Username: admin
```

Get the password (on admin instance):
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

### Access the Application

```
http://<nlb_dns>/
```

### kubectl (on admin instance)

```bash
aws ssm start-session --target <admin_instance_id> --region us-east-1
sudo su - ubuntu
kubectl get nodes
kubectl get pods -A
```

### Destroy

```bash
terraform destroy
```

> **Note:** During destroy, Helm/Kubernetes providers may log connection warnings since the cluster is torn down before provider cleanup. These are safe to ignore — all AWS resources are still removed.

---

## CI/CD Pipeline

The pipeline runs on pushes to `main` (or PRs) that change files under `k8s-app/` or the workflow file itself. Infra-only changes do not trigger it.

| Step | Tool | Type | Blocks pipeline? |
|------|------|------|-----------------|
| 1 | SonarQube | SAST | No (reports only) |
| 2 | Hadolint | Dockerfile lint | No (reports only) |
| 3 | Docker Build | Build | Yes (build failure stops pipeline) |
| 4 | Trivy | Image CVE scan | No (reports only) |
| 5 | Docker Push | Push | Yes — main branch only |
| 6 | OWASP ZAP | DAST | No (reports only) |
| 7 | DefectDojo | Upload | No — `if: always()` |
| 8 | GitOps Deploy | Deploy | Yes — main branch only, after push |

All scan reports are aggregated in DefectDojo under product `k8s-app`, engagement `CI/CD Pipeline`.

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `SONAR_TOKEN` | SonarQube authentication token |
| `SONAR_HOST_URL` | SonarQube server URL |
| `DOCKERHUB_USERNAME` | Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token |
| `DEFECTDOJO_URL` | DefectDojo base URL |
| `DEFECTDOJO_API_KEY` | DefectDojo API v2 key |
| `GITOPS_TOKEN` | GitHub PAT with repo write access to `kubeadm-gitops` |

---

## DefectDojo (Local)

```bash
# Start
docker compose -f defectdojo/docker-compose.yml up -d

# Access at http://localhost:8080 — admin / admin
# Get API key: top-right user menu → API v2 Key

# Stop
docker compose -f defectdojo/docker-compose.yml down
```

---

## Security Design

| Control | Implementation |
|---------|---------------|
| No SSH | Port 22 not open anywhere |
| No public IPs | All EC2 in private subnet |
| No bastion | SSM Session Manager handles terminal access |
| API server access | Only admin EC2 security group can reach port 6443 |
| Node access | SSM only — all sessions logged in CloudTrail |
| Worker join | Automated via SSM Parameter Store (no manual token copying) |
| Public exposure | NLB exposes only ports 80 and 8080 (app + ArgoCD) |
