#!/usr/bin/env bash
################################################################################
# GitHub Actions Runner Systemd Service Setup
# File: scripts/github-runner-systemd-setup.sh
# Purpose: Install and configure systemd service for auto-start/auto-restart
# Usage: ./scripts/github-runner-systemd-setup.sh
# Owner: Infrastructure Team
################################################################################

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
RUNNER_HOME="/opt/github-actions-runner"
RUNNER_USER="runner"
SERVICE_NAME="github-actions-runner"

echo "════════════════════════════════════════════════════════════════════════════"
echo "  GitHub Actions Runner Systemd Service Setup"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Configuration:"
echo "  • Service Name: ${SERVICE_NAME}"
echo "  • Runner Home: ${RUNNER_HOME}"
echo "  • Runner User: ${RUNNER_USER}"
echo ""

# ════════════════════════════════════════════════════════════════════════════
# PHASE 1: INSTALL SYSTEMD SERVICE
# ════════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}▸ Phase 1: Creating systemd service...${NC}"

# Use built-in installation if available (newer versions)
if [[ -f "${RUNNER_HOME}/svc.sh" ]]; then
  echo "  Using built-in systemd installation..."
  cd "${RUNNER_HOME}"
  sudo ./svc.sh install "${RUNNER_USER}"
  echo -e "${GREEN}✓ Systemd service installed${NC}"
else
  # Manual service file creation (for compatibility)
  echo "  Creating manual systemd service file..."
  
  SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
  
  sudo tee "${SERVICE_FILE}" > /dev/null <<'EOF'
[Unit]
Description=GitHub Actions Runner
Documentation=https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/configuring-the-self-hosted-runner-application-as-a-service
After=network.target

[Service]
Type=simple
User=runner
WorkingDirectory=/opt/github-actions-runner
ExecStart=/opt/github-actions-runner/run.sh
Restart=always
RestartSec=15
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  echo -e "${GREEN}✓ Systemd service file created${NC}"
fi

# ════════════════════════════════════════════════════════════════════════════
# PHASE 2: RELOAD & ENABLE SERVICE
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}▸ Phase 2: Enabling and starting service...${NC}"

# Reload systemd daemon
echo "  Reloading systemd daemon..."
sudo systemctl daemon-reload

# Enable service for auto-start on boot
echo "  Enabling service for auto-start..."
sudo systemctl enable "${SERVICE_NAME}" || sudo systemctl enable "${SERVICE_NAME}.service"

# Start the service
echo "  Starting service..."
sudo systemctl start "${SERVICE_NAME}" || sudo systemctl start "${SERVICE_NAME}.service"

echo -e "${GREEN}✓ Service enabled and started${NC}"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 3: VERIFY SERVICE
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}▸ Phase 3: Verifying service...${NC}"

# Check service status
echo "  Service status:"
sudo systemctl status "${SERVICE_NAME}" --no-pager -l | head -10 || true

# Check if running
if sudo systemctl is-active --quiet "${SERVICE_NAME}"; then
  echo -e "${GREEN}✓ Service is running${NC}"
else
  echo -e "${YELLOW}⚠ Service may be starting - check logs:${NC}"
  echo "    sudo journalctl -u ${SERVICE_NAME} -f"
fi

# ════════════════════════════════════════════════════════════════════════════
# PHASE 4: USEFUL COMMANDS
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo "  SERVICE SETUP COMPLETE"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Useful commands:"
echo ""
echo "  • View service status:"
echo "    sudo systemctl status ${SERVICE_NAME}"
echo ""
echo "  • View live logs:"
echo "    sudo journalctl -u ${SERVICE_NAME} -f"
echo ""
echo "  • Restart service:"
echo "    sudo systemctl restart ${SERVICE_NAME}"
echo ""
echo "  • Stop service:"
echo "    sudo systemctl stop ${SERVICE_NAME}"
echo ""
echo "  • Restart on next boot:"
echo "    sudo systemctl start ${SERVICE_NAME}"
echo ""
echo "  • View recent logs (last 50 lines):"
echo "    sudo journalctl -u ${SERVICE_NAME} -n 50"
echo ""
echo "  • Uninstall service (if needed):"
echo "    sudo systemctl stop ${SERVICE_NAME}"
echo "    sudo systemctl disable ${SERVICE_NAME}"
echo "    sudo rm /etc/systemd/system/${SERVICE_NAME}.service"
echo "    sudo systemctl daemon-reload"
echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "${GREEN}✓ Systemd service setup complete${NC}"
