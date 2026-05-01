#!/bin/bash
# Migrate Terraform state from local file to MinIO S3 backend
# Safely moves state while maintaining integrity and enabling rollback

set -euo pipefail

trap 'log_error "Migration failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/*.tmp' EXIT

TERRAFORM_DIR="${1:-.}"
BACKUP_DIR="${2:-.terraform-state-backup}"
DRY_RUN="${DRY_RUN:-false}"

log_info() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_info "Terraform State Migration to MinIO S3 Backend"
log_info "=============================================="
log_info "Directory: $TERRAFORM_DIR"
log_info "Backup: $BACKUP_DIR"
log_info "Dry-run: $DRY_RUN"
log_info ""

# Step 1: Backup current state
log_info "Step 1: Backing up current state"
mkdir -p "$BACKUP_DIR"

if [[ -f "$TERRAFORM_DIR/terraform.tfstate" ]]; then
  BACKUP_FILE="$BACKUP_DIR/terraform.tfstate.backup-$(date +%Y%m%d-%H%M%S)"
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "  [DRY-RUN] Would backup to: $BACKUP_FILE"
  else
    cp "$TERRAFORM_DIR/terraform.tfstate" "$BACKUP_FILE"
    log_info "  ✓ Backed up to: $BACKUP_FILE"
  fi
else
  log_info "  No existing state file to backup"
fi

# Step 2: Verify backend configuration exists
log_info "Step 2: Verifying backend configuration"
if [[ ! -f "$TERRAFORM_DIR/backend.tf" ]]; then
  log_error "Backend configuration not found: $TERRAFORM_DIR/backend.tf"
  exit 1
fi
log_info "  ✓ Backend configuration found"

# Step 3: Validate terraform configuration
log_info "Step 3: Validating Terraform configuration"
if [[ "$DRY_RUN" == "true" ]]; then
  log_info "  [DRY-RUN] Would validate configuration"
else
  cd "$TERRAFORM_DIR"
  if ! terraform validate; then
    log_error "Terraform validation failed"
    exit 1
  fi
  log_info "  ✓ Configuration validated"
fi

# Step 4: Initialize with backend
log_info "Step 4: Initializing Terraform with backend"
if [[ "$DRY_RUN" == "true" ]]; then
  log_info "  [DRY-RUN] Would run: terraform init"
else
  cd "$TERRAFORM_DIR"
  if terraform init -upgrade; then
    log_info "  ✓ Terraform initialized with backend"
  else
    log_error "Terraform init failed"
    exit 1
  fi
fi

# Step 5: Verify state migration
log_info "Step 5: Verifying state in backend"
if [[ "$DRY_RUN" == "true" ]]; then
  log_info "  [DRY-RUN] Would verify backend state"
else
  cd "$TERRAFORM_DIR"
  if terraform state list > /dev/null 2>&1; then
    RESOURCE_COUNT=$(terraform state list | wc -l)
    log_info "  ✓ State accessible in backend"
    log_info "  ✓ Resources in state: $RESOURCE_COUNT"
  else
    log_error "Cannot access state in backend"
    exit 1
  fi
fi

# Step 6: Plan to verify nothing will change
log_info "Step 6: Verifying infrastructure matches state"
if [[ "$DRY_RUN" == "true" ]]; then
  log_info "  [DRY-RUN] Would run: terraform plan"
else
  cd "$TERRAFORM_DIR"
  if terraform plan -json | jq -s 'map(select(.type == "resource_drift")) | length' | grep -q "^0$"; then
    log_info "  ✓ Infrastructure matches state (no drift)"
  else
    log_info "  ⚠ Some resources may have drifted"
    log_info "  ⚠ Review with: terraform plan"
  fi
fi

# Step 7: Remove local state file (optional, keep for safety)
log_info "Step 7: Local state file handling"
log_info "  Local state file: $TERRAFORM_DIR/terraform.tfstate"
log_info "  ⚠ KEEPING local file for safety (can be deleted after verification)"
log_info "  To remove: rm $TERRAFORM_DIR/terraform.tfstate*"

log_info ""
log_info "=============================================="
log_info "Migration Status: SUCCESS"
log_info ""
log_info "Next steps:"
log_info "1. Verify remote state is working:"
log_info "   cd $TERRAFORM_DIR && terraform state list"
log_info ""
log_info "2. Test a small change:"
log_info "   terraform apply -auto-approve (on non-critical resource)"
log_info ""
log_info "3. After verification, delete local state:"
log_info "   rm $TERRAFORM_DIR/terraform.tfstate*"
log_info ""
log_info "4. Verify with other hosts:"
log_info "   Access state from replica: terraform state list"
log_info ""
log_info "Backup location: $BACKUP_DIR"
log_info "Restore if needed: cp $BACKUP_FILE $TERRAFORM_DIR/terraform.tfstate"
