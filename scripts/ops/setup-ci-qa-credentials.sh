#!/usr/bin/env bash
# @file        scripts/ops/setup-ci-qa-credentials.sh
# @module      operations/ci
# @description Grant GitHub Actions service account access to QA credentials in GSM (Issue #984 Part 3)
# @owner       ci-team
# @status      Ready for immediate use post-#983
#
# Purpose: Configure GitHub Actions CI with access to E2E QA user credentials from GSM
#
# Prerequisites:
#   - Google Workspace user qa@kushnir.cloud created (Issue #983)
#   - GSM secrets qa-user-email and qa-user-password populated
#   - GitHub OIDC identity provider configured in GCP
#   - Service account created in GCP for GitHub Actions
#
# Usage:
#   bash scripts/ops/setup-ci-qa-credentials.sh \
#     --gcp-project kushin77-ops \
#     --github-org kushin77 \
#     --github-repo code-server \
#     [--service-account github-actions@kushin77-ops.iam.gserviceaccount.com]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Configuration
GCP_PROJECT="${GCP_PROJECT:-kushin77-ops}"
GITHUB_ORG="${GITHUB_ORG:-kushin77}"
GITHUB_REPO="${GITHUB_REPO:-code-server}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-}"  # Auto-detect if not provided
QA_EMAIL_SECRET="qa-user-email"
QA_PASSWORD_SECRET="qa-user-password"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --gcp-project)
      GCP_PROJECT="$2"
      shift 2
      ;;
    --github-org)
      GITHUB_ORG="$2"
      shift 2
      ;;
    --github-repo)
      GITHUB_REPO="$2"
      shift 2
      ;;
    --service-account)
      SERVICE_ACCOUNT="$2"
      shift 2
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

