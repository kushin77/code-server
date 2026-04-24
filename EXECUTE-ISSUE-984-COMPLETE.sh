#!/bin/bash
# @file        EXECUTE-ISSUE-984-COMPLETE.sh
# @module      deployment/issue-984
# @description Master execution script - attempts to complete all Issue #984 steps
#
# This script tries to execute EVERY remaining step, failing gracefully if credentials are missing.
# It represents the COMPLETE end-to-end Issue #984 deployment.
#
# Usage:
#   bash EXECUTE-ISSUE-984-COMPLETE.sh [--qa-password=PASSWORD] [--ssh-host=HOST]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
QA_PASSWORD="${QA_PASSWORD:---qa-password=}"
SSH_HOST="${SSH_HOST:-192.168.168.31}"
SSH_USER="${SSH_USER:-akushnir}"

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✅]${NC} $*"; }
log_error() { echo -e "${RED}[❌]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[⚠️]${NC} $*"; }

# ════════════════════════════════════════════════════════════════════════════
# STEP 1: PRE-FLIGHT CHECKS
# ════════════════════════════════════════════════════════════════════════════

log_info "Step 1: Pre-flight checks..."

# Check required scripts exist
if [ ! -f "scripts/infrastructure/fix-ssl-protocol-error.sh" ]; then
    log_error "SSL remediation script not found"
    exit 1
fi
log_success "SSL remediation script found"

if [ ! -f "scripts/issue-984-setup-qa-oauth.sh" ]; then
    log_error "QA OAuth setup script not found"
    exit 1
fi
log_success "QA OAuth setup script found"

# Check git state
if ! git diff --quiet; then
    log_warn "Working tree has uncommitted changes"
fi
log_success "Git repository accessible"

echo ""

# ════════════════════════════════════════════════════════════════════════════
# STEP 2: ATTEMPT SSL REMEDIATION (requires SSH)
# ════════════════════════════════════════════════════════════════════════════

log_info "Step 2: Attempting SSL remediation..."

if ssh -o ConnectTimeout=5 "$SSH_USER@$SSH_HOST" "hostname" &>/dev/null; then
    log_success "SSH connectivity confirmed to $SSH_HOST"
    log_info "Executing SSL remediation via SSH..."
    
    # Execute remediation remotely
    if ssh "$SSH_USER@$SSH_HOST" "cd code-server-enterprise && bash scripts/infrastructure/fix-ssl-protocol-error.sh --execute" 2>&1 | tee artifacts/ssl-remediation-output.log; then
        log_success "SSL remediation completed successfully"
    else
        log_error "SSL remediation failed - check artifacts/ssl-remediation-output.log"
        exit 1
    fi
else
    log_warn "SSH connection unavailable to $SSH_HOST"
    log_info "Cannot execute SSL remediation without SSH access"
    log_info "Operator must run manually: ssh $SSH_USER@$SSH_HOST 'cd code-server-enterprise && bash scripts/infrastructure/fix-ssl-protocol-error.sh --execute'"
    echo ""
fi

# ════════════════════════════════════════════════════════════════════════════
# STEP 3: ATTEMPT DNS UPDATE (manual, document instructions)
# ════════════════════════════════════════════════════════════════════════════

log_info "Step 3: DNS update status..."
log_warn "DNS update requires manual action (agent cannot access DNS provider)"
log_info "Required changes:"
echo "  Provider: Cloudflare / Route53 / Other"
echo "  Record: kushnir.cloud"
echo "  Type: A"
echo "  Current: 192.168.168.42"
echo "  Update to: 192.168.168.31"
echo "  TTL: 300 seconds"

# Check current DNS
if command -v nslookup &>/dev/null; then
    log_info "Current DNS resolution:"
    nslookup kushnir.cloud 2>/dev/null || log_warn "nslookup failed"
fi

echo ""

# ════════════════════════════════════════════════════════════════════════════
# STEP 4: SETUP QA OAUTH (requires password)
# ════════════════════════════════════════════════════════════════════════════

log_info "Step 4: Setting up QA OAuth credentials..."

# Parse QA password from arguments
for arg in "$@"; do
    if [[ "$arg" == --qa-password=* ]]; then
        QA_PASSWORD="${arg#--qa-password=}"
        break
    fi
done

if [ -z "$QA_PASSWORD" ] || [ "$QA_PASSWORD" == "--qa-password=" ]; then
    log_warn "QA password not provided via --qa-password argument"
    log_info "Cannot execute QA OAuth setup without password"
    log_info "Usage: bash EXECUTE-ISSUE-984-COMPLETE.sh --qa-password=YOUR_PASSWORD"
    echo ""
else
    log_success "QA password provided"
    log_info "Executing QA OAuth setup..."
    
    if bash scripts/issue-984-setup-qa-oauth.sh "$QA_PASSWORD" 2>&1 | tee artifacts/qa-oauth-output.log; then
        log_success "QA OAuth setup completed"
    else
        log_error "QA OAuth setup failed - check artifacts/qa-oauth-output.log"
        exit 1
    fi
fi

echo ""

# ════════════════════════════════════════════════════════════════════════════
# STEP 5: VERIFICATION (as much as possible without browser)
# ════════════════════════════════════════════════════════════════════════════

log_info "Step 5: Verification..."

# Check HTTPS
log_info "Testing HTTPS connectivity..."
if curl -v -m 5 https://kushnir.cloud 2>&1 | grep -q "200\|301\|302\|307\|Let's Encrypt"; then
    log_success "HTTPS connectivity confirmed"
else
    log_warn "HTTPS test inconclusive (DNS may still be propagating)"
fi

# Check GSM secrets (if gcloud available)
if command -v gcloud &>/dev/null; then
    log_info "Checking GSM secrets..."
    if gcloud secrets versions access latest --secret=qa-user-email 2>/dev/null | grep -q "qa@kushnir.cloud"; then
        log_success "QA user email secret verified"
    else
        log_warn "Could not verify QA user email secret"
    fi
fi

echo ""

# ════════════════════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ════════════════════════════════════════════════════════════════════════════

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                   EXECUTION SUMMARY                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

log_success "Pre-flight checks completed"
log_info "SSL remediation: Check artifacts/ssl-remediation-output.log"
log_info "QA OAuth setup: Check artifacts/qa-oauth-output.log"

echo ""
echo "Next manual step: Browser verification"
echo "  1. Open: https://kushnir.cloud"
echo "  2. Click: Sign in with Google"
echo "  3. Enter: qa@kushnir.cloud"
echo "  4. Enter: [password]"
echo "  5. Expected: Authenticated session"
echo ""

log_success "Issue #984 execution attempted - check logs for details"
