#!/usr/bin/env bash
# @file        scripts/ops/setup-k3s-sudoers.sh
# @description Configure passwordless sudo for k3s installer on remote hosts
# @governance  GOV-002: One-time setup for sudoers configuration
# @usage       bash scripts/ops/setup-k3s-sudoers.sh <host> [<ssh_user>]

set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

# Parse arguments
HOST="${1:-192.168.168.31}"
SSH_USER="${2:-akushnir}"

echo -e "${BLUE}Setting up passwordless sudo for k3s on ${SSH_USER}@${HOST}${NC}"
echo -e "${BLUE}This requires ONE interactive authentication.${NC}\n"

# The sudoers entry to add
SUDOERS_ENTRY="akushnir ALL=(ALL) NOPASSWD: /usr/bin/curl, /usr/bin/sh, /usr/local/bin/k3s, /opt/k3s/bin/k3s, /usr/bin/install, /usr/bin/systemctl"

# Use ssh -t to allocate TTY so user can enter password interactively
echo "Adding sudoers entry for k3s commands..."
ssh -t "${SSH_USER}@${HOST}" "echo '${SUDOERS_ENTRY}' | sudo tee -a /etc/sudoers.d/k3s-install > /dev/null && sudo chmod 440 /etc/sudoers.d/k3s-install && echo -e '\n${GREEN}✓ Sudoers configured successfully${NC}' && sudo -n echo 'Passwordless sudo verified'"

echo -e "\n${GREEN}Setup complete. You can now run the provisioner:${NC}"
echo "bash scripts/ops/provision-k3s-cluster.sh"
