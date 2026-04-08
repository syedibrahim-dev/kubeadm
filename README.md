# Private Kubernetes Cluster on AWS — DevSecOps

A fully automated, private Kubernetes cluster on AWS provisioned with Terraform and kubeadm. Features GitOps deployment via ArgoCD, a public NLB for direct access, and a security-focused CI/CD pipeline with Kustomize-based deployments.

---

## Architecture

```
                        Internet
                            │
              ┌─────────────▼──────────────┐
              │   Network Load Balancer     │
              │       (public subnet)       │
              │   :80   → app              │
              │   :8080 → ArgoCD UI        │
              └─────────────┬──────────────┘
                            │
              ┌─────────────▼──────────────────────────────┐
              │              Private Subnet                 │
              │                                            │
              │  ┌──────────────┐  ┌─────────────────────┐ │
              │  │  Admin EC2   │  │   K8s Worker Node   │ │
              │  │  (kubectl)   │  │  :30080 ingress-nginx│ │
              │  └──────┬───────┘  │  :30082 ArgoCD      │ │
              │         │          └─────────────────────┘ │
              │  ┌──────▼───────────────────────────────┐  │
              │  │        K8s Control Plane             │  │
              │  │        (10.0.10.100:6443)            │  │
              │  └──────────────────────────────────────┘  │
              └────────────────────────────────────────────┘
                            │
              ┌─────────────▼──────────────┐
              │       NAT Gateway          │
              │      (outbound only)       │
              └────────────────────────────┘
```

- All EC2 instances are in a **private subnet** — no public IPs
- Node access is via **AWS SSM Session Manager** only — no SSH, no bastion
- The Kubernetes API server is reachable **only from the admin EC2** (security group enforced)
- The NLB exposes the app and ArgoCD UI publicly — no port-forwarding needed

---

## Two-Stage Terraform

The K8s API server is a private IP unreachable from your laptop, so Terraform deployment is split:

**Stage 1 — run once from your laptop:**
```bash
terraform apply
```
Creates VPC, subnets, NAT gateway, security groups, NLB, and all EC2 instances.

**Stage 2 — runs automatically on the admin EC2 via cloud-init:**

`admin-setup.sh` executes on first boot:
1. Waits for control plane to finish bootstrapping
2. Fetches kubeconfig from AWS SSM Parameter Store
3. Copies kubeconfig to `.terraform/kubeconfig` (required by Helm/K8s providers)
4. Runs `terraform apply -var="deploy_argocd=true" -target='module.argocd[0]'`

The admin EC2 is inside the VPC so it can reach `10.0.10.100:6443` — Helm and the Kubernetes provider work correctly from there.

---

## Kubernetes Bootstrap

Fully automated via `user_data` scripts — no manual steps:

| Component | Script | What it does |
|-----------|--------|--------------|
| Control Plane | `control-plane-setup.sh` | `kubeadm init`, installs Calico CNI, uploads kubeconfig + join command to SSM Parameter Store |
| Workers | `worker-setup.sh` | Reads join command from SSM, runs `kubeadm join` automatically |
| Admin | `admin-setup.sh` | Installs kubectl, fetches kubeconfig from SSM, runs Stage 2 Terraform |

---

## GitOps with Kustomize

Two repositories:

| Repo | Purpose |
|------|---------|
| `kubeadm` (this repo) | App source, Dockerfiles, CI/CD pipeline, Terraform infra |
| `kubeadm-gitops` | Kubernetes manifests managed by ArgoCD |

**GitOps repo structure:**
```
kubeadm-gitops/k8s-app/
├── base/                        # Shared manifests (never edited by CI/CD)
│   ├── 01-namespace.yaml
│   ├── 02-mongodb-hostpath.yaml
│   ├── 03-go-backend.yaml
│   ├── 04-react-frontend.yaml
│   ├── 05-ingress.yaml
│   └── kustomization.yaml
└── overlays/
    └── production/
        └── kustomization.yaml   ← CI/CD only ever touches this file
```

**Deployment flow:**
```
Developer pushes to k8s-app/ in kubeadm
         │
         ▼
GitHub Actions pipeline
  → SonarQube, Hadolint, Trivy, ZAP scans
  → builds & pushes SHA-tagged images to Docker Hub
  → kustomize edit set image → updates overlays/production/kustomization.yaml
         │
         ▼
ArgoCD detects kustomization change
  → renders base + overlay
  → syncs cluster (rolling update, zero downtime)
```

