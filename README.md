# Private Kubernetes Cluster on AWS — DevSecOps

A fully automated, private Kubernetes cluster on AWS provisioned with Terraform and kubeadm. Features GitOps deployment via ArgoCD, nginx ingress with AWS CCM-provisioned NLB, a Terraform-managed external ALB, and a security-focused CI/CD pipeline.

---

## Architecture Overview

```
                          Internet
                              │
              ┌───────────────▼────────────────┐
              │     External ALB (Terraform)    │  ← app traffic only
              │     port 80, internet-facing    │  ← /argocd* blocked (fixed-response 404)
              │     spans public subnets AZ1+AZ2│
              └───────────────┬────────────────┘
                              │ IP targets (NLB private IPs)
              ┌───────────────▼────────────────┐
              │   Internal NLB (CCM-provisioned)│  ← private subnets, VPC-only
              │   nginx LoadBalancer service    │
              └───────────────┬────────────────┘
                              │ NodePort (dynamic, 30000-32767)
              ┌───────────────▼────────────────┐
              │     ingress-nginx controller    │  ← routes by URL path
              │                                │
              │   /          → app pods         │
              │   /argocd    → argocd-server    │  ← VPC-only (whitelist enforced)
              └────────────────────────────────┘

              ┌──────────────────────────────────────────────────────┐
              │   AZ1 — Private Subnet (10.0.10.0/24)                │
              │                                                      │
              │  ┌─────────────┐  ┌──────────────┐  ┌────────────┐  │
              │  │  Admin EC2  │  │  K8s Worker  │  │  Control   │  │
              │  │ 10.0.10.246 │  │    Node(s)   │  │   Plane    │  │
              │  │  (kubectl)  │  │              │  │ 10.0.10.100│  │
              │  └─────────────┘  └──────────────┘  └────────────┘  │
              └──────────────────────────────────────────────────────┘
              ┌──────────────────────────────────────────────────────┐
              │   AZ2 — Private Subnet (10.0.11.0/24)                │
              │   (ALB/NLB subnets only — no K8s nodes here)         │
              └──────────────────────────────────────────────────────┘
                              │
              ┌───────────────▼────────────────┐
              │          NAT Gateway            │
              │         (outbound only)         │
              └─────────────────────────────────┘
```

- All EC2 instances are in **private subnets** — no public IPs
- Node access is via **AWS SSM Session Manager** only — no SSH, no open ports
- The Kubernetes API server is reachable **only from the admin EC2** (security group enforced)
- **ingress-nginx** handles all in-cluster HTTP routing; **AWS CCM** auto-provisions the internal NLB
- The **external ALB** is a pure Terraform resource — wired to the NLB's private IPs as IP targets
- ArgoCD is **not internet-facing** — blocked at ALB and whitelist-restricted at nginx; accessed via SSM tunnel only

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
    │         │  2. Deploy AWS CCM (DaemonSet)
    │         │     - removes uninitialized taint on nodes
    │         │     - sets zone/region labels
    │         │     - watches LoadBalancer services → provisions NLB
    │         │  3. Uploads kubeconfig + join command to SSM Parameter Store
    │         │
    ├──► Worker EC2(s) (boot, run worker-setup.sh)
    │         │
    │         │  1. Fetch join command from SSM Parameter Store
    │         │  2. kubeadm join → joins cluster
    │         │
    └──► Admin EC2 (boots, runs admin-setup.sh)
              │
              │  1. Fetches kubeconfig from SSM Parameter Store
              │  2. Waits for all nodes Ready + CCM taint cleared
              │  3. terraform apply -var="deploy_argocd=true" -target='module.argocd[0]'
              │         │
              │         ├──► Helm ──► ingress-nginx (type: LoadBalancer)
              │         │               └──► CCM detects service → provisions internal NLB
              │         │               └──► wait_for_nlb polls until NLB hostname appears
              │         │
              │         ├──► Terraform ──► External ALB + Target Group + Listener
              │         │               └──► register_nlb_targets: discovers NLB IPs via
              │         │                    AWS CLI → registers as ALB IP targets
              │         │
              │         ├──► Helm ──► ArgoCD (ClusterIP, server.rootpath=/argocd)
              │         │
              │         └──► kubectl apply ──► ArgoCD Application CR
              │                               ArgoCD nginx Ingress (/argocd, Prefix, no rewrite)
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
    ├── SonarQube SAST  ──► scan source code
    ├── Hadolint        ──► scan Dockerfiles
    ├── Docker Build    ──► build images (SHA tagged)
    ├── Trivy           ──► scan container images
    ├── Docker Push     ──► Docker Hub
    │       └── <user>/go-backend:<sha>
    │       └── <user>/node-frontend:<sha>
    ├── OWASP ZAP       ──► DAST scan live frontend
    ├── DefectDojo      ──► upload all scan reports
    └── Kustomize Deploy
            │
            └──► kustomize edit set image go-backend:<sha>
                 kustomize edit set image node-frontend:<sha>
                        │
                        ▼
                 kubeadm-gitops repo updated
                 k8s-app/overlays/production/kustomization.yaml
                        │
                        ▼ (ArgoCD polls every 3 mins)
                 ArgoCD detects change → syncs cluster (rolling update, zero downtime)
