#!/bin/bash
# Manual deploy script — only needed if auto-deploy via Terraform/ArgoCD fails.
# Under normal operation, admin-setup.sh runs Stage 2 Terraform automatically
# which deploys ArgoCD + AWS Load Balancer Controller via Helm.

set -e

echo "Deploying ArgoCD + AWS Load Balancer Controller via Terraform (Stage 2)..."

cd /home/ubuntu/kubeadm-infra

mkdir -p .terraform
cp ~/.kube/config .terraform/kubeconfig
chmod 600 .terraform/kubeconfig

terraform init
terraform apply -var="deploy_argocd=true" -target='module.argocd[0]' -auto-approve

echo ""
echo "Deployment complete!"
echo ""
echo "Get ArgoCD admin password:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "Get public ALB DNS (app):"
echo "  kubectl get ingress app-ingress -n test-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
echo ""
echo "Get internal ALB DNS (ArgoCD):"
echo "  kubectl get ingress argocd-server-ingress -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
echo ""
echo "Check ArgoCD application sync status:"
echo "  kubectl get application k8s-app -n argocd"
