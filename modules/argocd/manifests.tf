# ─────────────────────────────────────────────────────────────────────────────
# ARGOCD APPLICATION CR
# Tells ArgoCD which GitOps repo/path/branch to sync from.
# kubectl_manifest replaces null_resource + local-exec: helm_release.argocd
# with wait=true already ensures the CRD and server are ready before this runs.
# ─────────────────────────────────────────────────────────────────────────────

resource "kubectl_manifest" "argocd_application" {
  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: ${var.resource_names.argocd_application}
      namespace: ${var.namespaces.argocd}
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
  YAML

  depends_on = [helm_release.argocd]
}

# ─────────────────────────────────────────────────────────────────────────────
# ARGOCD NGINX INGRESS
# Routes /argocd → argocd-server (ClusterIP).
# No rewrite: server.rootpath=/argocd means ArgoCD handles the /argocd prefix
# itself. Rewriting to / causes 404 because ArgoCD only serves at /argocd.
# whitelist-source-range restricts to VPC CIDR — ArgoCD is internal-only.
# The external ALB also blocks /argocd* at the listener rule level (layer 1).
# ─────────────────────────────────────────────────────────────────────────────

resource "kubectl_manifest" "argocd_ingress" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: ${var.resource_names.argocd_ingress}
      namespace: ${var.namespaces.argocd}
      annotations:
        nginx.ingress.kubernetes.io/whitelist-source-range: "${var.vpc_cidr}"
    spec:
      ingressClassName: nginx
      rules:
        - http:
            paths:
              - path: ${var.argocd_root_path}
                pathType: Prefix
                backend:
                  service:
                    name: argocd-server
                    port:
                      number: 80
  YAML

  depends_on = [helm_release.argocd, helm_release.nginx_ingress]
}
