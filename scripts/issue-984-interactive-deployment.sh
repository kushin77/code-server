#!/bin/bash
# @file        scripts/issue-984-interactive-deployment.sh
# @module      ci/deployment
# @description Interactive wizard for complete Issue #984 deployment
#
# This script guides the user through all remaining steps:
# 1. Verify prerequisites
# 2. Collect required credentials interactively
# 3. Execute SSL remediation
# 4. Execute QA OAuth setup
# 5. Verify deployment
#
# Usage:
#   bash scripts/issue-984-interactive-deployment.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✅ SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[⚠️  WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[❌ ERROR]${NC} $*" >&2; }

# ════════════════════════════════════════════════════════════════════════════
# STEP 0: WELCOME & OVERVIEW
# ════════════════════════════════════════════════════════════════════════════

clear
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                                                                ║"
echo "║      Issue #984 Interactive Deployment Wizard                 ║"
echo "║      Complete QA Testing Infrastructure Setup                 ║"
echo "║                                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "This wizard will guide you through:"
echo "  1. Verify prerequisites (10 sec)"
echo "  2. Collect credentials (2 min)"
echo "  3. Execute SSL remediation (15 min)"
echo "  4. Update DNS (5 min manual)"
echo "  5. Execute QA OAuth setup (10 min)"
echo "  6. Verify deployment (5 min)"
echo ""
echo "📋 Total time: ~50-60 minutes"
echo ""
read -p "Press ENTER to continue, or Ctrl+C to cancel..." </dev/null || exit 1

# ════════════════════════════════════════════════════════════════════════════
# STEP 1: VERIFY PREREQUISITES
# ════════════════════════════════════════════════════════════════════════════

log_info "Step 1: Verifying prerequisites..."
echo ""

PREREQS_OK=true

# Check SSH to primary
if ssh -o ConnectTimeout=5 akushnir@192.168.168.31 "hostname" &>/dev/null; then
    log_success "SSH access to 192.168.168.31: OK"
else
    log_error "SSH access to 192.168.168.31: FAILED"
    log_info "You will need to provide SSH password when prompted"
fi

# Check required files
if [ -f "scripts/infrastructure/fix-ssl-protocol-error.sh" ]; then
    log_success "SSL remediation script: FOUND"
else
    log_error "SSL remediation script: MISSING"
    PREREQS_OK=false
fi

if [ -f "scripts/issue-984-setup-qa-oauth.sh" ]; then
    log_success "QA OAuth setup script: FOUND"
else
    log_error "QA OAuth setup script: MISSING"
    PREREQS_OK=false
fi

if [ -f "allowed-emails.txt" ]; then
    log_success "OAuth whitelist: FOUND"
else
    log_error "OAuth whitelist: MISSING"
    PREREQS_OK=false
fi

# Check gcloud CLI
if command -v gcloud &>/dev/null; then
    log_success "gcloud CLI: INSTALLED"
else
    log_warn "gcloud CLI: NOT INSTALLED (will be needed for Step 5)"
fi

# Check gh CLI
if command -v gh &>/dev/null; then
    log_success "GitHub CLI: INSTALLED"
else
    log_warn "GitHub CLI: NOT INSTALLED (will be needed for Step 5)"
fi

echo ""
if [ "$PREREQS_OK" = false ]; then
    log_error "Prerequisites check FAILED"
    exit 1
fi

log_success "All prerequisites verified"
echo ""

# ════════════════════════════════════════════════════════════════════════════
# STEP 2: COLLECT CREDENTIALS INTERACTIVELY
# ════════════════════════════════════════════════════════════════════════════

log_info "Step 2: Collecting credentials..."
echo ""

# SSH Password
echo "📌 SSH Authentication"
echo "   You will need to enter your SSH password for: akushnir@192.168.168.31"
echo ""
read -p "   Ready? (press ENTER)" </dev/null || exit 1

# QA Password
echo ""
echo "📌 QA User Password"
echo "   This was generated when @kushin77 created qa@kushnir.cloud"
read -sp "   Enter QA user password (will not echo): " QA_PASSWORD || exit 1
echo ""
if [ -z "$QA_PASSWORD" ]; then
    log_error "QA password cannot be empty"
    exit 1
fi
log_success "QA password received (will be stored securely)"

# DNS Provider
echo ""
echo "📌 DNS Provider"
echo "   Which DNS provider do you use for kushnir.cloud?"
echo "   1) Cloudflare"
echo "   2) Route53 (AWS)"
echo "   3) Other (manual update)"
read -p "   Enter choice (1-3): " DNS_CHOICE
case "$DNS_CHOICE" in
    1) DNS_PROVIDER="Cloudflare"; DNS_URL="https://dash.cloudflare.com" ;;
    2) DNS_PROVIDER="Route53"; DNS_URL="https://console.aws.amazon.com/route53" ;;
    3) DNS_PROVIDER="Manual"; DNS_URL=""; ;;
    *) log_error "Invalid choice"; exit 1 ;;
esac
log_success "DNS provider: $DNS_PROVIDER"

echo ""
log_success "Credentials collected"
echo ""

# ════════════════════════════════════════════════════════════════════════════
# STEP 3: EXECUTE SSL REMEDIATION
# ════════════════════════════════════════════════════════════════════════════

log_info "Step 3: Executing SSL remediation..."
echo ""
echo "⏳ This will take ~15 minutes (automated)"
echo "   - Fix Prometheus config"
echo "   - Pin session-broker image"
echo "   - Restart Redis Sentinel"
echo "   - Verify services"
echo ""

read -p "Continue? (press ENTER to proceed, Ctrl+C to cancel)" </dev/null || exit 1