```

---

### Phase 3 — Runtime Traffic Flow

```
                          INTERNET
                              │
              ┌───────────────▼────────────────┐
              │     External ALB (Terraform)    │
              │     internet-facing, port 80    │
              │                                 │
              │  Rule 1 (priority 1):           │
              │    /argocd* → fixed 404         │  ← ArgoCD blocked from internet
              │                                 │
              │  Default:                       │
              │    forward → ALB target group   │
              └───────────────┬────────────────┘
                              │ IP targets (NLB private IPs, port 80)
              ┌───────────────▼────────────────┐
              │   Internal NLB (CCM)            │
              │   private subnets, port 80      │
              └───────────────┬────────────────┘
                              │ NodePort
              ┌───────────────▼────────────────┐
              │       ingress-nginx pod         │
              └───────────────┬────────────────┘
                              │
              ┌───────────────▼────────────────┐
              │         app pods               │
              │  (frontend / backend / mongo)  │
              └─────────────────────────────────┘


              ARGOCD — VPC-ONLY (two isolation layers)
              ─────────────────────────────────────────

              Layer 1: External ALB blocks /argocd* at listener rule level
              Layer 2: nginx whitelist-source-range: 10.0.0.0/16

              Developer access only via SSM tunnel:

              laptop
                │
                │ aws ssm start-session (IAM-authenticated, CloudTrail-logged)
                ▼
              SSM tunnel (local port 8080 → NLB:80)
                │
                ▼
              ingress-nginx  (/argocd Prefix → argocd-server, source in VPC CIDR)
                │
                ▼
              argocd-server (ClusterIP, rootpath=/argocd)
                │
                ▼
              http://localhost:8080/argocd
```

---

## Isolation Design

| Threat | Control |
|--------|---------|
| Internet access to ArgoCD | ALB listener rule blocks `/argocd*` with fixed 404 — before nginx |
| VPC-but-not-SSM access to ArgoCD | nginx `whitelist-source-range: 10.0.0.0/16` enforced at ingress |
| Direct SSH to nodes | Port 22 closed; no public IPs; SSM only |
| K8s API exposure | Security group: port 6443 only from admin EC2 SG |
| Worker join token leakage | Automated via SSM Parameter Store — no manual token handling |
| Push into cluster | GitOps is pull-based — ArgoCD pulls from GitHub, nothing pushes in |
| Public IP on any EC2 | All instances in private subnets — no public IPs assigned |

---

## nginx Ingress + CCM Architecture

The ingress-nginx controller is deployed as a `type: LoadBalancer` service. AWS CCM (Cloud Controller Manager) watches this service and automatically provisions an internal NLB in the private subnets.

```
nginx Service (type: LoadBalancer)
  annotations:
    aws-load-balancer-type: nlb
    aws-load-balancer-internal: "true"
    aws-load-balancer-subnets: <private-subnet-ids>
          │
          ▼ CCM watches this service
  AWS provisions internal NLB automatically
          │
          ▼
  NLB hostname appears in service.status.loadBalancer.ingress[0].hostname
          │
          ▼
  Terraform wait_for_nlb polls until hostname is set
  Terraform register_nlb_targets discovers NLB private IPs via AWS CLI
  → registers IPs in external ALB target group
