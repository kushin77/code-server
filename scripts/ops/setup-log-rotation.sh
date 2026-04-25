#!/bin/bash
###############################################################################
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# Purpose: Configures log rotation for infrastructure logs
# Author: Autonomous Infrastructure
# Date: 2026-04-25
# Related issues: #1534 (IaC Governance), #1536 (Infrastructure Standards)
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"
readonly LOGROTATE_CONF="${LOGROTATE_CONF:-logrotate.snippet}"
readonly ROTATION_FREQUENCY="${ROTATION_FREQUENCY:-daily}"
readonly ROTATION_COUNT="${ROTATION_COUNT:-7}"

echo "[INFO] Setting up log rotation..."

# Create logrotate configuration snippet
cat <<CONF > "${LOGROTATE_CONF}"
${LOG_DIR}/*.log {
    ${ROTATION_FREQUENCY}
    rotate ${ROTATION_COUNT}
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
CONF

echo "[SUCCESS] Log rotation configuration generated at ${LOGROTATE_CONF}"
echo "[INFO] To apply, run: sudo mv ${LOGROTATE_CONF} /etc/logrotate.d/code-server-enterprise"
