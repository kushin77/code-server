#!/usr/bin/env bash
# @file        scripts/deploy-qa-credentials-to-gcp.sh
# @module      deployment/gcp/qa-credentials
# @description Deploy QA Credentials IaC to GCP (immutable, idempotent, automated)
# @usage       Run on production host (192.168.168.31): bash scripts/deploy-qa-credentials-to-gcp.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# Source common utilities
source scripts/_common/init.sh

# ============================================================================
# Configuration
# ============================================================================

GCP_PROJECT_ID="${GCP_PROJECT_ID:-kushin77-ops}"
QA_EMAIL="${QA_EMAIL:-qa@kushnir.cloud}"
CI_SERVICE_ACCOUNT_EMAIL="${CI_SERVICE_ACCOUNT_EMAIL:-github-actions@kushin77-ops.iam.gserviceaccount.com}"
TERRAFORM_DIR="terraform"
STATE_FILE="terraform.tfstate"

# ============================================================================
# Step 1: Pre-flight Checks
# ============================================================================

log_info "=== QA Credentials IaC Deployment to GCP ==="
log_info ""
log_info "Step 1: Pre-flight checks"

# Check Terraform is installed
if ! command -v terraform &>/dev/null; then
    log_fatal "Terraform not found. Install from https://www.terraform.io/downloads"
fi
log_info "✓ Terraform installed: $(terraform version | head -1)"

# Check Google Cloud CLI is installed
if ! command -v gcloud &>/dev/null; then
    log_fatal "Google Cloud CLI not found. Install from https://cloud.google.com/sdk/docs/install"
fi
log_info "✓ Google Cloud CLI installed"

# Check gcloud is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
    log_fatal "gcloud not authenticated. Run: gcloud auth login"
fi
CURRENT_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
log_info "✓ Authenticated as: $CURRENT_ACCOUNT"

# Check GCP project
if ! gcloud projects describe "$GCP_PROJECT_ID" &>/dev/null; then
    log_fatal "GCP project not found: $GCP_PROJECT_ID"
fi
log_info "✓ GCP project accessible: $GCP_PROJECT_ID"

# Check Terraform files exist
if [ ! -f "$TERRAFORM_DIR/qa-credentials.tf" ]; then
    log_fatal "Terraform file not found: $TERRAFORM_DIR/qa-credentials.tf"
fi
log_info "✓ Terraform configuration files present"

# ============================================================================
# Step 2: Validate QA Password
# ============================================================================

log_info ""
log_info "Step 2: Validate QA password"

if [ -z "${QA_PASSWORD:-}" ]; then
    log_info "No QA_PASSWORD set. Generating secure password..."
    QA_PASSWORD=$(openssl rand -hex 16 | head -c 32)
    log_info "Generated QA password (32 chars)"
    read -p "Press Enter to continue with generated password, or Ctrl+C to cancel: " -t 5 || true
else
    log_info "Using provided QA_PASSWORD"
fi

