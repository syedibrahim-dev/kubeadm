# Private Kubernetes Cluster on AWS — DevSecOps

A fully automated, private Kubernetes cluster on AWS provisioned with Terraform and kubeadm. Features GitOps deployment via ArgoCD, AWS-native load balancing via AWS Load Balancer Controller, and a security-focused CI/CD pipeline.

---

## Architecture

```
                        Internet
                            │
              ┌─────────────▼──────────────┐
              │    Public ALB (AWS LBC)     │  ← app traffic only
              │    port 80, internet-facing │
              │    spans AZ1 + AZ2          │
              └─────────────┬──────────────┘
                            │ NodePort
                            ▼
                       react-frontend pod (NodePort 80)
                       go-backend pod    (NodePort 8080)

              ┌─────────────────────────────┐
              │   Internal ALB (AWS LBC)    │  ← VPC-only, no public IP
              │   port 80, scheme: internal │
              │   spans AZ1 + AZ2          │
              └─────────────┬──────────────┘
                            │ NodePort
                            ▼
                       argocd-server pod (NodePort)

              ┌──────────────────────────────────────────────────────┐
              │   AZ1 — Private Subnet (10.0.10.0/24)                │
              │                                                      │
              │  ┌─────────────┐   ┌──────────────┐   ┌──────────┐  │
              │  │  Admin EC2  │   │  K8s Worker  │   │  Control │  │
              │  │  (kubectl)  │   │     Node     │   │  Plane   │  │
              │  └─────────────┘   └──────────────┘   │10.0.10.100│ │
              │                                        └──────────┘  │
              └──────────────────────────────────────────────────────┘
              ┌──────────────────────────────────────────────────────┐
              │   AZ2 — Private Subnet (10.0.11.0/24)                │
              │   (ALB subnet only — no K8s nodes here)              │
              └──────────────────────────────────────────────────────┘
                            │
              ┌─────────────▼──────────────┐
              │       NAT Gateway          │
              │      (outbound only)       │
              └────────────────────────────┘
```

- All EC2 instances are in a **private subnet** — no public IPs
- Node access is via **AWS SSM Session Manager** only — no SSH, no open ports
- The Kubernetes API server is reachable **only from the admin EC2** (security group enforced)
- **AWS Load Balancer Controller** provisions ALBs directly from Ingress resources — no ingress-nginx needed
- ArgoCD is **not internet-facing** — internal ALB only, accessed via SSM tunnel through admin EC2
- **Two AZs** are required — AWS ALB must span at least 2 availability zones. AZ2 subnets exist for ALB only; all K8s nodes run in AZ1

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
    │         │  2. Deploy AWS CCM (DaemonSet) — node lifecycle only
    │         │     (removes uninitialized taint, sets zone/region labels)
    │         │  3. Uploads kubeconfig + join command to SSM Parameter Store
    │         │
    ├──► Worker EC2 (boots, runs worker-setup.sh)
    │         │
    │         │  1. Fetches join command from SSM Parameter Store
    │         │  2. kubeadm join → joins cluster
    │         │
    └──► Admin EC2 (boots, runs admin-setup.sh)
              │
              │  1. Fetches kubeconfig from SSM Parameter Store
              │  2. Waits for all nodes Ready
              │  3. Waits for CCM to clear uninitialized taint
              │  4. terraform apply -var="deploy_argocd=true"
              │         │
              │         ├──► Helm ──► ArgoCD (NodePort)
              │         ├──► Helm ──► AWS Load Balancer Controller
              │         └──► kubectl apply ──► ArgoCD Application CR
              │                               ArgoCD Ingress (internal ALB)
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
               ┌─────────────▼──────────────────┐
               │   Public ALB (AWS LBC)          │
               │   scheme: internet-facing       │
               │   target-type: instance         │
               └──────────────┬─────────────────┘
                              │ NodePort
               ┌──────────────▼─────────────────┐
               │          app pods               │
               └─────────────────────────────────┘


               VPC-ONLY (not internet-routable)
               ┌─────────────────────────────────┐
               │   Internal ALB (AWS LBC)         │
               │   scheme: internal              │
               │   target-type: instance         │
               └──────────────┬─────────────────┘
                              │ NodePort
               ┌──────────────▼─────────────────┐
               │       argocd-server pod         │
               └─────────────────────────────────┘

               Developers reach ArgoCD via SSM tunnel:
               laptop ──► SSM ──► admin EC2 ──► internal ALB
```

---

## AWS Load Balancer Controller

AWS LBC is a single Kubernetes controller that provisions ALBs directly from Ingress resources:

```
You write this Ingress:                  LBC calls AWS API:
──────────────────────────               ──────────────────────────────
kind: Ingress                       →    aws elbv2 create-load-balancer
  ingressClassName: alb             →      --type application
  scheme: internet-facing           →      --scheme internet-facing
  target-type: instance             →    aws elbv2 create-target-group
  path: /                           →    aws elbv2 create-listener
  backend: react-frontend:80        →    aws elbv2 register-targets (NodePorts)
