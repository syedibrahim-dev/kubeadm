# Private Kubernetes Cluster on AWS — DevSecOps

A fully automated, private Kubernetes cluster on AWS provisioned with Terragrunt + kubeadm. Features GitOps deployment via ArgoCD, nginx ingress with AWS CCM-provisioned NLB, a Terraform-managed external ALB, and a security-focused CI/CD pipeline.

---

## Architecture Overview

```
                          Internet
                              │
              ┌───────────────▼────────────────┐
              │     External ALB (Terraform)    │  ← app traffic only
              │     port 80, internet-facing    │  ← /argocd* blocked (fixed-response 404)
              └───────────────┬────────────────┘
                              │ IP targets (NLB private IPs)
              ┌───────────────▼────────────────┐
              │   Internal NLB (CCM-provisioned)│  ← private subnets, VPC-only
              │   nginx LoadBalancer service    │
              └───────────────┬────────────────┘
                              │ NodePort
              ┌───────────────▼────────────────┐
              │     ingress-nginx controller    │
              │   /          → app pods         │
              │   /argocd    → argocd-server    │  ← VPC-only
              └────────────────────────────────┘

              ┌──────────────────────────────────────────────────────┐
              │   AZ1 — Private Subnet (10.0.10.0/24)                │
              │  ┌─────────────┐  ┌──────────────┐  ┌────────────┐  │
              │  │  Admin EC2  │  │  K8s Worker  │  │  Control   │  │
              │  │ (kubectl +  │  │    Node(s)   │  │   Plane    │  │
              │  │  Terragrunt)│  │              │  │ 10.0.10.100│  │
              │  └─────────────┘  └──────────────┘  └────────────┘  │
              └──────────────────────────────────────────────────────┘
                              │
              ┌───────────────▼────────────────┐
              │          NAT Gateway            │
              │         (outbound only)         │
              └─────────────────────────────────┘
```

- All EC2 instances in **private subnets** — no public IPs
- Node access via **AWS SSM Session Manager** only — no SSH, no open ports
- K8s API server reachable **only from the admin EC2** (security group enforced)
- ArgoCD is **not internet-facing** — blocked at ALB, whitelist-restricted at nginx

---

## Terragrunt Structure

```
live/
├── terragrunt.hcl              # Root: remote_state, generate "provider_aws", account locals
├── account.hcl                 # AWS account ID + region (read by root)
│
├── _envcommon/                 # Shared module source + constant inputs only
│   ├── vpc.hcl                 #   terraform { source }
│   ├── security.hcl            #   terraform { source }
│   ├── compute.hcl             #   terraform { source } + inputs { ccm_version, pod_subnet_cidr, worker_name }
│   ├── admin.hcl               #   terraform { source } + inputs { admin_name }
│   └── argocd.hcl              #   terraform { source } + locals { kubeconfig_path } + generate "provider_all"
│
└── dev/
    ├── env.hcl                 # Environment locals: cluster_name, VPC CIDRs, k8s_version, etc.
    ├── vpc/terragrunt.hcl
    ├── security/terragrunt.hcl
    ├── compute/terragrunt.hcl
    ├── admin/terragrunt.hcl
    └── argocd/terragrunt.hcl
```

### Three-Include Pattern

Every child module uses three named includes:

```hcl
# 1. Root — remote_state backend + AWS provider generation
include "root" {
  path           = find_in_parent_folders()
  expose         = true
  merge_strategy = "deep"
}

# 2. Env — environment-level locals (cluster_name, CIDRs, k8s_version, etc.)
include "env" {
  path           = find_in_parent_folders("env.hcl")
  expose         = true
  merge_strategy = "no_merge"
}

# 3. Envcommon — module source + constant inputs
include "envcommon" {
  path           = "${get_repo_root()}/live/_envcommon/<module>.hcl"
  expose         = true
  merge_strategy = "deep"
}
```

### What Lives Where

