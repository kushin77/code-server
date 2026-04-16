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

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Removing Falco runtime security...${NC}"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}✗ This script must be run as root${NC}"
    exit 1
fi

# Stop services
systemctl stop falco falco-sidekick 2>/dev/null || true
systemctl disable falco falco-sidekick 2>/dev/null || true

# Remove packages
apt-get remove -y falco falco-dkms 2>/dev/null || true

# Remove configuration
rm -rf /etc/falco/rules.d/* 2>/dev/null || true
rm -f /etc/systemd/system/falco.service 2>/dev/null || true
rm -f /etc/systemd/system/falco-sidekick.service 2>/dev/null || true
rm -f /usr/local/bin/falco-sidekick 2>/dev/null || true
rm -rf ~/.falco 2>/dev/null || true

# Reload systemd
systemctl daemon-reload 2>/dev/null || true

echo -e "${GREEN}✓ Falco removed${NC}"
