# Pre-install cleanup — removes stale LBC webhooks and partial Helm releases
# from any previous failed attempt. Must run before Helm installs so ArgoCD
# Service creation is never blocked by a dead webhook endpoint.
resource "null_resource" "pre_install_cleanup" {
  provisioner "local-exec" {
    environment = {
      KUBECONFIG = "/home/ubuntu/.kube/config"
    }
    command = <<-EOT
      echo "Cleaning up stale LBC webhooks and partial releases..."
      kubectl delete mutatingwebhookconfigurations aws-load-balancer-webhook --ignore-not-found=true
      kubectl delete validatingwebhookconfigurations aws-load-balancer-webhook --ignore-not-found=true
      helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
      helm uninstall argocd -n argocd 2>/dev/null || true
      echo "Cleanup complete."
    EOT
  }

  depends_on = [var.cluster_ready]
}

# ArgoCD — NodePort service, accessed via internal ALB through AWS LBC
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.11"
  timeout          = 600
  wait             = true

  values = [
    yamlencode({
      server = {
        service = {
          type = "NodePort"
        }
      }
      configs = {
        params = {
          "server.insecure" = true
        }
      }
    })
  ]

  depends_on = [var.cluster_ready, null_resource.pre_install_cleanup, null_resource.wait_for_lbc_webhook]
}

# Look up the VPC by tag — avoids a module dependency that would force VPC creation
# when running Stage 2 (terraform apply -target='module.argocd[0]') on admin EC2.
data "aws_vpc" "cluster" {
  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# AWS Load Balancer Controller — single controller that provisions ALBs from Ingress resources.
# Replaces two separate ingress-nginx controllers.
# Uses EC2 instance profile for AWS API access (no IRSA needed for non-EKS).
resource "helm_release" "aws_lbc" {
  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  namespace        = "kube-system"
  version          = "1.8.1"
  timeout          = 600

  values = [
    yamlencode({
      clusterName = var.cluster_name
      region      = var.aws_region
      vpcId       = data.aws_vpc.cluster.id
      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
      }
      enableShield = false
      enableWaf    = false
      enableWafv2  = false
    })
  ]

  wait       = true
  depends_on = [var.cluster_ready, null_resource.pre_install_cleanup]
}

# Waits for the LBC webhook server to actually accept connections before ArgoCD
# installs. helm wait=true only checks pod Running state — the webhook server
# inside LBC starts a few seconds later. Any Service creation during that gap
# hits connection refused and fails the entire ArgoCD install.
resource "null_resource" "wait_for_lbc_webhook" {
  provisioner "local-exec" {
    environment = {
      KUBECONFIG = "/home/ubuntu/.kube/config"
    }
    command = <<-EOT
      echo "Waiting for LBC webhook endpoint to be ready..."
      for i in $(seq 1 36); do
        ENDPOINT=$(kubectl get endpoints aws-load-balancer-webhook-service \
          -n kube-system \
          -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)
        if echo "$ENDPOINT" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
          echo "LBC webhook is ready at $ENDPOINT"
          exit 0
        fi
        echo "Not ready yet, attempt $i/36..."
        sleep 5
      done
      echo "ERROR: LBC webhook endpoint never became ready"
      exit 1
    EOT
  }

  depends_on = [helm_release.aws_lbc]
}

data "kubernetes_secret" "argocd_admin_password" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = "argocd"
  }
  depends_on = [helm_release.argocd]
}

data "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-server-ingress"
    namespace = "argocd"
  }
  depends_on = [null_resource.argocd_application]
}

resource "null_resource" "argocd_application" {
  triggers = {
    gitops_repo_url = var.gitops_repo_url
    gitops_branch   = var.gitops_branch
    app_namespace   = var.app_namespace
    gitops_path     = var.gitops_path
  }

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = "/home/ubuntu/.kube/config"
    }

    command = <<-EOT
      echo "Waiting for ArgoCD server to be ready..."
      kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
      echo "Waiting for AWS Load Balancer Controller to be ready..."
      kubectl wait --for=condition=available --timeout=300s \
        deployment/aws-load-balancer-controller -n kube-system
      echo "Applying ArgoCD Application CR and Ingress..."
      kubectl apply -f - <<'EOF'
      apiVersion: argoproj.io/v1alpha1
      kind: Application
      metadata:
        name: k8s-app
        namespace: argocd
      spec:
        project: default
        source:
          repoURL: ${var.gitops_repo_url}
          targetRevision: ${var.gitops_branch}
          path: ${var.gitops_path}
        destination:
          server: https://kubernetes.default.svc
          namespace: ${var.app_namespace}
        syncPolicy:
          automated:
            prune: true
            selfHeal: true
          syncOptions:
          - CreateNamespace=true
      ---
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: argocd-server-ingress
        namespace: argocd
        annotations:
          alb.ingress.kubernetes.io/scheme: internal
          alb.ingress.kubernetes.io/target-type: instance
          alb.ingress.kubernetes.io/backend-protocol: HTTP
      spec:
        ingressClassName: alb
        rules:
        - http:
            paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: argocd-server
                  port:
                    number: 80
      EOF
    EOT
  }

  depends_on = [helm_release.argocd, helm_release.aws_lbc]
}
