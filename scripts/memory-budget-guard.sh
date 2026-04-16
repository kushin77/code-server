#!/bin/bash
# P2 #448: Memory Budget Guard for code-server
# Monitor code-server RSS memory and trigger alerts/actions at thresholds
# 
# Thresholds:
# - 80%: Warning (notify via Prometheus)
# - 90%: Critical (attempt optimization)
# - 95%: Emergency (notify ops, prepare for restart)
# 100%: OOM Killer (restart service)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/logger.sh" 2>/dev/null || {
    log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
}

# Configuration
CONTAINER_NAME="${1:-code-server}"
MEMORY_LIMIT_MB="${2:-4096}"  # 4GB default limit
WARNING_THRESHOLD="${3:-3276}"  # 80% of 4GB
CRITICAL_THRESHOLD="${4:-3686}"  # 90% of 4GB
EMERGENCY_THRESHOLD="${5:-3891}"  # 95% of 4GB

METRICS_FILE="/tmp/code-server-memory-budget.prom"
ALERT_COOLDOWN=300  # seconds (5 min between alerts)
LAST_ALERT_FILE="/tmp/code-server-memory-alert-$(date +%H)"

# Prometheus metrics initialization
setup_metrics() {
    cat > "$METRICS_FILE" << 'EOF'
# HELP code_server_memory_bytes_rss Resident set size in bytes
# TYPE code_server_memory_bytes_rss gauge
# HELP code_server_memory_threshold_status Memory threshold status (0=ok, 1=warning, 2=critical, 3=emergency)
# TYPE code_server_memory_threshold_status gauge
# HELP code_server_memory_oomkiller_restarts OOM killer restarts count
# TYPE code_server_memory_oomkiller_restarts counter
EOF
}

# Get actual RSS memory for container
get_container_memory() {
    local container="$1"
    
    if docker inspect "$container" &>/dev/null 2>&1; then
        # Docker container
        docker stats --no-stream "$container" --format "{{.MemUsage}}" 2>/dev/null | \
            awk '{print $1}' | sed 's/MiB//' | awk '{print int($1 * 1024 * 1024)}'
    else
        # Process (if running directly)
        pgrep -f "code-server" | head -1 | xargs -I {} cat /proc/{}/status 2>/dev/null | \
            grep "VmRSS" | awk '{print $2 * 1024}'  # Convert KB to bytes
    fi
}

# Update Prometheus metrics
update_metrics() {
    local rss_bytes="$1"
    local threshold_status="$2"
    
    cat >> "$METRICS_FILE" << EOF

code_server_memory_bytes_rss $rss_bytes
code_server_memory_threshold_status $threshold_status
code_server_memory_limit_bytes $((MEMORY_LIMIT_MB * 1024 * 1024))
code_server_memory_warning_threshold $((WARNING_THRESHOLD * 1024 * 1024))
code_server_memory_critical_threshold $((CRITICAL_THRESHOLD * 1024 * 1024))
code_server_memory_emergency_threshold $((EMERGENCY_THRESHOLD * 1024 * 1024))
EOF
}

# Check if alert cooldown has passed
should_alert() {
    local alert_key="$1"
    
    if [[ ! -f "$LAST_ALERT_FILE" ]]; then
        touch "$LAST_ALERT_FILE"
        return 0
    fi
    
    local last_time=$(stat -f %m "$LAST_ALERT_FILE" 2>/dev/null || stat -c %Y "$LAST_ALERT_FILE")
    local current_time=$(date +%s)
    local elapsed=$((current_time - last_time))
    
    if [[ $elapsed -gt $ALERT_COOLDOWN ]]; then
        touch "$LAST_ALERT_FILE"
        return 0
    fi
    return 1
}

# Send alert to Slack webhook (if configured)
send_slack_alert() {
    local level="$1"
    local message="$2"
    local rss_mb="$3"
    
    if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
        return 0
    fi
    
    local color="yellow"
    [[ "$level" == "CRITICAL" ]] && color="orange"
    [[ "$level" == "EMERGENCY" ]] && color="red"
    
    curl -s -X POST "$SLACK_WEBHOOK_URL" \
        -H 'Content-Type: application/json' \
        -d "{
            \"attachments\": [{
                \"color\": \"$color\",
                \"title\": \"Code-Server Memory $level\",
                \"text\": \"$message\",
                \"fields\": [{
                    \"title\": \"Memory Usage\",
                    \"value\": \"${rss_mb} MB / ${MEMORY_LIMIT_MB} MB\",
                    \"short\": true
                }, {
                    \"title\": \"Threshold\",
                    \"value\": \"$((CRITICAL_THRESHOLD / 1024))% full\",
                    \"short\": true
                }]
            }]
        }" 2>/dev/null || true
}

