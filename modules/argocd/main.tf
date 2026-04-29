# ─────────────────────────────────────────────────────────────────────────────
# NOTE: AWS Load Balancer Controller (LBC) code is commented out below.
# ALB and NLB are now managed by modules/loadbalancer (pure Terraform).
# Uncomment the LBC blocks if you want to switch back to LBC-managed load
# balancers — you would also need to restore the LBC IAM policy in the
# compute module and revert nginx to LoadBalancer type with NLB annotations.
# ─────────────────────────────────────────────────────────────────────────────

# Pre-install cleanup — removes partial releases and stale resources from any
# previous failed attempt so a fresh deploy always starts from a clean state.
# NOTE: helm is not installed on the admin EC2 — kubectl is used instead.
resource "null_resource" "pre_install_cleanup" {
  provisioner "local-exec" {
    environment = {
      KUBECONFIG = "/home/ubuntu/.kube/config"
    }
    command = <<-EOT
      echo "Cleaning up stale resources from any previous attempt..."

      # Remove stale LBC resources if present from older deploys that had LBC enabled.
      # LBC is not in the current Terraform code so it will not be re-installed.
      kubectl delete deployment aws-load-balancer-controller -n kube-system --ignore-not-found 2>/dev/null || true
      kubectl delete validatingwebhookconfiguration aws-load-balancer-webhook --ignore-not-found 2>/dev/null || true

      # Delete namespaces so Helm installs always start from a clean slate.
      kubectl delete namespace ingress-nginx --ignore-not-found 2>/dev/null || true
      kubectl delete namespace argocd --ignore-not-found 2>/dev/null || true

      # Wait for namespaces to be fully terminated before Helm re-creates them.
      echo "Waiting for namespaces to terminate..."
      kubectl wait --for=delete namespace/ingress-nginx --timeout=60s 2>/dev/null || true
      kubectl wait --for=delete namespace/argocd --timeout=60s 2>/dev/null || true

      echo "Cleanup complete."
    EOT
  }

  depends_on = [var.cluster_ready]
}

# ── LBC: commented out ────────────────────────────────────────────────────────
# data "aws_vpc" "cluster" {
#   tags = {
#     "kubernetes.io/cluster/${var.cluster_name}" = "owned"
#   }
# }
#
# resource "helm_release" "aws_lbc" {
#   name             = "aws-load-balancer-controller"
#   repository       = "https://aws.github.io/eks-charts"
#   chart            = "aws-load-balancer-controller"
#   namespace        = "kube-system"
#   version          = "1.8.1"
#   timeout          = 600
#   wait             = true
#   values = [
#     yamlencode({
#       clusterName  = var.cluster_name
#       region       = var.aws_region
#       vpcId        = data.aws_vpc.cluster.id
#       serviceAccount = { create = true, name = "aws-load-balancer-controller" }
#       enableShield = false
#       enableWaf    = false
#       enableWafv2  = false
#     })
#   ]
#   depends_on = [var.cluster_ready, null_resource.pre_install_cleanup]
# }
#
# resource "null_resource" "wait_for_lbc_webhook" {
#   provisioner "local-exec" {
#     environment = { KUBECONFIG = "/home/ubuntu/.kube/config" }
#     command     = <<-EOT
#       echo "Waiting for LBC webhook endpoint to be ready..."
#       for i in $(seq 1 36); do
#         ENDPOINT=$(kubectl get endpoints aws-load-balancer-webhook-service \
#           -n kube-system -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)
#         if echo "$ENDPOINT" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
#           echo "LBC webhook is ready at $ENDPOINT"
#           exit 0
#         fi
#         echo "Not ready yet, attempt $i/36..."
#         sleep 5
#       done
#       echo "ERROR: LBC webhook endpoint never became ready"
#       exit 1
#     EOT
#   }
#   depends_on = [helm_release.aws_lbc]
# }
# ─────────────────────────────────────────────────────────────────────────────

