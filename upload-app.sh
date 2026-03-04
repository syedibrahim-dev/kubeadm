#!/bin/bash
# Upload k8s-app to S3 for automated delivery to the admin EC2 instance.
# Run this from the workspace root after `terraform apply` has completed.

set -e

# ─── Resolve bucket name ───────────────────────────────────────────────────────
BUCKET_NAME="${1:-}"

if [ -z "$BUCKET_NAME" ]; then
    # Try to pull it from Terraform output automatically
    if command -v terraform &> /dev/null && [ -f "terraform.tfstate" ]; then
        BUCKET_NAME=$(terraform output -raw s3_bucket_name 2>/dev/null || true)
    fi
fi

if [ -z "$BUCKET_NAME" ]; then
    echo "ERROR: Could not determine the S3 bucket name."
    echo "Usage: $0 [bucket-name]"
    echo "       Or run from the Terraform workspace directory so the name is read automatically."
    exit 1
fi

# ─── Resolve AWS region ────────────────────────────────────────────────────────
AWS_REGION="${AWS_DEFAULT_REGION:-}"

if [ -z "$AWS_REGION" ] && command -v terraform &> /dev/null && [ -f "terraform.tfstate" ]; then
    AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || true)
fi

AWS_REGION="${AWS_REGION:-us-east-1}"

# ─── Check k8s-app directory exists ────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR/k8s-app"

if [ ! -d "$APP_DIR" ]; then
    echo "ERROR: k8s-app directory not found at $APP_DIR"
    exit 1
fi

# ─── Upload ────────────────────────────────────────────────────────────────────
echo "Uploading k8s-app to s3://$BUCKET_NAME/k8s-app/ (region: $AWS_REGION)..."

aws s3 sync "$APP_DIR/" "s3://$BUCKET_NAME/k8s-app/" \
    --region "$AWS_REGION" \
    --delete \
    --exclude "*.DS_Store" \
    --exclude "node_modules/*" \
    --exclude "frontend/node_modules/*" \
    --exclude "backend/vendor/*"

echo ""
echo "Upload complete!"
echo ""
echo "If the admin instance is ALREADY RUNNING, manually re-sync inside it:"
echo ""
echo "  sudo su - ubuntu"
echo "  aws s3 sync s3://$BUCKET_NAME/k8s-app/ ~/k8s-app/ --region $AWS_REGION --delete"
echo "  chmod +x ~/k8s-app/deploy.sh"
echo ""
echo "Then deploy:"
echo "  cd ~/k8s-app && bash deploy.sh"
echo ""
