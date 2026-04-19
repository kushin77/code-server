#!/bin/bash
# @file        scripts/memory-budget-guard.sh
# @module      operations
# @description memory budget guard — on-prem code-server
# @owner       platform
# @status      active
#
# Memory Budget Guard Script - P2 #448 Implementation
# Monitors and controls memory usage across services
# Purpose: Prevent OOM events, maintain system stability
#
# Usage: ./scripts/memory-budget-guard.sh [--threshold 80] [--action warn|throttle|kill]
#
# Environment variables:
#   MEMORY_THRESHOLD    - Alert when usage exceeds % (default: 80)
#   MEMORY_ACTION       - Action to take: warn, throttle, kill (default: warn)
#   LOG_FILE            - Where to log alerts (default: /var/log/memory-budget.log)
#

set -euo pipefail

# Configuration
MEMORY_THRESHOLD="${MEMORY_THRESHOLD:-80}"
MEMORY_ACTION="${MEMORY_ACTION:-warn}"
LOG_FILE="${LOG_FILE:-/var/log/memory-budget.log}"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
HISTORY_SIZE="${HISTORY_SIZE:-100}"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# State tracking
declare -a PROCESS_HISTORY=()
ALERT_COUNT=0
THROTTLE_COUNT=0

# ============================================================================
# Utility Functions
# ============================================================================

log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    case "$level" in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message" >&2
            ;;
        INFO)
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
    esac
}

get_total_memory() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        free | grep Mem | awk '{print $2}'
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        vm_stat | grep "Pages free" | awk '{print $3}' | tr -d '.'
    fi
}

get_used_memory() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        free | grep Mem | awk '{print $3}'
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        vm_stat | grep -E "Pages wired|Pages active" | awk '{sum+=$3} END {print sum}'
    fi
}

get_memory_percentage() {
    local total=$(get_total_memory)
    local used=$(get_used_memory)
    
    if [[ -z "$total" || "$total" -eq 0 ]]; then
        echo "0"
    else
        echo $((used * 100 / total))
    fi
}

get_process_memory() {
    local pid="$1"
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [[ -f "/proc/$pid/status" ]]; then
            grep VmRSS /proc/$pid/status | awk '{print $2}'
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        ps -o rss= -p "$pid" 2>/dev/null || echo "0"
    fi
}

get_process_name() {
    local pid="$1"
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        comm -n "$pid" 2>/dev/null || echo "unknown"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        ps -o comm= -p "$pid" 2>/dev/null || echo "unknown"
    fi
}

# ============================================================================
# Docker Container Monitoring
# ============================================================================

check_docker_memory() {
    if ! command -v docker &> /dev/null; then
        return
    fi
    
    log "INFO" "Checking Docker container memory..."
    
    # Get all running containers
    while read -r container_id; do
        local container_name=$(docker ps --filter "id=$container_id" --format "{{.Names}}")
        local memory_usage=$(docker stats --no-stream --format "{{.MemUsage}}" "$container_id" 2>/dev/null || echo "0B")
        local memory_limit=$(docker stats --no-stream --format "{{.MemLimit}}" "$container_id" 2>/dev/null || echo "0B")
        
        log "INFO" "Container: $container_name | Usage: $memory_usage | Limit: $memory_limit"
        
    done < <(docker ps -q 2>/dev/null || true)
}

# ============================================================================
# Process Monitoring and Management
# ============================================================================

get_top_processes() {
    local count="${1:-10}"
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        ps aux --sort=-%mem | head -n $((count + 1)) | tail -n "$count"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        ps aux -m | sort -rn -k3 | head -n "$count"
    fi
}

alert_high_memory() {
    local pid="$1"
    local process_name="$2"
    local memory_mb="$3"
    
    ALERT_COUNT=$((ALERT_COUNT + 1))
    
    case "$MEMORY_ACTION" in
        warn)
            log "WARN" "High memory: PID $pid ($process_name) using ${memory_mb}MB"
            ;;
        throttle)
            log "WARN" "Throttling PID $pid ($process_name) using ${memory_mb}MB"
            throttle_process "$pid"
            ;;
        kill)
            log "ERROR" "Killing PID $pid ($process_name) using ${memory_mb}MB - memory threshold exceeded"
            kill_process "$pid"
            ;;
    esac
}

throttle_process() {
    local pid="$1"
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Use cgroups v2 to limit CPU
        if [[ -d "/sys/fs/cgroup/system.slice" ]]; then
            cgset -r cpu.max="50000 100000" "/proc/$pid" 2>/dev/null || true
            THROTTLE_COUNT=$((THROTTLE_COUNT + 1))
            log "INFO" "Throttled PID $pid to 50% CPU"
        fi
    fi
}

kill_process() {
    local pid="$1"
    
    # Only kill if it's not a critical system process
    local process_name=$(get_process_name "$pid")
    local critical_procs="init|systemd|docker|kubelet|node"
    
    if [[ "$process_name" =~ $critical_procs ]]; then
        log "WARN" "Refusing to kill critical process: $process_name (PID $pid)"
        return
    fi
    
    if kill -9 "$pid" 2>/dev/null; then
        log "ERROR" "Killed PID $pid ($process_name)"
    fi
}

# ============================================================================
# System Analysis
# ============================================================================

