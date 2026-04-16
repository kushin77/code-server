#!/usr/bin/env bash
################################################################################
# MinIO Setup & Initialization Script
# File: scripts/minio-setup.sh
# Purpose: Initialize MinIO bucket and credentials for Terraform remote state
# Usage: ./scripts/minio-setup.sh
# Owner: Infrastructure Team
# Requirements: MinIO container running (docker-compose up -d minio)
################################################################################

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ════════════════════════════════════════════════════════════════════════════

MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://minio:9000}"
MINIO_ROOT_USER="${MINIO_ROOT_USER:-minioadmin}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-minioadmin}"
BUCKET_NAME="terraform-state"
TERRAFORM_USER="terraform"
TERRAFORM_PASSWORD="${TERRAFORM_STATE_PASSWORD:-terraform_secure_password_change_me}"

echo "════════════════════════════════════════════════════════════════════════════"
echo "  MinIO Setup for Terraform Remote State"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Configuration:"
echo "  • MinIO Endpoint: ${MINIO_ENDPOINT}"
echo "  • Root User: ${MINIO_ROOT_USER}"
echo "  • Bucket: ${BUCKET_NAME}"
echo "  • Terraform User: ${TERRAFORM_USER}"
echo ""

# ════════════════════════════════════════════════════════════════════════════
# PHASE 1: CHECK MINIO CONNECTIVITY
# ════════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}▸ Phase 1: Checking MinIO connectivity...${NC}"

# Check if mc (MinIO client) is installed
if ! command -v mc &> /dev/null; then
  echo -e "${RED}✗ MinIO client (mc) not found${NC}"
  echo "  Install: brew install minio/stable/mc (macOS) or see https://docs.min.io/minio/linux/reference/minio-mc.html"
  exit 1
fi

# Configure MinIO alias
echo "  Setting up MinIO alias..."
mc alias set minio "${MINIO_ENDPOINT}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" || {
  echo -e "${RED}✗ Failed to connect to MinIO${NC}"
  echo "  Verify MinIO is running: docker-compose up -d minio"
  exit 1
}

echo -e "${GREEN}✓ Connected to MinIO${NC}"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 2: CREATE BUCKET
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}▸ Phase 2: Creating bucket for Terraform state...${NC}"

if mc ls "minio/${BUCKET_NAME}" >/dev/null 2>&1; then
  echo -e "${YELLOW}⚠ Bucket '${BUCKET_NAME}' already exists${NC}"
else
  echo "  Creating bucket: ${BUCKET_NAME}"
  mc mb "minio/${BUCKET_NAME}"
  echo -e "${GREEN}✓ Bucket created${NC}"
fi

# Enable versioning (allows rollback to previous state)
echo "  Enabling versioning on bucket..."
mc version enable "minio/${BUCKET_NAME}"
echo -e "${GREEN}✓ Versioning enabled${NC}"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 3: CREATE SERVICE ACCOUNT FOR TERRAFORM
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}▸ Phase 3: Creating Terraform service account...${NC}"

# Create policy for Terraform access to terraform-state bucket only
POLICY_NAME="terraform-state-policy"
POLICY_JSON=$(cat <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketVersioning",
        "s3:ListBucketVersions"
      ],
      "Resource": "arn:aws:s3:::terraform-state"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetObjectVersion"
      ],
      "Resource": "arn:aws:s3:::terraform-state/*"
    }
  ]
}
EOF
)

echo "  Saving policy: ${POLICY_NAME}"
echo "${POLICY_JSON}" > /tmp/terraform-policy.json

# Create policy in MinIO (using root credentials)
mc admin policy create "minio" "${POLICY_NAME}" /tmp/terraform-policy.json || {
  echo -e "${YELLOW}⚠ Policy already exists${NC}"
}

# Create service account
echo "  Creating service account: ${TERRAFORM_USER}"
SA_JSON=$(mc admin user svcacct add --json "minio" "${MINIO_ROOT_USER}" | head -1 || true)

if [[ -z "$SA_JSON" || "$SA_JSON" == "" ]]; then
  # Service account creation failed, user may already exist
  echo -e "${YELLOW}⚠ Service account creation failed (may already exist)${NC}"
  echo "  Using manual credentials from environment variables:"
  echo "    AWS_ACCESS_KEY_ID=${TERRAFORM_USER}"
  echo "    AWS_SECRET_ACCESS_KEY=<from .env TERRAFORM_STATE_PASSWORD>"
else
  # Extract credentials from response
  TF_ACCESS_KEY=$(echo "$SA_JSON" | jq -r '.accessKey')
  TF_SECRET_KEY=$(echo "$SA_JSON" | jq -r '.secretKey')
  
  echo -e "${GREEN}✓ Service account created${NC}"
  echo "  Access Key: ${TF_ACCESS_KEY}"
  echo "  Secret Key: ${TF_SECRET_KEY} (save to .env as TERRAFORM_STATE_PASSWORD)"
fi

# Add policy to terraform user
echo "  Attaching policy to ${TERRAFORM_USER}..."
mc admin policy attach "minio" "${POLICY_NAME}" --user="${TERRAFORM_USER}" || {
  echo -e "${YELLOW}⚠ Policy attachment skipped${NC}"
}

echo -e "${GREEN}✓ Service account configured${NC}"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 4: VERIFY AND DISPLAY SUMMARY
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}▸ Phase 4: Verification${NC}"

echo "  Checking bucket contents:"
mc ls "minio/${BUCKET_NAME}" || true
echo -e "${GREEN}✓ Bucket verified${NC}"

echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo "  MinIO SETUP COMPLETE"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo ""
echo "1. Update .env with Terraform credentials:"
echo "   export AWS_ACCESS_KEY_ID=${TERRAFORM_USER}"
echo "   export AWS_SECRET_ACCESS_KEY=<secret-key>"
echo ""
echo "2. Update terraform/backend-s3.tf to uncomment the 'backend \"s3\"' block"
echo ""
echo "3. Migrate local state to remote:"
echo "   cd terraform"
echo "   terraform init -migrate-state"
echo ""
echo "4. Verify remote state:"
echo "   terraform state list"
echo "   terraform state show (should pull from MinIO)"
echo ""
echo "5. Backup local state file (optional, can delete after):"
echo "   cp terraform.tfstate terraform.tfstate.backup"
echo "   rm terraform.tfstate terraform.tfstate.lock.hcl"
echo ""
echo "6. MinIO Web Console:"
echo "   http://minio:9001 (credentials: ${MINIO_ROOT_USER}/${MINIO_ROOT_PASSWORD})"
echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "${GREEN}✓ MinIO setup complete${NC}"