# Trigger optimization (stop unused extensions, disable features)
trigger_optimization() {
    local action="$1"
    
    log "🔧 Attempting memory optimization: $action"
    
    case "$action" in
        "disable-extensions")
            # Tell code-server to disable non-critical extensions
            curl -s -X POST "http://localhost:8080/api/vscode/extensions/disable" \
                -H "Content-Type: application/json" \
                -d '{"extensions": ["ms-python.python", "ms-vscode.cpptools"]}' 2>/dev/null || true
            ;;
        "gc-collect")
            # Force garbage collection (if GC API available)
            curl -s -X POST "http://localhost:8080/api/system/gc" 2>/dev/null || true
            ;;
        "flush-cache")
            # Clear internal caches
            docker exec "$CONTAINER_NAME" rm -rf /home/coder/.cache/* 2>/dev/null || true
            ;;
        *)
            log "⚠️  Unknown optimization action: $action"
            ;;
    esac
}

# Handle OOM scenario (graceful restart)
handle_oom() {
    log "🚨 EMERGENCY: OOM condition detected - preparing restart"
    
    send_slack_alert "EMERGENCY" "Code-server OOM imminent - restarting" "$1"
    
    # Graceful shutdown + restart
    docker restart "$CONTAINER_NAME" 2>/dev/null || {
        log "Failed to restart container, attempting process kill"
        pkill -f "code-server" || true
        sleep 2
        docker-compose up -d "$CONTAINER_NAME" || true
    }
    
    # Increment restart counter
    local restart_count=$(($(docker exec "$CONTAINER_NAME" \
        cat /tmp/oomkiller-restarts 2>/dev/null || echo "0") + 1))
    
    echo "$restart_count" | docker exec -i "$CONTAINER_NAME" \
        tee /tmp/oomkiller-restarts > /dev/null
}

# Main loop
main() {
    setup_metrics
    
    log "📊 Starting memory budget guard for $CONTAINER_NAME"
    log "   Memory limit: ${MEMORY_LIMIT_MB}MB"
    log "   Warning:     ${WARNING_THRESHOLD}MB (80%)"
    log "   Critical:    ${CRITICAL_THRESHOLD}MB (90%)"
    log "   Emergency:   ${EMERGENCY_THRESHOLD}MB (95%)"
    log ""
    
    while true; do
        local rss_bytes=$(get_container_memory "$CONTAINER_NAME")
        local rss_mb=$((rss_bytes / 1024 / 1024))
        local percentage=$((rss_mb * 100 / MEMORY_LIMIT_MB))
        
        # Determine threshold status
        local threshold_status=0  # OK
        local status_label="✓ OK"
        
        if [[ $rss_mb -ge $EMERGENCY_THRESHOLD ]]; then
            threshold_status=3
            status_label="🚨 EMERGENCY"
            if should_alert "emergency"; then
                send_slack_alert "EMERGENCY" "Memory at ${percentage}% of limit" "$rss_mb"
                handle_oom "$rss_mb"
            fi
        elif [[ $rss_mb -ge $CRITICAL_THRESHOLD ]]; then
            threshold_status=2
            status_label="⚠️  CRITICAL"
            if should_alert "critical"; then
                send_slack_alert "CRITICAL" "Memory at ${percentage}% of limit" "$rss_mb"
                trigger_optimization "disable-extensions"
            fi
        elif [[ $rss_mb -ge $WARNING_THRESHOLD ]]; then
            threshold_status=1
            status_label="⚠  WARNING"
            if should_alert "warning"; then
                send_slack_alert "WARNING" "Memory at ${percentage}% of limit" "$rss_mb"
                trigger_optimization "gc-collect"
            fi
        fi
        
        # Update Prometheus metrics
        update_metrics "$rss_bytes" "$threshold_status"
        
        # Log status
        log "$status_label: $rss_mb MB / ${MEMORY_LIMIT_MB} MB (${percentage}%)"
        
        # Sleep before next check (configurable via env)
        sleep "${MEMORY_CHECK_INTERVAL:-30}"
    done
}

# Run main function
main "$@"
