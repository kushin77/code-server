#!/bin/bash
# @file scripts/bootstrap/setup-terraform-backend.sh
# @description P1 #2421: Bootstrap S3 backend and DynamoDB lock table for Terraform state management
# @governance GOV-002: State infrastructure must be set up before any terraform apply

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration
BUCKET_NAME="${TF_BUCKET_NAME:-code-server-enterprise-tfstate}"
LOCK_TABLE="${TF_LOCK_TABLE:-code-server-enterprise-tfstate-lock}"
KMS_ALIAS="${TF_KMS_ALIAS:-alias/terraform-state}"
AWS_REGION="${AWS_REGION:-us-east-1}"

log_info() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"; }
log_error() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2; }
log_success() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [✅] $*"; }

# Check prerequisites
for cmd in aws jq; do
  if ! command -v "$cmd" &>/dev/null; then
    log_error "$cmd not found. Please install it first."
    exit 1
  fi
done

log_info "Setting up Terraform backend infrastructure..."

# 1. Create S3 bucket if it doesn't exist
log_info "Step 1/5: Creating S3 bucket..."
if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null; then
  log_success "S3 bucket already exists: $BUCKET_NAME"
else
  log_info "Creating S3 bucket: $BUCKET_NAME"
  aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$AWS_REGION" \
    $([ "$AWS_REGION" != "us-east-1" ] && echo "--create-bucket-configuration LocationConstraint=$AWS_REGION" || true) \
    || log_error "Failed to create bucket"
  log_success "S3 bucket created: $BUCKET_NAME"
fi

# 2. Enable versioning on the bucket
log_info "Step 2/5: Enabling S3 versioning..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --region "$AWS_REGION" \
  --versioning-configuration Status=Enabled
log_success "S3 versioning enabled"

# 3. Enable server-side encryption
log_info "Step 3/5: Enabling S3 encryption..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --region "$AWS_REGION" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
log_success "S3 encryption enabled (SSE-S3)"

# 4. Create DynamoDB lock table if it doesn't exist
log_info "Step 4/5: Creating DynamoDB lock table..."
if aws dynamodb describe-table --table-name "$LOCK_TABLE" --region "$AWS_REGION" 2>/dev/null | jq -e '.Table' >/dev/null; then
  log_success "DynamoDB table already exists: $LOCK_TABLE"
else
  log_info "Creating DynamoDB table: $LOCK_TABLE"
  aws dynamodb create-table \
    --table-name "$LOCK_TABLE" \
    --region "$AWS_REGION" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --tags Key=Project,Value=code-server-enterprise Key=Purpose,Value=terraform-state-lock
  
  # Wait for table to be active
  log_info "Waiting for DynamoDB table to be active..."
  aws dynamodb wait table-exists --table-name "$LOCK_TABLE" --region "$AWS_REGION"
  log_success "DynamoDB table created and active: $LOCK_TABLE"
fi

# 5. Enable point-in-time recovery
log_info "Step 5/5: Enabling DynamoDB point-in-time recovery..."
aws dynamodb update-continuous-backups \
  --table-name "$LOCK_TABLE" \
  --region "$AWS_REGION" \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true 2>/dev/null || true
log_success "DynamoDB backup configured"

log_success "Terraform backend infrastructure setup complete!"
log_info ""
log_info "Next steps:"
log_info "1. Run 'terraform init' in terraform/environments/private/"
log_info "2. Run 'terraform init' in terraform/environments/air-gapped/"
log_info "3. Verify state is being stored: aws s3 ls s3://$BUCKET_NAME/"
log_info "4. Verify lock table: aws dynamodb describe-table --table-name $LOCK_TABLE --region $AWS_REGION"