```

**Why nginx + CCM over AWS Load Balancer Controller:**

| | nginx + CCM (current) | AWS LBC |
|---|---|---|
| In-cluster routing | nginx handles path/host rules | ALB handles rules |
| Load balancer provisioning | CCM provisions NLB for nginx service | LBC provisions ALB per Ingress |
| ArgoCD subpath | `/argocd` prefix via nginx Ingress | Requires ALB path rules |
| External ALB | Single Terraform ALB → NLB → nginx | One ALB per Ingress resource |
| IRSA / IAM complexity | CCM only needs basic EC2 permissions | LBC needs IAM policy for elbv2 |

---

## Two-Stage Terraform

The K8s API server (`10.0.10.100:6443`) is a private IP unreachable from your laptop, so Terraform is split into two stages.

**Stage 1 — run from your laptop:**
```bash
terraform init
terraform apply
```
Creates: VPC (4 subnets across 2 AZs), NAT gateway, security groups, all EC2 instances.

**Stage 2 — runs automatically on the admin EC2 via cloud-init:**

`admin-setup.sh` executes on first boot:
1. Waits for the control plane to finish bootstrapping
2. Fetches kubeconfig from AWS SSM Parameter Store
3. Copies kubeconfig to `.terraform/kubeconfig`
4. Runs `terraform apply -var="deploy_argocd=true" -target='module.argocd[0]'`

The admin EC2 is inside the VPC so it can reach `10.0.10.100:6443` directly.

> **Why `-target`?** Stage 2 starts with a fresh git clone and no Terraform state. `module.argocd` discovers VPC/subnet IDs via `data` sources (tag-based, no dependency on `module.vpc`), so `-target='module.argocd[0]'` only creates Helm releases and AWS load balancer resources — it never attempts to recreate VPC or EC2 instances.

---

## Project Structure

```
kubeadm/
├── main.tf                        # Root module — wires all modules together
├── variables.tf                   # All input variables
├── providers.tf                   # AWS, Helm, Kubernetes, Null providers
├── outputs.tf                     # Instance IDs, ALB DNS, access info
├── data.tf                        # Data sources (AMI, AZs)
├── config/
│   └── terraform.tfvars           # Variable values
│
├── modules/
│   ├── vpc/                       # VPC, 4 subnets across 2 AZs, NAT gateway
│   ├── security/                  # Security groups for K8s nodes and admin
│   ├── compute/                   # EC2: control plane + workers, IAM roles
│   ├── admin/                     # Admin EC2 — kubectl gateway, runs Stage 2
│   ├── argocd/                    # nginx ingress + ArgoCD (Helm) + external ALB (Terraform)
│   └── loadbalancer/              # Intentionally empty (all LB resources in modules/argocd)
│
├── scripts/
│   ├── control-plane-setup.sh     # kubeadm init, CCM deploy, SSM upload
│   ├── worker-setup.sh            # kubeadm join via SSM Parameter Store
│   └── admin-setup.sh             # kubectl setup + CCM taint wait + Stage 2 deploy
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
- IAM permissions: `ec2:Describe*`, `elasticloadbalancing:*`, `iam:Get*`, `iam:List*`, `ssm:*`, and standard Terraform permissions

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

Get the external ALB DNS:
```bash
# From your laptop
aws elbv2 describe-load-balancers \
  --region us-east-1 \
  --query "LoadBalancers[?contains(LoadBalancerName,'k8s-external-alb')].DNSName" \
  --output text

# Or from admin EC2 (if Terraform state is present)
cd ~/kubeadm-infra && terraform output external_alb_dns
```
```
http://<external-ALB-DNS>/       # frontend
http://<external-ALB-DNS>/api/   # backend API
```

### ArgoCD UI

ArgoCD is VPC-internal only — blocked at the ALB and whitelist-restricted at nginx. Access via SSM tunnel to the internal NLB:

```bash
# Step 1 — get internal NLB hostname (on admin EC2)
kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Step 2 — open SSM tunnel (on your laptop)
aws ssm start-session --target <admin_instance_id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<NLB-DNS>"],"portNumber":["80"],"localPortNumber":["8080"]}'

# Step 3 — open in browser
http://localhost:8080/argocd
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

The `pre_destroy_cleanup` null_resource fires automatically before EC2 termination. It:
1. Pauses ArgoCD sync
2. Deletes the `ingress-nginx` namespace via SSM command (triggers CCM to delete the NLB)
3. Waits for the SSM command to complete

This prevents the NLB from remaining attached to VPC subnets and blocking VPC deletion.

```bash
# On your laptop
terraform destroy
```

> If Stage 2 was run on the admin EC2, the external ALB and NLB are tracked in Terraform state there, not on your laptop. Run `terraform destroy` on the admin EC2 first if needed, or destroy resources manually via AWS console before running destroy from your laptop.

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
| No public IPs | All EC2 in private subnets only |
| No bastion | AWS SSM Session Manager — IAM-authenticated, CloudTrail-logged |
| API server isolation | Only admin EC2 security group can reach port 6443 |
| Worker join | Automated via SSM Parameter Store — no manual token handling |
| ArgoCD — internet blocked | ALB listener rule: `/argocd*` → fixed-response 404 (before nginx) |
| ArgoCD — VPC restricted | nginx `whitelist-source-range: 10.0.0.0/16` — second isolation layer |
| ArgoCD — access method | SSM port-forward tunnel → internal NLB → nginx → `/argocd` |
| Public exposure | External ALB port 80 (app only) — ArgoCD never reachable from internet |
| GitOps | Pull-based (ArgoCD pulls from GitHub) — nothing pushes into the cluster |