```

**Requirements:**
- Services must be `type: NodePort` (not `ClusterIP`) — LBC routes ALB traffic to NodePorts on EC2 nodes
- Subnets must exist in **at least 2 availability zones** — AWS ALB hard requirement
- Public subnets tagged `kubernetes.io/role/elb = 1` — LBC uses this to discover internet-facing ALB subnets
- Private subnets tagged `kubernetes.io/role/internal-elb = 1` — for internal ALB subnet discovery

**Why LBC over ingress-nginx + CCM:**

| | Old (ingress-nginx + CCM) | New (AWS LBC) |
|---|---|---|
| Controllers | 2 (public + internal) | 1 |
| Hops | Internet → NLB → nginx pod → app | Internet → ALB → app |
| Routing layer | nginx (in-cluster) | ALB (AWS-managed) |
| Public/internal separation | Two separate controllers | One annotation per Ingress |
| AWS-native | No | Yes |

---

## Two-Stage Terraform

The K8s API server is a private IP unreachable from your laptop, so Terraform is split:

**Stage 1 — run from your laptop:**
```bash
terraform init
terraform apply
```
Creates VPC (4 subnets across 2 AZs), NAT gateway, security groups, and all EC2 instances.

**Stage 2 — runs automatically on the admin EC2 via cloud-init:**

`admin-setup.sh` executes on first boot:
1. Waits for the control plane to finish bootstrapping
2. Fetches kubeconfig from AWS SSM Parameter Store
3. Copies kubeconfig to `.terraform/kubeconfig` (required by Helm/K8s providers)
4. Runs `terraform apply -var="deploy_argocd=true" -target='module.argocd[0]'`

The admin EC2 is inside the VPC so it can reach `10.0.10.100:6443` directly.

> **Why `-target`?** Stage 2 starts with a fresh git clone and no Terraform state. The argocd module uses a `data "aws_vpc"` lookup (no module dependency on VPC), so `-target='module.argocd[0]'` only creates Helm releases and Kubernetes resources — it never attempts to recreate VPC or EC2 instances.

---

## Project Structure

```
kubeadm/
├── main.tf                        # Root module — wires all modules together
├── variables.tf                   # All input variables
├── providers.tf                   # AWS, Helm, Kubernetes, Null providers
├── outputs.tf                     # Instance IDs, ALB hostnames, access info
├── data.tf                        # Data sources (AMI, AZs)
├── config/
│   └── terraform.tfvars           # Variable values
│
├── modules/
│   ├── vpc/                       # VPC, 4 subnets across 2 AZs, NAT gateway
│   ├── security/                  # Security groups for K8s nodes and admin
│   ├── compute/                   # EC2: control plane + workers, IAM roles + LBC policy
│   ├── admin/                     # Admin EC2 — kubectl gateway, runs Stage 2
│   └── argocd/                    # ArgoCD + AWS Load Balancer Controller via Helm
│
├── scripts/
│   ├── control-plane-setup.sh     # kubeadm init, CCM (node lifecycle), SSM upload
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

Get the public ALB DNS (on admin EC2, available ~2 min after Stage 2 completes):
```bash
kubectl get ingress app-ingress -n test-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```
```
http://<public-ALB-DNS>/
```

### ArgoCD UI

ArgoCD is on an internal ALB — not internet-accessible. Access via SSM tunnel:

```bash
# Step 1 — get internal ALB DNS (on admin EC2)
kubectl get ingress argocd-server-ingress -n argocd \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Step 2 — open SSM tunnel (on your laptop)
aws ssm start-session --target <admin_instance_id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<internal-ALB-DNS>"],"portNumber":["80"],"localPortNumber":["8080"]}'

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

**Always delete Ingress resources first** — AWS LBC creates ALBs outside Terraform state. If you skip this, the VPC subnet deletion will hang indefinitely.

```bash
# Step 1 — on admin EC2: pause ArgoCD sync + delete Ingress resources
kubectl patch app k8s-app -n argocd -p '{"spec":{"syncPolicy":null}}' --type=merge
kubectl delete ingress app-ingress -n test-app
kubectl delete ingress argocd-server-ingress -n argocd

# Step 2 — wait ~60s for AWS LBC to delete the ALBs
sleep 60

# Step 3 — on your laptop
terraform destroy
```

> The `pre_destroy_nlb_cleanup` null_resource automates this — it fires before EC2s are terminated and sends the above commands via SSM. Without it, ALBs remain attached to subnets and VPC deletion hangs indefinitely.

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
| ArgoCD isolation | Internal ALB only — not internet-facing, accessed via SSM tunnel |
| Public exposure | Public ALB port 80 (app only) — ArgoCD never exposed publicly |
| GitOps | Pull-based (ArgoCD pulls from GitHub) — nothing pushes into the cluster |
