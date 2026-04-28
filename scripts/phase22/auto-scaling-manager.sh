#!/bin/bash

################################################################################
# Phase 22: Auto-Scaling Manager
# Purpose: Automatic CPU/memory/queue-based scaling
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
CPU_SCALE_UP_THRESHOLD=70
CPU_SCALE_DOWN_THRESHOLD=30
MEMORY_SCALE_UP_THRESHOLD=75
MEMORY_SCALE_DOWN_THRESHOLD=40
MIN_REPLICAS=3
MAX_REPLICAS=50
SCALE_UP_COOLDOWN=120
SCALE_DOWN_COOLDOWN=300
SCALE_LOG="${REPO_ROOT}/logs/auto-scaling.log"
mkdir -p "$(dirname "${SCALE_LOG}")"

log_scaling() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${SCALE_LOG}"
}

################################################################################
# Section 1: Metric Collection
################################################################################

get_cpu_usage() {
    # Get average CPU usage from Prometheus
    if command -v curl &>/dev/null; then
        curl -s "http://localhost:9090/api/v1/query?query=avg(rate(container_cpu_usage_seconds_total[5m]))*100" \
            | jq '.data.result[0].value[1] | tonumber' 2>/dev/null || echo "50"
    else
        echo "50"
    fi
}

get_memory_usage() {
    # Get average memory usage from Prometheus
    if command -v curl &>/dev/null; then
        curl -s "http://localhost:9090/api/v1/query?query=avg(container_memory_usage_bytes/container_spec_memory_limit_bytes)*100" \
            | jq '.data.result[0].value[1] | tonumber' 2>/dev/null || echo "50"
    else
        echo "50"
    fi
}

get_queue_depth() {
    # Get message queue depth (RabbitMQ/Redis/etc)
    local queue_count=0
    
    if command -v redis-cli &>/dev/null; then
        queue_count=$(redis-cli LLEN "job-queue" 2>/dev/null || echo "0")
    fi
    
    echo "$queue_count"
}

get_current_replicas() {
    local service="${1:-api-server}"
    
    docker-compose ps "$service" 2>/dev/null | grep -c "$service" || echo "1"
}

################################################################################
# Section 2: Scaling Decisions
################################################################################

decide_scaling_action() {
    local cpu=$(get_cpu_usage)
    local memory=$(get_memory_usage)
    local queue=$(get_queue_depth)
    local current_replicas=$(get_current_replicas "api-server")
    
    log_scaling "📊 Metrics: CPU=$cpu%, Memory=$memory%, Queue=$queue, Replicas=$current_replicas"
    
    # Scale up conditions
    if (( $(echo "$cpu > $CPU_SCALE_UP_THRESHOLD" | bc -l) )) || \
       (( $(echo "$memory > $MEMORY_SCALE_UP_THRESHOLD" | bc -l) )) || \
       [ "$queue" -gt 1000 ]; then
        
        log_scaling "📈 SCALE UP decision: High resource usage"
        echo "scale-up"
        return 0
    fi
    
    # Scale down conditions
    if (( $(echo "$cpu < $CPU_SCALE_DOWN_THRESHOLD" | bc -l) )) && \
       (( $(echo "$memory < $MEMORY_SCALE_DOWN_THRESHOLD" | bc -l) )) && \
       [ "$queue" -lt 100 ]; then
        
        log_scaling "📉 SCALE DOWN decision: Low resource usage"
        echo "scale-down"
        return 0
    fi
    
    log_scaling "➡️  No scaling action needed"
    echo "no-action"
    return 0
}

################################################################################
# Section 3: Scale Up
################################################################################

scale_up() {
    local service="${1:-api-server}"
    local current=$(get_current_replicas "$service")
    local new_count=$((current + 1))
    
    if [ $new_count -gt $MAX_REPLICAS ]; then
        log_scaling "⚠️  Already at max replicas ($MAX_REPLICAS)"
        return 1
    fi
    
    log_scaling "📈 Scaling UP: $current → $new_count replicas"
    
    cd "${REPO_ROOT}" || exit 1
    docker-compose up -d --scale "$service=$new_count" 2>/dev/null || {
        log_scaling "❌ Scale up failed"
        return 1
    }
    
    log_scaling "✅ Scale up successful"
    
    # Send metrics
    send_scaling_metric "scale-up" "success" $new_count
    return 0
}

################################################################################
# Section 4: Scale Down
################################################################################

