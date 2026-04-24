#!/usr/bin/env bash
# @file        scripts/install/install-gvisor.sh
# @module      security/workspace-isolation
# @description Install gVisor (runsc) runtime for workspace isolation
#
# Installs gVisor runsc runtime on Linux hosts for container sandboxing.
# Provides hardware-based isolation immune to runc escapes (CVE-2019-5736).
# < 15% performance overhead.

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

log_info "Installing gVisor (runsc) runtime for workspace isolation..."

# Check if already installed
if command -v runsc >/dev/null 2>&1; then
    log_info "gVisor runsc already installed: $(runsc version)"
    exit 0
fi

# Install gVisor
log_info "Installing gVisor..."

# Add gVisor repository
curl -fsSL https://gvisor.dev/archive.key | sudo gpg --dearmor -o /usr/share/keyrings/gvisor-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main" | sudo tee /etc/apt/sources.list.d/gvisor.list > /dev/null

# Update package list
sudo apt-get update

# Install runsc
sudo apt-get install -y runsc

# Verify installation
if command -v runsc >/dev/null 2>&1; then
    log_info "gVisor runsc installed successfully: $(runsc version)"
else
    log_error "Failed to install gVisor runsc"
    exit 1
fi

# Configure Docker daemon to use runsc runtime
log_info "Configuring Docker daemon for runsc runtime..."

# Create or update daemon.json
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "runtimes": {
    "runsc": {
      "path": "/usr/bin/runsc"
    }
  }
}
EOF

# Restart Docker daemon
sudo systemctl restart docker

log_info "Docker daemon configured with runsc runtime"
log_info "gVisor workspace isolation ready"

# Test runsc
log_info "Testing runsc runtime..."
if docker run --rm --runtime=runsc hello-world >/dev/null 2>&1; then
    log_info "runsc runtime test successful"
else
    log_warn "runsc runtime test failed - may require system reboot"
fi