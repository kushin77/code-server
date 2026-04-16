#!/bin/bash
# VRRP State Change Notification Script
# P2 #365: Virtual IP Failover Implementation
# Purpose: Handle VRRP state transitions and notify operators
# Generated: April 15, 2026

set -euo pipefail

STATE="${1:-UNKNOWN}"
HOST="${2:-unknown}"
HOSTNAME=$(hostname)
TIMESTAMP=$(date -Iseconds)
LOG_FILE="/var/log/keepalived/state-changes.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Log state change
log_state_change() {
    local level="$1"
    local msg="$2"
    echo "[${TIMESTAMP}] [${level}] VRRP State Change: ${msg}" >> "$LOG_FILE"
}

# Send notification email
send_notification() {
    local subject="$1"
    local body="$2"
    
    # Try to send email (graceful failure if mail not available)
    if command -v mail >/dev/null 2>&1; then
        echo -e "$body" | mail -s "$subject" ops@example.com 2>/dev/null || true
    fi
}

# Handle state transitions
case "$STATE" in
    MASTER)
        log_state_change "INFO" "$HOSTNAME → MASTER (VIP: 192.168.168.40)"
        
        # Verify VIP is assigned
        if ip addr show | grep -q "192.168.168.40"; then
            log_state_change "INFO" "VIP 192.168.168.40 successfully assigned to $HOSTNAME"
        else
            log_state_change "ERROR" "VIP 192.168.168.40 NOT assigned despite MASTER state!"
        fi
        
        # Ensure services are running
        if [[ -f /docker-compose.yml ]]; then
            docker-compose up -d 2>/dev/null || log_state_change "WARN" "docker-compose up failed"
        fi
        
        # Update DNS record via dynamic DNS
        if [[ -f /etc/bind/keys/ddns-update.key ]]; then
            nsupdate -k /etc/bind/keys/ddns-update.key <<EOF 2>/dev/null || true
server localhost 53
zone internal
update delete code-server.internal IN A
update add code-server.internal 300 IN A 192.168.168.40
send
EOF
            log_state_change "INFO" "DNS updated: code-server.internal → 192.168.168.40"
        fi
        
        # Send email notification
        send_notification \
            "✅ VRRP MASTER: $HOSTNAME ($(date))" \
            "VRRP State Change\n\nHost: $HOSTNAME\nState: MASTER\nVIP: 192.168.168.40\nTimestamp: $TIMESTAMP\n\nThis host is now serving the virtual IP and handling client connections."
        
        # Write state to Prometheus textfile collector
        echo "keepalived_vrrp_state_master{host=\"$HOSTNAME\"} 1" > /var/lib/node_exporter/keepalived_vrrp.prom
        echo "keepalived_vrrp_state_backup{host=\"$HOSTNAME\"} 0" >> /var/lib/node_exporter/keepalived_vrrp.prom
        ;;
        
    BACKUP)
        log_state_change "INFO" "$HOSTNAME → BACKUP (standby)"
        
        # Verify VIP is NOT assigned
        if ! ip addr show | grep -q "192.168.168.40"; then
            log_state_change "INFO" "VIP 192.168.168.40 correctly NOT assigned (backup mode)"
        else
            log_state_change "ERROR" "VIP 192.168.168.40 still assigned in BACKUP state!"
        fi
        
        # Send email notification
        send_notification \
            "⚠️ VRRP BACKUP: $HOSTNAME ($(date))" \
            "VRRP State Change\n\nHost: $HOSTNAME\nState: BACKUP (Standby)\nVIP: 192.168.168.40 (owned by primary)\nTimestamp: $TIMESTAMP\n\nThis host is in standby mode and will take over if primary fails."
        
        # Write state to Prometheus textfile collector
        echo "keepalived_vrrp_state_master{host=\"$HOSTNAME\"} 0" > /var/lib/node_exporter/keepalived_vrrp.prom
        echo "keepalived_vrrp_state_backup{host=\"$HOSTNAME\"} 1" >> /var/lib/node_exporter/keepalived_vrrp.prom
        ;;
        
    FAULT)
        log_state_change "ERROR" "$HOSTNAME → FAULT state"
        
        # Send email notification (highest priority)
        send_notification \
            "❌ VRRP FAULT ALERT: $HOSTNAME ($(date))" \
            "CRITICAL VRRP ALERT\n\nHost: $HOSTNAME\nState: FAULT\nTimestamp: $TIMESTAMP\n\nKeepAlived has detected a fault condition and cannot participate in VRRP elections.\n\nImmediate Action Required:\n1. SSH to $HOSTNAME\n2. Check keepalived status: sudo systemctl status keepalived\n3. Review logs: sudo journalctl -u keepalived -n 50\n4. Restart if needed: sudo systemctl restart keepalived"
        
        # Attempt automatic recovery
        log_state_change "WARN" "Attempting automatic keepalived restart..."
        systemctl restart keepalived 2>/dev/null || log_state_change "ERROR" "systemctl restart keepalived failed"
        
        # Write state to Prometheus textfile collector
        echo "keepalived_vrrp_state_fault{host=\"$HOSTNAME\"} 1" > /var/lib/node_exporter/keepalived_vrrp.prom
        ;;
        
    *)
        log_state_change "WARN" "Unknown state: $STATE"
        send_notification \
            "⚠️ VRRP Unknown State: $HOSTNAME" \
            "Unknown VRRP state transition received.\n\nHost: $HOSTNAME\nState: $STATE\nTimestamp: $TIMESTAMP"
        ;;
esac

# Log completion
log_state_change "INFO" "Notification script completed"

exit 0
