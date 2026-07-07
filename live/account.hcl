# ─────────────────────────────────────────────────────────────────────────────
# ACCOUNT-LEVEL config — one file per AWS account.
# Place a different account.hcl in each account root if you add multi-account. MULTIACCOUNT SETUP
# ─────────────────────────────────────────────────────────────────────────────

locals {
  aws_account_id = "569023477847" # e.g. "123456789012"
  aws_region     = "us-east-1"
}
