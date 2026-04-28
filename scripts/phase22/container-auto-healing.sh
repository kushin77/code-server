#!/bin/bash

################################################################################
# Phase 22: Container Auto-Healing System
# Purpose: Automatically restart unhealthy containers
# Date: April 28, 2026
################################################################################

set -euo pipefail

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR%/scripts*}" && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh" || exit 1

# Configuration
HEALTH_CHECK_INTERVAL=10
MAX_RESTART_ATTEMPTS=5
RESTART_LOG="${REPO_ROOT}/logs/container-healing.log"
mkdir -p "$(dirname "${RESTART_LOG}")"

log_healing() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${RESTART_LOG}"
}

################################################################################
# Section 1: Health Check Monitoring
################################################################################

monitor_container_health() {
    log_healing "🔍 Monitoring container health..."
    
    local unhealthy_containers=()
    
    # Get all running containers
    local containers=$(docker ps --format '{{.ID}}\t{{.Names}}\t{{.Status}}' | grep -v "healthy" || true)
    
    while IFS=$'\t' read -r container_id container_name status; do
        [ -z "$container_id" ] && continue
        
        # Check container health status
        local health_status=$(docker inspect \
            --format='{{.State.Health.Status}}' \
            "$container_id" 2>/dev/null || echo "unknown")
        
        case "$health_status" in
            unhealthy)
                unhealthy_containers+=("$container_id:$container_name")
                log_healing "⚠️  Unhealthy: $container_name ($container_id)"
                ;;
            starting)
                # Wait for container to be healthy
                log_healing "⏳ Starting: $container_name"
                ;;
            healthy)
                log_healing "✅ Healthy: $container_name"
                ;;
            *)
                log_healing "❓ Unknown health status for $container_name: $health_status"
                ;;
        esac
    done <<< "$containers"
    
    # Return unhealthy containers
    printf '%s\n' "${unhealthy_containers[@]}" 2>/dev/null || true
}

################################################################################
# Section 2: Auto-Restart Logic
################################################################################

auto_restart_container() {
    local container_spec="$1"
    local container_id="${container_spec%:*}"
    local container_name="${container_spec#*:}"
    
    log_healing "🔄 Attempting to restart: $container_name ($container_id)"
    
    # Get restart count
    local restart_count=$(docker inspect \
        --format='{{json .RestartCount}}' \
        "$container_id" 2>/dev/null || echo "0")
    
    # Check if max attempts reached
    if [ "$restart_count" -ge "$MAX_RESTART_ATTEMPTS" ]; then
        log_healing "❌ Max restart attempts reached for $container_name (count: $restart_count/$MAX_RESTART_ATTEMPTS)"
        
        # Alert on max retries
        send_alert "CRITICAL" "Container $container_name failed after $MAX_RESTART_ATTEMPTS restarts"
        return 1
    fi
    
    # Get container logs for debugging
    local recent_logs=$(docker logs --tail 20 "$container_id" 2>&1 | tail -5)
    log_healing "📋 Recent logs: $recent_logs"
    
    # Stop container (cleanup)
    log_healing "Stopping container: $container_name"
    docker stop "$container_id" || true
    
    # Wait for graceful shutdown
    sleep 2
    
    # Remove container to force recreation
    log_healing "Removing container: $container_name"
    docker rm "$container_id" || true
    
    # Recreate and start container using docker-compose
    log_healing "Recreating container via docker-compose..."
    cd "${REPO_ROOT}" || exit 1
    
    # Find and recreate the service
    if docker-compose up -d "$container_name" 2>/dev/null; then
        log_healing "✅ Container restarted successfully: $container_name"
        
        # Wait for health check
        sleep 5
        
        # Verify health
        local new_health=$(docker inspect \
            --format='{{.State.Health.Status}}' \
            "$(docker ps -q -f name=$container_name)" 2>/dev/null || echo "unknown")
        
        if [ "$new_health" = "healthy" ]; then
            log_healing "✅ Container is healthy after restart"
            return 0
        else
            log_healing "⚠️  Container health status: $new_health (may still be starting)"
            return 0
        fi
    else
        log_healing "❌ Failed to recreate container: $container_name"
        return 1
    fi
}

################################################################################
# Section 3: Alert & Metrics
################################################################################

send_alert() {
    local severity="$1"
    local message="$2"
    
    # Send to Prometheus
    if command -v curl &>/dev/null; then
        curl -s -X POST "http://localhost:9091/metrics/job/container-healing" \
            --data-binary "container_healing_events{severity=\"$severity\"} 1" 2>/dev/null || true
    fi
    
    # Log to syslog
    logger -t container-healing -p "user.${severity,,}" "$message" 2>/dev/null || true
}

################################################################################
# Section 4: Continuous Monitoring
################################################################################

continuous_monitoring() {
    log_healing "🚀 Starting continuous container health monitoring..."
    
    while true; do
        # Check for unhealthy containers
        local unhealthy=$(monitor_container_health)
        
        if [ -n "$unhealthy" ]; then
            while IFS= read -r container_spec; do
                [ -z "$container_spec" ] && continue
                
                # Auto-restart
                if auto_restart_container "$container_spec"; then
                    send_alert "INFO" "Container healed: $container_spec"
                else
                    send_alert "WARN" "Container healing failed: $container_spec"
                fi
            done <<< "$unhealthy"
        fi
        
        # Wait before next check
        sleep "$HEALTH_CHECK_INTERVAL"
    done
}

################################################################################
# Section 5: Manual Container Healing
################################################################################

heal_container() {
    local container_name="$1"
    
    log_healing "🩹 Manual healing initiated for: $container_name"
    
    # Find container
    local container_id=$(docker ps -q -f name="$container_name" || echo "")
    
    if [ -z "$container_id" ]; then
        log_healing "❌ Container not found: $container_name"
        return 1
    fi
    
    auto_restart_container "$container_id:$container_name"
}

################################################################################
# Section 6: Main Execution
################################################################################

main() {
    local mode="${1:-continuous}"
    local container_name="${2:-}"
    
    case "$mode" in
        continuous)
            continuous_monitoring
            ;;
        heal)
            if [ -z "$container_name" ]; then
                log_healing "Usage: $0 heal <container_name>"
                exit 1
            fi
            heal_container "$container_name"
            ;;
        check)
            monitor_container_health
            ;;
        *)
            echo "Usage: $0 {continuous|heal|check} [container_name]"
            exit 1
            ;;
    esac
}

# Run main
main "$@"
