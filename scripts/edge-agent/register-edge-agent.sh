#!/bin/bash
###############################################################################
# @file        scripts/edge-agent/register-edge-agent.sh
# @module      edge-agent/register-edge-agent
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
#
# @file scripts/edge-agent/register-edge-agent.sh
# @description Register edge agent with control plane and establish heartbeat
# @governance GOV-002: IaC, immutable, idempotent, deterministic
# @author GitHub Copilot
# @created 2026-04-24
#
# Usage:
#   bash scripts/edge-agent/register-edge-agent.sh \
#     --agent-id=worker-01 \
#     --location=us-west \
#     --capacity=8 \
#     --control-plane=http://localhost:8080
#
# Behavior:
#   1. Idempotent: Checks if agent already registered (updates if exists)
#   2. Deterministic: Uses agent-id as unique identifier
#   3. Immutable: All config externalized to environment variables
#   4. Audit: All registration events logged to stdout + log file
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Agent registration failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Registration cleanup..."; true' EXIT

readonly SCRIPT_VERSION="1.0"
readonly LOG_DIR="artifacts/edge-agent-logs"
readonly TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
readonly LOG_FILE="${LOG_DIR}/registration-${TIMESTAMP}.log"

# Configuration with defaults
AGENT_ID="${AGENT_ID:-}"
LOCATION="${EDGE_LOCATION:-us-west}"
CAPACITY="${EDGE_CAPACITY:-4}"
CONTROL_PLANE="${CONTROL_PLANE:-http://localhost:8080}"
HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-30}"  # seconds
HEARTBEAT_TIMEOUT="${HEARTBEAT_TIMEOUT:-10}"   # seconds
MAX_REGISTRATION_RETRIES="${MAX_REGISTRATION_RETRIES:-3}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --agent-id=*) AGENT_ID="${1#*=}" ;;
        --location=*) LOCATION="${1#*=}" ;;
        --capacity=*) CAPACITY="${1#*=}" ;;
        --control-plane=*) CONTROL_PLANE="${1#*=}" ;;
        --heartbeat-interval=*) HEARTBEAT_INTERVAL="${1#*=}" ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

mkdir -p "$LOG_DIR"

