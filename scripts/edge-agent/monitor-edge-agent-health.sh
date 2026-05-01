#!/bin/bash
###############################################################################
# @file        scripts/edge-agent/monitor-edge-agent-health.sh
# @module      edge-agent/monitor-edge-agent-health
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Health monitoring failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Health monitoring cleanup..."; true' EXIT

###############################################################################
#
# @file scripts/edge-agent/monitor-edge-agent-health.sh
# @description Monitor edge agent heartbeats and manage agent lifecycle
# @governance GOV-002: IaC, immutable, idempotent
# @author GitHub Copilot
# @created 2026-04-24
#
# Usage:
#   bash scripts/edge-agent/monitor-edge-agent-health.sh \
#     --control-plane=http://localhost:8080 \
#     --heartbeat-timeout=30
#

set -euo pipefail

readonly SCRIPT_VERSION="1.0"
readonly LOG_DIR="artifacts/edge-agent-logs"
readonly TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
readonly LOG_FILE="${LOG_DIR}/health-monitor-${TIMESTAMP}.log"

# Configuration
CONTROL_PLANE="${CONTROL_PLANE:-http://localhost:8080}"
HEARTBEAT_TIMEOUT="${HEARTBEAT_TIMEOUT:-30}"  # seconds; agents assumed dead if no heartbeat
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-10}"  # seconds

mkdir -p "$LOG_DIR"

log_info() {
    echo "[$(date -u +'%Y-%m-%d %H:%M:%S UTC')] INFO: $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date -u +'%Y-%m-%d %H:%M:%S UTC')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo "[$(date -u +'%Y-%m-%d %H:%M:%S UTC')] SUCCESS: $*" | tee -a "$LOG_FILE"
}

# Fetch all registered edge agents
fetch_registered_agents() {
    local control_plane=$1
    
    curl -fsS \
        -X GET \
        "${control_plane}/api/v1/edge-agents" \
        -H "Content-Type: application/json" \
        2>/dev/null || echo "[]"
}

# Check agent health
check_agent_health() {
    local agent_id=$1
    local control_plane=$2
    local timeout=$3
    
    # Fetch agent status
    local agent_data=$(curl -fsS \
        -X GET \
        "${control_plane}/api/v1/edge-agents/${agent_id}/status" \
        -H "Content-Type: application/json" \
        2>/dev/null || echo "{}")
    
    if echo "$agent_data" | grep -q "error"; then
        return 1  # Unhealthy
    fi
    
    # Check last heartbeat time
    local last_heartbeat=$(echo "$agent_data" | grep -o '"last_heartbeat":"[^"]*' | cut -d'"' -f4)
    local current_time=$(date -u +%s)
    local heartbeat_time=$(date -d "$last_heartbeat" +%s 2>/dev/null || echo "0")
    local time_since_heartbeat=$((current_time - heartbeat_time))
    
    if [ "$time_since_heartbeat" -gt "$timeout" ]; then
        log_error "Agent $agent_id: heartbeat timeout ($time_since_heartbeat > $timeout)"
        return 1  # Unhealthy
    fi
    
    return 0  # Healthy
}

# Mark agent as unhealthy
mark_agent_unhealthy() {
    local agent_id=$1
    local control_plane=$2
    local reason=$3
    
    log_error "Marking agent $agent_id as unhealthy: $reason"
    
    curl -fsS \
        -X PATCH \
        "${control_plane}/api/v1/edge-agents/${agent_id}" \
        -H "Content-Type: application/json" \
        -d '{
            "status": "unhealthy",
            "failure_reason": "'$reason'",
            "failed_at": "'$(date -u +'%Y-%m-%dT%H:%M:%SZ')'"
        }' \
        2>/dev/null || true
}

# Health check loop
health_check_loop() {
    local control_plane=$1
    local interval=$2
    local timeout=$3
    
    log_info "Starting health check loop (interval: ${interval}s, timeout: ${timeout}s)"
    
    while true; do
        log_info "Running health checks..."
        
        local agents=$(fetch_registered_agents "$control_plane")
        local agent_count=$(echo "$agents" | grep -o '"agent_id"' | wc -l)
        
        log_info "Checking $agent_count edge agents"
        
        # Check each agent
        local unhealthy_count=0
        while IFS= read -r agent_id; do
            if [ -n "$agent_id" ]; then
                if check_agent_health "$agent_id" "$control_plane" "$timeout"; then
                    log_info "Agent $agent_id: HEALTHY"
                else
                    mark_agent_unhealthy "$agent_id" "$control_plane" "Heartbeat timeout"
                    unhealthy_count+=1
                fi
            fi
        done < <(echo "$agents" | grep -o '"agent_id":"[^"]*' | cut -d'"' -f4)
        
        if [ "$unhealthy_count" -gt 0 ]; then
            log_error "Found $unhealthy_count unhealthy agent(s)"
        fi
        
        sleep "$interval"
    done
}

# Main
main() {
    log_info "=== Edge Agent Health Monitor Started ==="
    log_info "Version: $SCRIPT_VERSION"
    log_info "Control Plane: $CONTROL_PLANE"
    log_info "Heartbeat Timeout: ${HEARTBEAT_TIMEOUT}s"
    
    health_check_loop "$CONTROL_PLANE" "$HEALTH_CHECK_INTERVAL" "$HEARTBEAT_TIMEOUT"
}

main "$@"
