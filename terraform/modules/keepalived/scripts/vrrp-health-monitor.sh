#!/bin/bash
#
# VRRP Health Check Script — Keepalived uses this to determine host health
#
# This script is executed periodically by Keepalived to monitor the health
# of critical services. If health checks fail, Keepalived will demote this
# host's priority or trigger failover (VIP moves to replica).
#
# Exit codes:
#   0 = Healthy (pass check)
#   1 = Unhealthy (fail check, trigger failover)
#   2 = Script error (don't change priority)

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Services to monitor (host:port)
HEALTH_CHECKS=(
    "localhost:9090"  # Prometheus
    "localhost:5432"  # PostgreSQL
    "localhost:8080"  # Code-server
)

MAX_RETRIES=2
TIMEOUT_SECONDS=2
LOG_FILE="/var/log/keepalived/health-check.log"

# ==============================================================================
# FUNCTIONS
# ==============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>&1
}

check_port() {
    local host="$1"
    local port="$2"
    
    # Try to connect to the port
    if timeout "$TIMEOUT_SECONDS" bash -c "</dev/tcp/${host}/${port}" >/dev/null 2>&1; then
        return 0  # Success
    else
        return 1  # Failure
    fi
}

check_all_services() {
    local failures=0
    
    for check in "${HEALTH_CHECKS[@]}"; do
        local host="${check%%:*}"
        local port="${check##*:}"
        
        if ! check_port "$host" "$port"; then
            failures=$((failures + 1))
            log "✗ FAILED: $check"
        else
            log "✓ OK: $check"
        fi
    done
    
    return "$failures"
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Health check started"

# Run health checks
if check_all_services; then
    log "✓ All health checks PASSED"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0  # Healthy
else
    failures=$?
    if [[ $failures -ge $MAX_RETRIES ]]; then
        log "✗ Health checks FAILED ($failures/$((${#HEALTH_CHECKS[@]})) services down)"
        log "→ Failover will be triggered"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 1  # Unhealthy, trigger failover
    else
        log "⚠ Some checks failed ($failures/$((${#HEALTH_CHECKS[@]})))"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 0  # Don't fail yet, wait for next check
    fi
fi
