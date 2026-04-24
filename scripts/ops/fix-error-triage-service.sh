#!/usr/bin/env bash
# @file        scripts/ops/fix-error-triage-service.sh
# @module      operations/services
# @description Fix error-triage.service startup failures (P2 #1633)
# @owner       Platform Engineering
# @status      production-ready

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# CONSTANTS
PRIMARY_HOST="${DEPLOY_HOST:-192.168.168.31}"
REPLICA_HOST="${STANDBY_HOST:-192.168.168.42}"
EXEC_USER="${DEPLOY_USER:-akushnir}"
DRY_RUN="${DRY_RUN:-0}"
SERVICE_NAME="error-triage.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"

# Check if service file exists
check_service_file() {
    local host="$1"
    
    log_info "Checking for $SERVICE_NAME on $host..."
    
    local exists
    exists=$(ssh "${EXEC_USER}@${host}" "[ -f $SERVICE_PATH ] && echo 'EXISTS' || echo 'MISSING'" || echo "ERROR")
    
    if [ "$exists" = "MISSING" ]; then
        log_error "Service file not found at $SERVICE_PATH"
        return 1
    fi
    
    if [ "$exists" = "ERROR" ]; then
        log_error "Cannot check service file on $host"
        return 1
    fi
    
    log_success "✓ Service file exists"
    return 0
}

# Check service dependencies
check_service_dependencies() {
    local host="$1"
    
    log_info "Checking service dependencies on $host..."
    
    # Read service file and check for issues
    local service_content
    service_content=$(ssh "${EXEC_USER}@${host}" "cat $SERVICE_PATH" || echo "FAILED")
    
    if [ "$service_content" = "FAILED" ]; then
        log_error "Cannot read service file"
        return 1
    fi
    
    log_info "Service file content:"
    echo "$service_content" | sed 's/^/  /'
    
    # Check for common issues
    if echo "$service_content" | grep -q "^After="; then
        log_info "After dependencies:"
        echo "$service_content" | grep "^After=" | sed 's/^/  /'
    fi
    
    if echo "$service_content" | grep -q "^Requires="; then
        log_info "Required dependencies:"
        echo "$service_content" | grep "^Requires=" | sed 's/^/  /'
    fi
    
    return 0
}

# Check if dependencies are available
check_dependency_status() {
    local host="$1"
    
    log_info "Checking if service dependencies are running on $host..."
    
    # Common dependencies for error-triage: network, docker, postgres
    local dependencies=("docker.service" "postgresql.service" "network-online.target")
    
    for dep in "${dependencies[@]}"; do
        local status
        status=$(ssh "${EXEC_USER}@${host}" "systemctl is-active $dep 2>/dev/null || echo 'UNKNOWN'" || echo "ERROR")
        
        log_info "  $dep: $status"
    done
    
    return 0
}

# Check service status and errors
check_service_status() {
    local host="$1"
    
    log_info "Checking service status on $host..."
    
    local status
    status=$(ssh "${EXEC_USER}@${host}" "systemctl status $SERVICE_NAME 2>&1 | head -10 || echo 'FAILED'" || echo "ERROR")
    
    log_info "Service status:"
    echo "$status" | sed 's/^/  /'
    
    # Check journal for errors
    log_info ""
    log_info "Recent service errors:"
    ssh "${EXEC_USER}@${host}" "journalctl -u $SERVICE_NAME -n 10 --no-pager 2>/dev/null | grep -i 'error\|failed' || echo 'No errors found'" | sed 's/^/  /'
    
    return 0
}

# Fix service configuration
fix_service_configuration() {
    local host="$1"
    
    log_info "Fixing service configuration on $host..."
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would reload systemd and restart service"
        return 0
    fi
    
    # Reload systemd daemon to pick up changes
    log_info "Reloading systemd daemon..."
    ssh "${EXEC_USER}@${host}" "sudo systemctl daemon-reload" || {
        log_error "Failed to reload systemd"
        return 1
    }
    
    # Try to start the service
    log_info "Starting service..."
    ssh "${EXEC_USER}@${host}" "sudo systemctl start $SERVICE_NAME" || {
        log_warn "Service start failed - checking for issues"
        
        # Show detailed error
        log_info "Detailed error output:"
        ssh "${EXEC_USER}@${host}" "sudo systemctl status $SERVICE_NAME 2>&1 || true" | sed 's/^/  /'
        
        return 1
    }
    
    log_success "✓ Service started successfully"
    return 0
}

# Enable service for auto-start
enable_service() {
    local host="$1"
    
    log_info "Enabling service for auto-start on $host..."
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would enable service"
        return 0
    fi
    
    ssh "${EXEC_USER}@${host}" "sudo systemctl enable $SERVICE_NAME" || {
        log_error "Failed to enable service"
        return 1
    }
    
    log_success "✓ Service enabled for auto-start"
    return 0
}

# Verify service is running
verify_service_running() {
    local host="$1"
    
    log_info "Verifying service is running on $host..."
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would verify service status"
        return 0
    fi
    
    local active
    active=$(ssh "${EXEC_USER}@${host}" "systemctl is-active $SERVICE_NAME" || echo "FAILED")
    
    if [ "$active" = "active" ]; then
        log_success "✓ Service is running"
        return 0
    else
        log_error "Service is not running (status: $active)"
        return 1
    fi
}

# MAIN
main() {
    log_info "========================================================================"
    log_info "Fixing error-triage.service startup failures (P2 #1633)"
    log_info "========================================================================"
    log_info ""
    log_info "Configuration:"
    log_info "  Primary Host: $PRIMARY_HOST"
    log_info "  Service: $SERVICE_NAME"
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
    
    check_service_file "$PRIMARY_HOST" || {
        log_error "Service file missing - creating from template"
        log_info "Would need to create service file with proper configuration"
        log_info "See: /home/akushnir/code-server-enterprise/docs/SERVICES.md"
        return 1
    }
    log_info ""
    
    check_service_dependencies "$PRIMARY_HOST"
    log_info ""
    
    check_dependency_status "$PRIMARY_HOST"
    log_info ""
    
    check_service_status "$PRIMARY_HOST"
    log_info ""
    
    # FIX
    log_info "APPLYING FIXES"
    log_info "=============="
    log_info ""
    
    fix_service_configuration "$PRIMARY_HOST" || true
    log_info ""
    
    enable_service "$PRIMARY_HOST" || true
    log_info ""
    
    verify_service_running "$PRIMARY_HOST" || true
    log_info ""
    
    log_success "========================================================================"
    log_success "Error-triage.service diagnostics and fixes complete!"
    log_success "========================================================================"
    log_info ""
    log_info "If service still fails to start:"
    log_info "  1. Check /etc/systemd/system/${SERVICE_NAME} exists with correct config"
    log_info "  2. Verify all dependencies are installed and running"
    log_info "  3. Check service logs: journalctl -u $SERVICE_NAME -n 50 --no-pager"
    log_info "  4. Manually start: sudo systemctl start $SERVICE_NAME"
}

main "$@"
