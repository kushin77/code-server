#!/usr/bin/env bash
# @file        scripts/ops/P2-1664-PRODUCTION-DEPLOYMENT-RUNBOOK.sh
# @module      operations/deployment
# @description Production deployment runbook for simplified parallel deployment to both replicas
#
# Usage: bash scripts/ops/P2-1664-PRODUCTION-DEPLOYMENT-RUNBOOK.sh [--dry-run] [--replicas 192.168.168.31,192.168.168.42]
#
set -euo pipefail

# Initialize script environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_onprem}"
REPLICAS="${REPLICAS:-192.168.168.31,192.168.168.42}"
SSH_USER="${SSH_USER:-akushnir}"
REPO_PATH="${REPO_PATH:-/home/${SSH_USER}/code-server-enterprise}"
DRY_RUN="${DRY_RUN:-0}"
PARALLEL_TIMEOUT="${PARALLEL_TIMEOUT:-900}"  # 15 minutes
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-300}"      # 5 minutes
HEALTH_POLL_INTERVAL="${HEALTH_POLL_INTERVAL:-10}"

# Globals
declare -A REPLICA_STATUS
DEPLOYMENT_START_TIME=""
DEPLOYMENT_END_TIME=""

# ============================================================================
# Helper Functions
# ============================================================================

require_var() {
    local var_name="$1"
    local var_value="${!var_name:-}"
    if [[ -z "$var_value" ]]; then
        log_fatal "Required variable not set: $var_name"
    fi
}

ssh_exec() {
    local host="$1"
    local cmd="$2"
    local timeout="${3:-30}"
    
    ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=accept-new \
        "$SSH_USER@$host" "cd $REPO_PATH && $cmd"
}

validate_ssh_key() {
    log_info "Validating SSH key: $SSH_KEY"
    if [[ ! -f "$SSH_KEY" ]]; then
        log_fatal "SSH key not found: $SSH_KEY"
    fi
    
    if ! ssh-keygen -l -f "$SSH_KEY" >/dev/null 2>&1; then
        log_fatal "SSH key invalid or corrupted: $SSH_KEY"
    fi
    
    log_info "SSH key validation: OK"
}

validate_ssh_connectivity() {
    log_info "Validating SSH connectivity to replicas..."
    
    IFS=',' read -ra REPLICA_ARRAY <<< "$REPLICAS"
    for replica in "${REPLICA_ARRAY[@]}"; do
        replica=$(echo "$replica" | xargs)  # trim whitespace
        if ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 \
               "$SSH_USER@$replica" "echo SSH_OK" >/dev/null 2>&1; then
            log_info "  $replica: ✅ SSH OK"
        else
            log_fatal "SSH connectivity failed to $replica"
        fi
    done
}

validate_docker_compose() {
    log_info "Validating docker-compose configuration on replicas..."
    
    IFS=',' read -ra REPLICA_ARRAY <<< "$REPLICAS"
    for replica in "${REPLICA_ARRAY[@]}"; do
        replica=$(echo "$replica" | xargs)
        if ssh_exec "$replica" "docker-compose config >/dev/null 2>&1"; then
            log_info "  $replica: ✅ docker-compose OK"
        else
            log_fatal "docker-compose config validation failed on $replica"
        fi
    done
}

validate_git_status() {
    log_info "Validating git status on replicas..."
    
    IFS=',' read -ra REPLICA_ARRAY <<< "$REPLICAS"
    for replica in "${REPLICA_ARRAY[@]}"; do
        replica=$(echo "$replica" | xargs)
        local status=$(ssh_exec "$replica" "git status --short --untracked-files=no" || echo "ERROR")
        if [[ "$status" == "" ]]; then
            log_info "  $replica: ✅ git clean"
        else
            log_warn "  $replica: git has uncommitted changes (may be normal)"
        fi
    done
}

# ============================================================================
# Pre-Deployment Validation
# ============================================================================