print_memory_status() {
    local percentage="$1"
    local total=$(get_total_memory)
    local used=$(get_used_memory)
    
    echo ""
    echo "╔════════════════════════════════════════════════════╗"
    echo "║          MEMORY BUDGET STATUS REPORT              ║"
    echo "╠════════════════════════════════════════════════════╣"
    
    if [[ "$percentage" -lt 50 ]]; then
        status="${GREEN}HEALTHY${NC}"
    elif [[ "$percentage" -lt 80 ]]; then
        status="${YELLOW}WARNING${NC}"
    else
        status="${RED}CRITICAL${NC}"
    fi
    
    printf "║ Status: %-45s ║\n" "$(echo -e $status)"
    printf "║ Total Memory: %-41s ║\n" "$((total / 1024))MB"
    printf "║ Used Memory: %-42s ║\n" "$((used / 1024))MB"
    printf "║ Usage: %-46s ║\n" "${percentage}%"
    printf "║ Threshold: %-44s ║\n" "${MEMORY_THRESHOLD}%"
    printf "║ Action on Breach: %-39s ║\n" "$MEMORY_ACTION"
    
    echo "╠════════════════════════════════════════════════════╣"
    echo "║ TOP MEMORY CONSUMING PROCESSES                    ║"
    echo "╠════════════════════════════════════════════════════╣"
    
    get_top_processes 5 | while read -r line; do
        printf "║ %-50s ║\n" "$line"
    done
    
    echo "╠════════════════════════════════════════════════════╣"
    printf "║ Alerts Triggered: %-36s ║\n" "$ALERT_COUNT"
    printf "║ Processes Throttled: %-35s ║\n" "$THROTTLE_COUNT"
    echo "╚════════════════════════════════════════════════════╝"
    echo ""
}

# ============================================================================
# Monitoring Loop
# ============================================================================

monitor_loop() {
    log "INFO" "Starting memory budget guard (threshold: ${MEMORY_THRESHOLD}%, action: $MEMORY_ACTION)"
    
    while true; do
        local memory_percentage=$(get_memory_percentage)
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        
        # Append to history
        PROCESS_HISTORY+=("$timestamp:$memory_percentage%")
        
        # Keep only last N entries
        if [[ ${#PROCESS_HISTORY[@]} -gt $HISTORY_SIZE ]]; then
            PROCESS_HISTORY=("${PROCESS_HISTORY[@]:(-$HISTORY_SIZE)}")
        fi
        
        # Check threshold
        if [[ "$memory_percentage" -gt "$MEMORY_THRESHOLD" ]]; then
            log "WARN" "Memory usage at ${memory_percentage}% (threshold: ${MEMORY_THRESHOLD}%)"
            
            # Check Docker containers
            check_docker_memory
            
            # Check processes
            get_top_processes 5 | tail -n +2 | while read -r line; do
                local pid=$(echo "$line" | awk '{print $2}')
                local mem_percent=$(echo "$line" | awk '{print $4}')
                local process_name=$(get_process_name "$pid")
                local memory_kb=$(get_process_memory "$pid")
                local memory_mb=$((memory_kb / 1024))
                
                # Alert if process is using >5% of memory
                if (( $(echo "$mem_percent > 5" | bc -l) )); then
                    alert_high_memory "$pid" "$process_name" "$memory_mb"
                fi
            done
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# ============================================================================
# Command Line Parsing
# ============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --threshold)
                MEMORY_THRESHOLD="$2"
                shift 2
                ;;
            --action)
                MEMORY_ACTION="$2"
                shift 2
                ;;
            --interval)
                CHECK_INTERVAL="$2"
                shift 2
                ;;
            --log)
                LOG_FILE="$2"
                shift 2
                ;;
            --status)
                print_memory_status "$(get_memory_percentage)"
                exit 0
                ;;
            --history)
                echo "Memory Usage History:"
                for entry in "${PROCESS_HISTORY[@]}"; do
                    echo "$entry"
                done
                exit 0
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << 'EOF'
Memory Budget Guard - Service Memory Monitoring and Control

USAGE:
    ./scripts/memory-budget-guard.sh [OPTIONS]

OPTIONS:
    --threshold PCT      Memory threshold percentage (default: 80)
    --action ACTION      Action to take: warn, throttle, kill (default: warn)
    --interval SEC       Check interval in seconds (default: 30)
    --log FILE           Log file path (default: /var/log/memory-budget.log)
    --status             Print current memory status and exit
    --history            Print memory history and exit
    --help               Show this help message

ENVIRONMENT VARIABLES:
    MEMORY_THRESHOLD    - Override --threshold
    MEMORY_ACTION       - Override --action
    CHECK_INTERVAL      - Override --interval
    LOG_FILE            - Override --log

EXAMPLES:
    # Monitor with default settings (80% threshold, warn only)
    ./scripts/memory-budget-guard.sh

    # Monitor with 70% threshold and throttle action
    ./scripts/memory-budget-guard.sh --threshold 70 --action throttle

    # Check current status
    ./scripts/memory-budget-guard.sh --status

    # Run as background service
    ./scripts/memory-budget-guard.sh --action warn &
    disown

ACTIONS:
    warn       - Log warnings only (default, safest)
    throttle   - Limit CPU to 50% for high-memory processes
    kill       - Terminate high-memory processes (use with caution!)

LOGS:
    All events logged to: $LOG_FILE
    Monitor with: tail -f $LOG_FILE

EOF
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Ensure valid action
    case "$MEMORY_ACTION" in
        warn|throttle|kill)
            ;;
        *)
            log "ERROR" "Invalid action: $MEMORY_ACTION (must be: warn, throttle, kill)"
            exit 1
            ;;
    esac
    
    # Print startup status
    log "INFO" "Configuration: Threshold=${MEMORY_THRESHOLD}%, Action=$MEMORY_ACTION, Interval=${CHECK_INTERVAL}s"
    print_memory_status "$(get_memory_percentage)"
    
    # Start monitoring
    monitor_loop
}

# Run main
main "$@"
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
source "$SCRIPT_DIR/_common/init.sh"

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
