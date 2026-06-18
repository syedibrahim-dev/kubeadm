# ─────────────────────────────────────────────────────────────────────────────
# ENVIRONMENT-LEVEL config — shared values used by two or more modules.
# Module-specific config (instance types, chart versions, etc.) lives in
# each module's own terragrunt.hcl locals block.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  environment  = "dev"
  cluster_name = "kubeadm-cluster"

  # ── Network topology (vpc + security + argocd) ─────────────────────────────
  vpc_cidr              = "10.0.0.0/16"
  public_subnet_cidr    = "10.0.1.0/24"
  private_subnet_cidr   = "10.0.10.0/24"
  public_subnet_2_cidr  = "10.0.2.0/24"
  private_subnet_2_cidr = "10.0.11.0/24"

  # ── Kubernetes (compute + admin) ───────────────────────────────────────────
  k8s_version        = "1.31"
  control_plane_name = "K8s-Control-Plane"
  enable_auto_setup  = true
}
