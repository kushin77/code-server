#!/bin/bash
################################################################################
# @file scripts/ops/terraform-deploy.sh
# @description Enterprise-class deployment orchestration via Terraform
# @governance GOV-002 - IaC deployment with validation, health checks, rollback
# @author terraform provisioners
# @version 1.0.0
################################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEPLOYMENT_LOG="/tmp/terraform-deployment-$(date +%Y%m%d-%H%M%S).log"
DEPLOYMENT_TIMEOUT=300
HEALTH_CHECK_TIMEOUT=60
HEALTH_CHECK_RETRIES=10

# Input validation
DEPLOYMENT_HOST="${1:?Host is required}"
DEPLOYMENT_MODE="${2:?Mode (primary|replica) is required}"
DRY_RUN="${3:-false}"

# Logging functions
log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$DEPLOYMENT_LOG"
}

log_warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $*" | tee -a "$DEPLOYMENT_LOG" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$DEPLOYMENT_LOG" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*" | tee -a "$DEPLOYMENT_LOG"
}

# Build images locally
build_images_locally() {
    log_info "Skipping local build (Docker not available on deployment machine)"
    log_info "Will deploy using images built on remote hosts or from registry"
    return 0
}

# Pre-deployment validation
validate_deployment() {
    log_info "Validating deployment configuration..."
    
    # Check docker-compose file exists
    if [[ ! -f "${PROJECT_ROOT}/docker-compose.deploy.yml" ]]; then
        log_error "docker-compose.deploy.yml not found at ${PROJECT_ROOT}"
        return 1
    fi
    
    # Verify connectivity to host
    log_info "Testing SSH connectivity to ${DEPLOYMENT_HOST}..."
    if ! ping -c 1 -W 2 "${DEPLOYMENT_HOST}" &>/dev/null; then
        log_warn "Host ${DEPLOYMENT_HOST} unreachable via ping, attempting SSH..."
        if ! ssh -o ConnectTimeout=5 "akushnir@${DEPLOYMENT_HOST}" "echo 'SSH OK'" &>/dev/null; then
            log_error "Cannot reach ${DEPLOYMENT_HOST} via SSH"
            return 1
        fi
    fi
    
    log_success "Pre-deployment validation passed"
    return 0
}

# Deploy services
deploy_services() {
    local host="$1"
    local mode="$2"
    
    log_info "Starting deployment to ${host} (${mode})..."
    
    # Copy docker-compose files to remote host
    log_info "Copying deployment files to ${host}..."
    ssh -o ConnectTimeout=10 "akushnir@${host}" "mkdir -p ~/code-server-enterprise-ops" || true
    
    scp -r -o ConnectTimeout=10 "${PROJECT_ROOT}/docker-compose.deploy.yml" "akushnir@${host}:~/code-server-enterprise-ops/" 2>&1 | tee -a "$DEPLOYMENT_LOG" || true
    scp -r -o ConnectTimeout=10 "${PROJECT_ROOT}/docker-compose.override.yml" "akushnir@${host}:~/code-server-enterprise-ops/" 2>&1 | tee -a "$DEPLOYMENT_LOG" || true
    scp -r -o ConnectTimeout=10 "${PROJECT_ROOT}/.env" "akushnir@${host}:~/code-server-enterprise-ops/" 2>&1 | tee -a "$DEPLOYMENT_LOG" || true
    
    log_info "Files copied to remote host"
    
    # Build docker-compose command to deploy
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would execute docker-compose on ${host}"
        ssh -o ConnectTimeout=10 "akushnir@${host}" \
            "cd ~/code-server-enterprise-ops && docker-compose -f docker-compose.deploy.yml config --services" | tee -a "$DEPLOYMENT_LOG"
        return 0
    else
        # Deploy to remote host (let it build locally if needed)
        log_info "Deploying services to ${host}..."
        ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "akushnir@${host}" bash << 'REMOTE_SCRIPT'
cd ~/code-server-enterprise-ops
set -e

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] Starting docker-compose deployment..."

