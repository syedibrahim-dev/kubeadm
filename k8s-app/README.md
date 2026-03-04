# Kubernetes Test Application

A simple Node.js + MongoDB application for testing your Kubernetes cluster with Ingress.

## Architecture

- **Node.js App**: Express API with CRUD operations (2 replicas for load balancing)
- **MongoDB**: Database for persistence (1 replica with PVC)
- **Ingress**: NGINX Ingress Controller for routing
- **Access**: Port-forwarding from admin instance to local PC/WSL

## Deployment Steps

### 1. Connect to Admin Instance via SSM

From your local PC/WSL:

```bash
# Get admin instance ID
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=K8s-Admin" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text

# Connect via SSM
aws ssm start-session --target <INSTANCE_ID>
```

### 2. Copy Kubernetes Manifests to Admin Instance

On your **local PC/WSL**, copy the k8s manifests to the admin instance:

```bash
# Create a tarball
cd /home/ibrahim/kubeadm
tar -czf k8s-app.tar.gz k8s-app/

# Copy to S3 (temporary bucket method) or use SSM document
aws s3 cp k8s-app.tar.gz s3://YOUR-BUCKET/
```

On the **admin instance**:

```bash
# Download from S3
aws s3 cp s3://YOUR-BUCKET/k8s-app.tar.gz ~/
tar -xzf k8s-app.tar.gz
cd k8s-app/k8s
```

**Alternative**: Manually create the files on the admin instance using the YAML content.

### 3. Install NGINX Ingress Controller

On the **admin instance**:

```bash
# Install NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/baremetal/deploy.yaml

# Wait for ingress controller to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# Check ingress controller status
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

### 4. Deploy the Application

On the **admin instance**:

```bash
cd ~/k8s-app/k8s

# Apply all manifests
kubectl apply -f 01-namespace.yaml
kubectl apply -f 02-mongodb.yaml
kubectl apply -f 03-nodejs-app.yaml
kubectl apply -f 04-ingress.yaml

# Or apply all at once
kubectl apply -f .

# Watch deployment progress
kubectl get pods -n test-app -w
```

### 5. Verify Deployment

```bash
# Check all resources
kubectl get all -n test-app

# Check ingress
kubectl get ingress -n test-app

# Check MongoDB logs
kubectl logs -n test-app -l app=mongodb

# Check Node.js app logs
kubectl logs -n test-app -l app=nodejs-app
```

### 6. Port Forward to Local PC/WSL

#### Option 1: Port Forward the Service (Recommended for Testing)

On the **admin instance**:

```bash
# Forward Node.js app service to admin instance
kubectl port-forward -n test-app svc/nodejs-app 8080:80 --address=0.0.0.0
```

Then from your **local PC/WSL**, create an SSM session with port forwarding:

```bash
# Forward from admin instance to your local machine
aws ssm start-session \
  --target <INSTANCE_ID> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

Now access the app at: **http://localhost:8080**

#### Option 2: Port Forward the Ingress Controller

On the **admin instance**:

```bash
# Get ingress controller service name
kubectl get svc -n ingress-nginx

# Forward ingress controller
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80 --address=0.0.0.0
```

Then from your **local PC/WSL**:

```bash
aws ssm start-session \
  --target <INSTANCE_ID> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

Access with host header: `curl -H "Host: test-app.local" http://localhost:8080`

Or add to your local `/etc/hosts`:
```
127.0.0.1 test-app.local
```

Then visit: **http://test-app.local:8080**

#### Option 3: Direct Pod Port Forward (Debugging)

```bash
# Get a pod name
kubectl get pods -n test-app -l app=nodejs-app

# Forward directly to pod
kubectl port-forward -n test-app <POD_NAME> 8080:3000 --address=0.0.0.0
```

Then use SSM port forwarding as shown above.

## Testing the Application

### MongoDB Connection Issues

```bash
# Test MongoDB connectivity from app pod
kubectl exec -n test-app -it <NODEJS_POD> -- sh
apk add --no-cache mongodb-tools
mongosh mongodb://mongodb:27017/testdb
```
## Cleanup

```bash
# Delete all app resources
kubectl delete namespace test-app

# Delete ingress controller (optional)
kubectl delete namespace ingress-nginx
```

## Architecture Diagram

```
┌─────────────────┐
│  Local PC/WSL   │
│   localhost     │
│    :8080        │
└────────┬────────┘
         │ SSM Port Forward
         │
┌────────▼────────┐
│ Admin Instance  │
│ kubectl port-   │
│ forward :8080   │
└────────┬────────┘
         │ K8s Network
         │
┌────────▼────────────────────────┐
│     Ingress Controller          │
│  (ingress-nginx-controller)     │
└────────┬────────────────────────┘
         │
┌────────▼────────────────────────┐
│    Service: nodejs-app          │
│         (ClusterIP)             │
└─────┬──────────────┬────────────┘
      │              │
┌─────▼─────┐  ┌────▼──────┐
│  Pod 1    │  │  Pod 2    │
│ nodejs-app│  │nodejs-app │
└─────┬─────┘  └────┬──────┘
      │             │
      └──────┬──────┘
             │
      ┌──────▼──────┐
      │  Service:   │
      │  mongodb    │
      └──────┬──────┘
             │
      ┌──────▼──────┐
      │  MongoDB    │
      │   Pod       │
      │   + PVC     │
      └─────────────┘
```


