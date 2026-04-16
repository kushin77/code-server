#!/bin/bash
# @file        scripts/memory-monitor.sh
# @module      operations
# @description memory monitor — on-prem code-server
# @owner       platform
# @status      active
# Memory Monitor & Alert Script
# Monitors VS Code and Docker container memory usage
# Alerts when threshold exceeded, suggests remediation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

MEMORY_THRESHOLD_PCT=85
CHECK_INTERVAL=60
LOG_FILE="/tmp/memory-monitor.log"

alert() {
    local severity=$1
    local message=$2
    local timestamp=$(date -u "+%Y-%m-%d %H:%M:%S UTC")
    echo "[$timestamp] [$severity] $message" | tee -a "$LOG_FILE"
}

# Function to check VS Code memory
check_vscode_memory() {
    if command -v ps &> /dev/null; then
        local used_pct=$(ps aux | grep -i code | grep -v grep | awk '{sum+=$6} END {print int(sum/1024*100/$(nproc))}' 2>/dev/null || echo "0")
        
        if [ "$used_pct" -gt "$MEMORY_THRESHOLD_PCT" ]; then
            alert "WARN" "VS Code memory usage high: $used_pct% (threshold: $MEMORY_THRESHOLD_PCT%)"
            alert "INFO" "Recommendation: Disable extensions or increase system RAM"
            return 1
        else
            alert "OK" "VS Code memory usage normal: $used_pct%"
            return 0
        fi
    fi
}

# Function to check Docker container memory
check_docker_memory() {
    if command -v docker &> /dev/null; then
        local containers=$(docker ps --format "{{.Names}}")
        
        for container in $containers; do
            local mem_usage=$(docker stats --no-stream $container 2>/dev/null | tail -1 | awk '{print $4}' | tr -d '%')
            
            if [ "$mem_usage" -gt "$MEMORY_THRESHOLD_PCT" ]; then
                alert "WARN" "Docker container [$container] memory high: $mem_usage%"
                alert "INFO" "Consider: docker update --memory=4g $container"
                return 1
            else
                alert "OK" "Docker container [$container] memory: $mem_usage%"
            fi
        done
        return 0
    fi
}

# Function to check for zombie processes
check_zombie_processes() {
    local zombie_count=$(ps aux | awk '$8 ~ /Z/ {count++} END {print count+0}')
    
    if [ "$zombie_count" -gt 0 ]; then
        alert "WARN" "Found $zombie_count zombie processes - may indicate crashes"
        alert "INFO" "Recommendation: Restart the service or investigate parent process"
        return 1
    else
        alert "OK" "No zombie processes detected"
        return 0
    fi
}

# Main loop
main() {
    alert "INFO" "Memory Monitor started (threshold: $MEMORY_THRESHOLD_PCT%, interval: ${CHECK_INTERVAL}s)"
    
    while true; do
        check_vscode_memory || true
        check_docker_memory || true
        check_zombie_processes || true
        
        echo "---" >> "$LOG_FILE"
        sleep "$CHECK_INTERVAL"
    done
}

# Handle SIGTERM for graceful shutdown
trap 'alert "INFO" "Memory Monitor stopped"; exit 0' SIGTERM

main "$@"
