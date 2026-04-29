#!/bin/bash
###############################################################################
# @file        scripts/ops/deploy-production-fix.sh
# @module      ops/deploy-production-fix
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
#
# @file scripts/ops/deploy-production-fix.sh
# @description Idempotent production deployment with health verification
# @governance GOV-002: Immutable, deterministic, version-controlled deployment
# @author GitHub Copilot
# @created 2026-04-24
#
# Usage:
#   ssh akushnir@${PRIMARY_HOST} 'cd code-server-enterprise && bash scripts/ops/deploy-production-fix.sh'
#   ssh akushnir@${REPLICA_HOST} 'cd code-server-enterprise && bash scripts/ops/deploy-production-fix.sh'
#

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT


set -euo pipefail

# Source canonical environment variables (SSOT)
if [ -f "${REPO_ROOT}/.env.infrastructure" ]; then
    set -a
    source "${REPO_ROOT}/.env.infrastructure"
    set +a
else
    echo "[ERROR] .env.infrastructure not found in ${REPO_ROOT}. Aborting." >&2
    exit 1
fi

# Fail-fast: Ensure required environment variables are set
required_vars=(PRIMARY_HOST REPLICA_HOST OAUTH2_COOKIE_SECRET SCHEDULER_API_KEY DATABASE_URL)
for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "[ERROR] Required environment variable $var is not set. Aborting." >&2
        exit 1
    fi
done

readonly DOCKER_COMPOSE_FILE="${REPO_ROOT}/docker-compose.yml"
readonly LOG_FILE="/tmp/deploy-$(date +%Y%m%d-%H%M%S).log"
readonly HEALTH_CHECK_RETRIES=30
readonly HEALTH_CHECK_INTERVAL=2

# Logging functions
log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*" | tee -a "$LOG_FILE"
}

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Deployment failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/deploy-*.log 2>/dev/null || true' EXIT

# Idempotent git sync: only pull if HEAD diverges from origin/main
sync_code() {
    log_info "Verifying code state..."
    
    # Fetch latest remote state
    git fetch origin main 2>/dev/null || log_error "Failed to fetch origin"
    
    # Check if local HEAD matches origin/main
    local local_head=$(git rev-parse HEAD 2>/dev/null || echo "")
    local remote_head=$(git rev-parse origin/main 2>/dev/null || echo "")
    
    if [ "$local_head" != "$remote_head" ]; then
        log_info "Code update available. Pulling latest changes..."
        git reset --hard origin/main || log_error "Failed to reset to origin/main"
        log_success "Code synchronized to origin/main"
    else
        log_info "Code already synchronized (HEAD == origin/main)"
    fi
}

# Rebuild services with fresh dependencies
rebuild_services() {
    log_info "Rebuilding Docker images to pick up dependency updates..."
    
    # Force rebuild without cache for critical services
    docker-compose build --no-cache execution-scheduler 2>&1 | tee -a "$LOG_FILE"
    docker-compose build --no-cache oauth2-proxy 2>&1 | tee -a "$LOG_FILE"
    
    log_success "Docker images rebuilt"
}

# Idempotent deployment: only restart services that need it
deploy_services() {
    log_info "Deploying services (idempotent)..."
    
    # Use 'up -d' which is idempotent - creates only missing containers, updates existing
    docker-compose up -d 2>&1 | tee -a "$LOG_FILE"
    
    log_success "Services deployed"
}

# Verify health with retries
verify_health() {
    local service_name=$1
    local health_endpoint=$2
    local retry_count=0
    
    log_info "Verifying health of $service_name..."
    
    while [ $retry_count -lt "$HEALTH_CHECK_RETRIES" ]; do
        if curl -sf "$health_endpoint" >/dev/null 2>&1; then
            log_success "$service_name is healthy"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt "$HEALTH_CHECK_RETRIES" ]; then
            log_info "Health check failed for $service_name (attempt $retry_count/$HEALTH_CHECK_RETRIES). Retrying in ${HEALTH_CHECK_INTERVAL}s..."
            sleep "$HEALTH_CHECK_INTERVAL"
        fi
    done
    
    log_error "$service_name failed health check after $HEALTH_CHECK_RETRIES attempts"
    return 1
}

# Main deployment flow
main() {
    log_info "=== Production Deployment (IaC-Compliant) ==="
    log_info "Repository: $REPO_ROOT"
    log_info "Log file: $LOG_FILE"
    
    # Step 1: Synchronize code
    sync_code
    
    # Step 2: Rebuild services
    rebuild_services
    
    # Step 3: Deploy
    deploy_services
    
    # Step 4: Wait for stabilization
    log_info "Waiting for services to stabilize (30s)..."
    sleep 30
    
    # Step 5: Health checks
    log_info "Running health checks..."
    local health_ok=true
    
    if ! verify_health "PostgreSQL" "http://localhost:5432" 2>/dev/null; then
        health_ok=false
    fi
    
    if ! verify_health "Execution-Scheduler" "http://localhost:8080/health"; then
        health_ok=false
    fi
    
    if ! verify_health "Redis" "redis://localhost:6379" 2>/dev/null; then
        health_ok=false
    fi
    
    # Step 6: Summary
    echo ""
    log_info "=== Deployment Summary ==="
    docker-compose ps --format "table {{.Names}}\t{{.Status}}" 2>&1 | tee -a "$LOG_FILE"
    
    if [ "$health_ok" = true ]; then
        log_success "Deployment completed successfully"
        return 0
    else
        log_error "Deployment completed with health check warnings - see logs for details"
        return 1
    fi
}

# Run main function
main "$@"