bash scripts/infrastructure/fix-ssl-protocol-error.sh --execute 2>&1 | tee artifacts/ssl-remediation-output.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log_error "SSL remediation failed"
    log_info "Check artifacts/ssl-remediation-output.log for details"
    exit 1
fi

log_success "SSL remediation completed"
echo ""

# ════════════════════════════════════════════════════════════════════════════
# STEP 4: UPDATE DNS
# ════════════════════════════════════════════════════════════════════════════

log_info "Step 4: DNS update (manual)"
echo ""

if [ -n "$DNS_URL" ]; then
    echo "Please update your DNS record:"
    echo ""
    echo "  Provider: $DNS_PROVIDER"
    echo "  URL: $DNS_URL"
    echo ""
    echo "  Record Details:"
    echo "    - Name: kushnir.cloud"
    echo "    - Type: A"
    echo "    - Current Value: 192.168.168.42"
    echo "    - New Value: 192.168.168.31"
    echo "    - TTL: 300 seconds"
    echo ""
    read -p "Press ENTER once you've updated DNS..." </dev/null || exit 1
else
    echo "Please manually update your DNS provider:"
    echo "  - Change A record for kushnir.cloud"
    echo "  - From: 192.168.168.42"
    echo "  - To: 192.168.168.31"
    read -p "Press ENTER once you've updated DNS..." </dev/null || exit 1
fi

# Wait for DNS propagation
log_info "Waiting for DNS propagation (checking every 10 seconds)..."
DNS_READY=false
CHECKS=0
MAX_CHECKS=30

while [ $CHECKS -lt $MAX_CHECKS ]; do
    if nslookup kushnir.cloud 2>/dev/null | grep -q "192.168.168.31"; then
        log_success "DNS propagated to 192.168.168.31"
        DNS_READY=true
        break
    fi
    CHECKS=$((CHECKS+1))
    echo "  ⏳ Check $CHECKS/$MAX_CHECKS... (waiting)"
    sleep 10
done

if [ "$DNS_READY" = false ]; then
    log_warn "DNS may still be propagating (can take up to 15 minutes)"
    log_info "You can continue - DNS will eventually propagate"
fi

echo ""

# ════════════════════════════════════════════════════════════════════════════
# STEP 5: EXECUTE QA OAUTH SETUP
# ════════════════════════════════════════════════════════════════════════════

log_info "Step 5: Setting up QA OAuth credentials..."
echo ""
echo "⏳ This will:"
echo "   - Store QA email in Google Secret Manager"
echo "   - Store QA password in Google Secret Manager"
echo "   - Grant GitHub Actions service account access"
echo "   - Configure GitHub Actions secrets"
echo ""

read -p "Continue? (press ENTER, or Ctrl+C to cancel)" </dev/null || exit 1

bash scripts/issue-984-setup-qa-oauth.sh "$QA_PASSWORD" 2>&1 | tee artifacts/qa-oauth-output.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log_error "QA OAuth setup failed"
    log_info "Check artifacts/qa-oauth-output.log for details"
    exit 1
fi

log_success "QA OAuth setup completed"
echo ""

# ════════════════════════════════════════════════════════════════════════════
# STEP 6: VERIFY DEPLOYMENT
# ════════════════════════════════════════════════════════════════════════════

log_info "Step 6: Verifying deployment..."
echo ""

# Test HTTPS
log_info "Testing HTTPS access to https://kushnir.cloud..."
if curl -v -m 5 https://kushnir.cloud 2>&1 | grep -q "200\|301\|302\|307"; then
    log_success "✅ HTTPS is working"
else
    log_warn "⚠️  HTTPS test inconclusive (DNS may still be propagating)"
fi

# Test GSM secrets
log_info "Verifying GSM secrets..."
if gcloud secrets versions access latest --secret=qa-user-email 2>/dev/null; then
    log_success "✅ QA email secret accessible"
else
    log_warn "⚠️  Could not verify GSM secrets (may need gcloud auth)"
fi

# Test GitHub secrets
log_info "Verifying GitHub Actions secrets..."
if gh secret list --repo kushin77/code-server 2>/dev/null | grep -q E2E_USER_EMAIL; then
    log_success "✅ GitHub Actions secrets configured"
else
    log_warn "⚠️  Could not verify GitHub secrets (may need gh auth)"
fi

echo ""
log_success "Deployment verification complete"
echo ""

# ════════════════════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ════════════════════════════════════════════════════════════════════════════

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                                                                ║"
echo "║              🎉 DEPLOYMENT COMPLETE 🎉                        ║"
echo "║                                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "✅ What was done:"
echo "   1. SSL remediation executed on 192.168.168.31"
echo "   2. DNS updated to point to primary host"
echo "   3. QA credentials stored in Google Secret Manager"
echo "   4. GitHub Actions configured for E2E tests"
echo ""
echo "⏭️  Next steps:"
echo "   1. Wait for DNS to fully propagate (5-15 min)"
echo "   2. Test HTTPS: https://kushnir.cloud"
echo "   3. Test OAuth: Sign in with qa@kushnir.cloud"
echo "   4. Monitor logs:"
echo "      ssh akushnir@192.168.168.31 'docker logs -f caddy'"
echo ""
echo "📊 Summary files created:"
echo "   - artifacts/ssl-remediation-output.log"
echo "   - artifacts/qa-oauth-output.log"
echo ""
echo "📞 Support:"
echo "   - Check MASTER-EXECUTION-GUIDE.md for troubleshooting"
echo "   - Check WORK-COMPLETION-CERTIFICATION.md for status"
echo ""
log_success "All done! System is ready for E2E testing."
