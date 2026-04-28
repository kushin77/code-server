#!/bin/bash
#
# @file shutdown-cluster.sh
# @description Shut down all Docker containers on both cluster hosts (PRIMARY and REPLICA)
# @author DevOps
# @date 2026-04-27
#

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# ============================================================================
# Configuration from environment variables
# ============================================================================

PRIMARY_HOST="${PRIMARY_HOST:?PRIMARY_HOST must be set (e.g., 192.168.1.10 or primary.example.com)}"
REPLICA_HOST="${REPLICA_HOST:?REPLICA_HOST must be set (e.g., 192.168.1.20 or replica.example.com)}"

# SSH options
SSH_USER="${SSH_USER:-root}"
SSH_KEY="${SSH_KEY:-}"
SSH_PORT="${SSH_PORT:-22}"

# Graceful shutdown timeout (seconds)
SHUTDOWN_TIMEOUT="${SHUTDOWN_TIMEOUT:-30}"

# ============================================================================
# Helper Functions
# ============================================================================

# Note: Logging functions (log_info, log_warn, log_error) are provided by
# scripts/_common/init.sh which sources apps/_shared/test.sh for enhanced logging.

build_ssh_command() {
    local host=$1
    local cmd=$2
    
    local ssh_opts="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -p ${SSH_PORT}"
    
    if [[ -n "${SSH_KEY}" ]]; then
        ssh_opts+=" -i ${SSH_KEY}"
    fi
    
    echo "ssh ${ssh_opts} ${SSH_USER}@${host} '${cmd}'"
}

shutdown_host() {
    local host=$1
    local host_label=$2
    
    log_info "Shutting down containers on ${host_label} (${host})..."
    
    # Command to execute on remote host: stop and remove all containers
    local remote_cmd="docker ps -a -q | xargs -r docker stop --time=${SHUTDOWN_TIMEOUT} 2>/dev/null || true"
    
    local ssh_cmd=$(build_ssh_command "${host}" "${remote_cmd}")
    
    if eval "${ssh_cmd}"; then
        log_info "✅ Successfully stopped containers on ${host_label}"
        
        # Get list of remaining containers (should be empty after stop)
        local verify_cmd="docker ps -a -q"
        local verify_ssh=$(build_ssh_command "${host}" "${verify_cmd}")
        
        if containers=$(eval "${verify_ssh}" 2>/dev/null); then
            if [[ -z "${containers}" ]]; then
                log_info "✅ All containers removed from ${host_label}"
            else
                log_warn "Containers still present on ${host_label}: ${containers}"
            fi
        fi
    else
        log_error "❌ Failed to shut down containers on ${host_label}"
        return 1
    fi
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

log_info "Performing pre-flight checks..."

# Verify SSH connectivity
if ! ssh -o ConnectTimeout=5 -p "${SSH_PORT}" "${SSH_USER}@${PRIMARY_HOST}" "echo 'SSH to PRIMARY_HOST OK'" 2>/dev/null; then
    log_error "Cannot SSH to PRIMARY_HOST (${PRIMARY_HOST}). Check host, credentials, and network."
    exit 1
fi
log_info "✅ SSH connectivity to PRIMARY_HOST verified"

if ! ssh -o ConnectTimeout=5 -p "${SSH_PORT}" "${SSH_USER}@${REPLICA_HOST}" "echo 'SSH to REPLICA_HOST OK'" 2>/dev/null; then
    log_error "Cannot SSH to REPLICA_HOST (${REPLICA_HOST}). Check host, credentials, and network."
    exit 1
fi
log_info "✅ SSH connectivity to REPLICA_HOST verified"

# ============================================================================
# Main Shutdown Sequence
# ============================================================================

log_info ""
log_warn "🛑 SHUTTING DOWN CLUSTER"
log_warn "   PRIMARY_HOST: ${PRIMARY_HOST}"
log_warn "   REPLICA_HOST: ${REPLICA_HOST}"
log_warn "   This will stop ALL Docker containers on both hosts"
log_info ""

read -p "Continue? (yes/no): " -r response
if [[ ! "${response}" =~ ^[Yy][Ee][Ss]$ ]]; then
    log_warn "Shutdown cancelled"
    exit 0
fi

log_info ""
log_info "Starting shutdown sequence..."
log_info ""

# Shutdown both hosts in parallel
shutdown_host "${PRIMARY_HOST}" "PRIMARY_HOST" &
PRIMARY_PID=$!

shutdown_host "${REPLICA_HOST}" "REPLICA_HOST" &
REPLICA_PID=$!

# Wait for both to complete
PRIMARY_EXIT=0
REPLICA_EXIT=0

wait ${PRIMARY_PID} || PRIMARY_EXIT=$?
wait ${REPLICA_PID} || REPLICA_EXIT=$?

# ============================================================================
# Shutdown Summary
# ============================================================================

log_info ""
log_info "Shutdown Complete"
log_info "═══════════════════════════════════════════════════════════════"

if [[ ${PRIMARY_EXIT} -eq 0 && ${REPLICA_EXIT} -eq 0 ]]; then
    log_info "✅ All containers on both hosts have been stopped"
    exit 0
else
    log_error "⚠️  Some errors occurred during shutdown"
    [[ ${PRIMARY_EXIT} -ne 0 ]] && log_error "   PRIMARY_HOST shutdown failed (exit code: ${PRIMARY_EXIT})"
    [[ ${REPLICA_EXIT} -ne 0 ]] && log_error "   REPLICA_HOST shutdown failed (exit code: ${REPLICA_EXIT})"
    exit 1
fi
