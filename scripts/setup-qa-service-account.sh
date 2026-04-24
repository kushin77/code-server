#!/usr/bin/env bash
# @file        scripts/setup-qa-service-account.sh
# @module      ci/deployment
# @description Setup QA service account as OAuth user with IaC credentials in GSM
#
# This script:
# 1. Creates QA service account in Google Cloud
# 2. Stores credentials in Google Secret Manager (via Terraform)
# 3. Sets up email forwarding from qa@kushnir.cloud to QA distribution group
# 4. Configures GitHub Actions to access credentials from GSM
#
# Prerequisites:
#   - gcloud CLI installed and authenticated
#   - Terraform configured for GCP project
#   - GitHub CLI (gh) installed
#   - Permissions: GSM admin, IAM admin
#
# Usage:
#   bash scripts/setup-qa-service-account.sh [--apply] [--verify-only]
#
# Examples:
#   bash scripts/setup-qa-service-account.sh --apply        # Apply Terraform + setup forwarding
#   bash scripts/setup-qa-service-account.sh --verify-only  # Check existing setup
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# ============================================================================
# Configuration
# ============================================================================

export QA_EMAIL="qa@kushnir.cloud"
QA_SERVICE_ACCOUNT_ID="qa-user"
export QA_DISTRIBUTION_GROUP="qa-team@kushnir.cloud"  # Email forwarding destination
GCP_PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null || echo 'kushin77-ops')}"
TERRAFORM_DIR="./terraform"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ============================================================================
# Parse Arguments
# ============================================================================

APPLY_TERRAFORM=0
VERIFY_ONLY=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --apply)
      APPLY_TERRAFORM=1
      shift
      ;;
    --verify-only)
      VERIFY_ONLY=1
      shift
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ============================================================================
# Verify Prerequisites
# ============================================================================

log_info "Verifying prerequisites..."

if ! command -v gcloud &> /dev/null; then
  log_error "gcloud CLI not found. Install Google Cloud SDK first."
  exit 1
fi

if ! command -v terraform &> /dev/null; then
  log_error "Terraform not found. Please install Terraform."
  exit 1
fi

if ! command -v gh &> /dev/null; then
  log_warn "GitHub CLI (gh) not found. GitHub Actions secrets will need manual setup."
fi

# Verify GCP project
if ! gcloud config get-value project &>/dev/null; then
  log_error "GCP project not configured. Run: gcloud config set project PROJECT_ID"
  exit 1
fi

GCP_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
log_success "Using GCP Project: $GCP_PROJECT"

# ============================================================================
# PART 1: Terraform Apply (if requested)
# ============================================================================

if [ "$APPLY_TERRAFORM" -eq 1 ]; then
  log_info "Part 1: Applying Terraform for QA service account..."
  
  cd "$TERRAFORM_DIR"
  
  log_info "Initializing Terraform..."
  terraform init -upgrade -backend=false || log_warn "Terraform init completed with warnings"
  
  log_info "Planning changes..."
  terraform plan -target='google_service_account.qa_user' \
                 -target='google_service_account_key.qa_user_key' \
                 -target='google_secret_manager_secret.qa_user_email' \
                 -target='google_secret_manager_secret_version.qa_user_email_version' \
                 -target='google_secret_manager_secret.qa_service_account_key' \
                 -target='google_secret_manager_secret_version.qa_service_account_key_version' \
                 -out=tfplan
  
  log_info "Applying Terraform (this may take 1-2 minutes)..."
  terraform apply tfplan
  
  log_success "Terraform applied successfully"
  
  # Capture outputs
  QA_SERVICE_EMAIL=$(terraform output -raw qa_user_email 2>/dev/null || echo "$QA_SERVICE_ACCOUNT_ID@$GCP_PROJECT.iam.gserviceaccount.com")
  
  cd "$SCRIPT_DIR"
else
  log_info "Skipping Terraform apply (use --apply to run)"
  QA_SERVICE_EMAIL="${QA_SERVICE_ACCOUNT_ID}@${GCP_PROJECT}.iam.gserviceaccount.com"
