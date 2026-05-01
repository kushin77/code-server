#!/bin/bash
#
# @file shutdown-cluster-defaults.sh
# @description Shut down all Docker containers on cluster with defaults from code-server repo
# @author DevOps
# @date 2026-04-27
# @usage
#   # Using defaults from terraform/drop-package/terraform.tfvars.example:
#   bash shutdown-cluster-defaults.sh
#
#   # Or override:
#   PRIMARY_HOST=192.168.168.31 REPLICA_HOST=192.168.168.42 bash shutdown-cluster-defaults.sh
#

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# ============================================================================
# Configuration with intelligent defaults
# ============================================================================

# Try to source .env.infrastructure if it exists and sets values
if [[ -f .env.infrastructure ]] && grep -q "PRIMARY_HOST\|REPLICA_HOST" .env.infrastructure; then
    set +e
    source .env.infrastructure 2>/dev/null || true
    set -e
fi

# Use environment variables or values sourced from .env.infrastructure
PRIMARY_HOST="${PRIMARY_HOST:?PRIMARY_HOST must be set}"
REPLICA_HOST="${REPLICA_HOST:?REPLICA_HOST must be set}"
SSH_USER="${SSH_USER:-akushnir}"
SSH_KEY="${SSH_KEY:-}"
SSH_PORT="${SSH_PORT:-22}"
SHUTDOWN_TIMEOUT="${SHUTDOWN_TIMEOUT:-30}"
FORCE="${FORCE:-false}"

# ============================================================================
# Helper Functions
# ============================================================================

# Note: Logging functions (log_info, log_warn, log_error, log_debug) are provided by
# scripts/_common/init.sh which sources apps/_shared/test.sh for enhanced logging.

build_ssh_command() {
    local host=$1
    local cmd=$2

    local ssh_opts="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes -p ${SSH_PORT}"

    if [[ -n "${SSH_KEY}" ]]; then
        ssh_opts+=" -i ${SSH_KEY}"
    fi

    echo "ssh ${ssh_opts} ${SSH_USER}@${host} '${cmd}'"
}

test_ssh_connection() {
    local host=$1
    local label=$2

    log_debug "Testing SSH connectivity to ${label} (${host})..."

    local ssh_opts="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes -p ${SSH_PORT}"
    if [[ -n "${SSH_KEY}" ]]; then
        ssh_opts+=" -i ${SSH_KEY}"
    fi

    if ssh ${ssh_opts} "${SSH_USER}@${host}" "echo 'OK'" 2>/dev/null | grep -q OK; then
        log_info "✅ SSH connectivity to ${label} (${host}) verified"
        return 0
    else
        log_error "❌ Cannot SSH to ${label} (${host})"
        log_error "   User: ${SSH_USER}, Port: ${SSH_PORT}"
        return 1
    fi
}

get_container_count() {
    local host=$1

    local ssh_cmd=$(build_ssh_command "${host}" "docker ps -a -q | wc -l")
    eval "${ssh_cmd}" 2>/dev/null || echo "0"
}

shutdown_host() {
    local host=$1
    local host_label=$2

    log_info ""
    log_info "Shutting down containers on ${host_label} (${host})..."

    # Get count before shutdown
    local count_before=$(get_container_count "${host}")
    log_debug "Containers before shutdown: ${count_before}"

    # Command to stop all containers
    local remote_cmd="docker ps -a -q | xargs -r docker stop --time=${SHUTDOWN_TIMEOUT} 2>/dev/null || true"
    local ssh_cmd=$(build_ssh_command "${host}" "${remote_cmd}")

    if eval "${ssh_cmd}"; then
        log_info "✅ Container stop command executed on ${host_label}"

        # Verify containers are stopped
        sleep 2
        local count_after=$(get_container_count "${host}")
        log_debug "Containers after shutdown: ${count_after}"

        if [[ ${count_after} -eq 0 ]]; then
            log_info "✅ All containers removed from ${host_label}"
        else
            log_warn "⚠️  ${count_after} container(s) still present on ${host_label}"
        fi

        return 0
    else
        log_error "❌ Failed to execute shutdown commands on ${host_label}"
        return 1
    fi
}

