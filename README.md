# Private Kubernetes Cluster on AWS — DevSecOps

A fully automated, private Kubernetes cluster on AWS provisioned with Terraform and kubeadm. Features GitOps deployment via ArgoCD, AWS CCM-provisioned NLBs, and a security-focused CI/CD pipeline.

---

## Architecture

```
                        Internet
                            │
              ┌─────────────▼──────────────┐
              │     Public NLB (CCM)        │  ← app traffic only
              │       port 80               │
              └─────────────┬──────────────┘
                            │
              ┌─────────────▼──────────────┐
              │   ingress-nginx (public)    │
              │   routes: / → app           │
              └─────────────┬──────────────┘
                            │
              ┌─────────────▼──────────────────────────────┐
              │              Private Subnet                  │
              │                                             │
              │  ┌─────────────┐   ┌─────────────────────┐ │
              │  │  Admin EC2  │   │   K8s Worker Node   │ │
              │  │  (kubectl)  │   │   (app pods)        │ │
              │  └──────┬──────┘   └─────────────────────┘ │
              │         │                                   │
              │  ┌──────▼───────────────────────────────┐  │
              │  │        K8s Control Plane             │  │
              │  │        (10.0.10.100:6443)            │  │
              │  └──────────────────────────────────────┘  │
              │                                             │
              │  ┌──────────────────────────────────────┐  │
              │  │   Internal NLB (CCM) — VPC only       │  │
              │  │   ingress-nginx-internal → ArgoCD    │  │
              │  └──────────────────────────────────────┘  │
              └────────────────────────────────────────────┘
                            │
              ┌─────────────▼──────────────┐
              │       NAT Gateway          │
              │      (outbound only)       │
              └────────────────────────────┘
```

- All EC2 instances are in a **private subnet** — no public IPs
- Node access is via **AWS SSM Session Manager** only — no SSH, no open ports
- The Kubernetes API server is reachable **only from the admin EC2** (security group enforced)
- **Two CCM-provisioned NLBs**: public (app) and internal (ArgoCD)
- ArgoCD is **not internet-facing** — accessed via SSM tunnel through the admin EC2

---

## Full Architecture

### Phase 1 — Infrastructure Bootstrap (one-time, ~15 mins)

```
YOUR LAPTOP
───────────
terraform apply
    │
    ├──► AWS VPC + Subnets + NAT Gateway + Security Groups
    │
    ├──► Control Plane EC2 (boots, runs control-plane-setup.sh)
    │         │
    │         │  1. kubeadm init + Calico CNI
    │         │  2. Deploy AWS CCM (DaemonSet) — manages NLB lifecycle
    │         │  3. base64 encode kubeconfig
    │         │  4. aws ssm put-parameter
    │         │         └──► SSM Parameter Store
    │         │               ├── /k8s/K8s-Control-Plane/kubeconfig
    │         │               └── /k8s/K8s-Control-Plane/join-command
    │         │
    ├──► Worker EC2 (boots, runs worker-setup.sh)
    │         │
    │         │  1. aws ssm get-parameter (join-command)
    │         │  2. kubeadm join ──► joins cluster
    │         │
    └──► Admin EC2 (boots, runs admin-setup.sh)
              │
              │  1. aws ssm get-parameter (kubeconfig)
              │  2. saves to ~/.kube/config
              │  3. copies to kubeadm-infra/.terraform/kubeconfig
              │  4. waits for all nodes Ready
              │  5. waits for CCM to clear uninitialized taint
              │  6. terraform apply -var="deploy_argocd=true"
              │         │
              │         ├──► Helm ──► ArgoCD (ClusterIP)
              │         ├──► Helm ──► ingress-nginx (public NLB via CCM)
              │         ├──► Helm ──► ingress-nginx-internal (internal NLB via CCM)
              │         └──► kubectl apply ──► ArgoCD Application CR + Ingress
              │
              └──► Cluster is fully ready
```

---

### Phase 2 — CI/CD + GitOps Flow (every code push)

```
DEVELOPER
─────────
git push (k8s-app/** changed)
    │
    ▼
GitHub Actions Pipeline
    │
    ├── SonarQube SAST ──► scan source code
    ├── Hadolint       ──► scan Dockerfiles
    ├── Docker Build   ──► build images (SHA tagged)
    ├── Trivy          ──► scan container images
    ├── Docker Push    ──► Docker Hub
    │       └── <user>/go-backend:<sha>
    │       └── <user>/node-frontend:<sha>
    ├── OWASP ZAP      ──► DAST scan live frontend
    ├── DefectDojo     ──► upload all scan reports
    └── Kustomize Deploy
            │
            └──► kustomize edit set image go-backend:<sha>
                 kustomize edit set image node-frontend:<sha>
                        │
                        ▼
                 kubeadm-gitops repo
                 k8s-app/overlays/production/kustomization.yaml updated
                        │
                        ▼ (ArgoCD polls every 3 mins)
                 ArgoCD detects change
                        │
                        └── syncs cluster (rolling update, zero downtime)
```

---

### Phase 3 — Runtime Traffic Flow

