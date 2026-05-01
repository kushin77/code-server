#!/bin/bash
###############################################################################
# @file        scripts/ops/setup-log-rotation.sh
# @module      ops/setup-log-rotation
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"
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
