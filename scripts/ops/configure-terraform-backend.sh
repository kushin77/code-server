#!/bin/bash
# Configure Terraform to use MinIO S3 backend for centralized state management
# This enables:
# - Centralized state storage (not tied to single host)
# - State locking to prevent concurrent applies
# - State versioning for rollback capability
# - Multi-host access to state

set -euo pipefail

trap 'echo "Backend configuration failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/*.tmp' EXIT

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TERRAFORM_DIR="${REPO_ROOT}/terraform/environments/private"
BACKEND_CONFIG_FILE="${TERRAFORM_DIR}/backend.tf"

# Configuration
MINIO_ENDPOINT="${MINIO_ENDPOINT:-localhost:9000}"
MINIO_BUCKET="${MINIO_BUCKET:-terraform-state}"
MINIO_KEY="${MINIO_KEY:-primary/terraform.tfstate}"
MINIO_REGION="${MINIO_REGION:-us-east-1}"
MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-minioadmin}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-minioadmin-change-me}"
MINIO_USE_SSL="${MINIO_USE_SSL:-false}"

echo "Configuring Terraform S3 backend"
echo "  Endpoint: $MINIO_ENDPOINT"
echo "  Bucket: $MINIO_BUCKET"
echo "  Key: $MINIO_KEY"
echo ""

# Create backend.tf configuration
cat > "${BACKEND_CONFIG_FILE}" << 'EOF'
# Terraform S3 Backend Configuration
# Stores state in MinIO S3-compatible storage for centralized management

terraform {
  backend "s3" {
    # S3-compatible endpoint (MinIO)
    endpoint            = var.minio_endpoint
    bucket              = var.minio_bucket
    key                 = var.minio_key
    region              = var.minio_region
    
    # Authentication
    access_key          = var.minio_access_key
    secret_key          = var.minio_secret_key
    
    # Settings
    use_path_style      = true
    skip_credentials_validation = false
    skip_region_validation      = false
    
    # Locking for state consistency
    dynamodb_table      = "terraform-locks"
    
    # Encryption at rest (if supported)
    sse                 = "AES256"
    
    # Options
    encrypt             = true
    skip_requesting_account_id = false
  }
}
EOF

echo "✓ Backend configuration created: $BACKEND_CONFIG_FILE"
echo ""
echo "Backend Configuration:"
cat "$BACKEND_CONFIG_FILE"
echo ""
echo "Next steps:"
echo "1. Set environment variables:"
echo "   export AWS_ACCESS_KEY_ID=$MINIO_ACCESS_KEY"
echo "   export AWS_SECRET_ACCESS_KEY=$MINIO_SECRET_KEY"
echo ""
echo "2. Initialize Terraform with backend:"
echo "   cd $TERRAFORM_DIR"
echo "   terraform init"
echo ""
echo "3. Migrate state to backend:"
echo "   ./scripts/ops/terraform-state-migrate.sh"
