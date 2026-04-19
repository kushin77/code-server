#!/usr/bin/env bash
# @file        terraform/modules/keepalived/scripts/keepalived-notify.sh
# @module      terraform/keepalived
# @description notify hook for keepalived state transitions
#

set -euo pipefail

STATE="${1:-UNKNOWN}"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname || echo unknown-host)"
VIP="${PROD_VIP:-unknown-vip}"
LOG_FILE="/var/log/keepalived/notify.log"

mkdir -p "$(dirname "$LOG_FILE")"
printf '%s state=%s host=%s vip=%s\n' "$TS" "$STATE" "$HOSTNAME_SHORT" "$VIP" >> "$LOG_FILE"

exit 0