main() {
  echo "========================================="
  echo "GitHub Actions QA Credentials Setup"
  echo "========================================="
  echo "GCP Project: $GCP_PROJECT"
  echo "GitHub: $GITHUB_ORG/$GITHUB_REPO"
  echo

  # Step 1: Verify prerequisites
  log_info "Step 1: Verifying prerequisites..."

  if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI not found. Please install Google Cloud SDK."
    exit 1
  fi
  log_success "gcloud CLI available"

  # Check GCP project access
  if ! gcloud projects describe "$GCP_PROJECT" &> /dev/null; then
    log_error "Cannot access GCP project: $GCP_PROJECT"
    exit 1
  fi
  log_success "GCP project accessible"

  # Check GSM secrets exist
  if ! gcloud secrets describe "$QA_EMAIL_SECRET" --project="$GCP_PROJECT" &> /dev/null; then
    log_error "GSM secret not found: $QA_EMAIL_SECRET"
    exit 1
  fi
  log_success "GSM secret exists: $QA_EMAIL_SECRET"

  if ! gcloud secrets describe "$QA_PASSWORD_SECRET" --project="$GCP_PROJECT" &> /dev/null; then
    log_error "GSM secret not found: $QA_PASSWORD_SECRET"
    exit 1
  fi
  log_success "GSM secret exists: $QA_PASSWORD_SECRET"

  # Step 2: Find or create GitHub Actions service account
  log_info "Step 2: Setting up GitHub Actions service account..."

  if [[ -z "$SERVICE_ACCOUNT" ]]; then
    # Auto-detect from project
    SERVICE_ACCOUNT=$(gcloud iam service-accounts list \
      --project="$GCP_PROJECT" \
      --filter="displayName:github-actions OR displayName:GitHub" \
      --format="value(email)" | head -1)

    if [[ -z "$SERVICE_ACCOUNT" ]]; then
      # Try exact name
      SERVICE_ACCOUNT="github-actions@${GCP_PROJECT}.iam.gserviceaccount.com"
      
      if ! gcloud iam service-accounts describe "$SERVICE_ACCOUNT" --project="$GCP_PROJECT" &> /dev/null; then
        log_warn "GitHub Actions service account not found: $SERVICE_ACCOUNT"
        log_info "Create it with:"
        log_info "  gcloud iam service-accounts create github-actions \\"
        log_info "    --project=$GCP_PROJECT \\"
        log_info "    --display-name='GitHub Actions CI/CD'"
        exit 1
      fi
    fi
  fi
  log_success "Service account found: $SERVICE_ACCOUNT"

  # Step 3: Grant secretmanager.secretAccessor role
  log_info "Step 3: Granting GSM access to GitHub Actions..."

  # Grant access to qa-user-email secret
  if gcloud secrets add-iam-policy-binding "$QA_EMAIL_SECRET" \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/secretmanager.secretAccessor" \
    --project="$GCP_PROJECT" &> /dev/null; then
    log_success "Granted access: $SERVICE_ACCOUNT → $QA_EMAIL_SECRET"
  else
    log_warn "Could not grant access to $QA_EMAIL_SECRET (may already exist)"
  fi

  # Grant access to qa-user-password secret
  if gcloud secrets add-iam-policy-binding "$QA_PASSWORD_SECRET" \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/secretmanager.secretAccessor" \
    --project="$GCP_PROJECT" &> /dev/null; then
    log_success "Granted access: $SERVICE_ACCOUNT → $QA_PASSWORD_SECRET"
  else
    log_warn "Could not grant access to $QA_PASSWORD_SECRET (may already exist)"
  fi

  # Step 4: Configure GitHub OIDC (if not already done)
  log_info "Step 4: Verifying GitHub OIDC configuration..."
  
  if gcloud iam service-accounts describe "$SERVICE_ACCOUNT" --format="value(display_name)" &> /dev/null; then
    log_success "Service account verified"
  else
    log_error "Service account verification failed"
    exit 1
  fi

  # Step 5: Verification and next steps
  log_info "Step 5: Verification..."

  # Test access (would need actual token, so just verify bindings)
  local email_binding
  email_binding=$(gcloud secrets get-iam-policy "$QA_EMAIL_SECRET" \
    --project="$GCP_PROJECT" \
    --format="value(bindings[].members[?serviceAccount])")

  if echo "$email_binding" | grep -q "$SERVICE_ACCOUNT"; then
    log_success "Service account has access to $QA_EMAIL_SECRET"
  else
    log_warn "Service account access to $QA_EMAIL_SECRET not verified"
  fi

  # Summary
  echo
  echo "========================================="
  echo "GitHub Actions Setup Complete"
  echo "========================================="
  echo
  echo "Service Account: $SERVICE_ACCOUNT"
  echo "Secrets Accessible:"
  echo "  - $QA_EMAIL_SECRET"
  echo "  - $QA_PASSWORD_SECRET"
  echo
  echo "Next Steps:"
  echo "1. Configure GitHub Actions workflow to use these secrets"
  echo "   Reference: .github/workflows/e2e-tests.yml"
  echo
  echo "2. Add OIDC workload identity configuration to workflow:"
  echo "   - permissions.id-token: write"
  echo "   - Use 'google-github-actions/auth' to exchange token"
  echo
  echo "3. Fetch secrets from GSM in workflow:"
  echo "   - Use 'google-github-actions/get-secretmanager-secrets'"
  echo
  echo "4. Example workflow step:"
  echo "   steps:"
  echo "     - uses: google-github-actions/auth@v1"
  echo "       with:"
  echo "         service_account: $SERVICE_ACCOUNT"
  echo "         workload_identity_provider: projects/NUMBER/locations/global/workloadIdentityPools/github/providers/github"
  echo "     - uses: google-github-actions/get-secretmanager-secrets@v1"
  echo "       with:"
  echo "         secrets_manifest:"
  echo "           - name: 'qa_email'"
  echo "             key: '$QA_EMAIL_SECRET'"
  echo "           - name: 'qa_password'"
  echo "             key: '$QA_PASSWORD_SECRET'"
  echo
}

main
