#!/bin/bash
# Deploy Issue #1636 - Passwordless Sudo Configuration
# This script sets up passwordless sudo for the akushnir user on Replica 1
# 
# IMPORTANT: This script REQUIRES ONE-TIME INTERACTIVE SUDO SETUP
# The initial password entry cannot be automated for security reasons.
#
# Usage: 
#   ssh akushnir@192.168.168.31
#   bash ~/code-server-enterprise/scripts/deploy-passwordless-sudo.sh

set -euo pipefail

SUDOERS_FILE="/etc/sudoers.d/akushnir"
SUDOERS_TEMPLATE="./etc/sudoers.d/akushnir"

echo "================================================================================"
echo "  Issue #1636: Passwordless Sudo Deployment"
echo "================================================================================"
echo ""
echo "This will enable passwordless sudo for the akushnir user."
echo "You will be prompted for your password ONCE to validate the sudoers configuration."
echo ""

# Step 1: Verify sudoers template exists
if [ ! -f "$SUDOERS_TEMPLATE" ]; then
  echo "❌ ERROR: Sudoers template not found at $SUDOERS_TEMPLATE"
  echo "   Make sure you're running from the code-server-enterprise directory"
  exit 1
fi

# Step 2: Test current sudo (should require password)
echo "Step 1: Testing current sudo (will prompt for password)..."
if sudo -l > /dev/null 2>&1; then
  echo "✅ Current sudo access works"
else
  echo "⚠️  Current sudo may require password (this is expected)"
fi

# Step 3: Validate sudoers template syntax
echo ""
echo "Step 2: Validating sudoers template..."
if sudo visudo -cf "$SUDOERS_TEMPLATE"; then
  echo "✅ Sudoers template is valid"
else
  echo "❌ ERROR: Sudoers template has invalid syntax"
  exit 1
fi

# Step 4: Install sudoers configuration
echo ""
echo "Step 3: Installing passwordless sudo configuration..."
echo "You will be prompted for your password to install the sudoers file."
echo ""

# Copy the template to sudoers.d with proper permissions
# This WILL require a password because we're creating a file in /etc
sudo cp "$SUDOERS_TEMPLATE" "$SUDOERS_FILE"
sudo chmod 0440 "$SUDOERS_FILE"

echo "✅ Sudoers file installed"

# Step 5: Verify passwordless sudo works
echo ""
echo "Step 4: Testing passwordless sudo..."
echo "Running: sudo -n whoami (should not prompt for password)"

if sudo -n whoami > /dev/null 2>&1; then
  echo "✅ Passwordless sudo is working!"
  WHOAMI=$(sudo -n whoami)
  echo "   Current user via sudo -n: $WHOAMI"
else
  echo "❌ ERROR: Passwordless sudo is not working"
  echo "   This may indicate a configuration problem"
  exit 1
fi

# Step 6: Verify key infrastructure commands work passwordless
echo ""
echo "Step 5: Testing infrastructure commands..."
echo "   - systemctl status: $(sudo -n systemctl is-system-running)"
echo "   - mount command available: $(sudo -n test -x /bin/mount && echo 'yes' || echo 'no')"

# Step 7: Final verification
echo ""
echo "================================================================================"
echo "  ✅ Issue #1636: Passwordless Sudo Deployment Complete!"
echo "================================================================================"
echo ""
echo "The akushnir user can now run sudo commands without a password."
echo "This enables automated infrastructure operations across the cluster."
echo ""
echo "Next steps:"
echo "  1. Deploy to Replica 2: ssh akushnir@192.168.168.42 < deploy-passwordless-sudo.sh"
echo "  2. Run fstab sync: bash scripts/ops/sync-fstab-between-replicas.sh"
echo "  3. Verify cluster parity: bash scripts/ops/check-replica-parity.sh"
echo ""
