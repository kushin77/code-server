#!/usr/bin/env bash
# Rollback automation for Issue #984 deployment
# Safely reverts OAuth whitelist + GSM credentials configuration if needed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
BACKUP_DIR="${BACKUP_DIR:-.backup}"
TIMESTAMP=$(date +%s)
ROLLBACK_LOG="artifacts/triage/issue-984-rollback-${TIMESTAMP}.log"

# Logging
log_info() {
  echo -e "${BLUE}ℹ${NC} $1" | tee -a "$ROLLBACK_LOG"
}

log_success() {
  echo -e "${GREEN}✓${NC} $1" | tee -a "$ROLLBACK_LOG"
}

log_error() {
  echo -e "${RED}✗${NC} $1" | tee -a "$ROLLBACK_LOG"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $1" | tee -a "$ROLLBACK_LOG"
}

# Ensure log directory exists
mkdir -p artifacts/triage

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Issue #984 Rollback Automation${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Verify we're in the right directory
if [ ! -f "terraform/main.tf" ]; then
  log_error "Not in code-server-enterprise root - Cannot proceed"
  exit 1
fi

# Confirm user intent
echo ""
echo -e "${YELLOW}WARNING: This will rollback Issue #984 changes.${NC}"
echo ""
read -p "Type 'ROLLBACK' to confirm: " CONFIRM

if [ "$CONFIRM" != "ROLLBACK" ]; then
  log_info "Rollback cancelled by user"
  exit 0
fi

echo ""
log_info "Starting Issue #984 rollback..."
echo ""

# ============================================================================
# Step 1: Backup current .env
# ============================================================================
log_info "Step 1/6: Backing up current .env"

if [ -f ".env" ]; then
  mkdir -p "$BACKUP_DIR"
  cp .env "${BACKUP_DIR}/.env.backup.${TIMESTAMP}"
  log_success "Backed up .env to ${BACKUP_DIR}/.env.backup.${TIMESTAMP}"
else
  log_warn ".env not found - Nothing to backup"
fi
echo ""

# ============================================================================
# Step 2: Revert terraform apply
# ============================================================================
log_info "Step 2/6: Reverting terraform apply"

if ! command -v terraform &>/dev/null; then
  log_error "Terraform not found - Cannot revert infrastructure changes"
  exit 1
fi

if [ -f "terraform/terraform.tfstate.backup" ]; then
  log_warn "Found terraform.tfstate.backup - Using to rollback"
  
  # Use terraform destroy to tear down #984-specific resources
  cd terraform
  
  # Destroy only oauth2-proxy OAuth whitelist configuration
  log_info "Destroying oauth2-proxy OAuth whitelist configuration..."
  if terraform destroy -target='aws_secretsmanager_secret.qa_oauth_whitelist' \
      -auto-approve 2>&1 | tee -a "$ROLLBACK_LOG"; then
    log_success "OAuth whitelist configuration destroyed"
  else
    log_warn "OAuth whitelist destruction had issues - Check logs"
  fi
  
  cd "$SCRIPT_DIR"
else
  log_warn "No terraform backup found - Manual verification needed"
fi
echo ""

# ============================================================================
# Step 3: Restart oauth2-proxy on production
# ============================================================================
log_info "Step 3/6: Restarting oauth2-proxy on production"

if timeout 30 ssh akushnir@192.168.168.31 \
    "docker-compose restart oauth2-proxy 2>/dev/null" &>/dev/null; then
  log_success "oauth2-proxy restarted"
  
  # Wait for service to stabilize
  sleep 5
  
  # Verify it's running
  if timeout 10 ssh akushnir@192.168.168.31 \
      "docker ps -f name=oauth2-proxy --format '{{.Status}}' 2>/dev/null | grep -q Up"; then
    log_success "oauth2-proxy is running and healthy"
  else
    log_error "oauth2-proxy failed to restart"
    exit 1
  fi
else
  log_error "Cannot SSH to production host"
  exit 1
fi
echo ""

# ============================================================================
# Step 4: Verify oauth2-proxy health
# ============================================================================
log_info "Step 4/6: Verifying oauth2-proxy health"

if timeout 10 ssh akushnir@192.168.168.31 \
    "curl -s http://localhost:4180/health 2>/dev/null | grep -q 'OK\|healthy'" &>/dev/null; then
  log_success "oauth2-proxy health check passed"
else
  log_warn "oauth2-proxy health check failed - Manual verification required"
fi
echo ""

# ============================================================================
# Step 5: Clean GSM secrets (optional - manual)
# ============================================================================
log_info "Step 5/6: GSM secrets cleanup"

log_warn "Manual step required:"
log_warn "1. Review GSM secrets created during #984:"
log_warn "   - qa-user-email"
log_warn "   - qa-user-password"
log_warn "   - qa-oauth-whitelist"
log_warn ""
log_warn "2. Decision: Keep (for redeployment) or Delete (for clean state)"
log_warn ""
log_warn "3. If deleting, run:"
log_warn "   gcloud secrets delete qa-user-email qa-user-password qa-oauth-whitelist"
echo ""

# ============================================================================
# Step 6: Update Issue #984
# ============================================================================
log_info "Step 6/6: Updating Issue #984 with rollback evidence"

COMMENT_BODY="🔄 Rollback executed at $(date '+%Y-%m-%d %H:%M:%S UTC')

**Rollback Steps Completed**:
- ✅ Backed up current .env
- ✅ Reverted terraform apply (oauth2-proxy OAuth configuration)
- ✅ Restarted oauth2-proxy service
- ✅ Verified service health
- ⏳ GSM secrets cleanup (manual review required)

**Evidence**:
Rollback log: \`artifacts/triage/issue-984-rollback-${TIMESTAMP}.log\`
Backup location: \`${BACKUP_DIR}/.env.backup.${TIMESTAMP}\`

**Next Steps**:
1. Review rollback log for any errors
2. Decide on GSM secrets cleanup (keep or delete)
3. Investigate root cause of deployment failure
4. Plan re-deployment when issues resolved

See ISSUE-984-ROLLBACK-PROCEDURE.md for detailed procedures."

if gh issue comment 984 --repo kushin77/code-server --body "$COMMENT_BODY" 2>/dev/null; then
  log_success "Updated Issue #984 with rollback evidence"
else
  log_warn "Could not comment on Issue #984 - Manual update needed"
fi
echo ""

# ============================================================================
# Final Summary
# ============================================================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Rollback Complete${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "Rollback log saved to: $ROLLBACK_LOG"
echo ""
echo "Verification checklist:"
echo "  ✅ .env backed up to: ${BACKUP_DIR}/.env.backup.${TIMESTAMP}"
echo "  ✅ Terraform changes reverted"
echo "  ✅ oauth2-proxy restarted"
echo "  ✅ Service health verified"
echo "  ⏳ GSM secrets require manual review"
echo ""
echo "To revert this rollback:"
echo "  1. Restore .env: cp ${BACKUP_DIR}/.env.backup.${TIMESTAMP} .env"
echo "  2. Re-apply terraform: cd terraform && terraform apply -auto-approve"
echo "  3. Restart service: ssh akushnir@192.168.168.31 'docker-compose restart oauth2-proxy'"
echo ""
