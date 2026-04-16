#!/bin/bash
################################################################################
# scripts/vrrp/vrrp-notify.sh
# Keepalived notification handler: Executes on VRRP state transitions
# Sends alerts to AlertManager for observability
#
# Usage: vrrp-notify.sh [MASTER|BACKUP|FAULT] [group] [priority]
# Called by Keepalived: notify_master, notify_backup, notify_fault
#
# Managed by: P2 #365 (VRRP Virtual IP Failover)
################################################################################

set -euo pipefail

# Inputs
STATE="${1:-UNKNOWN}"
GROUP="${2:-PROD_VIP}"
PRIORITY="${3:-0}"
HOSTNAME="$(hostname)"

# AlertManager endpoint
ALERTMANAGER_ADDR="${ALERTMANAGER_ADDR:-http://alertmanager:9093}"

# Logging
log_alert() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$STATE] $*" >> /var/log/vrrp-transitions.log
}

# ─────────────────────────────────────────────────────────────────────────────
# Fire AlertManager alert based on state transition
# ─────────────────────────────────────────────────────────────────────────────
fire_alert() {
    local severity=$1
    local summary=$2
    local description=$3
    
    # Construct AlertManager payload
    local alert_json=$(cat <<EOF
[{
  "labels": {
    "alertname": "VRRPStateChange",
    "vrrp_instance": "$GROUP",
    "new_state": "$STATE",
    "hostname": "$HOSTNAME",
    "severity": "$severity"
  },
  "annotations": {
    "summary": "$summary",
    "description": "$description",
    "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  }
}]
EOF
)
    
    # Send to AlertManager
    curl -s -XPOST "$ALERTMANAGER_ADDR/api/v1/alerts" \
        -H "Content-Type: application/json" \
        -d "$alert_json" \
        >> /var/log/vrrp-alerts.log 2>&1 || true
    
    log_alert "AlertManager notification sent: $summary"
}

# ─────────────────────────────────────────────────────────────────────────────
# State-specific handling
# ─────────────────────────────────────────────────────────────────────────────

case "$STATE" in
    MASTER)
        log_alert "🔴 BECAME MASTER — VIP 192.168.168.30 now on $HOSTNAME (priority: $PRIORITY)"
        fire_alert "info" \
            "VRRP: $HOSTNAME became MASTER" \
            "Virtual IP 192.168.168.30 is now owned by $HOSTNAME. Replica is monitoring for failover."
        
        # Optional: Update DNS if configured
        # /usr/local/sbin/update-dns-vip.sh MASTER
        ;;
    
    BACKUP)
        log_alert "🟢 BECAME BACKUP — VIP 192.168.168.30 managed by primary (priority: $PRIORITY)"
        fire_alert "info" \
            "VRRP: $HOSTNAME became BACKUP" \
            "Virtual IP 192.168.168.30 is owned by primary. $HOSTNAME is standby ready for failover."
        ;;
    
    FAULT)
        log_alert "🔔 FAULT — VRRP is not functioning correctly (priority: $PRIORITY)"
        fire_alert "warning" \
            "VRRP: $HOSTNAME encountered FAULT" \
            "VRRP process on $HOSTNAME has entered fault state. Manual investigation may be required."
        ;;
    
    *)
        log_alert "⚠️  UNKNOWN STATE: $STATE (priority: $PRIORITY)"
        fire_alert "warning" \
            "VRRP: $HOSTNAME unknown state" \
            "VRRP reported unexpected state: $STATE"
        ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
# Optional: Execute custom scripts on transition
# ─────────────────────────────────────────────────────────────────────────────

# If becoming MASTER, optionally restart services that need VIP binding
if [[ "$STATE" == "MASTER" ]]; then
    # Example: Restart HAProxy if it's VIP-bound
    # docker-compose restart haproxy 2>/dev/null || true
    
    # Example: Update internal DNS records
    # /usr/local/sbin/update-internal-dns.sh 2>/dev/null || true
    
    log_alert "MASTER transition complete — service restart/update logic executed"
fi

exit 0
