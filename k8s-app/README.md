# Kubernetes Application (React + Go + MongoDB)

A full-stack application deployed via GitOps (ArgoCD) on a private Kubernetes cluster.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        test-app namespace                        │
│                                                                  │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐        │
│   │   React     │    │   Go        │    │  MongoDB    │        │
│   │  Frontend   │───▶│  Backend    │───▶│  Database   │        │
│   │  (nginx)    │    │ (distroless)│    │   + PVC     │        │
│   └─────────────┘    └─────────────┘    └─────────────┘        │
│         │                                                       │
│         ▼                                                       │
│   ┌─────────────────────────────────────┐                      │
│   │      NGINX Ingress Controller       │                      │
│   │  /      → react-frontend:80         │                      │
│   │  /api/* → go-backend:8080           │                      │
│   └─────────────────────────────────────┘                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Deployment

This repo contains **application source code only** (frontend, backend, Dockerfiles).

**Kubernetes manifests** are in the separate GitOps repo:
- https://github.com/syedibrahim-dev/kubeadm-gitops

Deployment is handled by **ArgoCD** which watches the gitops repo for changes.

```bash
# On Admin instance - run the deploy script (one-time setup)
./deploy.sh
```

### GitOps Workflow

1. Code change → Push to `kubeadm` repo
2. GitHub Actions → Build image → Push to ECR
3. Pipeline updates manifest in `kubeadm-gitops` repo
4. ArgoCD detects change → Deploys to cluster

---

## Port Forwarding Commands

Since the cluster is private (no public IPs), use port forwarding to access services.

### Step 1: Connect to Admin Instance

```bash
# Get admin instance ID
cd ~/kubeadm
terraform output admin_instance_id

# Connect via SSM
aws ssm start-session --target <ADMIN_INSTANCE_ID> --region us-east-1

# Switch to ubuntu user
sudo su - ubuntu
```

### Step 2: kubectl Port Forwarding (on Admin Instance)

#### ArgoCD Dashboard
```bash
kubectl port-forward svc/argocd-server -n argocd 8443:443
```

#### Application via Ingress
```bash
kubectl port-forward svc/ingress-nginx-controller -n ingress-nginx 8080:80
```

#### Direct Service Access (bypass ingress)
```bash
# React Frontend
kubectl port-forward svc/react-frontend -n test-app 3000:80

# Go Backend
kubectl port-forward svc/go-backend -n test-app 8081:8080

# MongoDB
kubectl port-forward svc/mongodb -n test-app 27017:27017
```

### Step 3: SSM Tunnel to Your Local Machine

Open a **new terminal** on your local machine and create an SSM tunnel:

#### ArgoCD (https://localhost:8443)
```bash
aws ssm start-session --target <ADMIN_INSTANCE_ID> \
  --document-name AWS-StartPortForwardingSession \
  --parameters 'portNumber=8443,localPortNumber=8443' \
  --region us-east-1
```

#### Application (http://localhost:8080)
```bash
aws ssm start-session --target <ADMIN_INSTANCE_ID> \
  --document-name AWS-StartPortForwardingSession \
  --parameters 'portNumber=8080,localPortNumber=8080' \
  --region us-east-1
```

#### React Frontend Direct (http://localhost:3000)
```bash
aws ssm start-session --target <ADMIN_INSTANCE_ID> \
  --document-name AWS-StartPortForwardingSession \
  --parameters 'portNumber=3000,localPortNumber=3000' \
  --region us-east-1
```

#### Go Backend Direct (http://localhost:8081)
```bash
aws ssm start-session --target <ADMIN_INSTANCE_ID> \
  --document-name AWS-StartPortForwardingSession \
  --parameters 'portNumber=8081,localPortNumber=8081' \
  --region us-east-1
```

---

## Quick Reference

| Service | kubectl port-forward | SSM tunnel | Access URL |
|---------|---------------------|------------|------------|
| **ArgoCD** | `svc/argocd-server -n argocd 8443:443` | `portNumber=8443,localPortNumber=8443` | https://localhost:8443 |
| **App (Ingress)** | `svc/ingress-nginx-controller -n ingress-nginx 8080:80` | `portNumber=8080,localPortNumber=8080` | http://localhost:8080 |
| **React Frontend** | `svc/react-frontend -n test-app 3000:80` | `portNumber=3000,localPortNumber=3000` | http://localhost:3000 |
| **Go Backend** | `svc/go-backend -n test-app 8081:8080` | `portNumber=8081,localPortNumber=8081` | http://localhost:8081 |
| **MongoDB** | `svc/mongodb -n test-app 27017:27017` | `portNumber=27017,localPortNumber=27017` | mongodb://localhost:27017 |

---

## ArgoCD Access

```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Login: admin / <password from above>
```

---

## Testing the Application

### Via Ingress
```bash
# Health check
curl http://localhost:8080/api/health

# List items
curl http://localhost:8080/api/items

# Create item
curl -X POST http://localhost:8080/api/items \
  -H "Content-Type: application/json" \
  -d '{"name": "test item"}'
```

### Direct Backend
```bash
curl http://localhost:8081/health
curl http://localhost:8081/items
```

---

## Verify Deployment

```bash
# Check all resources
kubectl get all -n test-app

# Check pods
kubectl get pods -n test-app

# Check ingress
kubectl get ingress -n test-app

# Check ArgoCD sync status
kubectl get application k8s-app -n argocd

# View logs
kubectl logs -n test-app -l app=go-backend
kubectl logs -n test-app -l app=react-frontend
kubectl logs -n test-app -l app=mongodb
```

---

## Cleanup

```bash
# Delete application (ArgoCD will remove all resources)
kubectl delete application k8s-app -n argocd

# Or delete namespace directly
kubectl delete namespace test-app

# Delete ingress controller (optional)
kubectl delete namespace ingress-nginx

# Delete ArgoCD (optional)
kubectl delete namespace argocd
```


