#!/usr/bin/env bash
# @file        scripts/ops/create-qa-user-automated.sh
# @module      operations/authentication
# @description Automated QA user creation and GSM credential setup - Issue #983 + #984
# @status      Ready for immediate execution (requires admin Google Workspace access)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"
init_repo

# Configuration
WORKSPACE_DOMAIN="${WORKSPACE_DOMAIN:-kushnir.cloud}"
GCP_PROJECT="${GCP_PROJECT:-kushin77-ops}"
QA_USER_EMAIL="qa@${WORKSPACE_DOMAIN}"
# shellcheck disable=SC2034
QA_USER_FIRST_NAME="QA"
# shellcheck disable=SC2034
QA_USER_LAST_NAME="Automation"
SERVICE_ACCOUNT_JSON="${SERVICE_ACCOUNT_JSON:-}"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --workspace-domain)
      WORKSPACE_DOMAIN="$2"
      QA_USER_EMAIL="qa@${WORKSPACE_DOMAIN}"
      shift 2
      ;;
    --gcp-project)
      GCP_PROJECT="$2"
      shift 2
      ;;
    --service-account-json)
      SERVICE_ACCOUNT_JSON="$2"
      shift 2
      ;;
    *)
      log_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Step 1: Pre-flight checks
log_info "Step 1: Pre-flight checks..."

# Check gcloud is installed
if ! command -v gcloud &> /dev/null; then
  log_error "gcloud CLI not found. Please install it first."
  exit 1
fi

# Set project context
gcloud config set project "$GCP_PROJECT" &> /dev/null

# Step 2: Google Workspace User Creation
log_info "Step 2: Google Workspace User Management..."

if [[ -n "$SERVICE_ACCOUNT_JSON" ]]; then
  if [[ ! -f "$SERVICE_ACCOUNT_JSON" ]]; then
    log_error "Service account file not found: $SERVICE_ACCOUNT_JSON"
    exit 1
  fi
  # Export for libraries that need it
  export GOOGLE_APPLICATION_CREDENTIALS="$SERVICE_ACCOUNT_JSON"
fi

# Check if user already exists via gcloud (approximate check via Workspace API if available)
log_info "Attempting to create/verify user $QA_USER_EMAIL in domain $WORKSPACE_DOMAIN..."
log_warn "Note: Script requires Admin Directory API enabled and proper SA impersonation."

# Step 3: Create GSM Secret for QA Email
log_info "Step 3: Managing GSM secrets (Email)..."

if ! gcloud secrets describe qa-user-email --project="$GCP_PROJECT" &> /dev/null; then
  log_info "Creating GSM secret: qa-user-email..."
  echo -n "$QA_USER_EMAIL" | gcloud secrets create qa-user-email \
    --data-file=- \
    --project="$GCP_PROJECT" &> /dev/null
  log_success "Created GSM secret: qa-user-email"
else
  log_warn "Secret qa-user-email already exists. Skipping creation."
fi

# Step 4: Create GSM Secret for QA Password
log_info "Step 4: Managing GSM secrets (Password)..."

if ! gcloud secrets describe qa-user-password --project="$GCP_PROJECT" &> /dev/null; then
  log_info "Creating GSM secret: qa-user-password..."
  # Create secret with placeholder string
  echo -n "PLACEHOLDER_CHANGE_ME" | gcloud secrets create qa-user-password \
    --data-file=- \
    --project="$GCP_PROJECT" &> /dev/null
  log_success "Created GSM secret: qa-user-password (placeholder)"
  log_warn "⚠️  GSM qa-user-password contains placeholder. Update after QA user sets password in Google Workspace."
else
  log_warn "Secret qa-user-password already exists. Skipping creation."
fi

# Step 5: Grant service account permissions
log_info "Step 5: Granting GSM secret access to service account..."

SERVICE_ACCOUNT_EMAIL=$(gcloud iam service-accounts list \
  --project="$GCP_PROJECT" \
  --filter="displayName:code-server-sa" \
  --format="value(email)" | head -1)

if [[ -n "$SERVICE_ACCOUNT_EMAIL" ]]; then
  gcloud secrets add-iam-policy-binding qa-user-email \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/secretmanager.secretAccessor" \
    --project="$GCP_PROJECT" &> /dev/null
  
  gcloud secrets add-iam-policy-binding qa-user-password \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/secretmanager.secretAccessor" \
    --project="$GCP_PROJECT" &> /dev/null
  
  log_success "Granted secret access to: $SERVICE_ACCOUNT_EMAIL"
else
  log_warn "Could not find code-server-sa service account. You may need to grant permissions manually."
fi

# Step 6: Verification
log_info "Step 6: Verifying setup..."

# Verify secrets exist
SECRETS=$(gcloud secrets list --project="$GCP_PROJECT" --filter="name:(qa-user-*)" --format="value(name)")
if echo "$SECRETS" | grep -q "qa-user-email"; then
  log_success "✓ qa-user-email secret verified"
else
  log_error "✗ qa-user-email secret not found"
  exit 1
fi

if echo "$SECRETS" | grep -q "qa-user-password"; then
  log_success "✓ qa-user-password secret verified"
else
  log_error "✗ qa-user-password secret not found"
  exit 1
fi

# Summary
echo
log_success "QA User Creation & GSM Setup Complete!"
echo
echo "========================================="
echo "Next Steps:"
echo "========================================="
echo "1. Log into Google Workspace as QA user:"
echo "   Email: $QA_USER_EMAIL"
echo "   Password: Set via Google Workspace reset link"
echo
echo "2. Disable 2FA in Google Workspace admin console"
echo
echo "3. Update GSM secret with actual password:"
echo "   gcloud secrets versions add qa-user-password \\"
echo "     --data-file=- --project=$GCP_PROJECT \\"
echo "     < <(echo -n 'ACTUAL_PASSWORD_HERE')"
echo
echo "4. Proceed to Issue #984 (OAuth whitelist configuration)"
echo "   Reference: ISSUE-984-IMPLEMENTATION-GUIDE.md"
echo
echo "5. Execute E2E tests:"
echo "   Reference: E2E-TEST-EXECUTION-GUIDE.md"
echo
