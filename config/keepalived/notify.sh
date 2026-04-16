#!/bin/bash
# /etc/keepalived/notify.sh
# =========================
# Fires on every VRRP state transition.
# Sends alert to AlertManager so on-call team is notified immediately.
#
# Arguments:
#   $1 = new state: MASTER | BACKUP | FAULT | STOP
#
# Environment:
#   ALERTMANAGER_URL  (default: http://127.0.0.1:9093)
#   VRRP_INSTANCE     (default: PROD_VIP)
#
# Install: sudo cp this file /etc/keepalived/notify.sh && chmod +x

set -euo pipefail

STATE="${1:-UNKNOWN}"
HOSTNAME=$(hostname -s)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ALERTMANAGER_URL="${ALERTMANAGER_URL:-http://127.0.0.1:9093}"
VRRP_INSTANCE="${VRRP_INSTANCE:-PROD_VIP}"

# Map VRRP state to alert severity
case "$STATE" in
    MASTER)  SEVERITY="warning"  ;;
    BACKUP)  SEVERITY="info"     ;;
    FAULT)   SEVERITY="critical" ;;
    STOP)    SEVERITY="warning"  ;;
    *)       SEVERITY="info"     ;;
esac

# Log state transition to syslog
logger -t keepalived "VRRP $VRRP_INSTANCE on $HOSTNAME transitioned to $STATE"

# Fire AlertManager webhook
curl --silent --max-time 5 \
  --request POST \
  --header "Content-Type: application/json" \
  --data "[
    {
      \"labels\": {
        \"alertname\": \"VRRPStateChange\",
        \"severity\": \"${SEVERITY}\",
        \"instance\": \"${HOSTNAME}\",
        \"vrrp_instance\": \"${VRRP_INSTANCE}\",
        \"new_state\": \"${STATE}\"
      },
      \"annotations\": {
        \"summary\": \"VRRP ${VRRP_INSTANCE} on ${HOSTNAME} changed to ${STATE}\",
        \"description\": \"The VRRP virtual IP (192.168.168.30) state changed to ${STATE} on host ${HOSTNAME} at ${TIMESTAMP}. This indicates a primary/replica role change or a health check failure.\",
        \"runbook_url\": \"https://github.com/kushin77/code-server/blob/main/docs/runbooks/vrrp-failover.md\"
      },
      \"startsAt\": \"${TIMESTAMP}\"
    }
  ]" \
  "${ALERTMANAGER_URL}/api/v2/alerts" || \
    logger -t keepalived "WARNING: Failed to notify AlertManager at ${ALERTMANAGER_URL}"

# On MASTER transition: send gratuitous ARP to update L2 switch tables
if [ "$STATE" = "MASTER" ]; then
    # Ensure VIP is responsive immediately after taking over
    if command -v arping &>/dev/null; then
        arping -c 3 -A -I eth0 192.168.168.30 2>/dev/null || true
    fi
    logger -t keepalived "Sent gratuitous ARP for VIP 192.168.168.30 on ${HOSTNAME}"
fi

exit 0
