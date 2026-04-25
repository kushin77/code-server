#!/bin/bash
# Automated sudoers setup for k3s provisioning
# Execute: ssh -t akushnir@192.168.168.31 'bash -s' < /path/to/this/script

set -e

echo "=== K3s Sudoers Configuration ==="
echo ""
echo "Configuring passwordless sudo for k3s installation..."
echo ""

SUDOERS_ENTRY='akushnir ALL=(ALL) NOPASSWD: /usr/local/bin/k3s'

# Write sudoers entry (requires password here)
echo "$SUDOERS_ENTRY" | sudo tee /etc/sudoers.d/k3s-install > /dev/null

# Set correct permissions
sudo chmod 0440 /etc/sudoers.d/k3s-install

# Validate sudoers syntax
if sudo visudo -c -q 2>/dev/null; then
    echo "✅ Sudoers file syntax validated"
else
    echo "❌ Sudoers validation failed"
    sudo rm -f /etc/sudoers.d/k3s-install
    exit 1
fi

# Verify passwordless sudo works
if sudo -n echo "test" >/dev/null 2>&1; then
    echo "✅ Passwordless sudo verified successfully!"
else
    echo "❌ Passwordless sudo not working"
    exit 1
fi

echo ""
echo "=== Configuration Complete ==="
echo "✓ Sudoers entry created: $SUDOERS_ENTRY"
echo "✓ File permissions set: 0440"
echo "✓ Syntax validated"
echo "✓ Passwordless sudo verified"
echo ""
echo "Next: Run K3s provisioner"
echo "  bash scripts/ops/provision-k3s-cluster.sh"