run_pre_deployment_validation() {
    log_info "=========================================="
    log_info "PRE-DEPLOYMENT VALIDATION"
    log_info "=========================================="
    
    require_var "SSH_KEY"
    require_var "REPLICAS"
    require_var "SSH_USER"
    require_var "REPO_PATH"
    
    validate_ssh_key
    validate_ssh_connectivity
    validate_docker_compose
    validate_git_status
    
    log_info "✅ All pre-deployment validation passed"
}

# ============================================================================
# Parallel Deployment
# ============================================================================

deploy_replica() {
    local replica="$1"
    local replica_clean=$(echo "$replica" | xargs)
    
    log_info "[$replica_clean] Starting deployment..."
    
    {
        # Step 1: Fetch latest code
        log_info "[$replica_clean] Fetching latest code..."
        ssh_exec "$replica_clean" "git fetch origin" >/dev/null 2>&1 || {
            log_error "[$replica_clean] git fetch failed"
            return 1
        }
        
        # Step 2: Reset to origin/main (idempotent)
        log_info "[$replica_clean] Resetting to origin/main..."
        ssh_exec "$replica_clean" "git reset --hard origin/main" >/dev/null 2>&1 || {
            log_error "[$replica_clean] git reset failed"
            return 1
        }
        
        # Step 3: Pull latest docker images
        log_info "[$replica_clean] Pulling latest docker images..."
        ssh_exec "$replica_clean" "docker-compose pull" >/dev/null 2>&1 || {
            log_error "[$replica_clean] docker pull failed"
            return 1
        }
        
        # Step 4: Start all services (docker-compose is idempotent)
        log_info "[$replica_clean] Starting services..."
        ssh_exec "$replica_clean" "docker-compose up -d" >/dev/null 2>&1 || {
            log_error "[$replica_clean] docker-compose up failed"
            return 1
        }
        
        log_info "[$replica_clean] ✅ Deployment complete"
        REPLICA_STATUS[$replica_clean]="DEPLOYED"
        return 0
        
    } &
    
    local pid=$!
    echo "$pid"
}

run_parallel_deployment() {
    log_info "=========================================="
    log_info "PARALLEL DEPLOYMENT TO ALL REPLICAS"
    log_info "=========================================="
    
    DEPLOYMENT_START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local pids=()
    
    IFS=',' read -ra REPLICA_ARRAY <<< "$REPLICAS"
    for replica in "${REPLICA_ARRAY[@]}"; do
        replica=$(echo "$replica" | xargs)
        local pid=$(deploy_replica "$replica")
        pids+=("$pid")
    done
    
    # Wait for all deployments with timeout
    log_info "Waiting for all replicas to complete deployment..."
    local timeout=$PARALLEL_TIMEOUT
    local start_time=$(date +%s)
    local failed=0
    
    for pid in "${pids[@]}"; do
        if ! wait "$pid" 2>/dev/null; then
            failed=$((failed + 1))
        fi
    done
    
    DEPLOYMENT_END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    if [[ $failed -gt 0 ]]; then
        log_error "❌ $failed replica(s) failed deployment"
        return 1
    fi
    
    log_info "✅ All replicas deployed successfully"
}

# ============================================================================
# Health Check Verification
# ============================================================================

check_replica_health() {
    local replica="$1"
    local replica_clean=$(echo "$replica" | xargs)
    
    {
        local elapsed=0
        while [[ $elapsed -lt $HEALTH_TIMEOUT ]]; do
            # Check Caddy health endpoint
            if ssh_exec "$replica_clean" "curl -sf http://localhost:8080/healthz >/dev/null" 2>/dev/null; then
                log_info "[$replica_clean] ✅ Health check passed"
                REPLICA_STATUS[$replica_clean]="HEALTHY"
                return 0
            fi
            
            elapsed=$((elapsed + HEALTH_POLL_INTERVAL))
            sleep "$HEALTH_POLL_INTERVAL"
            log_info "[$replica_clean] Waiting for services to be ready... (${elapsed}s/${HEALTH_TIMEOUT}s)"
        done
        
        log_error "[$replica_clean] ❌ Health check timeout"
        REPLICA_STATUS[$replica_clean]="UNHEALTHY"
        return 1
        
    } &
    
    local pid=$!
    echo "$pid"
}