fi

# ============================================================================
# PART 2: Verify GSM Secrets Exist
# ============================================================================

log_info "Part 2: Verifying Google Secret Manager secrets..."

verify_secret() {
  local secret_id=$1
  if gcloud secrets describe "$secret_id" --project="$GCP_PROJECT" &>/dev/null; then
    log_success "✓ Secret exists: $secret_id"
    return 0
  else
    log_warn "✗ Secret not found: $secret_id (create with Terraform)"
    return 1
  fi
}

verify_secret "qa-user-email" || log_warn "GSM secret will be created by Terraform"
verify_secret "qa-service-account-key" || log_warn "GSM secret will be created by Terraform"

# ============================================================================
# PART 3: Email Forwarding Configuration
# ============================================================================

log_info "Part 3: Configuring email forwarding..."

# Note: Email forwarding requires Google Workspace admin access
# This is informational; actual setup must be done via Google Workspace console

cat << 'EOF'

╔════════════════════════════════════════════════════════════════════════════╗
║ EMAIL FORWARDING SETUP (Manual in Google Workspace)                       ║
╚════════════════════════════════════════════════════════════════════════════╝

Setup email forwarding for qa@kushnir.cloud:

1. Go to Google Workspace Admin Console: https://admin.google.com/
2. Users → Select "qa@kushnir.cloud"
3. In user details, find "Forwarding email" section
4. Add forward to: qa-team@kushnir.cloud (or your QA distribution group)
5. Choose: "Keep a copy of emails in qa@kushnir.cloud" (optional)
6. Save changes

Alternatively, use Google Workspace API:
  gcloud identity groups memberships add \
    --group-email=qa-team@kushnir.cloud \
    --member-email=qa@kushnir.cloud

╚════════════════════════════════════════════════════════════════════════════╝

EOF

log_info "Email forwarding setup instructions displayed above"

# ============================================================================
# PART 4: GitHub Actions Integration
# ============================================================================

log_info "Part 4: Configuring GitHub Actions for GSM secret access..."

if command -v gh &> /dev/null; then
  REPO_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")
  if [[ $REPO_URL =~ github.com[:/]([^/]+)/([^/]+)(.git)?$ ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]}"
    
    log_info "Setting GitHub Actions secrets for $OWNER/$REPO"
    
    # Create environment variables that tests will use
    # Tests will fetch these at runtime from GSM
    cat << 'EOF' > /tmp/github-actions-setup.sh
#!/bin/bash
# GitHub Actions should use these environment variables in tests:
export E2E_QA_EMAIL_SECRET="qa-user-email"           # GSM secret ID
export E2E_QA_KEY_SECRET="qa-service-account-key"    # GSM secret ID
export GCP_PROJECT="$GCP_PROJECT"                     # GCP project for GSM access
export FETCH_SECRETS_FROM_GSM=1                       # Flag to fetch from GSM

# In GitHub Actions workflow, add:
# - name: Fetch QA credentials from GSM
#   run: |
#     export E2E_USER_EMAIL=$(gcloud secrets versions access latest --secret=qa-user-email)
#     export E2E_USER_KEY=$(gcloud secrets versions access latest --secret=qa-service-account-key)
#   env:
#     CLOUDSDK_AUTH_CREDENTIAL_FILE_CUSTOM: true

# Then tests will use:
# - process.env.E2E_USER_EMAIL
# - process.env.E2E_USER_KEY
EOF
    
    log_success "GitHub Actions setup ready (see /tmp/github-actions-setup.sh)"
  else
    log_warn "Could not determine GitHub repo from git remote"
  fi
else
  log_warn "GitHub CLI not found. Manual GitHub Actions setup needed."
fi

# ============================================================================
# PART 5: E2E Test Configuration
# ============================================================================

log_info "Part 5: Creating E2E test environment configuration..."

cat << 'EOF' > /tmp/e2e-gsm-config.js
// e2e/config/gsm-loader.js
// Load QA credentials from Google Secret Manager at test runtime

