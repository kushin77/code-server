#!/bin/bash
# @file scripts/ha/notify-vrrp.sh
# @description Keepalived VRRP state change notification script
# @usage Called by keepalived when transitioning between MASTER and BACKUP states
# Args: $1 = 'master' or 'backup'

set -eu

trap 'exit 1' ERR
trap 'true' EXIT

STATE="${1:-unknown}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE="/var/log/keepalived-state-changes.log"

# Log the state transition
{
  echo "[$TIMESTAMP] VRRP State Change: $STATE"
  echo "  Container: code-server-keepalived"
  echo "  Host: $(hostname)"
  if [ "$STATE" = "master" ]; then
    echo "  Action: Now MASTER of VIP 192.168.168.30/24 — accepting traffic"
  elif [ "$STATE" = "backup" ]; then
    echo "  Action: Now BACKUP — standby mode"
  fi
  echo ""
} >> "$LOG_FILE" 2>&1 || true

# Optional: Send notification to monitoring system or log aggregator
# Example: curl -X POST http://monitoring:9000/vrrp -d "state=$STATE&host=$(hostname)"

exit 0