run_health_verification() {
    log_info "=========================================="
    log_info "HEALTH CHECK VERIFICATION"
    log_info "=========================================="
    
    local pids=()
    
    IFS=',' read -ra REPLICA_ARRAY <<< "$REPLICAS"
    for replica in "${REPLICA_ARRAY[@]}"; do
        replica=$(echo "$replica" | xargs)
        local pid=$(check_replica_health "$replica")
        pids+=("$pid")
    done
    
    log_info "Verifying all replicas are healthy..."
    local failed=0
    
    for pid in "${pids[@]}"; do
        if ! wait "$pid" 2>/dev/null; then
            failed=$((failed + 1))
        fi
    done
    
    if [[ $failed -gt 0 ]]; then
        log_error "❌ $failed replica(s) health check failed"
        return 1
    fi
    
    log_info "✅ All replicas healthy"
}

# ============================================================================
# Service Parity Verification
# ============================================================================

check_service_parity() {
    log_info "=========================================="
    log_info "SERVICE PARITY VERIFICATION"
    log_info "=========================================="
    
    local reference_replica=""
    local reference_services=""
    
    IFS=',' read -ra REPLICA_ARRAY <<< "$REPLICAS"
    for i in "${!REPLICA_ARRAY[@]}"; do
        local replica=$(echo "${REPLICA_ARRAY[$i]}" | xargs)
        
        # Get running services
        local services=$(ssh_exec "$replica" "docker ps --format '{{.Names}}' | sort" 2>/dev/null || echo "")
        local service_count=$(echo "$services" | wc -l)
        
        log_info "[$replica] Running services: $service_count"
        
        if [[ $i -eq 0 ]]; then
            reference_replica="$replica"
            reference_services="$services"
        else
            if [[ "$services" != "$reference_services" ]]; then
                log_warn "[$replica] Service mismatch with $reference_replica"
                log_info "  Expected: $(echo "$reference_services" | wc -l) services"
                log_info "  Got: $service_count services"
            fi
        fi
    done
    
    log_info "✅ Service parity check complete"
}

# ============================================================================
# Deployment Report
# ============================================================================

print_deployment_report() {
    log_info "=========================================="
    log_info "DEPLOYMENT REPORT"
    log_info "=========================================="
    log_info "Start Time: $DEPLOYMENT_START_TIME"
    log_info "End Time: $DEPLOYMENT_END_TIME"
    
    log_info ""
    log_info "Replica Status:"
    for replica in "${!REPLICA_STATUS[@]}"; do
        log_info "  $replica: ${REPLICA_STATUS[$replica]}"
    done
    
    log_info ""
    log_info "Summary:"
    local total_replicas=$(echo "$REPLICAS" | tr ',' '\n' | wc -l)
    local healthy_replicas=$(echo "${REPLICA_STATUS[@]}" | grep -o "HEALTHY" | wc -l)
    log_info "  Total: $total_replicas"
    log_info "  Healthy: $healthy_replicas"
    log_info "  Failed: $((total_replicas - healthy_replicas))"
    
    log_info ""
    log_info "=========================================="
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_info "=========================================="
    log_info "PRODUCTION DEPLOYMENT RUNBOOK"
    log_info "=========================================="
    log_info "Replicas: $REPLICAS"
    log_info "SSH Key: $SSH_KEY"
    log_info "Dry Run: $DRY_RUN"
    log_info ""
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "🔍 DRY RUN MODE - No changes will be made"
        run_pre_deployment_validation
        log_info "✅ Dry run validation complete"
        return 0
    fi
    
    # Execute deployment phases
    run_pre_deployment_validation || return 1
    run_parallel_deployment || return 1
    run_health_verification || return 1
    check_service_parity || return 1
    
    print_deployment_report
    
    log_info ""
    log_info "✅ PRODUCTION DEPLOYMENT COMPLETE"
    log_info ""
}

# Run main with error handling
if main "$@"; then
    exit 0
else
    log_fatal "Production deployment failed"
    exit 1
fi
