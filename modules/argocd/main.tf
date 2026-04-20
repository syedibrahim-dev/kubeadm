resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.11"
  timeout          = 600

  values = [
    yamlencode({
      server = {
        service = {
          type = "ClusterIP"
        }
      }
      configs = {
        params = {
          "server.insecure" = true
        }
      }
    })
  ]

  depends_on = [var.cluster_ready]
}

resource "null_resource" "argocd_application" {
  triggers = {
    gitops_repo_url = var.gitops_repo_url
    gitops_branch   = var.gitops_branch
    app_namespace   = var.app_namespace
    gitops_path     = var.gitops_path
  }

  provisioner "local-exec" {
    # Explicit KUBECONFIG so kubectl works regardless of shell environment
    environment = {
      KUBECONFIG = "/home/ubuntu/.kube/config"
    }

    command = <<-EOT
      echo "Waiting for ArgoCD server to be ready..."
      kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
      echo "ArgoCD server is ready. Applying Application CR and Ingress..."
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
          nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
      spec:
        ingressClassName: nginx-internal
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

  depends_on = [helm_release.argocd, helm_release.ingress_nginx_internal]
}

# Public ingress-nginx — internet-facing NLB, serves app traffic only
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.11.3"
  timeout          = 600

  values = [
    yamlencode({
      controller = {
        ingressClassResource = {
          name            = "nginx"
          enabled         = true
          default         = false
          controllerValue = "k8s.io/ingress-nginx"
        }
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
          }
        }
      }
    })
  ]

  depends_on = [var.cluster_ready]
}

# Internal ingress-nginx — VPC-only NLB, serves admin tools (ArgoCD, etc.)
# The aws-load-balancer-internal annotation tells CCM to provision an internal NLB
# (no public IP, only reachable from within the VPC).
resource "helm_release" "ingress_nginx_internal" {
  name             = "ingress-nginx-internal"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx-internal"
  create_namespace = true
  version          = "4.11.3"
  timeout          = 600

  values = [
    yamlencode({
      controller = {
        ingressClassResource = {
          name            = "nginx-internal"
          enabled         = true
          default         = false
          controllerValue = "k8s.io/ingress-nginx-internal"
        }
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type"     = "nlb"
            "service.beta.kubernetes.io/aws-load-balancer-internal" = "true"
          }
        }
      }
    })
  ]

  depends_on = [var.cluster_ready]
}