# ============================================================================
# Banner and Confirmation
# ============================================================================

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           DOCKER CLUSTER SHUTDOWN UTILITY                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

log_info "Configuration:"
log_info "  PRIMARY_HOST:      ${PRIMARY_HOST}"
log_info "  REPLICA_HOST:      ${REPLICA_HOST}"
log_info "  SSH_USER:          ${SSH_USER}"
log_info "  SSH_PORT:          ${SSH_PORT}"
if [[ -n "${SSH_KEY}" ]]; then
    log_info "  SSH_KEY:           ${SSH_KEY}"
fi
log_info "  SHUTDOWN_TIMEOUT:  ${SHUTDOWN_TIMEOUT}s"
echo ""

# ============================================================================
# Pre-flight Checks
# ============================================================================

log_info "Running pre-flight checks..."

if ! test_ssh_connection "${PRIMARY_HOST}" "PRIMARY_HOST"; then
    log_error "Cannot proceed without connectivity to PRIMARY_HOST"
    exit 1
fi

if ! test_ssh_connection "${REPLICA_HOST}" "REPLICA_HOST"; then
    log_error "Cannot proceed without connectivity to REPLICA_HOST"
    exit 1
fi

log_info "✅ All connectivity checks passed"
echo ""

# ============================================================================
# Confirm Shutdown
# ============================================================================

if [[ "${FORCE}" != "true" ]]; then
    log_warn "🛑 ABOUT TO SHUT DOWN ALL CONTAINERS ON BOTH HOSTS"
    log_warn ""
    log_warn "This will:"
    log_warn "  • Stop all Docker containers on PRIMARY_HOST (${PRIMARY_HOST})"
    log_warn "  • Stop all Docker containers on REPLICA_HOST (${REPLICA_HOST})"
    log_warn ""

    read -p "Continue? (type 'yes' to proceed): " -r response
    if [[ ! "${response}" =~ ^[Yy][Ee][Ss]$ ]]; then
        log_warn "Shutdown cancelled by user"
        exit 0
    fi
else
    log_info "FORCE=true: Proceeding without confirmation"
fi

# ============================================================================
# Main Shutdown Sequence
# ============================================================================

log_info ""
log_warn "🛑 Starting shutdown sequence..."
log_info ""

# Shutdown both hosts in parallel for faster execution
shutdown_host "${PRIMARY_HOST}" "PRIMARY_HOST" &
PRIMARY_PID=$!

shutdown_host "${REPLICA_HOST}" "REPLICA_HOST" &
REPLICA_PID=$!

# Wait for both to complete
PRIMARY_EXIT=0
REPLICA_EXIT=0

wait ${PRIMARY_PID} 2>/dev/null || PRIMARY_EXIT=$?
wait ${REPLICA_PID} 2>/dev/null || REPLICA_EXIT=$?

# ============================================================================
# Summary
# ============================================================================

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
log_info "Shutdown Complete"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

if [[ ${PRIMARY_EXIT} -eq 0 && ${REPLICA_EXIT} -eq 0 ]]; then
    log_info "✅ SUCCESS: All containers on both hosts have been stopped"
    echo ""
    exit 0
else
    log_error "❌ ERRORS occurred during shutdown:"
    [[ ${PRIMARY_EXIT} -ne 0 ]] && log_error "   • PRIMARY_HOST shutdown failed (exit: ${PRIMARY_EXIT})"
    [[ ${REPLICA_EXIT} -ne 0 ]] && log_error "   • REPLICA_HOST shutdown failed (exit: ${REPLICA_EXIT})"
    echo ""
    exit 1
fi
