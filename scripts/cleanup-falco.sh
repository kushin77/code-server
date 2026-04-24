#!/usr/bin/env bash
# @file        scripts/cleanup-falco.sh
# @module      maintenance
# @description cleanup falco — on-prem code-server
# @owner       platform
# @status      active
# ════════════════════════════════════════════════════════════════════════════
# Cleanup Falco Runtime Security (for rollback)
# ════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common/init.sh"

log_info "Removing Falco runtime security..."

if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# Stop services
systemctl stop falco falco-sidekick 2>/dev/null || true
systemctl disable falco falco-sidekick 2>/dev/null || true

# Remove packages
apt-get remove -y falco falco-dkms 2>/dev/null || true

# Remove configuration
find /etc/falco/rules.d -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
rm -f /etc/systemd/system/falco.service 2>/dev/null || true
rm -f /etc/systemd/system/falco-sidekick.service 2>/dev/null || true
rm -f /usr/local/bin/falco-sidekick 2>/dev/null || true
rm -rf "${HOME}/.falco" 2>/dev/null || true

# Reload systemd
systemctl daemon-reload 2>/dev/null || true

log_success "Falco removed"
