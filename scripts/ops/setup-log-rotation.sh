#!/bin/bash
###############################################################################
# @file        scripts/ops/setup-log-rotation.sh
# @module      ops/setup-log-rotation
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
# @file scripts/ops/setup-log-rotation.sh
# @description Configures log rotation for infrastructure logs to prevent disk exhaustion.
# @governance GOV-002

set -euo pipefail

LOG_DIR="logs"

echo "[INFO] Setting up log rotation..."

# Create logrotate configuration snippet
cat <<CONF > logrotate.snippet
$PWD/$LOG_DIR/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
CONF

echo "[SUCCESS] Log rotation configuration generated at logrotate.snippet"
echo "[INFO] To apply, run: sudo mv logrotate.snippet /etc/logrotate.d/code-server-enterprise"
