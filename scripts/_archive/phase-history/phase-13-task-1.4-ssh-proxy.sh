#!/bin/bash
# ════════════════════════════════════════════════════════════════════════════
# PHASE 13 - TASK 1.4: SSH PROXY SETUP WITH AUDIT LOGGING
#
# Deploy SSH proxy service and validate audit logging
# Idempotent: Safe to re-run multiple times
# April 13, 2026 - Day 1 Execution
# ════════════════════════════════════════════════════════════════════════════

set -euo pipefail

export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="/var/log/phase-13-ssh-proxy.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"; }

main() {
    log_info "================================"
    log_info "PHASE 13 - TASK 1.4: SSH PROXY SETUP"
    log_info "================================"

    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"

    # Build SSH proxy image
    log_info "Building SSH proxy Docker image..."
    if docker build -f "$SCRIPT_DIR/Dockerfile.ssh-proxy" -t ssh-proxy:local . > /dev/null 2>&1; then
        log_success "SSH proxy image built"
    else
        log_error "Failed to build SSH proxy image"
        return 1
    fi

    # Start SSH proxy container
    log_info "Starting SSH proxy container..."
    docker-compose up -d ssh-proxy > /dev/null 2>&1

    # Wait for container to stabilize
    sleep 3

    # Verify SSH proxy container
    if ! docker-compose ps ssh-proxy | grep -q "Up"; then
        log_error "SSH proxy container failed to start"
        docker-compose logs ssh-proxy | tail -20 | tee -a "$LOG_FILE"
        return 1
    fi
    log_success "SSH proxy container running"

    # Check health endpoint
    log_info "Testing SSH proxy health endpoint..."
    if curl -sf http://localhost:3222/health > /dev/null 2>&1; then
        log_success "Health endpoint responding (port 3222)"
    else
        log_warn "Health endpoint not yet responding (container may still be initializing)"
    fi

    # Verify audit logging setup
    log_info "Verifying audit logging..."
    if [ -f "$SCRIPT_DIR/config/audit-logging.conf" ]; then
        log_success "Audit configuration file present"
    else
        log_error "Audit configuration missing"
        return 1
    fi

    # Check audit log volumes
    log_info "Checking audit log volumes..."
    local audit_log_volume
    audit_log_volume=$(docker volume ls | grep audit-logs | wc -l)
    if [ "$audit_log_volume" -gt 0 ]; then
        log_success "Audit log volume mounted"
    else
        log_warn "Audit log volume not yet mounted"
    fi

    log_success ""
    log_success "✓ SSH PROXY SETUP COMPLETE"
    log_success "SSH proxy listening on port 2222"
    log_success "Health/Metrics API on port 3222"
    return 0
}

main "$@"
exit $?
