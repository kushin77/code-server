#!/bin/bash

###############################################################################
# GPU DRIVER UPGRADE - SUDOERS-FIRST APPROACH
# 
# Step 1: Add akushnir to sudoers for GPU commands (requires ONE sudo)
# Step 2: Execute driver upgrade (now passwordless)
###############################################################################

set -e

# Step 1: Create sudoers file
cat > /tmp/gpu-allow-nopasswd << 'SUDO_CONF'
# Allow akushnir passwordless sudo for GPU driver installation
akushnir ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /sbin/reboot
SUDO_CONF

echo "[*] Adding akushnir to sudoers for GPU operations..."

# Use sudo to install the sudoers file (only sudo needed here)
sudo tee /etc/sudoers.d/gpu-install < /tmp/gpu-allow-nopasswd > /dev/null
sudo chmod 0440 /etc/sudoers.d/gpu-install

echo "[✓] Sudoers configured for passwordless apt-get and reboot"

# Step 2: Now run the upgrade (should be passwordless thanks to sudoers)
echo ""
echo "[*] Executing GPU driver upgrade (now passwordless)..."
echo ""

sudo bash /tmp/gpu-driver-upgrade-direct.sh

