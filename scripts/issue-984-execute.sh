#!/bin/bash
# @file        scripts/issue-984-execute.sh
# @module      qa/oauth
# @description One-command execution of Issue #984 QA OAuth whitelist and GSM credential setup
#
# This script automates all steps required to activate QA OAuth testing after the QA user
# has been created in Google Workspace (Issue #983). It handles:
# 1. Verifying QA email is in allowed-emails.txt
# 2. Creating/updating GSM secrets for QA credentials
# 3. Granting CI service account access to GSM
# 4. Redeploying oauth2-proxy service
# 5. Validating E2E credentials are loadable
#
# Usage: bash scripts/issue-984-execute.sh <QA_USER_PASSWORD>
# Example: bash scripts/issue-984-execute.sh "secretpassword123"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Require QA user password as argument
if [[ -z "${1:-}" ]]; then
    log_fatal "Usage: bash scripts/issue-984-execute.sh <QA_USER_PASSWORD>"
fi

QA_PASSWORD="$1"
PROJECT_ID=$(gcloud config get-value project)

log_info "=== Executing Issue #984: QA OAuth Whitelist + GSM Credentials ==="

# Step 1: Verify whitelist
log_info "Step 1: Verifying allowed-emails.txt..."
if grep -q "qa@kushnir.cloud" allowed-emails.txt; then
    log_info "✓ qa@kushnir.cloud found in allowed-emails.txt"
else
    log_fatal "✗ qa@kushnir.cloud NOT found in allowed-emails.txt"
fi

# Step 2: Create GSM secrets
log_info "Step 2: Creating/updating GSM secrets..."
gcloud secrets describe qa-user-email >/dev/null 2>&1 || \
    gcloud secrets create qa-user-email --replication-policy=automatic
gcloud secrets describe qa-user-password >/dev/null 2>&1 || \
    gcloud secrets create qa-user-password --replication-policy=automatic

echo -n "qa@kushnir.cloud" | gcloud secrets versions add qa-user-email --data-file=-
echo -n "$QA_PASSWORD" | gcloud secrets versions add qa-user-password --data-file=-
log_info "✓ GSM secrets created/updated"

# Step 3: Grant CI service account access
log_info "Step 3: Granting CI service account access to GSM secrets..."
gcloud secrets add-iam-policy-binding qa-user-email \
    --member="serviceAccount:github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" >/dev/null 2>&1 || true
gcloud secrets add-iam-policy-binding qa-user-password \
    --member="serviceAccount:github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" >/dev/null 2>&1 || true
log_info "✓ CI service account permissions granted"

# Step 4: Redeploy oauth2-proxy
log_info "Step 4: Redeploying oauth2-proxy..."
ssh akushnir@${DEPLOY_HOST} "cd code-server-enterprise && docker-compose restart oauth2-proxy oauth2-proxy-portal" || {
    log_error "Failed to redeploy oauth2-proxy. Ensure SSH access to ${DEPLOY_HOST}"
    exit 1
}
sleep 5
log_info "✓ oauth2-proxy restarted"

# Step 5: Validate
log_info "Step 5: Validating setup..."
source scripts/fetch-gsm-secrets.sh --non-interactive
if [[ "${E2E_USER_EMAIL:-}" == "qa@kushnir.cloud" ]]; then
    log_info "✓ E2E_USER_EMAIL loaded: $E2E_USER_EMAIL"
else
    log_error "✗ E2E_USER_EMAIL not loaded correctly"
    exit 1
fi

if [[ -n "${E2E_USER_PASSWORD:-}" ]]; then
    log_info "✓ E2E_USER_PASSWORD loaded (masked)"
else
    log_error "✗ E2E_USER_PASSWORD not loaded"
    exit 1
fi

log_info ""
log_info "=== Issue #984 EXECUTION COMPLETE ==="
log_info ""
log_info "Next steps:"
log_info "1. Manually test OAuth login (see validation section above)"
log_info "2. Run E2E smoke tests: npx playwright test oauth-login.spec.ts"
log_info "3. Close Issue #984"
log_info "4. Unblock Issues #986-990 (E2E test implementation)"