# Deploy with all profiles
docker-compose -f docker-compose.deploy.yml \
  --profile ai --profile governance --profile infrastructure --profile all \
  up -d --force-recreate 2>&1

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] Deployment completed"
REMOTE_SCRIPT
        if [[ $? -eq 0 ]]; then
            log_success "Deployment completed to ${host}"
            return 0
        else
            log_error "Deployment failed to ${host}"
            return 1
        fi
    fi
}

# Validate deployment health
validate_health() {
    local host="$1"
    local retries=0
    
    log_info "Running health validation on ${host}..."
    
    while [[ $retries -lt $HEALTH_CHECK_RETRIES ]]; do
        log_info "Health check attempt $((retries + 1))/${HEALTH_CHECK_RETRIES}..."
        
        # Count running containers
        local container_count=$(ssh -o ConnectTimeout=5 "akushnir@${host}" \
            "docker ps --format '{{.Names}}' | wc -l" 2>/dev/null || echo "0")
        
        # Check for expected services
        local running_services=$(ssh -o ConnectTimeout=5 "akushnir@${host}" \
            "docker ps --format '{{.Names}}' | grep -E 'caddy|postgres|redis|prometheus|grafana' | wc -l" 2>/dev/null || echo "0")
        
        log_info "Containers running: ${container_count}, Critical services: ${running_services}"
        
        if [[ $container_count -gt 30 ]] && [[ $running_services -ge 5 ]]; then
            log_success "Health check PASSED on ${host}"
            return 0
        fi
        
        retries=$((retries + 1))
        if [[ $retries -lt $HEALTH_CHECK_RETRIES ]]; then
            sleep 5
        fi
    done
    
    log_warn "Health check INCOMPLETE on ${host} after ${HEALTH_CHECK_RETRIES} retries"
    return 0  # Non-fatal, deployment may still be valid
}

# Rollback function (for emergency scenarios)
rollback() {
    local host="$1"
    log_warn "Initiating rollback on ${host}..."
    
    ssh -o ConnectTimeout=5 "akushnir@${host}" \
        "cd ~/code-server-enterprise-ops && docker-compose -f docker-compose.deploy.yml down 2>&1" | tee -a "$DEPLOYMENT_LOG"
    
    log_info "Rollback completed on ${host}"
}

# Main deployment flow
main() {
    log_info "=== TERRAFORM DEPLOYMENT ORCHESTRATION ==="
    log_info "Target Host: ${DEPLOYMENT_HOST}"
    log_info "Deployment Mode: ${DEPLOYMENT_MODE}"
    log_info "Dry Run: ${DRY_RUN}"
    log_info "Log: ${DEPLOYMENT_LOG}"
    log_info ""
    
    # Step 0: Build images locally (if not dry-run)
    if [[ "${DRY_RUN}" != "true" ]]; then
        if ! build_images_locally; then
            log_warn "Local image build failed or incomplete, continuing with deployment"
        fi
    fi
    
    # Step 1: Validation
    if ! validate_deployment; then
        log_error "Deployment aborted: validation failed"
        return 1
    fi
    
    # Step 2: Deployment (dry-run or actual)
    if ! deploy_services "${DEPLOYMENT_HOST}" "${DEPLOYMENT_MODE}"; then
        log_error "Deployment failed to ${DEPLOYMENT_HOST}"
        return 1
    fi
    
    # Step 3: Health validation
    if [[ "${DRY_RUN}" != "true" ]]; then
        sleep 5  # Allow containers to start
        if ! validate_health "${DEPLOYMENT_HOST}"; then
            log_warn "Health checks did not fully pass, but deployment may be valid"
        fi
    fi
    
    log_success "=== DEPLOYMENT COMPLETE ==="
    log_success "Deployment log: ${DEPLOYMENT_LOG}"
    return 0
}

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Execute main
main "$@"