| Layer | File | Contents |
|-------|------|----------|
| Root | `live/terragrunt.hcl` | `remote_state` (local backend), `generate "provider_aws"`, account-level locals (`aws_region`, `aws_account_id`) |
| Env | `live/dev/env.hcl` | `cluster_name`, VPC CIDRs, `k8s_version`, `control_plane_name`, `enable_auto_setup` |
| Envcommon | `live/_envcommon/*.hcl` | `terraform { source }` + hardcoded constants (`ccm_version`, `pod_subnet_cidr`, etc.) |
| Child | `live/dev/<module>/terragrunt.hcl` | `dependency` blocks + all `inputs` (env.locals refs, dependency outputs, env-specific values) |

### How Inputs Flow

```
include.root.locals.aws_region          ─┐
include.env.locals.cluster_name         ─┤
include.env.locals.k8s_version          ─┤──► child inputs {}
dependency.vpc.outputs.private_subnet_id─┤
"t3.medium"  (env-specific literal)     ─┘

"v1.31.1"    (constant literal)         ────► _envcommon/compute.hcl inputs {}
```

`_envcommon` only holds values identical across every environment. Everything else lives in the child.

### Dependency Graph

```
vpc ──► security ──► compute ──► admin ──► argocd
         └──────────────────────────────────────┘
```

Dependency blocks are declared in each child's `terragrunt.hcl` using relative paths (`../vpc`, `../security`, etc.) with `mock_outputs` for validate/plan.

---


---

## Adding a New Environment

1. Create `live/<env>/env.hcl` with environment-specific locals
2. Create `live/<env>/<module>/terragrunt.hcl` with the three includes + env-specific inputs
3. `_envcommon` files remain untouched

No changes to modules or root config needed.

---

## Access

### kubectl (via SSM)

```bash
aws ssm start-session --target <admin_instance_id> --region us-east-1
# inside session:
sudo su - ubuntu
kubectl get nodes
kubectl get pods -A
```

### Application

```bash
aws elbv2 describe-load-balancers \
  --region us-east-1 \
  --query "LoadBalancers[?contains(LoadBalancerName,'k8s-external-alb')].DNSName" \
  --output text
```

```
http://<ALB-DNS>/       # frontend
http://<ALB-DNS>/api/   # backend API
```

### ArgoCD UI (SSM tunnel — VPC only)

```bash
# Get internal NLB hostname (on admin EC2)
kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Open SSM tunnel (on your laptop)
aws ssm start-session --target <admin_instance_id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<NLB-DNS>"],"portNumber":["80"],"localPortNumber":["8080"]}'
```

Open `http://localhost:8080/argocd` — username: `admin`

Get password (on admin EC2):
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

---

## Prerequisites

- AWS CLI configured with credentials
- Terragrunt >= 0.75
- Terraform >= 1.10
- AWS Session Manager Plugin

IAM permissions: `ec2:Describe*`, `elasticloadbalancing:*`, `iam:Get*`, `iam:List*`, `ssm:*`

---

## CI/CD Pipeline

Triggers on pushes to `main` that modify `k8s-app/**`.

| Step | Tool | Blocks? |
|------|------|---------|
| 1 | SonarQube SAST | No |
| 2 | Hadolint (Dockerfile lint) | No |
| 3 | Docker Build | Yes |
| 4 | Trivy (image CVE scan) | No |
| 5 | Docker Push | Yes — main only |
| 6 | OWASP ZAP DAST | No |
| 7 | DefectDojo upload | No |
| 8 | Kustomize Deploy → GitOps push | Yes — main only |

Step 8 updates image tags in `kubeadm-gitops/k8s-app/overlays/production/kustomization.yaml`. ArgoCD polls every 3 minutes and syncs the cluster automatically.

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

## Security Design

| Control | Implementation |
|---------|---------------|
| No SSH | Port 22 closed on all instances |
| No public IPs | All EC2 in private subnets only |
| No bastion | AWS SSM — IAM-authenticated, CloudTrail-logged |
| API server isolation | Port 6443 only from admin EC2 security group |
| Worker join | Automated via SSM Parameter Store — no manual token handling |
| ArgoCD internet | ALB listener rule: `/argocd*` → fixed-response 404 |
| ArgoCD VPC | nginx `whitelist-source-range: 10.0.0.0/16` |
| ArgoCD access | SSM port-forward → internal NLB → nginx → `/argocd` |
| GitOps | Pull-based — ArgoCD pulls from GitHub, nothing pushes into the cluster |
