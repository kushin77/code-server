#!/bin/bash

###############################################################################
# SUDOERS CONFIGURATION FOR GPU FIXES
# 
# This script configures passwordless sudo for GPU installation commands
# on host 192.168.168.31
#
# Usage:
#   sudo bash setup-sudoers-gpu.sh
#
###############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
  echo -e "${GREEN}[✓]${NC} $1"
}

error() {
  echo -e "${RED}[✗]${NC} $1"
}

echo "================================================"
echo "SUDOERS CONFIGURATION FOR GPU FIXES"
echo "================================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  error "This script must be run as root (use: sudo bash setup-sudoers-gpu.sh)"
  exit 1
fi

# Get the username to configure
if [ -z "$1" ]; then
  read -p "Enter username to configure (e.g., akushnir): " TARGET_USER
else
  TARGET_USER=$1
fi

# Validate user exists
if ! id "$TARGET_USER" >/dev/null 2>&1; then
  error "User $TARGET_USER does not exist"
  exit 1
fi

log "Configuring passwordless sudo for user: $TARGET_USER"

# Create sudoers file for GPU commands
cat > /etc/sudoers.d/gpu-fixes-$TARGET_USER << 'EOF'
# GPU Fixes - Passwordless Sudo for akushnir
# Generated: $(date)

Defaults:akushnir !require_tty

# GPU Driver Installation
akushnir ALL=(ALL) NOPASSWD: /usr/bin/apt-get update
akushnir ALL=(ALL) NOPASSWD: /usr/bin/apt-get install -y nvidia-driver-555*
akushnir ALL=(ALL) NOPASSWD: /usr/sbin/reboot

# CUDA 12.4 Installation
akushnir ALL=(ALL) NOPASSWD: /usr/bin/apt-get install -y cuda-12-4
akushnir ALL=(ALL) NOPASSWD: /usr/bin/apt-get install -y cuda-toolkit-12-4

# NVIDIA Container Runtime Installation
akushnir ALL=(ALL) NOPASSWD: /usr/bin/apt-get install -y nvidia-container-runtime
akushnir ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart docker

# Docker Daemon Configuration
akushnir ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/docker/daemon.json
akushnir ALL=(ALL) NOPASSWD: /usr/bin/systemctl daemon-reload
akushnir ALL=(ALL) NOPASSWD: /usr/sbin/systemctl restart docker

# General fixes
akushnir ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart *
akushnir ALL=(ALL) NOPASSWD: /usr/bin/systemctl status *
akushnir ALL=(ALL) NOPASSWD: /usr/bin/systemctl is-active *

EOF

# Fix permissions
chmod 0440 /etc/sudoers.d/gpu-fixes-$TARGET_USER

# Validate sudoers syntax
if ! visudo -c -f /etc/sudoers.d/gpu-fixes-$TARGET_USER >/dev/null 2>&1; then
  error "Sudoers file validation failed - rolling back"
  rm /etc/sudoers.d/gpu-fixes-$TARGET_USER
  exit 1
fi

log "Sudoers configuration installed for $TARGET_USER"
log "GPU commands can now be run without password"

echo ""
echo "Verification - test passwordless sudo:"
echo "  ssh akushnir@192.168.168.31 'sudo systemctl status docker'"

exit 0