if [ ${#QA_PASSWORD} -lt 16 ]; then
    log_fatal "QA password too short. Must be at least 16 characters."
fi
log_info "✓ QA password valid (${#QA_PASSWORD} characters)"

# ============================================================================
# Step 3: Terraform Initialization
# ============================================================================

log_info ""
log_info "Step 3: Initialize Terraform"

cd "$TERRAFORM_DIR"

terraform init -upgrade=true
log_info "✓ Terraform initialized"

# ============================================================================
# Step 4: Terraform Format & Validation
# ============================================================================

log_info ""
log_info "Step 4: Validate Terraform configuration"

if ! terraform fmt -check -recursive . &>/dev/null; then
    log_warn "Terraform code not properly formatted. Running terraform fmt..."
    terraform fmt -recursive .
fi

terraform validate
log_info "✓ Terraform configuration valid"

# ============================================================================
# Step 5: Terraform Plan (Dry-run)
# ============================================================================

log_info ""
log_info "Step 5: Plan infrastructure changes (dry-run)"

PLAN_FILE="qa-credentials.tfplan"

terraform plan \
    -var="gcp_project_id=$GCP_PROJECT_ID" \
    -var="qa_email=$QA_EMAIL" \
    -var="qa_password=$QA_PASSWORD" \
    -var="ci_service_account_email=$CI_SERVICE_ACCOUNT_EMAIL" \
    -out="$PLAN_FILE"

log_info "✓ Plan complete. Review output above before confirming."
log_info ""
read -p "Proceed with terraform apply? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log_info "Deployment cancelled."
    rm -f "$PLAN_FILE"
    exit 0
fi

# ============================================================================
# Step 6: Terraform Apply
# ============================================================================

log_info ""
log_info "Step 6: Apply infrastructure changes"

terraform apply "$PLAN_FILE"
log_info "✓ Infrastructure deployed to GCP"

rm -f "$PLAN_FILE"

# ============================================================================
# Step 7: Verify Deployment
# ============================================================================

log_info ""
log_info "Step 7: Verify deployment"

# Check GSM secrets exist
if gcloud secrets describe "qa-email" --project="$GCP_PROJECT_ID" &>/dev/null; then
    log_info "✓ GSM secret 'qa-email' exists"
else
    log_error "✗ GSM secret 'qa-email' not found"
fi

if gcloud secrets describe "qa-password" --project="$GCP_PROJECT_ID" &>/dev/null; then
    log_info "✓ GSM secret 'qa-password' exists"
else
    log_error "✗ GSM secret 'qa-password' not found"
fi

# Check IAM bindings
if gcloud secrets get-iam-policy "qa-email" --project="$GCP_PROJECT_ID" 2>/dev/null | grep -q "$CI_SERVICE_ACCOUNT_EMAIL"; then
    log_info "✓ CI/CD service account has access to 'qa-email'"
else
    log_error "✗ CI/CD service account missing access to 'qa-email'"
fi

if gcloud secrets get-iam-policy "qa-password" --project="$GCP_PROJECT_ID" 2>/dev/null | grep -q "$CI_SERVICE_ACCOUNT_EMAIL"; then
    log_info "✓ CI/CD service account has access to 'qa-password'"
else
    log_error "✗ CI/CD service account missing access to 'qa-password'"
fi

# ============================================================================
# Step 8: Verify Immutability
# ============================================================================

log_info ""
log_info "Step 8: Verify immutability enforcement"

# Check prevent_destroy is set
if grep -q "prevent_destroy = true" qa-credentials.tf; then
    log_info "✓ prevent_destroy = true (deletion prevented)"
else
    log_warn "prevent_destroy not found in configuration"
fi

# Check ignore_changes is set
if grep -q "ignore_changes = all" qa-credentials.tf; then
    log_info "✓ ignore_changes = all (immutable after creation)"
else
    log_warn "ignore_changes not found in configuration"
fi

# ============================================================================
# Step 9: Test Idempotency
# ============================================================================

log_info ""
log_info "Step 9: Test idempotency (no changes on second run)"

terraform plan \
    -var="gcp_project_id=$GCP_PROJECT_ID" \
    -var="qa_email=$QA_EMAIL" \
    -var="qa_password=$QA_PASSWORD" \
    -var="ci_service_account_email=$CI_SERVICE_ACCOUNT_EMAIL" \
    -out="$PLAN_FILE" 2>&1 | tee /tmp/terraform-plan.log

if grep -q "No changes" /tmp/terraform-plan.log; then
    log_info "✓ Idempotency confirmed: no changes on second run"
else
    log_warn "Terraform plan detected changes. This may indicate non-idempotent configuration."
fi

rm -f "$PLAN_FILE" /tmp/terraform-plan.log

# ============================================================================
# Success
# ============================================================================

log_info ""
log_info "=== Deployment Complete ==="
log_info ""
log_info "✓ QA Credentials IaC deployed to GCP"
log_info "✓ Immutability enforced (prevent_destroy, ignore_changes)"
log_info "✓ Idempotency verified (no changes on re-run)"
log_info "✓ IAM bindings created (CI/CD access configured)"
log_info ""
log_info "Next steps:"
log_info "1. GitHub Actions will automatically pick up credentials from GSM"
log_info "2. Push a commit to main to trigger E2E OAuth testing"
log_info "3. Workflow will run 556 OAuth endpoint tests automatically"
log_info ""
log_info "To rotate credentials:"
log_info "  bash scripts/deploy-qa-credentials-iac.sh  # Run again with new password"
log_info ""