The pipeline only ever modifies one file (`kustomization.yaml`) instead of sed-patching raw YAML manifests.

---

## Project Structure

```
kubeadm/
├── main.tf                        # Root module — wires all modules together
├── variables.tf                   # All input variables
├── providers.tf                   # AWS, Helm, Kubernetes, Null providers
├── outputs.tf                     # NLB DNS, instance IDs, access URLs
├── data.tf                        # Data sources (AMI, AZs)
├── config/
│   └── terraform.tfvars           # Variable values
│
├── modules/
│   ├── vpc/                       # VPC, public/private subnets, NAT gateway
│   ├── security/                  # Security groups for K8s nodes and admin
│   ├── compute/                   # EC2: control plane + workers, IAM roles
│   ├── admin/                     # Admin EC2 — kubectl gateway, runs Stage 2
│   ├── nlb/                       # Public NLB → ingress-nginx + ArgoCD NodePorts
│   └── argocd/                    # ArgoCD + ingress-nginx via Helm (Stage 2 only)
│
├── scripts/
│   ├── control-plane-setup.sh     # kubeadm init, uploads kubeconfig to SSM
│   ├── worker-setup.sh            # kubeadm join via SSM Parameter Store
│   └── admin-setup.sh             # kubectl setup + Stage 2 ArgoCD deployment
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

## Deploy

```bash
terraform init
terraform apply
```

After apply completes, Terraform prints the access URLs:
```
app_url    = "http://k8s-nlb-xxxx.elb.amazonaws.com"
argocd_url = "http://k8s-nlb-xxxx.elb.amazonaws.com:8080"
```

Allow 10-15 minutes for full cluster bootstrap and ArgoCD deployment.

**Monitor progress:**
```bash
aws ssm start-session --target <admin_instance_id> --region us-east-1

sudo tail -f /var/log/admin-setup.log    # Stage 1 bootstrap
sudo tail -f /var/log/argocd-deploy.log  # Stage 2 ArgoCD Terraform
```

**Retry Stage 2 manually if needed:**
```bash
sudo -u ubuntu bash /home/ubuntu/deploy-argocd.sh
```

---

## Access

### Application
```
http://<nlb_dns>/
```

### ArgoCD UI
```
http://<nlb_dns>:8080
Username: admin
```

Get the admin password (on admin instance):
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

### kubectl
```bash
aws ssm start-session --target <admin_instance_id> --region us-east-1
sudo su - ubuntu
kubectl get nodes
kubectl get pods -A
```

---

## Destroy

```bash
terraform destroy
```

Helm/Kubernetes providers may log connection warnings during destroy — safe to ignore, all AWS resources are removed.

---

## CI/CD Pipeline

Triggers on pushes to `main` (or PRs) that modify `k8s-app/**` or the workflow file. Terraform and infra changes do not trigger it.

| Step | Tool | Type | Blocks pipeline? |
|------|------|------|-----------------|
| 1 | SonarQube | SAST | No — reports only |
| 2 | Hadolint | Dockerfile lint | No — reports only |
| 3 | Docker Build | Build | Yes |
| 4 | Trivy | Image CVE scan | No — reports only |
| 5 | Docker Push | Registry | Yes — main only |
| 6 | OWASP ZAP | DAST | No — reports only |
| 7 | DefectDojo | Upload | No — `if: always()` |
| 8 | Kustomize Deploy | GitOps | Yes — main only, after push |

Step 8 runs `kustomize edit set image` to update image tags in `overlays/production/kustomization.yaml` then pushes to `kubeadm-gitops`. ArgoCD picks up the change and syncs the cluster.

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
# Access: http://localhost:8080 — admin / admin
# API key: top-right user menu → API v2 Key

# Stop
docker compose -f defectdojo/docker-compose.yml down
```

---

## Security Design

| Control | Implementation |
|---------|---------------|
| No SSH | Port 22 closed on all instances |
| No public IPs | All EC2 in private subnet only |
| No bastion | AWS SSM Session Manager — IAM-authenticated, CloudTrail-logged |
| API server isolation | Only admin EC2 security group can reach port 6443 |
| Worker join | Automated via SSM Parameter Store — no manual token handling |
| Public exposure | NLB on ports 80 (app) and 8080 (ArgoCD) only |
| GitOps | Pull-based (ArgoCD pulls from GitHub) — nothing pushes into the cluster |
