#!/bin/bash
# @file        scripts/keepalived-notify.sh
# @module      operations
# @description keepalived notify — on-prem code-server
# @owner       platform
# @status      active
#
# Keepalived Notification Script — Handle VRRP state changes
#
# This script is called by Keepalived when the VRRP state changes
# (MASTER, BACKUP, FAULT, STOP). It sends notifications and performs
# necessary actions for the state change.
#
# Called from keepalived.conf:
#   notify_master "/usr/local/bin/keepalived-notify.sh MASTER"
#   notify_backup "/usr/local/bin/keepalived-notify.sh BACKUP"
#   notify_fault  "/usr/local/bin/keepalived-notify.sh FAULT"
#   notify_stop   "/usr/local/bin/keepalived-notify.sh STOP"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

# ==============================================================================
# CONFIGURATION
# ==============================================================================

STATE="${1:-UNKNOWN}"
HOSTNAME="$(hostname)"
VIP="${PROD_VIP:-${STANDBY_HOST}}"
LOG_FILE="/var/log/keepalived-notify.log"

# Logging
mkdir -p "$(dirname "$LOG_FILE")"

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [KEEPALIVED] [$STATE] $*" | tee -a "$LOG_FILE"
}

# ==============================================================================
# HANDLERS
# ==============================================================================

handle_master() {
    # This host just became MASTER (now holding the VIP)
    log_message "✓ PROMOTED TO MASTER"
    log_message "  - VIP ${VIP} now on this host ($(hostname -I))"
    log_message "  - All traffic should flow here"
    
    # Optional: Notify monitoring system
    # curl -X POST http://monitoring.prod.internal:9093/api/v1/alerts \
    #      -H 'Content-Type: application/json' \
    #      -d "{\"status\":\"success\",\"message\":\"VRRP MASTER promoted on ${HOSTNAME}\"}"
    
    # Optional: Update local DNS
    # echo "$(date): Became MASTER" >> /etc/hosts.d/vrrp-status
}

handle_backup() {
    # This host is now BACKUP (standby, not holding VIP)
    log_message "✓ DEMOTED TO BACKUP"
    log_message "  - VIP ${VIP} is on other host"
    log_message "  - Ready to take over if primary fails"
    
    # Optional: Notify monitoring
    # curl -X POST http://monitoring.prod.internal:9093/api/v1/alerts \
    #      -H 'Content-Type: application/json' \
    #      -d "{\"status\":\"info\",\"message\":\"VRRP BACKUP on ${HOSTNAME}\"}"
}

handle_fault() {
    # This host has a fault (unhealthy, lost VIP)
    log_message "✗ FAULT DETECTED"
    log_message "  - Health check failed, VIP lost"
    log_message "  - Primary services may be down, check logs"
    
    # Alert monitoring
    # curl -X POST http://monitoring.prod.internal:9093/api/v1/alerts \
    #      -H 'Content-Type: application/json' \
    #      -d "{\"status\":\"error\",\"severity\":\"critical\",\"message\":\"VRRP FAULT on ${HOSTNAME}, VIP lost\"}"
    
    # Log system state for debugging
    log_message "System state at fault:"
    log_message "  - IP addresses: $(hostname -I)"
    log_message "  - Network interfaces: $(ip link show | grep -E 'eth|bond')"
    log_message "  - Health check status: Check /var/log/vrrp-health-monitor.log"
}

handle_stop() {
    # Keepalived is shutting down
    log_message "⊘ KEEPALIVED STOPPED"
    log_message "  - VRRP instance stopped"
    log_message "  - VIP will be released (if this host held it)"
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    case "$STATE" in
        MASTER)
            handle_master
            ;;
        BACKUP)
            handle_backup
            ;;
        FAULT)
            handle_fault
            ;;
        STOP)
            handle_stop
            ;;
        *)
            log_message "⚠ Unknown state: $STATE"
            exit 1
            ;;
    esac
}

# Ensure we're running as root (required for VIP manipulation)
if [[ $EUID -ne 0 ]]; then
    log_message "ERROR: This script must be run as root"
    exit 1
fi

main "$@"
