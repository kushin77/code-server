#!/usr/bin/env bash
# @file        scripts/ops/fix-ollama-init-container.sh
# @module      operations/containers
# @description Fix ollama-init container stuck in Created state (P2 #1632)
# @owner       Platform Engineering
# @status      production-ready

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh" || exit 1

# CONSTANTS
PRIMARY_HOST="${DEPLOY_HOST:-192.168.168.31}"
REPLICA_HOST="${STANDBY_HOST:-192.168.168.42}"
EXEC_USER="${DEPLOY_USER:-akushnir}"
DRY_RUN="${DRY_RUN:-0}"
CONTAINER_NAME="ollama-init"

# Check container state
check_container_state() {
    local host="$1"
    
    log_info "Checking $CONTAINER_NAME container state on $host..."
    
    local state
    state=$(ssh "${EXEC_USER}@${host}" "docker ps -a --filter name=$CONTAINER_NAME --format '{{.State}}' 2>/dev/null || echo 'UNKNOWN'" || echo "ERROR")
    
    log_info "Container state: $state"
    
    if [ "$state" = "created" ]; then
        log_warn "⚠ Container is in Created state (not running)"
        return 1
    elif [ "$state" = "running" ]; then
        log_success "✓ Container is running"
        return 0
    else
        log_info "Container status: $state"
        return 0
    fi
}

# Check docker-compose.yml configuration for ollama-init
check_compose_config() {
    local host="$1"
    
    log_info "Checking docker-compose configuration for $CONTAINER_NAME on $host..."
    
    local compose_path="/home/akushnir/code-server-enterprise/docker-compose.yml"
    
    # Check if service is defined
    local service_def
    service_def=$(ssh "${EXEC_USER}@${host}" "grep -A20 'ollama-init:' $compose_path 2>/dev/null | head -25 || echo 'NOT_FOUND'" || echo "ERROR")
    
    if [ "$service_def" = "NOT_FOUND" ]; then
        log_warn "ollama-init service not found in docker-compose.yml"
        return 1
    fi
    
    log_info "Service configuration:"
    echo "$service_def" | sed 's/^/  /'
    
    # Check for depends_on
    if echo "$service_def" | grep -q "depends_on:"; then
        log_info "Found depends_on configuration"
        echo "$service_def" | grep -A5 "depends_on:" | sed 's/^/  /'
    else
        log_warn "No depends_on configuration found - may need explicit dependencies"
    fi
    
    return 0
}

# Check logs for startup errors
check_container_logs() {
    local host="$1"
    
    log_info "Checking $CONTAINER_NAME container logs on $host..."
    
    local logs
    logs=$(ssh "${EXEC_USER}@${host}" "docker logs $CONTAINER_NAME 2>&1 | tail -20 || echo 'NO_LOGS'" || echo "ERROR")
    
    if [ "$logs" = "NO_LOGS" ] || [ "$logs" = "ERROR" ]; then
        log_warn "No logs found for container"
        return 1
    fi
    
    log_info "Recent container logs:"
    echo "$logs" | sed 's/^/  /'
    
    return 0
}

# Check ollama service dependency
check_ollama_dependency() {
    local host="$1"
    
    log_info "Checking ollama service (dependency) status on $host..."
    
    # Check if ollama container exists and is running
    local ollama_state
    ollama_state=$(ssh "${EXEC_USER}@${host}" "docker ps -a --filter name=ollama --format '{{.State}}' 2>/dev/null | head -1 || echo 'NOT_FOUND'" || echo "ERROR")
    
    log_info "Ollama service state: $ollama_state"
    
    if [ "$ollama_state" != "running" ]; then
        log_warn "Ollama service is not running - may be blocking ollama-init"
        return 1
    fi
    
    log_success "✓ Ollama service is running"
    return 0
}

# Fix container by removing and restarting
fix_container() {
    local host="$1"
    
    log_info "Fixing $CONTAINER_NAME container on $host..."
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would:"
        log_info "[DRY-RUN]   1. Stop container if running"
        log_info "[DRY-RUN]   2. Remove stuck container"
        log_info "[DRY-RUN]   3. Restart via docker-compose"
        return 0
    fi
    
    # Stop container
    log_info "Stopping container..."
    ssh "${EXEC_USER}@${host}" "docker stop $CONTAINER_NAME 2>/dev/null || true" > /dev/null
    
    # Remove container
    log_info "Removing container..."
    ssh "${EXEC_USER}@${host}" "docker rm $CONTAINER_NAME 2>/dev/null || true" > /dev/null
    
    # Restart via docker-compose
    log_info "Restarting via docker-compose..."
    ssh "${EXEC_USER}@${host}" "cd /home/akushnir/code-server-enterprise && docker-compose up -d $CONTAINER_NAME" || {
        log_error "Failed to restart container via docker-compose"
        return 1
    }
    
    log_success "✓ Container restarted"
    return 0
}

# Verify container is running after fix
verify_container_running() {
    local host="$1"
    
    log_info "Verifying $CONTAINER_NAME is running on $host..."
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would verify container is running"
        return 0
    fi
    
    # Give container a moment to start
    sleep 2
    
    local state
    state=$(ssh "${EXEC_USER}@${host}" "docker ps --filter name=$CONTAINER_NAME --format '{{.State}}'" || echo "UNKNOWN")
    
    if [ "$state" = "running" ]; then
        log_success "✓ Container is now running"
        return 0
    else
        log_warn "Container status: $state (expected: running)"
        return 1
    fi
}

# MAIN
main() {
    log_info "========================================================================"
    log_info "Fixing ollama-init container stuck state (P2 #1632)"
    log_info "========================================================================"
    log_info ""
    log_info "Configuration:"
    log_info "  Primary Host: $PRIMARY_HOST"
    log_info "  Container: $CONTAINER_NAME"
    log_info "  Dry-Run Mode: $([ "$DRY_RUN" = "1" ] && echo "YES" || echo "NO")"
    log_info ""
    
    log_info "Verifying SSH connectivity..."
    
    if ! ssh -o ConnectTimeout=5 "${EXEC_USER}@${PRIMARY_HOST}" "echo ok" > /dev/null 2>&1; then
        log_fatal "Cannot connect to primary host"
    fi
    log_success "✓ Connected to primary"
    log_info ""
    
    # DIAGNOSIS
    log_info "DIAGNOSIS"
    log_info "========="
    log_info ""
    
    check_container_state "$PRIMARY_HOST" || log_warn "Container not in expected state"
    log_info ""
    
    check_compose_config "$PRIMARY_HOST"
    log_info ""
    
    check_ollama_dependency "$PRIMARY_HOST" || log_warn "Ollama dependency may need attention"
    log_info ""
    
    check_container_logs "$PRIMARY_HOST" || true
    log_info ""
    
    # FIX
    log_info "APPLYING FIXES"
    log_info "=============="
    log_info ""
    
    fix_container "$PRIMARY_HOST" || return 1
    log_info ""
    
    verify_container_running "$PRIMARY_HOST" || true
    log_info ""
    
    log_success "========================================================================"
    log_success "ollama-init container diagnostics and fixes complete!"
    log_success "========================================================================"
    log_info ""
    log_info "If container still doesn't start:"
    log_info "  1. Check ollama container is running: docker ps | grep ollama"
    log_info "  2. Check logs: docker logs $CONTAINER_NAME"
    log_info "  3. Check docker-compose.yml for dependency configuration"
    log_info "  4. Manually start: docker-compose up -d $CONTAINER_NAME"
}

main "$@"