scale_down() {
    local service="${1:-api-server}"
    local current=$(get_current_replicas "$service")
    local new_count=$((current - 1))
    
    if [ $new_count -lt $MIN_REPLICAS ]; then
        log_scaling "⚠️  Already at min replicas ($MIN_REPLICAS)"
        return 1
    fi
    
    log_scaling "📉 Scaling DOWN: $current → $new_count replicas"
    
    cd "${REPO_ROOT}" || exit 1
    docker-compose up -d --scale "$service=$new_count" 2>/dev/null || {
        log_scaling "❌ Scale down failed"
        return 1
    }
    
    log_scaling "✅ Scale down successful"
    
    # Send metrics
    send_scaling_metric "scale-down" "success" $new_count
    return 0
}

################################################################################
# Section 5: Metrics & Alerting
################################################################################

send_scaling_metric() {
    local action="$1"
    local status="$2"
    local replica_count="$3"
    
    if command -v curl &>/dev/null; then
        curl -s -X POST "http://localhost:9091/metrics/job/auto-scaling" \
            --data-binary "scaling_actions_total{action=\"$action\",status=\"$status\"} 1
scaling_replicas{action=\"$action\"} $replica_count" \
            2>/dev/null || true
    fi
}

################################################################################
# Section 6: Cooldown Tracking
################################################################################

declare -g LAST_SCALE_UP_TIME=0
declare -g LAST_SCALE_DOWN_TIME=0

check_scale_up_cooldown() {
    local current_time=$(date +%s)
    local time_since=$((current_time - LAST_SCALE_UP_TIME))
    
    if [ $time_since -lt $SCALE_UP_COOLDOWN ]; then
        log_scaling "⏳ Scale-up cooldown active ($time_since/$SCALE_UP_COOLDOWN sec)"
        return 1
    fi
    return 0
}

check_scale_down_cooldown() {
    local current_time=$(date +%s)
    local time_since=$((current_time - LAST_SCALE_DOWN_TIME))
    
    if [ $time_since -lt $SCALE_DOWN_COOLDOWN ]; then
        log_scaling "⏳ Scale-down cooldown active ($time_since/$SCALE_DOWN_COOLDOWN sec)"
        return 1
    fi
    return 0
}

################################################################################
# Section 7: Continuous Scaling
################################################################################

continuous_scaling() {
    log_scaling "🚀 Starting continuous auto-scaling..."
    
    while true; do
        local action=$(decide_scaling_action)
        
        case "$action" in
            scale-up)
                if check_scale_up_cooldown; then
                    scale_up "api-server"
                    LAST_SCALE_UP_TIME=$(date +%s)
                fi
                ;;
            scale-down)
                if check_scale_down_cooldown; then
                    scale_down "api-server"
                    LAST_SCALE_DOWN_TIME=$(date +%s)
                fi
                ;;
            no-action)
                # Nothing
                ;;
        esac
        
        sleep 30  # Check every 30 seconds
    done
}

################################################################################
# Section 8: Manual Scaling
################################################################################

manual_scale() {
    local service="$1"
    local target_replicas="$2"
    
    if [ "$target_replicas" -lt $MIN_REPLICAS ] || [ "$target_replicas" -gt $MAX_REPLICAS ]; then
        log_scaling "❌ Invalid replica count: $target_replicas (min: $MIN_REPLICAS, max: $MAX_REPLICAS)"
        return 1
    fi
    
    log_scaling "🔧 Manual scaling: $service → $target_replicas replicas"
    
    cd "${REPO_ROOT}" || exit 1
    docker-compose up -d --scale "$service=$target_replicas" 2>/dev/null || {
        log_scaling "❌ Manual scaling failed"
        return 1
    }
    
    log_scaling "✅ Manual scaling successful"
    return 0
}

################################################################################
# Section 9: Main Execution
################################################################################

main() {
    local mode="${1:-continuous}"
    local service="${2:-api-server}"
    local target="${3:-}"
    
    case "$mode" in
        continuous)
            continuous_scaling
            ;;
        metrics)
            echo "CPU: $(get_cpu_usage)%"
            echo "Memory: $(get_memory_usage)%"
            echo "Queue: $(get_queue_depth) items"
            echo "Current replicas: $(get_current_replicas "$service")"
            ;;
        scale-to)
            if [ -z "$target" ]; then
                echo "Usage: $0 scale-to <service> <replica_count>"
                exit 1
            fi
            manual_scale "$service" "$target"
            ;;
        *)
            echo "Usage: $0 {continuous|metrics|scale-to} [service] [count]"
            exit 1
            ;;
    esac
}

main "$@"
