#!/bin/bash
# @file        scripts/docker-health-monitor.sh
# @module      operations
# @description docker health monitor — on-prem code-server
# @owner       platform
# @status      active
# Docker Container Health Monitor
# Monitors all containers for crashes, restarts, and resource issues

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

CHECK_INTERVAL=30
RESTART_THRESHOLD=3
LOG_FILE="/tmp/docker-health-monitor.log"

# Note: using canonical log_* functions from _common/logging.sh (sourced via init.sh)

# Function to check if container is running
check_container_status() {
    local container=$1
    local status=$(docker inspect $container --format='{{.State.Running}}' 2>/dev/null || echo "false")
    
    if [ "$status" = "false" ]; then
        log_warn "Container [$container] is NOT running"
        
        # Check restart count
        local restart_count=$(docker inspect $container --format='{{.RestartCount}}' 2>/dev/null || echo "0")
        if [ "$restart_count" -gt "$RESTART_THRESHOLD" ]; then
            log_error "Container [$container] restarted $restart_count times - potential crash loop"
        fi
        
        return 1
    else
        log_info "Container [$container] is running"
        return 0
    fi
}

# Function to check container health status
check_container_health() {
    local container=$1
    local health=$(docker inspect $container --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")
    
    case $health in
        "healthy")
            log_info "Container [$container] health: HEALTHY"
            return 0
            ;;
        "unhealthy")
            log_error "Container [$container] health: UNHEALTHY - may crash soon"
            return 1
            ;;
        "starting")
            log_info "Container [$container] health: STARTING"
            return 0
            ;;
        *)
            log_debug "Container [$container] health: $health (no health check configured)"
            return 0
            ;;
    esac
}

# Function to check container resource usage
check_container_resources() {
    local container=$1
    
    if command -v docker &> /dev/null && docker stats --no-stream "$container" &>/dev/null 2>&1; then
        local stats=$(docker stats --no-stream $container --format "table {{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" 2>/dev/null || echo "N/A")
        log_debug "Container [$container] resources: $stats"
    fi
}

# Function to check logs for errors
check_container_logs() {
    local container=$1
    local error_count=$(docker logs $container 2>/dev/null | grep -iE "error|exception|fatal|crash" | wc -l || echo "0")
    
    if [ "$error_count" -gt 0 ]; then
        log "WARN" "Container [$container] has $error_count error entries in logs"
        log "INFO" "Recent errors:"
        docker logs $container --tail 3 2>/dev/null | grep -iE "error|exception|fatal" | head -3 | sed 's/^/  /'
        return 1
    else
        log "OK" "Container [$container] logs: no errors detected"
        return 0
    fi
}

# Main monitoring loop
main() {
    log "INFO" "Docker Health Monitor started"
    
    # Get list of containers
    local containers=$(docker ps -a --format "{{.Names}}" || echo "")
    
    if [ -z "$containers" ]; then
        log "WARN" "No Docker containers found"
        exit 1
    fi
    
    while true; do
        log "INFO" "--- Health Check Cycle ---"
        
        for container in $containers; do
            check_container_status "$container" || true
            check_container_health "$container" || true
            check_container_resources "$container" || true
            check_container_logs "$container" || true
            echo "" >> "$LOG_FILE"
        done
        
        log "INFO" "Health check complete. Sleeping ${CHECK_INTERVAL}s..."
        sleep "$CHECK_INTERVAL"
    done
}

# Handle SIGTERM
trap 'log "INFO" "Docker Health Monitor stopped"; exit 0' SIGTERM

main "$@"
