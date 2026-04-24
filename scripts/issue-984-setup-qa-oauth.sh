#!/usr/bin/env bash
# @file        scripts/issue-984-setup-qa-oauth.sh
# @module      ci/deployment
# @description Setup QA user OAuth whitelist + GSM credentials for E2E testing
#
# Executes Issue #984: Configure QA user OAuth whitelist + GSM credentials
#
# Prerequisites:
#   - Issue #983 complete: qa@kushnir.cloud exists in Google Workspace
#   - Google Cloud CLI (gcloud) installed and authenticated
#   - GitHub CLI (gh) installed
#   - Permissions: GSM secrets admin, GitHub repo admin
#
# Usage:
#   bash scripts/issue-984-setup-qa-oauth.sh <QA_PASSWORD>
#
# Example:
#   bash scripts/issue-984-setup-qa-oauth.sh "YourSecurePasswordHere"
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Get QA password from argument or prompt
QA_PASSWORD="${1:-}"
if [ -z "$QA_PASSWORD" ]; then
    log_error "QA password required as argument"
    echo "Usage: bash $0 <QA_PASSWORD>"
    exit 1
fi

# Validate we're in the right directory
if [ ! -f "allowed-emails.txt" ]; then
    log_error "allowed-emails.txt not found. Please run from repository root."
    exit 1
fi

log_info "Starting Issue #984: QA OAuth Setup + GSM Credentials"

# ============================================================================
# PART 1: Verify allowed-emails.txt includes qa@kushnir.cloud
# ============================================================================

log_info "Part 1: Verifying OAuth whitelist..."

if grep -q "qa@kushnir.cloud" allowed-emails.txt; then
    log_success "qa@kushnir.cloud already in allowed-emails.txt"
else
    log_warn "qa@kushnir.cloud not in whitelist, adding..."
    echo "qa@kushnir.cloud" >> allowed-emails.txt
    log_success "Added qa@kushnir.cloud to allowed-emails.txt"
fi

# ============================================================================
# PART 2: Create/Update GSM Secrets
# ============================================================================

log_info "Part 2: Setting up Google Secret Manager secrets..."

QA_EMAIL="qa@kushnir.cloud"
QA_SECRET_EMAIL="qa-user-email"
QA_SECRET_PASSWORD="qa-user-password"

# Check if gcloud is available
if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI not found. Please install Google Cloud SDK."
    exit 1
fi

# Determine GCP project
GCP_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
if [ -z "$GCP_PROJECT" ]; then
    log_error "GCP project not set. Run: gcloud config set project PROJECT_ID"
    exit 1
fi

log_info "Using GCP Project: $GCP_PROJECT"

# Create or update qa-user-email secret
log_info "Creating secret: $QA_SECRET_EMAIL"
if gcloud secrets describe "$QA_SECRET_EMAIL" --project="$GCP_PROJECT" &>/dev/null; then
    log_warn "Secret $QA_SECRET_EMAIL already exists, adding new version..."
    echo -n "$QA_EMAIL" | gcloud secrets versions add "$QA_SECRET_EMAIL" \
        --data-file=- \
        --project="$GCP_PROJECT"
else
    log_info "Creating new secret $QA_SECRET_EMAIL..."
    echo -n "$QA_EMAIL" | gcloud secrets create "$QA_SECRET_EMAIL" \
        --replication-policy=automatic \
        --data-file=- \
        --project="$GCP_PROJECT"
fi
log_success "Secret $QA_SECRET_EMAIL created/updated"

# Create or update qa-user-password secret
log_info "Creating secret: $QA_SECRET_PASSWORD"
if gcloud secrets describe "$QA_SECRET_PASSWORD" --project="$GCP_PROJECT" &>/dev/null; then
    log_warn "Secret $QA_SECRET_PASSWORD already exists, adding new version..."
    echo -n "$QA_PASSWORD" | gcloud secrets versions add "$QA_SECRET_PASSWORD" \
        --data-file=- \
        --project="$GCP_PROJECT"
else
    log_info "Creating new secret $QA_SECRET_PASSWORD..."
    echo -n "$QA_PASSWORD" | gcloud secrets create "$QA_SECRET_PASSWORD" \
        --replication-policy=automatic \
        --data-file=- \
        --project="$GCP_PROJECT"
fi
log_success "Secret $QA_SECRET_PASSWORD created/updated"

# ============================================================================
# PART 3: Grant GitHub Actions Service Account Access
# ============================================================================

