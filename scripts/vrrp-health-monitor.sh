#!/bin/bash
#
# VRRP Health Monitor — Check primary host and trigger failover if unhealthy
#
# This script runs on both primary and replica (via Keepalived health check).
# It monitors critical services and signals Keepalived to trigger failover
# if the primary becomes unhealthy.
#
# Used by Keepalived in: /etc/keepalived/keepalived.conf
#   vrrp_script check_services {
#       script "/usr/local/bin/vrrp-health-monitor.sh"
#       interval 5
#       weight -20
#       fall 2
#   }

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Source inventory variables if available
if [[ -f /etc/code-server/inventory.env ]]; then
    source /etc/code-server/inventory.env
else
    # Fallback to defaults if inventory not available
    PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
    REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
fi

# Health check settings
HEALTH_CHECK_TIMEOUT=2
HEALTH_CHECK_RETRIES=2
CHECK_INTERVAL=5

# Service endpoints to monitor
SERVICES=(
    "http://127.0.0.1:8080/health"      # code-server
    "tcp://127.0.0.1:5432"              # PostgreSQL
    "tcp://127.0.0.1:6379"              # Redis
)

# Logging
LOG_FILE="/var/log/vrrp-health-monitor.log"
mkdir -p "$(dirname "$LOG_FILE")"

# ==============================================================================
# FUNCTIONS
# ==============================================================================

log_message() {
    local level="$1"
    shift
    local message="$*"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

check_http_endpoint() {
    local url="$1"
    local timeout="${2:-$HEALTH_CHECK_TIMEOUT}"
    
    if curl -sf --connect-timeout "$timeout" "$url" > /dev/null 2>&1; then
        return 0  # Success
    else
        return 1  # Failed
    fi
}

check_tcp_port() {
    local host_port="$1"
    local timeout="${2:-$HEALTH_CHECK_TIMEOUT}"
    local host="${host_port%:*}"
    local port="${host_port##*:}"
    
    if timeout "$timeout" bash -c "echo '' > /dev/tcp/$host/$port" 2>/dev/null; then
        return 0  # Success
    else
        return 1  # Failed
    fi
}

check_service() {
    local service="$1"
    local attempt=0
    
    # Retry logic for transient failures
    while [[ $attempt -lt $HEALTH_CHECK_RETRIES ]]; do
        if [[ "$service" == http* ]]; then
            if check_http_endpoint "$service"; then
                return 0
            fi
        elif [[ "$service" == tcp://* ]]; then
            local tcp_endpoint="${service#tcp://}"
            if check_tcp_port "$tcp_endpoint"; then
                return 0
            fi
        fi
        
        ((attempt++))
        if [[ $attempt -lt $HEALTH_CHECK_RETRIES ]]; then
            sleep 1
        fi
    done
    
    return 1  # All retries failed
}

check_all_services() {
    local failed_services=()
    
    log_message "INFO" "Starting health checks (interval=$CHECK_INTERVAL, retries=$HEALTH_CHECK_RETRIES)"
    
    for service in "${SERVICES[@]}"; do
        if ! check_service "$service"; then
            failed_services+=("$service")
            log_message "WARN" "Health check FAILED: $service"
        else
            log_message "DEBUG" "Health check OK: $service"
        fi
    done
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        log_message "ERROR" "Health checks failed for: ${failed_services[*]}"
        return 1
    else
        log_message "INFO" "All health checks passed"
        return 0
    fi
}

check_replication_lag() {
    # Optional: Check PostgreSQL replication lag
    # If replica is too far behind, don't promote it to primary
    
    if ! command -v psql &> /dev/null; then
        log_message "DEBUG" "psql not available, skipping replication lag check"
        return 0
    fi
    
    # This is a placeholder; actual implementation would check WAL position
    log_message "DEBUG" "Replication lag check (placeholder)"
    return 0
}

check_network_connectivity() {
    # Ensure we can reach the other host (primary or replica)
    local peer_host
    
    # Determine if we're primary or replica
    local my_ip
    my_ip=$(hostname -I | awk '{print $1}')
    
    if [[ "$my_ip" == "$PRIMARY_HOST" ]]; then
        peer_host="$REPLICA_HOST"
    else
        peer_host="$PRIMARY_HOST"
    fi
    
    log_message "DEBUG" "Checking connectivity to peer: $peer_host"
    
    if ping -c 1 -W "$HEALTH_CHECK_TIMEOUT" "$peer_host" > /dev/null 2>&1; then
        log_message "DEBUG" "Network connectivity OK to $peer_host"
        return 0
    else
        log_message "WARN" "Cannot reach peer host: $peer_host"
        return 1
    fi
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    log_message "INFO" "=== VRRP Health Monitor Started ==="
    
    # Run all health checks
    local all_healthy=true
    
    # Check services
    if ! check_all_services; then
        all_healthy=false
    fi
    
    # Check replication lag (for replica)
    if ! check_replication_lag; then
        all_healthy=false
    fi
    
    # Check network (optional, but useful for split-brain detection)
    if ! check_network_connectivity; then
        all_healthy=false
    fi
    
    # Report result
    if [[ "$all_healthy" == true ]]; then
        log_message "INFO" "=== Health Check PASSED ==="
        exit 0  # Healthy — Keepalived will use this node
    else
        log_message "ERROR" "=== Health Check FAILED ==="
        exit 1  # Unhealthy — Keepalived will demote this node
    fi
}

# Run main
main "$@"