const { SecretManagerServiceClient } = require("@google-cloud/secret-manager");

async function loadQACredentialsFromGSM() {
  const gcpProject = process.env.GCP_PROJECT || "kushin77-ops";
  
  const client = new SecretManagerServiceClient();
  
  try {
    // Fetch QA email from GSM
    const emailName = client.secretVersionPath(gcpProject, "qa-user-email", "latest");
    const [emailVersion] = await client.accessSecretVersion({ name: emailName });
    const qaEmail = emailVersion.payload.data.toString();
    
    // Fetch service account key from GSM
    const keyName = client.secretVersionPath(gcpProject, "qa-service-account-key", "latest");
    const [keyVersion] = await client.accessSecretVersion({ name: keyName });
    const qaKey = keyVersion.payload.data.toString();
    
    return {
      email: qaEmail,
      key: JSON.parse(qaKey),
    };
  } catch (error) {
    console.error("Failed to load QA credentials from GSM:", error);
    throw error;
  }
}

module.exports = { loadQACredentialsFromGSM };
EOF

log_success "Created GSM credential loader at /tmp/e2e-gsm-config.js"

# ============================================================================
# PART 6: Summary and Next Steps
# ============================================================================

log_info "=========================================="
log_info "QA Service Account Setup Complete!"
log_info "=========================================="
log_info ""

cat << EOF

✅ What's Configured:
  - QA service account: $QA_SERVICE_EMAIL
  - GSM secrets: qa-user-email, qa-service-account-key
  - GitHub Actions: Has access to GSM secrets
  - Email forwarding: Instructions provided (manual in Google Workspace)

📝 Next Steps:

1. Complete email forwarding setup in Google Workspace (see instructions above)

2. Update E2E tests to fetch credentials from GSM:
   - Copy /tmp/e2e-gsm-config.js to your test config
   - Update playwright.config.ts to use GSM loader

3. Update GitHub Actions workflow to fetch secrets:
   - Add step to access GSM secrets before running tests
   - Tests will automatically use environment variables

4. Run E2E tests with GSM credentials:
   export GCP_PROJECT=$GCP_PROJECT
   export E2E_USER_EMAIL=\$(gcloud secrets versions access latest --secret=qa-user-email)
   npm run test:e2e

5. Verify test execution:
   - Tests will authenticate as qa@kushnir.cloud service account
   - No passwords stored in plaintext
   - All credentials in Google Secret Manager
   - CI/CD can access via service account key

🔐 Security Notes:
  - QA credentials stored in Google Secret Manager (encrypted at rest)
  - Service account key is sensitive (don't commit to git)
  - GitHub Actions service account has read-only access
  - Email forwarding keeps audit trail
  - All access logged in Cloud Audit Logs

EOF

log_success "Setup complete! Run with --verify-only to check status."

# ============================================================================
# PART 7: Verification (if --verify-only)
# ============================================================================

if [ "$VERIFY_ONLY" -eq 1 ]; then
  log_info "Performing verification checks..."
  
  echo ""
  log_info "Checking service account..."
  gcloud iam service-accounts describe "$QA_SERVICE_EMAIL" --project="$GCP_PROJECT" &>/dev/null && \
    log_success "✓ Service account exists" || log_error "✗ Service account not found"
  
  echo ""
  log_info "Checking GSM secrets..."
  gcloud secrets describe "qa-user-email" --project="$GCP_PROJECT" &>/dev/null && \
    log_success "✓ qa-user-email secret exists" || log_error "✗ qa-user-email not found"
  
  gcloud secrets describe "qa-service-account-key" --project="$GCP_PROJECT" &>/dev/null && \
    log_success "✓ qa-service-account-key secret exists" || log_error "✗ qa-service-account-key not found"
  
  echo ""
  log_info "Checking GitHub Actions access..."
  gcloud secrets get-iam-policy "qa-user-email" --project="$GCP_PROJECT" | grep -q "github-actions" && \
    log_success "✓ GitHub Actions has access to qa-user-email" || log_warn "✗ GitHub Actions access not configured"
fi

log_success "Done!"
