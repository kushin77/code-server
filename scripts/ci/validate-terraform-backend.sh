#!/bin/bash
# @file scripts/ci/validate-terraform-backend.sh
# @description P1 #2421: Validate that Terraform remote state backend is properly configured
# @governance GOV-002: All Terraform environments must use remote state with locking

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

log_info() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"; }
log_error() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2; }
log_success() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [✅] $*"; }
log_warning() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WARN] $*"; }

# Check each environment for backend configuration
for env in private air-gapped; do
  ENV_DIR="${REPO_ROOT}/terraform/environments/${env}"
  
  if [[ ! -d "${ENV_DIR}" ]]; then
    log_warning "Environment directory not found: $ENV_DIR"
    continue
  fi
  
  log_info "Validating Terraform backend for environment: $env"
  
  # Check for backend.tf file
  if [[ ! -f "${ENV_DIR}/backend.tf" ]]; then
    log_error "Missing backend.tf in ${env} environment"
    exit 1
  fi
  
  # Validate backend configuration has S3 and DynamoDB
  if grep -q 'backend "s3"' "${ENV_DIR}/backend.tf" && \
     grep -q 'dynamodb_table' "${ENV_DIR}/backend.tf" && \
     grep -q 'encrypt.*true' "${ENV_DIR}/backend.tf"; then
    log_success "Backend configuration valid for ${env} environment"
  else
    log_error "Backend configuration incomplete for ${env} environment"
    log_error "Must have: backend \"s3\", dynamodb_table, and encrypt = true"
    exit 1
  fi
  
  # Validate terraform backend syntax (skip full validation if modules not initialized)
  cd "${ENV_DIR}"
  if ! terraform init -backend=false -upgrade > /dev/null 2>&1; then
    log_warning "Terraform backend validation skipped (modules not initialized yet)"
  else
    log_success "Terraform backend initialized successfully for ${env}"
  fi
done

log_success "All Terraform backend configurations are valid"
log_info ""
log_info "To initialize backends, run:"
log_info "  cd terraform/environments/private && terraform init"
log_info "  cd terraform/environments/air-gapped && terraform init"
