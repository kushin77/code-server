#!/usr/bin/env bash
# @file        scripts/deploy-passwordless-sudo.sh
# @module      deploy/privileges
# @description Configure passwordless sudo for deployment user on remote hosts
# @owner       infrastructure
# @status      active
#
# IMPORTANT: This script REQUIRES ONE-TIME INTERACTIVE SUDO SETUP
# The initial password entry cannot be automated for security reasons.
#
# Usage: 
#   ssh akushnir@192.168.168.31
#   bash ~/code-server-enterprise/scripts/deploy-passwordless-sudo.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common/init.sh"

SUDOERS_FILE="/etc/sudoers.d/akushnir"
SUDOERS_TEMPLATE="./etc/sudoers.d/akushnir"

log_info "================================================================================"
log_info "  Issue #1636: Passwordless Sudo Deployment"
log_info "================================================================================"
log_info ""
log_info "This will enable passwordless sudo for the akushnir user."
log_info "You will be prompted for your password ONCE to validate the sudoers configuration."
log_info ""

# Step 1: Verify sudoers template exists
if [ ! -f "$SUDOERS_TEMPLATE" ]; then
  log_error "Sudoers template not found at $SUDOERS_TEMPLATE"
  log_error "Make sure you're running from the code-server-enterprise directory"
  exit 1
fi

# Step 2: Test current sudo (should require password)
log_info "Step 1: Testing current sudo (will prompt for password)..."
if sudo -l > /dev/null 2>&1; then
  log_success "Current sudo access works"
else
  log_warn "Current sudo may require password (this is expected)"
fi

# Step 3: Validate sudoers template syntax
log_info ""
log_info "Step 2: Validating sudoers template..."
if sudo visudo -cf "$SUDOERS_TEMPLATE"; then
  log_success "Sudoers template is valid"
else
  log_error "Sudoers template has invalid syntax"
  exit 1
fi

# Step 4: Install sudoers configuration
log_info ""
log_info "Step 3: Installing passwordless sudo configuration..."
log_info "You will be prompted for your password to install the sudoers file."
log_info ""

# Copy the template to sudoers.d with proper permissions
# This WILL require a password because we're creating a file in /etc
sudo cp "$SUDOERS_TEMPLATE" "$SUDOERS_FILE"
sudo chmod 0440 "$SUDOERS_FILE"

log_success "Sudoers file installed"

# Step 5: Verify passwordless sudo works
log_info ""
log_info "Step 4: Testing passwordless sudo..."
log_info "Running: sudo -n whoami (should not prompt for password)"

if sudo -n whoami > /dev/null 2>&1; then
  log_success "Passwordless sudo is working!"
  WHOAMI=$(sudo -n whoami)
  log_info "   Current user via sudo -n: $WHOAMI"
else
  log_error "Passwordless sudo is not working"
  log_error "This may indicate a configuration problem"
  exit 1
fi

# Step 6: Verify key infrastructure commands work passwordless
log_info ""
log_info "Step 5: Testing infrastructure commands..."
log_info "   - systemctl status: $(sudo -n systemctl is-system-running)"
log_info "   - mount command available: $(sudo -n test -x /bin/mount && echo 'yes' || echo 'no')"

# Step 7: Final verification
log_info ""
log_info "================================================================================"
log_info "  Issue #1636: Passwordless Sudo Deployment Complete!"
log_info "================================================================================"
log_info ""
log_info "The akushnir user can now run sudo commands without a password."
log_info "This enables automated infrastructure operations across the cluster."
log_info ""
log_info "Next steps:"
log_info "  1. Deploy to Replica 2: ssh akushnir@192.168.168.42 < deploy-passwordless-sudo.sh"
log_info "  2. Run fstab sync: bash scripts/ops/sync-fstab-between-replicas.sh"
log_info "  3. Verify cluster parity: bash scripts/ops/check-replica-parity.sh"
log_info ""
