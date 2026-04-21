#!/usr/bin/env bash
# @file        scripts/monitor-hot-standby-health.sh
# @module      collaboration/hot-standby-failover
# @description Monitor hot-standby failover system health and performance
#
# Monitors issue #1321: Hot-standby failover with zero loss and < 1s failover

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"
source "$SCRIPT_DIR/_common/logging.sh"
source "$SCRIPT_DIR/_common/config.sh"

PRIMARY_ENDPOINT="${PRIMARY_ENDPOINT:-http://localhost:3001}"
STANDBY_ENDPOINT="${STANDBY_ENDPOINT:-http://localhost:3002}"
MONITOR_INTERVAL="${MONITOR_INTERVAL:-30}"

# Health check function
check_health() {
    local endpoint="$1"
    local name="$2"

    if curl -s --max-time 5 "${endpoint}/health" > /dev/null 2>&1; then
        echo "✓ ${name} is healthy"
        return 0
    else
        echo "✗ ${name} is unhealthy"
        return 1
    fi
}

# Get detailed health status
get_health_status() {
    local endpoint="$1"
    local name="$2"

    local response
    if ! response=$(curl -s --max-time 5 "${endpoint}/health" 2>/dev/null); then
        echo "${name}: UNHEALTHY - Cannot connect"
        return 1
    fi

    # Parse JSON response
    local role state sequence checksum lag
    role=$(echo "$response" | jq -r '.role' 2>/dev/null || echo "unknown")
    state=$(echo "$response" | jq -r '.state' 2>/dev/null || echo "unknown")
    sequence=$(echo "$response" | jq -r '.sequenceNumber' 2>/dev/null || echo "unknown")
    checksum=$(echo "$response" | jq -r '.checksum' 2>/dev/null || echo "unknown")
    lag=$(echo "$response" | jq -r '.lagMs' 2>/dev/null || echo "unknown")

    echo "${name}: Role=${role}, State=${state}, Seq=${sequence}, Checksum=${checksum}, Lag=${lag}ms"
}

# Check replication lag
check_replication_lag() {
    local primary_seq standby_seq

    primary_seq=$(curl -s "${PRIMARY_ENDPOINT}/health" | jq -r '.sequenceNumber' 2>/dev/null || echo "0")
    standby_seq=$(curl -s "${STANDBY_ENDPOINT}/health" | jq -r '.sequenceNumber' 2>/dev/null || echo "0")

    local lag=$((primary_seq - standby_seq))

    if [ "$lag" -gt 10 ]; then
        log_warn "High replication lag detected: ${lag} operations"
    elif [ "$lag" -gt 0 ]; then
        log_info "Replication lag: ${lag} operations"
    else
        log_info "Replication in sync"
    fi
}

# Check checksum consistency
check_checksum_consistency() {
    local primary_checksum standby_checksum

    primary_checksum=$(curl -s "${PRIMARY_ENDPOINT}/health" | jq -r '.checksum' 2>/dev/null || echo "")
    standby_checksum=$(curl -s "${STANDBY_ENDPOINT}/health" | jq -r '.checksum' 2>/dev/null || echo "")

    if [ "$primary_checksum" = "$standby_checksum" ] && [ -n "$primary_checksum" ]; then
        log_info "Checksum consistency: ✓ Match"
    else
        log_error "Checksum inconsistency detected!"
        log_error "Primary: ${primary_checksum}"
        log_error "Standby: ${standby_checksum}"
    fi
}

# Monitor loop
monitor_loop() {
    log_info "Starting hot-standby health monitoring..."
    log_info "Monitor interval: ${MONITOR_INTERVAL}s"
    log_info "Primary: ${PRIMARY_ENDPOINT}"
    log_info "Standby: ${STANDBY_ENDPOINT}"

    while true; do
        echo "=== Health Check $(date) ==="

        # Basic health checks
        local primary_healthy=0 standby_healthy=0

        if check_health "$PRIMARY_ENDPOINT" "Primary"; then
            primary_healthy=1
        fi

        if check_health "$STANDBY_ENDPOINT" "Standby"; then
            standby_healthy=1
        fi

        # Detailed status if healthy
        if [ $primary_healthy -eq 1 ]; then
            get_health_status "$PRIMARY_ENDPOINT" "Primary"
        fi

        if [ $standby_healthy -eq 1 ]; then
            get_health_status "$STANDBY_ENDPOINT" "Standby"
        fi

        # Replication checks
        if [ $primary_healthy -eq 1 ] && [ $standby_healthy -eq 1 ]; then
            check_replication_lag
            check_checksum_consistency
        fi

        # Alert on failures
        if [ $primary_healthy -eq 0 ] && [ $standby_healthy -eq 0 ]; then
            log_error "CRITICAL: Both replicas are unhealthy!"
        elif [ $primary_healthy -eq 0 ]; then
            log_warn "WARNING: Primary replica is unhealthy"
        elif [ $standby_healthy -eq 0 ]; then
            log_warn "WARNING: Standby replica is unhealthy"
        fi

        echo ""
        sleep "$MONITOR_INTERVAL"
    done
}

# Show usage
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Monitor hot-standby failover system health"
    echo ""
    echo "Options:"
    echo "  -i, --interval SECONDS    Monitor interval (default: 30)"
    echo "  -p, --primary URL         Primary endpoint (default: http://localhost:3001)"
    echo "  -s, --standby URL         Standby endpoint (default: http://localhost:3002)"
    echo "  -h, --help               Show this help"
    echo ""
    echo "Environment variables:"
    echo "  PRIMARY_ENDPOINT          Primary replica endpoint"
    echo "  STANDBY_ENDPOINT          Standby replica endpoint"
    echo "  MONITOR_INTERVAL          Monitor interval in seconds"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interval)
            MONITOR_INTERVAL="$2"
            shift 2
            ;;
        -p|--primary)
            PRIMARY_ENDPOINT="$2"
            shift 2
            ;;
        -s|--standby)
            STANDBY_ENDPOINT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is required for JSON parsing. Please install jq."
        exit 1
    fi

    monitor_loop
}

main "$@"