```
                         INTERNET
                             │
               ┌─────────────▼──────────────────┐
               │    Public NLB (CCM-provisioned)  │
               │    port 80 — app traffic only    │
               └──────────────┬─────────────────┘
                              │
               ┌──────────────▼─────────────────┐
               │     ingress-nginx (public)      │
               │     / ──► app pods              │
               └─────────────────────────────────┘


               VPC-ONLY (not internet-routable)
               ┌─────────────────────────────────┐
               │  Internal NLB (CCM-provisioned) │
               │  port 80 — ArgoCD only          │
               └──────────────┬─────────────────┘
                              │
               ┌──────────────▼─────────────────┐
               │  ingress-nginx-internal         │
               │  / ──► argocd-server            │
               └─────────────────────────────────┘

               Developers reach ArgoCD via SSM tunnel:
               laptop ──► SSM ──► admin EC2 ──► internal NLB
```

---

## AWS Cloud Controller Manager (CCM)

CCM runs as a DaemonSet on the control plane and manages the NLB lifecycle automatically:

- When `ingress-nginx` creates a `Service type: LoadBalancer`, CCM calls the AWS API to provision an NLB
- When the service is deleted, CCM deletes the NLB
- The `service.beta.kubernetes.io/aws-load-balancer-internal: "true"` annotation tells CCM to provision a VPC-internal NLB (no public IP)

**Important — before running `terraform destroy`**, delete the LoadBalancer services first so CCM can clean up the NLBs. Otherwise the VPC subnet deletion will hang:

```bash
# Run on admin EC2 BEFORE terraform destroy
kubectl delete svc ingress-nginx-controller -n ingress-nginx
kubectl delete svc ingress-nginx-internal-controller -n ingress-nginx-internal
# Wait ~30s then run terraform destroy from your laptop
```

---

## Two-Stage Terraform

The K8s API server is a private IP unreachable from your laptop, so Terraform deployment is split:

**Stage 1 — run once from your laptop:**
```bash
terraform init
terraform apply
```
Creates VPC, subnets, NAT gateway, security groups, and all EC2 instances.

**Stage 2 — runs automatically on the admin EC2 via cloud-init:**

`admin-setup.sh` executes on first boot:
1. Waits for control plane to finish bootstrapping
2. Fetches kubeconfig from AWS SSM Parameter Store
3. Copies kubeconfig to `.terraform/kubeconfig` (required by Helm/K8s providers)
4. Runs `terraform apply -var="deploy_argocd=true" -target='module.argocd[0]'`

The admin EC2 is inside the VPC so it can reach `10.0.10.100:6443` — Helm and the Kubernetes provider work correctly from there.

---

## Project Structure

```
kubeadm/
├── main.tf                        # Root module — wires all modules together
├── variables.tf                   # All input variables
├── providers.tf                   # AWS, Helm, Kubernetes, Null providers
├── outputs.tf                     # Instance IDs, NLB hostnames, access info
├── data.tf                        # Data sources (AMI, AZs)
├── config/
│   └── terraform.tfvars           # Variable values
│
├── modules/
│   ├── vpc/                       # VPC, public/private subnets, NAT gateway
│   ├── security/                  # Security groups for K8s nodes and admin
│   ├── compute/                   # EC2: control plane + workers, IAM roles + CCM policy
│   ├── admin/                     # Admin EC2 — kubectl gateway, runs Stage 2
│   └── argocd/                    # ArgoCD + ingress-nginx (public + internal) via Helm
│
├── scripts/
│   ├── control-plane-setup.sh     # kubeadm init, CCM deploy, uploads kubeconfig to SSM
│   ├── worker-setup.sh            # kubeadm join via SSM Parameter Store
│   └── admin-setup.sh             # kubectl setup + CCM taint wait + Stage 2 deployment
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

Allow 10-15 minutes for full cluster bootstrap and ArgoCD deployment.

**Monitor progress:**
```bash
aws ssm start-session --target <admin_instance_id> --region us-east-1
sudo tail -f /var/log/admin-setup.log
```

---

## Access

### Application
```
http://<public-NLB-DNS>/
```

Get the public NLB DNS (on admin EC2):
```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### ArgoCD UI

ArgoCD is on an internal NLB — not internet-accessible. Access via SSM tunnel:

```bash
# Step 1 — get internal NLB DNS (on admin EC2)
kubectl get svc -n ingress-nginx-internal ingress-nginx-internal-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Step 2 — open SSM tunnel (on your laptop)
aws ssm start-session --target <admin_instance_id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<internal-NLB-DNS>"],"portNumber":["80"],"localPortNumber":["8080"]}'

# Step 3 — open in browser
http://localhost:8080
Username: admin
```

Get the admin password (on admin EC2):
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

**Always delete LoadBalancer services first** — CCM creates NLBs outside Terraform state. If you skip this, the VPC subnet deletion will hang indefinitely.

```bash
# Step 1 — on admin EC2
kubectl delete svc ingress-nginx-controller -n ingress-nginx
kubectl delete svc ingress-nginx-internal-controller -n ingress-nginx-internal

# Step 2 — wait ~30s for CCM to delete the NLBs, then on your laptop
terraform destroy
```

---

## CI/CD Pipeline

Triggers on pushes to `main` (or PRs) that modify `k8s-app/**` or the workflow file.

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
| ArgoCD isolation | Internal NLB only — not internet-facing, accessed via SSM tunnel |
| Public exposure | Public NLB port 80 (app only) — ArgoCD never exposed publicly |
| GitOps | Pull-based (ArgoCD pulls from GitHub) — nothing pushes into the cluster |
