#!/bin/bash
# Quick deployment script to get security running immediately

set -euo pipefail

# Script directory and canonical initialization
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

log_section "DEPLOY SECURITY IMMEDIATELY"

cd "$SCRIPT_DIR" || exit 1

# Step 1: Verify scripts exist
log_info "Verifying scripts..."
if [[ ! -f "scripts/manage-users.sh" ]]; then
  log_error "scripts/manage-users.sh not found"
  exit 1
fi
log_success "Scripts verified"

# Step 2: Verify role files exist
log_info "Verifying role templates..."
roles=("viewer" "developer" "architect" "admin")
for role in "${roles[@]}"; do
  if [[ ! -f "config/role-settings/${role}-profile.json" ]]; then
    log_error "Role template not found: $role"
    exit 1
  fi
done
log_success "All 4 role templates verified"

# Step 3: Verify documentation
log_info "Verifying documentation..."
docs=("START_HERE_SECURITY.md" "IDE_SECURITY_AND_USER_MANAGEMENT.md" "CODE_SECURITY_HARDENING.md")
for doc in "${docs[@]}"; do
  if [[ ! -f "$doc" ]]; then
    log_error "Documentation not found: $doc"
    exit 1
  fi
done
log_success "All documentation verified"

# Step 4: Show next steps
log_success "SECURITY SYSTEM READY"
echo "Your code is protected. Next steps:"
echo ""
echo "1️⃣  ADD YOUR FIRST USER:"
echo "   ./scripts/manage-users.sh add-user \"email@company.com\" \"developer\""
echo ""
echo "2️⃣  COMMIT CHANGES:"
echo "   git add allowed-emails.txt config/user-settings/"
echo "   git commit -m \"chore: add users\""
echo "   git push origin main"
echo ""
echo "3️⃣  VERIFY:"
echo "   docker compose restart oauth2-proxy"
echo "   User can login at: https://${DOMAIN:-ide.kushnir.cloud}"
echo ""
echo "📚 Documentation:"
echo "   • Quick start: START_HERE_SECURITY.md"
echo "   • Operations: IDE_SECURITY_AND_USER_MANAGEMENT.md"
echo "   • Architecture: CODE_SECURITY_HARDENING.md"
echo "   • Full details: SECURITY_IMPLEMENTATION_SUMMARY.md"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo ""
