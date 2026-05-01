#!/bin/bash
#
# Setup systemd timer for continuous drift monitoring
# Run once to enable persistent monitoring on this system
#

set -euo pipefail

trap 'echo "Setup failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SYSTEMD_SOURCE_DIR="${REPO_ROOT}/systemd"
SYSTEMD_DEST_DIR="/etc/systemd/system"

echo "============================================"
echo "code-server Drift Monitoring Setup"
echo "============================================"
echo ""

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root or with sudo"
  echo ""
  echo "Usage:"
  echo "  sudo ${SCRIPT_DIR}/setup-drift-monitoring.sh"
  exit 1
fi

# Verify source files exist
if [[ ! -f "${SYSTEMD_SOURCE_DIR}/drift-monitor.service" ]]; then
  echo "Error: ${SYSTEMD_SOURCE_DIR}/drift-monitor.service not found"
  exit 1
fi

if [[ ! -f "${SYSTEMD_SOURCE_DIR}/drift-monitor.timer" ]]; then
  echo "Error: ${SYSTEMD_SOURCE_DIR}/drift-monitor.timer not found"
  exit 1
fi

echo "1. Installing systemd files..."
cp "${SYSTEMD_SOURCE_DIR}/drift-monitor.service" "${SYSTEMD_DEST_DIR}/"
cp "${SYSTEMD_SOURCE_DIR}/drift-monitor.timer" "${SYSTEMD_DEST_DIR}/"
echo "   ✓ Files installed to ${SYSTEMD_DEST_DIR}/"
echo ""

echo "2. Reloading systemd daemon..."
systemctl daemon-reload
echo "   ✓ Daemon reloaded"
echo ""

echo "3. Enabling timer..."
systemctl enable drift-monitor.timer
echo "   ✓ Timer enabled (will start on boot)"
echo ""

echo "4. Starting timer..."
systemctl start drift-monitor.timer
echo "   ✓ Timer started"
echo ""

echo "5. Verifying setup..."
echo ""
echo "   Timer status:"
systemctl status drift-monitor.timer --no-pager || true
echo ""
echo "   Next run:"
systemctl list-timers drift-monitor.timer --no-pager || true
echo ""

echo "6. Checking logs..."
echo ""
echo "   Recent log entries:"
journalctl -u drift-monitor.service -n 5 --no-pager || true
echo ""

echo "============================================"
echo "Setup Complete ✓"
echo "============================================"
echo ""
echo "The drift monitoring watchdog is now running"
echo "Monitoring will run every 5 minutes"
echo ""
echo "Commands to monitor:"
echo "  journalctl -u drift-monitor.service -f    # Follow logs"
echo "  systemctl status drift-monitor.timer       # Check timer status"
echo "  systemctl list-timers drift-monitor.timer  # Show next run time"
echo "  systemctl stop drift-monitor.timer         # Disable monitoring"
echo ""
