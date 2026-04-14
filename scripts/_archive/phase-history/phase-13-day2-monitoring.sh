#!/bin/bash
################################################################################
# Phase 13 Day 2: Real-Time Health Monitoring
# ─────────────────────────────────────────────────────────────────────────────
# Purpose: Monitor infrastructure health continuously during 24-hour load test
# Interval: Every 30 seconds
# Checks: Containers, memory, disk, network, resource utilization
#
# Idempotence: Infinite loop, safe to interrupt and resume
# Immutability: Append-only logs, no state modifications
# IaC: All thresholds configurable via environment variables
################################################################################

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration (Version Pinned)
# ─────────────────────────────────────────────────────────────────────────────

MONITORING_INTERVAL=${MONITORING_INTERVAL:-30}           # seconds
MEMORY_THRESHOLD=${MEMORY_THRESHOLD:-80}                 # percentage
DISK_THRESHOLD=${DISK_THRESHOLD:-80}                     # percentage
CPU_WARNING_THRESHOLD=${CPU_WARNING_THRESHOLD:-75}       # percentage

DOCKER_NETWORK="phase13-net"
CODE_SERVER_CONTAINER="code-server-31"

# Logging
TIMESTAMP=$(date +%s)
LOG_DIR="/tmp/phase-13-day2"
MONITORING_LOG="${LOG_DIR}/monitoring-${TIMESTAMP}.txt"

# ─────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

log_monitor() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $@" | tee -a "$MONITORING_LOG"
}

log_alert() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] ⚠️  ALERT: $@" | tee -a "$MONITORING_LOG"
}

log_critical() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] 🚨 CRITICAL: $@" | tee -a "$MONITORING_LOG"
}

# ─────────────────────────────────────────────────────────────────────────────
# Health Check Functions
# ─────────────────────────────────────────────────────────────────────────────

check_docker_daemon() {
    if docker info > /dev/null 2>&1; then
        log_monitor "✓ Docker daemon operational"
        return 0
    else
        log_critical "Docker daemon not responding"
        return 1
    fi
}

check_containers() {
    log_monitor "Container Status Check:"

    # Get list of all containers
    local containers=$(docker ps -a --format '{{.Names}}\t{{.Status}}')
    echo "$containers" | while read name status; do
        if [[ "$status" == *"Exited"* ]] || [[ "$status" == *"Dead"* ]]; then
            log_alert "  Container $name: $status"
        else
            log_monitor "  ✓ $name: $status"
        fi
    done

    # Check for specific required containers (Phase 13: code-server infrastructure)
    local required_containers=("code-server-31" "caddy-31" "ssh-proxy-31")
    for container in "${required_containers[@]}"; do
        if docker ps --filter "name=$container" --format '{{.Names}}' | grep -q "$container"; then
            log_monitor "  ✓ $container: exists"
        else
            log_alert "  Missing container: $container"
        fi
    done
}

check_memory() {
    local mem_info=$(free -m | awk 'NR==2 {printf "%d\t%d\t%.1f", $2, $3, ($3/$2)*100}')

    IFS=$'\t' read total used percent <<< "$mem_info"

    if (( $(echo "$percent > $MEMORY_THRESHOLD" | bc -l) )); then
        log_alert "Memory usage: ${percent}% ($used MB / $total MB) — exceeds threshold"
        return 1
    else
        log_monitor "✓ Memory usage: ${percent}% ($used MB / $total MB)"
        return 0
    fi
}

check_disk() {
    while IFS= read -r line; do
        if [ -z "$line" ]; then continue; fi

        local usage=$(echo "$line" | awk '{print $5}' | sed 's/%//')
        local mount=$(echo "$line" | awk '{print $6}')

        if (( usage > DISK_THRESHOLD )); then
            log_alert "Disk usage on $mount: ${usage}% — exceeds threshold"
            return 1
        else
            log_monitor "  ✓ $mount: ${usage}% available"
        fi
    done < <(df -h | tail -n +2)

    return 0
}

check_code_server_health() {
    # Test code-server endpoint via Caddy reverse proxy (port 80)
    local status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>&1)

    if [ "$status" = "200" ]; then
        log_monitor "✓ code-server health: HTTP $status (responding via Caddy reverse proxy)"
        return 0
    else
        log_alert "code-server health: HTTP $status (expected 200)"
        return 1
    fi
}

check_network_connectivity() {
    if docker network inspect "$DOCKER_NETWORK" > /dev/null 2>&1; then
        local connected=$(docker network inspect "$DOCKER_NETWORK" --format '{{len .Containers}}')
        log_monitor "✓ Docker network '$DOCKER_NETWORK': $connected containers connected"
        return 0
    else
        log_critical "Docker network '$DOCKER_NETWORK' not found"
        return 1
    fi
}

check_resource_limits() {
    # Check if any container is hitting resource limits
    local container_stats=$(docker stats --no-stream --format '{{.Container}}\t{{.CPUPerc}}\t{{.MemPerc}}' 2>/dev/null || true)

    echo "$container_stats" | while read container cpu mem; do
        local cpu_pct=$(echo "$cpu" | sed 's/%//')
        local mem_pct=$(echo "$mem" | sed 's/%//')

        if (( $(echo "$cpu_pct > $CPU_WARNING_THRESHOLD" | bc -l) )); then
            log_alert "  $container CPU: ${cpu_pct}%"
        fi

        if (( $(echo "$mem_pct > $MEMORY_THRESHOLD" | bc -l) )); then
            log_alert "  $container Memory: ${mem_pct}%"
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Monitoring Loop
# ─────────────────────────────────────────────────────────────────────────────

main() {
    mkdir -p "$LOG_DIR"

    log_monitor "═══════════════════════════════════════════════════════════════════════════"
    log_monitor "PHASE 13 DAY 2: REAL-TIME HEALTH MONITORING"
    log_monitor "═══════════════════════════════════════════════════════════════════════════"
    log_monitor ""
    log_monitor "Configuration:"
    log_monitor "  Monitoring Interval:     ${MONITORING_INTERVAL}s"
    log_monitor "  Memory Threshold:        ${MEMORY_THRESHOLD}%"
    log_monitor "  Disk Threshold:          ${DISK_THRESHOLD}%"
    log_monitor "  CPU Warning Threshold:   ${CPU_WARNING_THRESHOLD}%"
    log_monitor ""
    log_monitor "Log File: $MONITORING_LOG"
    log_monitor ""
    log_monitor "Starting continuous health monitoring..."
    log_monitor ""

    local iteration=0

    while true; do
        iteration=$((iteration + 1))

        log_monitor "───────────────────────────────────────────────────────────────────────────"
        log_monitor "Health Check #$iteration - $(date '+%H:%M:%S')"
        log_monitor "───────────────────────────────────────────────────────────────────────────"

        # Execute all health checks
        check_docker_daemon || true
        check_containers || true
        check_memory || true
        check_disk || true
        check_code_server_health || true
        check_network_connectivity || true
        check_resource_limits || true

        log_monitor ""

        # Wait for next check
        sleep "$MONITORING_INTERVAL"
    done
}

# Execute
main "$@"
