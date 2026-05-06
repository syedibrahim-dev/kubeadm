# ─────────────────────────────────────────────────────────────────────────────
# DATA SOURCES — discover Stage 1 infrastructure via tags.
# Self-contained: no dependency on module.vpc outputs, so
# -target=module.argocd[0] on the admin EC2 works without Stage 1 state.
# ─────────────────────────────────────────────────────────────────────────────

data "aws_vpc" "cluster" {
  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "tag:kubernetes.io/role/elb"
    values = ["1"]
  }
  filter {
    name   = "tag:kubernetes.io/cluster/${var.cluster_name}"
    values = ["owned"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "tag:kubernetes.io/role/internal-elb"
    values = ["1"]
  }
  filter {
    name   = "tag:kubernetes.io/cluster/${var.cluster_name}"
    values = ["owned"]
  }
}

# Read after ArgoCD is deployed — used in outputs.tf to surface the initial admin password.
data "kubernetes_secret" "argocd_admin_password" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = var.namespaces.argocd
  }
  depends_on = [helm_release.argocd]
}
