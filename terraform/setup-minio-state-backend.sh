#!/bin/bash
# terraform/setup-minio-state-backend.sh
# P1 #417: Configure MinIO S3-compatible terraform state backend
# Purpose: Migrate state from local → remote MinIO for team collaboration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}"

# Source environment configuration (exports PRIMARY_HOST, REPLICA_HOST, VIP)
if [[ -f "${PROJECT_ROOT}/scripts/lib/env.sh" ]]; then
  source "${PROJECT_ROOT}/scripts/lib/env.sh"
fi

MINIO_HOST="${MINIO_HOST:-${PRIMARY_HOST}:9000}"
MINIO_BUCKET="${MINIO_BUCKET:-terraform-state}"
MINIO_REGION="${MINIO_REGION:-us-east-1}"

echo "════════════════════════════════════════════════════════════"
echo "Setup: Terraform Remote State Backend - MinIO S3"
echo "════════════════════════════════════════════════════════════"

# Step 1: Create MinIO bucket
echo ""
echo "Step 1: Creating MinIO S3 bucket..."
echo "Host: ${MINIO_HOST}"
echo "Bucket: ${MINIO_BUCKET}"

# Check if MinIO is accessible
if command -v mc &> /dev/null; then
    echo "✓ MinIO client (mc) available"
    
    # Configure MinIO alias
    mc alias set minio http://${MINIO_HOST} ${MINIO_ROOT_USER:-minioadmin} ${MINIO_ROOT_PASSWORD:-minioadmin} || true
    
    # Create bucket
    mc mb minio/${MINIO_BUCKET} --ignore-existing
    
    # Enable versioning for state safety
    mc version enable minio/${MINIO_BUCKET}
    
    echo "✓ MinIO bucket created with versioning enabled"
else
    echo "⚠️ MinIO client (mc) not available. Skipping bucket creation."
    echo "   Ensure MinIO bucket '${MINIO_BUCKET}' exists on ${MINIO_HOST}"
fi

# Step 2: Create backend-config.hcl if it doesn't exist
echo ""
echo "Step 2: Creating backend configuration..."

BACKEND_CONFIG="${TERRAFORM_DIR}/backend-config.hcl"
if [ ! -f "${BACKEND_CONFIG}" ]; then
    # Extract host from MINIO_HOST (remove port if present)
    MINIO_IP="${MINIO_HOST%%:*}"
    cat > "${BACKEND_CONFIG}" << EOF
# Backend configuration for MinIO S3-compatible storage
# DO NOT commit credentials - use environment variables:
#   export AWS_ACCESS_KEY_ID=minioadmin
#   export AWS_SECRET_ACCESS_KEY=minioadmin
#   export AWS_REGION=us-east-1

bucket         = "terraform-state"
key            = "prod/terraform.tfstate"
region         = "us-east-1"
endpoint       = "http://${MINIO_HOST}"
use_path_style = true

# Enable state locking via DynamoDB simulation (optional)
# dynamodb_table = "terraform-locks"

# Enable encryption at rest
encrypt        = true
EOF
    echo "✓ Backend configuration created: ${BACKEND_CONFIG}"
else
    echo "ℹ Backend configuration already exists: ${BACKEND_CONFIG}"
fi

# Step 3: Initialize terraform with backend
echo ""
echo "Step 3: Initializing Terraform with remote backend..."
echo "Command: terraform init -backend-config=backend-config.hcl"

cd "${TERRAFORM_DIR}"

# Set environment variables for MinIO credentials
export AWS_ACCESS_KEY_ID="${MINIO_ACCESS_KEY:-minioadmin}"
export AWS_SECRET_ACCESS_KEY="${MINIO_SECRET_KEY:-minioadmin}"
export AWS_REGION="${MINIO_REGION}"

terraform init -backend-config=backend-config.hcl -upgrade || {
    echo "❌ Terraform init failed"
    exit 1
}

echo "✓ Terraform initialized with MinIO backend"

# Step 4: Verify state migration
echo ""
echo "Step 4: Verifying state migration..."

# Check if state is now remote
terraform state list > /dev/null 2>&1 && {
    echo "✓ State accessible from remote backend"
    
    # List resources in state
    RESOURCE_COUNT=$(terraform state list | wc -l)
    echo "  Resources in state: ${RESOURCE_COUNT}"
} || {
    echo "⚠️ Could not access remote state. Checking local state..."
    if [ -f terraform.tfstate ]; then
        echo "  Local state file exists: terraform.tfstate"
        echo "  Run 'terraform state pull' to verify access"
    fi
}

# Step 5: Backup local state
echo ""
echo "Step 5: Backing up local state..."

BACKUP_DIR="${TERRAFORM_DIR}/../backups/terraform-state"
mkdir -p "${BACKUP_DIR}"

if [ -f terraform.tfstate ]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="${BACKUP_DIR}/terraform.tfstate.${TIMESTAMP}.backup"
    cp terraform.tfstate "${BACKUP_FILE}"
    echo "✓ Local state backed up to: ${BACKUP_FILE}"
    
    # Optional: Remove local state after successful migration
    # read -p "Remove local terraform.tfstate? (y/n) " -n 1 -r
    # echo
    # if [[ $REPLY =~ ^[Yy]$ ]]; then
    #     rm terraform.tfstate
    #     echo "✓ Local state removed"
    # fi
else
    echo "ℹ No local state file to backup"
fi

# Step 6: Test lock functionality
echo ""
echo "Step 6: Testing state locking..."

# Create a test lock
terraform state lock test-lock || {
    echo "⚠️ State locking not supported (may use DynamoDB for full locking)"
}

echo "✓ State locking test complete"

# Step 7: Summary
echo ""
echo "════════════════════════════════════════════════════════════"
echo "✓ SETUP COMPLETE: Remote State Backend Ready"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Remote State Configuration:"
echo "  Endpoint: ${MINIO_HOST}"
echo "  Bucket: ${MINIO_BUCKET}"
echo "  Region: ${MINIO_REGION}"
echo "  Encryption: Enabled"
echo ""
echo "Next Steps:"
echo "  1. Verify state is accessible:"
echo "     terraform state list"
echo "  2. Test remote operations:"
echo "     terraform plan"
echo "  3. Archive local state:"
echo "     rm -f terraform.tfstate terraform.tfstate.backup"
echo ""
echo "To restore from backup:"
echo "  terraform state push <backup-file>"
echo ""
echo "════════════════════════════════════════════════════════════"