log_info() {
    local msg="[$(date -u +'%Y-%m-%d %H:%M:%S UTC')] INFO: $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

log_error() {
    local msg="[$(date -u +'%Y-%m-%d %H:%M:%S UTC')] ERROR: $*"
    echo "$msg" | tee -a "$LOG_FILE" >&2
}

log_success() {
    local msg="[$(date -u +'%Y-%m-%d %H:%M:%S UTC')] SUCCESS: $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

# Validation
validate_config() {
    log_info "Validating edge agent configuration..."
    
    if [ -z "$AGENT_ID" ]; then
        log_error "AGENT_ID is required (use --agent-id=<value> or AGENT_ID env var)"
        exit 1
    fi
    
    if [ -z "$CONTROL_PLANE" ]; then
        log_error "CONTROL_PLANE is required"
        exit 1
    fi
    
    log_success "Configuration valid"
}

# Check if agent already registered
is_agent_registered() {
    local agent_id=$1
    local control_plane=$2
    
    local response=$(curl -fsS \
        -X GET \
        "${control_plane}/api/v1/edge-agents/${agent_id}" \
        -H "Content-Type: application/json" \
        2>/dev/null || echo "")
    
    if [ -n "$response" ]; then
        return 0  # Agent exists
    else
        return 1  # Agent not found
    fi
}

# Register edge agent (idempotent)
register_agent() {
    local agent_id=$1
    local control_plane=$2
    local location=$3
    local capacity=$4
    
    log_info "Registering edge agent: $agent_id (location: $location, capacity: $capacity)"
    
    # Check if already registered
    if is_agent_registered "$agent_id" "$control_plane"; then
        log_info "Agent $agent_id already registered, updating existing registration..."
        
        # Update existing agent
        local response=$(curl -fsS \
            -X PATCH \
            "${control_plane}/api/v1/edge-agents/${agent_id}" \
            -H "Content-Type: application/json" \
            -d '{
                "location": "'$location'",
                "capacity": '$capacity',
                "status": "active",
                "registered_at": "'$(date -u +'%Y-%m-%dT%H:%M:%SZ')'",
                "last_heartbeat": "'$(date -u +'%Y-%m-%dT%H:%M:%SZ')'"
            }' \
            2>/dev/null || echo "{\"error\": \"update failed\"}")
        
        if echo "$response" | grep -q "error"; then
            log_error "Failed to update agent registration: $response"
            return 1
        fi
    else
        log_info "Registering new agent: $agent_id"
        
        # Register new agent
        local response=$(curl -fsS \
            -X POST \
            "${control_plane}/api/v1/edge-agents" \
            -H "Content-Type: application/json" \
            -d '{
                "agent_id": "'$agent_id'",
                "location": "'$location'",
                "capacity": '$capacity',
                "status": "active",
                "registered_at": "'$(date -u +'%Y-%m-%dT%H:%M:%SZ')'",
                "last_heartbeat": "'$(date -u +'%Y-%m-%dT%H:%M:%SZ')'"
            }' \
            2>/dev/null || echo "{\"error\": \"registration failed\"}")
        
        if echo "$response" | grep -q "error"; then
            log_error "Failed to register agent: $response"
            return 1
        fi
    fi
    
    log_success "Agent $agent_id registered/updated successfully"
    return 0
}

# Heartbeat daemon (runs in background)
start_heartbeat_daemon() {
    local agent_id=$1
    local control_plane=$2
    local interval=$3
    
    log_info "Starting heartbeat daemon (interval: ${interval}s)"
    
    # Store PID for tracking
    local pid_file="${LOG_DIR}/.heartbeat-${agent_id}.pid"
    
    # Daemonize heartbeat process
    (
        while true; do
            local timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
            
            # Send heartbeat
            local response=$(curl -fsS \
                -X POST \
                "${control_plane}/api/v1/edge-agents/${agent_id}/heartbeat" \
                -H "Content-Type: application/json" \
                -d '{
                    "timestamp": "'$timestamp'",
                    "status": "healthy"
                }' \
                --max-time "$HEARTBEAT_TIMEOUT" \
                2>/dev/null || echo "{\"error\": \"heartbeat failed\"}")
            
            if echo "$response" | grep -q "error"; then
                log_error "Heartbeat failed: $response"
            fi
            
            sleep "$interval"
        done
    ) > "${LOG_DIR}/heartbeat-${agent_id}.log" 2>&1 &
    
    echo $! > "$pid_file"
    log_success "Heartbeat daemon started (PID: $!)"
}

# Stop heartbeat daemon
stop_heartbeat_daemon() {
    local agent_id=$1
    local pid_file="${LOG_DIR}/.heartbeat-${agent_id}.pid"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill "$pid" 2>/dev/null; then
            log_success "Heartbeat daemon stopped (PID: $pid)"
            rm -f "$pid_file"
        else
            log_error "Failed to stop heartbeat daemon (PID: $pid)"
        fi
    fi
}

# Generate agent registration token (for secure authentication)
generate_registration_token() {
    local agent_id=$1
    if [[ -z "${AGENT_SECRET:-}" ]]; then
        log_error "AGENT_SECRET must be set"
        return 1
    fi

    local secret=$AGENT_SECRET
    
    # Simple token: base64(agent_id:timestamp:hmac)
    local timestamp=$(date -u +%s)
    local message="${agent_id}:${timestamp}"
    local hmac=$(echo -n "$message" | openssl dgst -sha256 -hmac "$secret" -hex | awk '{print $2}')
    
    local token=$(echo -n "${message}:${hmac}" | base64 -w0)
    echo "$token"
}

# Main execution
main() {
    log_info "=== Edge Agent Registration Started ==="
    log_info "Version: $SCRIPT_VERSION"
    log_info "Agent ID: $AGENT_ID"
    log_info "Control Plane: $CONTROL_PLANE"
    log_info "Log file: $LOG_FILE"
    
    validate_config
    
    # Register agent (with retry logic)
    local retry_count=0
    while [ $retry_count -lt $MAX_REGISTRATION_RETRIES ]; do
        if register_agent "$AGENT_ID" "$CONTROL_PLANE" "$LOCATION" "$CAPACITY"; then
            break
        else
            retry_count+=1
            if [ $retry_count -lt $MAX_REGISTRATION_RETRIES ]; then
                log_info "Retry $retry_count/$MAX_REGISTRATION_RETRIES..."
                sleep $((2 ** retry_count))  # Exponential backoff
            fi
        fi
    done
    
    if [ $retry_count -eq $MAX_REGISTRATION_RETRIES ]; then
        log_error "Failed to register agent after $MAX_REGISTRATION_RETRIES retries"
        exit 1
    fi
    
    # Generate and store registration token
    local token=$(generate_registration_token "$AGENT_ID")
    local token_file="${LOG_DIR}/.token-${AGENT_ID}"
    echo "$token" > "$token_file"
    chmod 600 "$token_file"
    log_info "Registration token stored: $token_file"
    
    # Start heartbeat daemon
    start_heartbeat_daemon "$AGENT_ID" "$CONTROL_PLANE" "$HEARTBEAT_INTERVAL"
    
    log_success "=== Edge Agent Registration Complete ==="
}

main "$@"
