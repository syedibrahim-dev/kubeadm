resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.11"

  values = [
    yamlencode({
      server = {
        service = {
          type          = "NodePort"
          nodePortHttp  = 30082
          nodePortHttps = 30083
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
      EOF
    EOT
  }

  depends_on = [helm_release.argocd]
}

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.11.3"

  # AWS CCM provisions an NLB automatically when it sees type: LoadBalancer.
  # The annotation tells CCM to use NLB (Layer 4) instead of CLB (classic).
  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "nlb"
  }

  depends_on = [var.cluster_ready]
}
