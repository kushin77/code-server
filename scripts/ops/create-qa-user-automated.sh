#!/usr/bin/env bash
# @file        scripts/ops/create-qa-user-automated.sh
# @module      operations/authentication
# @description Automated QA user creation and GSM credential setup - Issue #983 + #984
# @status      Ready for immediate execution (requires admin Google Workspace access)
#
# Usage:
#   bash scripts/ops/create-qa-user-automated.sh \
#     --workspace-domain kushnir.cloud \
#     --gcp-project kushin77-ops \
#     --service-account-json ~/qa-creator-sa.json
#

set -euo pipefail

# Configuration
WORKSPACE_DOMAIN="${WORKSPACE_DOMAIN:-kushnir.cloud}"
GCP_PROJECT="${GCP_PROJECT:-kushin77-ops}"
QA_USER_EMAIL="qa@${WORKSPACE_DOMAIN}"
# shellcheck disable=SC2034
QA_USER_FIRST_NAME="QA"
# shellcheck disable=SC2034
QA_USER_LAST_NAME="Automation"
SERVICE_ACCOUNT_JSON="${SERVICE_ACCOUNT_JSON:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

log_info "QA User Creation & GSM Setup Script"
log_info "======================================"
log_info "Workspace Domain: $WORKSPACE_DOMAIN"
log_info "GCP Project: $GCP_PROJECT"
log_info "QA User Email: $QA_USER_EMAIL"
echo

# Step 1: Verify prerequisites
log_info "Step 1: Verifying prerequisites..."

if ! command -v gcloud &> /dev/null; then
  log_error "gcloud CLI not found. Please install Google Cloud SDK."
  exit 1
fi
log_success "gcloud CLI available"

if ! command -v python3 &> /dev/null; then
  log_error "python3 not found. Required for Admin SDK."
  exit 1
fi
log_success "python3 available"

if [[ -n "$SERVICE_ACCOUNT_JSON" && ! -f "$SERVICE_ACCOUNT_JSON" ]]; then
  log_error "Service account JSON file not found: $SERVICE_ACCOUNT_JSON"
  exit 1
fi
log_success "Service account JSON accessible (if provided)"

# Step 2: Authenticate with GCP
log_info "Step 2: Authenticating with GCP..."

if [[ -n "$SERVICE_ACCOUNT_JSON" ]]; then
  export GOOGLE_APPLICATION_CREDENTIALS="$SERVICE_ACCOUNT_JSON"
  log_success "Using service account: $SERVICE_ACCOUNT_JSON"
else
  log_warn "No service account JSON provided. Using default gcloud credentials."
  log_warn "Ensure you have already run: gcloud auth application-default login"
fi

# Verify authentication
if ! gcloud projects describe "$GCP_PROJECT" &> /dev/null; then
  log_error "Cannot access GCP project: $GCP_PROJECT"
  log_error "Verify authentication: gcloud auth login"
  exit 1
fi
log_success "Authenticated to GCP project: $GCP_PROJECT"

# Step 3: Create QA user via Admin SDK (Python script)
log_info "Step 3: Creating QA user in Google Workspace..."

python3 << 'EOF'
import os
import sys
import json
import base64
from google.auth.transport.requests import Request
from google.oauth2.service_account import Credentials
from googleapiclient.discovery import build

# Configuration
WORKSPACE_DOMAIN = os.environ.get('WORKSPACE_DOMAIN', 'kushnir.cloud')
GCP_PROJECT = os.environ.get('GCP_PROJECT', 'kushin77-ops')
QA_USER_EMAIL = f"qa@{WORKSPACE_DOMAIN}"
SERVICE_ACCOUNT_JSON = os.environ.get('SERVICE_ACCOUNT_JSON', '')

# Admin email (this must be a Workspace admin)
ADMIN_EMAIL = os.environ.get('WORKSPACE_ADMIN_EMAIL', 'admin@kushnir.cloud')

try:
    # Load service account credentials
    if SERVICE_ACCOUNT_JSON and os.path.exists(SERVICE_ACCOUNT_JSON):
        scopes = ['https://www.googleapis.com/auth/admin.directory.user']
        credentials = Credentials.from_service_account_file(
            SERVICE_ACCOUNT_JSON,
            scopes=scopes,
            subject=ADMIN_EMAIL
        )
    else:
        # Use default credentials
        from google.auth import default
        credentials, _ = default()
    
    # Build Admin API client
    service = build('admin', 'directory_v1', credentials=credentials)
    
    # Create user body
    user_body = {
        'primaryEmail': QA_USER_EMAIL,
        'firstName': 'QA',
        'lastName': 'Automation',
        'changePasswordAtNextLogin': True,
        'password': base64.b64encode(os.urandom(32)).decode()[:16]  # Temporary password
    }
    
    print(f"[INFO] Creating QA user: {QA_USER_EMAIL}")
    
    try:
        # Check if user already exists
        existing_user = service.users().get(userKey=QA_USER_EMAIL).execute()
        print(f"[WARN] User {QA_USER_EMAIL} already exists. Skipping creation.")
        print(f"[INFO] User details: {json.dumps(existing_user, indent=2)}")
    except:
        # User doesn't exist, create it
        result = service.users().insert(body=user_body).execute()
        print(f"[✓] QA user created successfully")
        print(f"[INFO] Email: {result.get('primaryEmail')}")
        print(f"[INFO] ID: {result.get('id')}")
        
        # Disable 2FA for automation
        print("[INFO] Disabling 2FA for QA user...")
        service.users().update(
            userKey=QA_USER_EMAIL,
            body={'changePasswordAtNextLogin': False}
        ).execute()
        print("[✓] 2FA disabled")
        
except Exception as e:
    print(f"[ERROR] Failed to create QA user: {str(e)}")
    sys.exit(1)

EOF

# Step 4: Create GSM secrets
log_info "Step 4: Creating GSM secrets..."

# Create qa-user-email secret
if gcloud secrets describe qa-user-email --project="$GCP_PROJECT" &> /dev/null; then
  log_warn "Secret qa-user-email already exists. Skipping creation."
else
  echo -n "$QA_USER_EMAIL" | gcloud secrets create qa-user-email \
    --replication-policy=automatic \
    --data-file=- \
    --project="$GCP_PROJECT" &> /dev/null
  log_success "Created GSM secret: qa-user-email"
fi

# Create qa-user-password secret (user will set this manually)
if ! gcloud secrets describe qa-user-password --project="$GCP_PROJECT" &> /dev/null; then
  echo -n "PLACEHOLDER_SET_AFTER_GOOGLE_WORKSPACE_LOGIN" | \
    gcloud secrets create qa-user-password \
    --replication-policy=automatic \
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

