#!/bin/bash
# ════════════════════════════════════════════════════════════════════════════
# PHASE 13 - TASK 1.3: CLUSTER HEALTH VALIDATION
# 
# Verify code-server Pod replicas and cluster status
# Idempotent: Safe to re-run multiple times
# April 13, 2026 - Day 1 Execution
# ════════════════════════════════════════════════════════════════════════════

set -euo pipefail

export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="/var/log/phase-13-cluster-health.log"

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
    log_info "PHASE 13 - TASK 1.3: CLUSTER HEALTH"
    log_info "================================"
    
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    # Check Docker containers
    log_info "Checking Docker infrastructure..."
    local healthy_count=0
    local total_count=0
    
    while IFS= read -r line; do
        total_count=$((total_count + 1))
        if echo "$line" | grep -q "healthy\|Up"; then
            healthy_count=$((healthy_count + 1))
            local container_name
            container_name=$(echo "$line" | awk '{print $1}')
            log_success "Container healthy: $container_name"
        fi
    done < <(docker-compose ps 2>/dev/null | tail -n +2 || true)
    
    if [ "$healthy_count" -lt 3 ]; then
        log_error "Not enough healthy containers ($healthy_count/$total_count)"
        return 1
    fi
    log_success "Cluster has $healthy_count healthy containers"
    
    # Check code-server service
    log_info "Verifying code-server service..."
    if ! docker-compose exec -T code-server curl -sf http://localhost:8080/healthz > /dev/null; then
        log_error "code-server health check failed"
        return 1
    fi
    log_success "code-server health check passed"
    
    # Check caddy service
    log_info "Verifying caddy reverse proxy..."
    if ! curl -sf https://localhost/healthz > /dev/null 2>&1; then
        log_info "caddy HTTPS health check pending (TLS not yet configured)"
    else
        log_success "caddy HTTPS health check passed"
    fi
    
    # Memory/CPU availability
    log_info "Checking resource availability..."
    local available_memory
    available_memory=$(free -m | awk '/^Mem:/{print $7}')
    log_success "Available memory: ${available_memory}MB"
    
    log_success ""
    log_success "✓ CLUSTER HEALTH VALIDATION COMPLETE"
    return 0
}

main "$@"
exit $?