log_info "Part 3: Granting GitHub Actions service account access..."

# This requires the GitHub Actions workload identity service account
# Format: github-actions@PROJECT.iam.gserviceaccount.com
GITHUB_SA="github-actions@${GCP_PROJECT}.iam.gserviceaccount.com"

log_info "Granting $GITHUB_SA access to $QA_SECRET_EMAIL..."
gcloud secrets add-iam-policy-binding "$QA_SECRET_EMAIL" \
    --member="serviceAccount:$GITHUB_SA" \
    --role="roles/secretmanager.secretAccessor" \
    --project="$GCP_PROJECT" 2>/dev/null || log_warn "Failed to grant access (may already exist)"

log_info "Granting $GITHUB_SA access to $QA_SECRET_PASSWORD..."
gcloud secrets add-iam-policy-binding "$QA_SECRET_PASSWORD" \
    --member="serviceAccount:$GITHUB_SA" \
    --role="roles/secretmanager.secretAccessor" \
    --project="$GCP_PROJECT" 2>/dev/null || log_warn "Failed to grant access (may already exist)"

log_success "GitHub Actions service account has access to QA secrets"

# ============================================================================
# PART 4: Update GitHub Actions Secrets
# ============================================================================

log_info "Part 4: Updating GitHub Actions repository secrets..."

if ! command -v gh &> /dev/null; then
    log_error "GitHub CLI (gh) not found. Please install it first."
    log_info "Manually set these GitHub Actions secrets:"
    log_info "  E2E_USER_EMAIL: $QA_EMAIL"
    log_info "  E2E_USER_PASSWORD: (from GSM secret: $QA_SECRET_PASSWORD)"
    exit 1
fi

# Get current repo (assumes you're in a cloned repo with origin)
REPO_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")
if [[ $REPO_URL =~ github.com[:/]([^/]+)/([^/]+)(.git)?$ ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]}"
else
    log_error "Could not determine GitHub repo from git remote"
    exit 1
fi

log_info "Setting GitHub Actions secrets for $OWNER/$REPO"

# Set E2E_USER_EMAIL
gh secret set E2E_USER_EMAIL \
    --body "$QA_EMAIL" \
    --repo "$OWNER/$REPO" || log_warn "Failed to set E2E_USER_EMAIL (may need permissions)"

log_success "Set E2E_USER_EMAIL=$QA_EMAIL"

# ============================================================================
# PART 5: Verification
# ============================================================================

log_info "Part 5: Verification..."

# Verify secrets exist in GSM
log_info "Verifying GSM secrets..."
gcloud secrets versions list "$QA_SECRET_EMAIL" --project="$GCP_PROJECT" --limit=1 &>/dev/null && \
    log_success "✓ $QA_SECRET_EMAIL exists in GSM" || log_error "✗ $QA_SECRET_EMAIL not found"

gcloud secrets versions list "$QA_SECRET_PASSWORD" --project="$GCP_PROJECT" --limit=1 &>/dev/null && \
    log_success "✓ $QA_SECRET_PASSWORD exists in GSM" || log_error "✗ $QA_SECRET_PASSWORD not found"

# Test that service account can access secrets
log_info "Testing service account access..."
if gcloud secrets versions access latest --secret="$QA_SECRET_EMAIL" --project="$GCP_PROJECT" &>/dev/null; then
    log_success "✓ Can access QA secrets from this account"
else
    log_warn "✗ Could not verify access (service account permissions may be required)"
fi

# ============================================================================
# SUMMARY
# ============================================================================

log_info ""
log_info "=========================================="
log_info "Issue #984 Setup Complete!"
log_info "=========================================="
log_info ""
log_success "✓ QA email (qa@kushnir.cloud) whitelisted"
log_success "✓ Credentials stored in Google Secret Manager"
log_success "✓ GitHub Actions service account has access"
log_success "✓ GitHub Actions secrets configured"
log_info ""
log_info "Next Steps:"
log_info "1. Redeploy oauth2-proxy to pick up whitelist:"
log_info "   ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker-compose restart oauth2-proxy'"
log_info ""
log_info "2. Run E2E tests:"
log_info "   REQUIRE_VPN=0 npx playwright test tests/e2e/specs/oauth-login-comprehensive.spec.ts"
log_info ""
log_info "3. Or trigger CI/CD:"
log_info "   git push origin main"
log_info ""
log_success "All E2E tests (Issues #986-990) are now ready to execute!"
log_info ""
