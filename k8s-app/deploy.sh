#!/bin/bash
# Deploy script for React (nginx:alpine) + Go (distroless) + MongoDB on K8s

set -e

echo "🚀 Deploying React + Go + MongoDB on Kubernetes..."
echo ""

# ── NGINX Ingress Controller ──────────────────────────────────────────────────
echo "📦 Installing NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/baremetal/deploy.yaml

echo "⏳ Waiting for Ingress Controller..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s || true

# ── Application manifests ──────────────────────────────────────────────────────
echo " Deploying application manifests..."
kubectl apply -f k8s/01-namespace.yaml
kubectl apply -f k8s/02-mongodb-hostpath.yaml
kubectl apply -f k8s/03-go-backend.yaml
kubectl apply -f k8s/04-react-frontend.yaml
kubectl apply -f k8s/04-ingress.yaml

# ── Wait for rollouts ──────────────────────────────────────────────────────────
echo " Waiting for MongoDB..."
kubectl wait --namespace test-app \
  --for=condition=ready pod \
  --selector=app=mongodb \
  --timeout=120s || true

echo " Waiting for Go backend..."
kubectl wait --namespace test-app \
  --for=condition=ready pod \
  --selector=app=go-backend \
  --timeout=120s || true

echo " Waiting for React frontend..."
kubectl wait --namespace test-app \
  --for=condition=ready pod \
  --selector=app=react-frontend \
  --timeout=120s || true

# ── Status ────────────────────────────────────────────────────────────────────
echo ""
echo " Deployment complete!"
echo ""
echo " Resource Status:"
kubectl get all -n test-app
echo ""
echo " Ingress:"
kubectl get ingress -n test-app
echo ""
echo " Image sizes (after multi-stage build):"
echo "   go-backend:     ~20MB  (golang:1.22 builder → distroless/static)"
echo "   react-frontend: ~15MB  (node:18 builder → nginx:alpine)"
echo ""
echo " Access the application via SSM port forwarding:"
echo ""
echo "   Step 1 — Forward the ingress NodePort to localhost:"
NODE_PORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || echo "<NODEPORT>")
CONTROL_PLANE_ID=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "<INSTANCE_ID>")
echo "   aws ssm start-session --target <CONTROL_PLANE_INSTANCE_ID> \\"
echo "     --document-name AWS-StartPortForwardingSession \\"
echo "     --parameters 'portNumber=${NODE_PORT},localPortNumber=8080'"
echo ""
echo "   Step 2 — Add to /etc/hosts:"
echo "   127.0.0.1  test-app.local"
echo ""
echo "   Step 3 — Open browser:"
echo "   http://test-app.local:8080  →  React frontend"
echo "   http://test-app.local:8080/api/health  →  Go backend health"
echo "   http://test-app.local:8080/api/items   →  Items API"
echo ""
echo "🧪 Test the API:"
echo "   curl http://localhost:8080/health"
echo "   curl http://localhost:8080/items"