# nginx ingress controller — single controller for all HTTP routing.
# NodePort :30080 is the fixed entry point for both the external ALB and
# internal NLB (both managed by modules/loadbalancer via Terraform).
# nginx routes based on URL path:
#   /        → app pods (ClusterIP) — defined in GitOps repo Ingress resources
#   /argocd  → argocd-server (ClusterIP)
resource "helm_release" "nginx_ingress" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.10.1"
  timeout          = 600
  wait             = true

  values = [
    yamlencode({
      controller = {
        service = {
          type = "NodePort"
          nodePorts = {
            http  = 30080
            https = 30443
          }
        }
      }
    })
  ]

  # ── LBC approach: LoadBalancer type with NLB annotations (commented out) ──
  # values = [
  #   yamlencode({
  #     controller = {
  #       service = {
  #         type = "LoadBalancer"
  #         nodePorts = { http = 30080, https = 30443 }
  #         annotations = {
  #           "service.beta.kubernetes.io/aws-load-balancer-type"             = "external"
  #           "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "instance"
  #           "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internal"
  #           "service.beta.kubernetes.io/aws-load-balancer-name"            = "k8s-nginx-internal-nlb"
  #         }
  #       }
  #     }
  #   })
  # ]

  depends_on = [var.cluster_ready, null_resource.pre_install_cleanup]
  # ── LBC approach dependency (commented out) ──
  # depends_on = [var.cluster_ready, null_resource.pre_install_cleanup, null_resource.wait_for_lbc_webhook]
}

# ArgoCD — ClusterIP service, accessed via internal NLB → nginx → /argocd path.
# server.rootpath strips /argocd from all asset URLs so the UI loads correctly.
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
          type = "ClusterIP"
        }
      }
      configs = {
        params = {
          # server.insecure: skip TLS since nginx terminates nothing and we have no cert yet
          "server.insecure" = true
          # server.rootpath removed — ArgoCD now serves at / on its own domain
          # (argocd.internal.kubeadm-demo.com) so no path prefix stripping needed
        }
      }
    })
  ]

  depends_on = [var.cluster_ready, null_resource.pre_install_cleanup]
  # ── LBC approach dependency (commented out) ──
  # depends_on = [var.cluster_ready, null_resource.pre_install_cleanup, null_resource.wait_for_lbc_webhook]
}

data "kubernetes_secret" "argocd_admin_password" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = "argocd"
  }
  depends_on = [helm_release.argocd]
}

# Applies:
#   1. ArgoCD Application CR — tells ArgoCD to sync from the GitOps repo
#   2. ArgoCD nginx Ingress  — routes /argocd → argocd-server (ClusterIP)
#
# Note: external-alb-ingress is no longer applied here.
# The external ALB is now a Terraform resource in modules/loadbalancer.
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
      echo "Waiting for nginx ingress controller to be ready..."
      kubectl wait --for=condition=available --timeout=300s \
        deployment/ingress-nginx-controller -n ingress-nginx
      echo "Applying ArgoCD Application CR and nginx Ingress..."
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
      spec:
        ingressClassName: nginx
        rules:
        - host: argocd.${var.nlb_private_ip}.nip.io
          http:
            paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: argocd-server
                  port:
                    number: 80
      # ── Route53 approach: use real internal domain (commented out) ──
      # - host: argocd.internal.$${var.domain_name}
      #   http:
      #     paths:
      #     - path: /
      #       pathType: Prefix
      #       backend:
      #         service:
      #           name: argocd-server
      #           port:
      #             number: 80
      EOF
    EOT
  }

  depends_on = [helm_release.argocd, helm_release.nginx_ingress]
}

# ── LBC approach: data sources for dynamic ALB/NLB hostnames (commented out) ──
# data "kubernetes_ingress_v1" "external_alb" {
#   metadata { name = "external-alb-ingress", namespace = "ingress-nginx" }
#   depends_on = [null_resource.argocd_application]
# }
#
# data "kubernetes_service" "nginx_nlb" {
#   metadata { name = "ingress-nginx-controller", namespace = "ingress-nginx" }
#   depends_on = [helm_release.nginx_ingress]
# }
