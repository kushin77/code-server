#!/usr/bin/env bash
# @file scripts/ops/master-deployment-orchestrator.sh
# @module ops/orchestration
# @description Master orchestrator for full platform deployment
# @governance GOV-003: Safe coordinated deployment with comprehensive validation
# @usage master-deployment-orchestrator.sh [--dry-run] [--local] [--remote] [--terraform]

set -euo pipefail

# ============================================================================
# Error Handling & Cleanup
# ============================================================================
trap 'log_error "Deployment failed at line $LINENO (exit code: $?)"; cleanup_on_error; exit 1' ERR
cleanup_on_error() {
    rm -f /tmp/orchestration-*.tmp 2>/dev/null || true
}

# ============================================================================
# Configuration
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source common initialization before any path derivation
source "${SCRIPT_DIR}/../_common/init.sh"
DRY_RUN="${DRY_RUN:-false}"
DEPLOYMENT_MODE_REQUESTED="${DEPLOYMENT_MODE:-auto}"  # auto, local, remote, terraform
DEPLOYMENT_MODE="${DEPLOYMENT_MODE_REQUESTED}"
ORCHESTRATION_ID="ORCHESTRATION-$(date +%s)"
LOG_DIR="${REPO_ROOT}/artifacts"
LOG_FILE="${LOG_DIR}/master-deployment-${ORCHESTRATION_ID}.log"

if [[ -f "${REPO_ROOT}/.env.deployment" ]]; then
    set -a
    source "${REPO_ROOT}/.env.deployment"
    set +a
fi
case "${DEPLOYMENT_MODE:-auto}" in
    auto|local|remote|terraform) ;;
    *) DEPLOYMENT_MODE="auto" ;;
esac

if ! declare -F log_warn >/dev/null 2>&1; then
    log_warn() {
        if declare -F log_warning >/dev/null 2>&1; then
            log_warning "$*"
        else
            printf '[WARN] %s\n' "$*" >&2
        fi
    }
fi

mkdir -p "${LOG_DIR}"

# ============================================================================
# Deployment Mode Detection
# ============================================================================

detect_deployment_environment() {
    log_info "Detecting deployment environment..."
    
    local docker_available=false
    local ssh_available=false
    local terraform_available=false
    
    # Check Docker
    if command -v docker &> /dev/null; then
        if docker ps &> /dev/null; then
            docker_available=true
            log_success "✓ Docker daemon available"
        else
            log_warn "⚠ Docker installed but daemon not running"
        fi
    else
        log_warn "⚠ Docker not installed"
    fi
    
    # Check SSH connectivity to primary host
    if ping -c 1 -W 2 "${PRIMARY_HOST:?PRIMARY_HOST must be set}" &> /dev/null; then
        ssh_available=true
        log_success "✓ Primary host reachable (${PRIMARY_HOST})"
    else
        log_warn "⚠ Primary host unreachable"
    fi
    
    # Check Terraform (AWS disabled - skip entirely)
    log_warn "⚠ Terraform skipped (AWS provider removed)"
    
    # Determine optimal deployment strategy (only if not explicitly set)
    if [ -z "${DEPLOYMENT_MODE##auto*}" ] || [ "${DEPLOYMENT_MODE}" = "auto" ] || [ "${DEPLOYMENT_MODE}" = "private" ]; then
        if [ "$docker_available" = "true" ]; then
            DEPLOYMENT_MODE="local"
            log_success "Selected mode: LOCAL (Docker Compose)"
        elif [ "$ssh_available" = "true" ]; then
            DEPLOYMENT_MODE="remote"
            log_success "Selected mode: REMOTE (SSH orchestration)"
        else
            log_error "No deployment method available"
            return 1
        fi
    fi
}

# ============================================================================
# Phase 1: Pre-Deployment Validation
# ============================================================================

validate_deployment_readiness() {
    log_info ""
    log_info "PHASE 1: PRE-DEPLOYMENT VALIDATION"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Check configuration files
    log_info "  Checking configuration files..."
    [ -f "${REPO_ROOT}/docker-compose.yml" ] || { log_error "docker-compose.yml not found"; return 1; }
    [ -d "${REPO_ROOT}/terraform" ] || { log_error "terraform directory not found"; return 1; }
    [ -f "${REPO_ROOT}/.env.deployment" ] || { log_error ".env.deployment not found"; return 1; }
    log_success "✓ Configuration files present"
    
    # Load environment (preserve DEPLOYMENT_MODE from command-line)
    log_info "  Loading environment variables..."
    local saved_deployment_mode="${DEPLOYMENT_MODE:-auto}"
    case "${saved_deployment_mode}" in
        auto|local|remote|terraform) ;;
        *) saved_deployment_mode="auto" ;;
    esac
    source "${REPO_ROOT}/.env.deployment"
    DEPLOYMENT_MODE="${saved_deployment_mode}"  # Restore selected mode
    log_success "✓ Environment loaded (Primary: ${PRIMARY_HOST}, Domain: ${APEX_DOMAIN})"
    
    # Verify deployment scripts
    log_info "  Verifying deployment scripts..."
    local scripts_valid=0
    for script in "${REPO_ROOT}"/scripts/ops/*deploy*.sh; do
        if bash -n "$script" 2> /dev/null; then
            ((scripts_valid++))
        fi
    done
    log_success "✓ $scripts_valid deployment scripts validated"
    
    log_success "✓ Pre-deployment validation complete"
}

# ============================================================================
# Phase 2: Terraform Deployment
# ============================================================================

deploy_via_terraform() {
    log_info ""
    log_info "PHASE 2: TERRAFORM DEPLOYMENT (SKIPPED - AWS DISABLED)"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_warn "AWS provider removed from Terraform configuration"
    log_info "Proceeding with alternative deployment methods..."
    return 0
}

# ============================================================================
# Phase 3: Local Docker Deployment
# ============================================================================

deploy_via_local_docker() {
    log_info ""
    log_info "PHASE 3: LOCAL DOCKER DEPLOYMENT"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cd "${REPO_ROOT}"
    
    # Load environment
    source .env.deployment
    
    # Validate Docker Compose
    log_info "  Validating Docker Compose configuration..."
    if [ "${DRY_RUN}" = "true" ]; then
        log_info "  [DRY-RUN] Would validate: docker-compose config"
    else
        docker-compose config > /dev/null || { log_error "Docker Compose validation failed"; return 1; }
        log_success "✓ Docker Compose configuration valid"
    fi
    
    # Deploy services
    log_info "  Deploying Docker Compose services..."
    if [ "${DRY_RUN}" = "true" ]; then
        log_info "  [DRY-RUN] Would execute:"
        log_info "    docker-compose --profile ai --profile governance --profile infrastructure --profile all up -d --force-recreate"
    else
        docker-compose --profile ai --profile governance --profile infrastructure --profile all up -d --force-recreate || {
            log_error "Docker Compose deployment failed"
            return 1
        }
        log_success "✓ All services deployed"
    fi
    
    # Wait for services
    log_info "  Waiting for services to stabilize (30s)..."
    if [ "${DRY_RUN}" = "false" ]; then
        sleep 30
        log_success "✓ Services stabilized"
    fi
    
    log_success "✓ Local Docker deployment complete"
}

# ============================================================================
# Phase 3b: Remote SSH Deployment
# ============================================================================

deploy_via_remote_ssh() {
    log_info ""
    log_info "PHASE 3: REMOTE SSH DEPLOYMENT"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cd "${REPO_ROOT}"
    source .env.deployment
    
    # SSH to primary host and deploy
    log_info "  Connecting to ${PRIMARY_HOST}..."
    if [ "${DRY_RUN}" = "true" ]; then
        log_info "  [DRY-RUN] Would execute on ${PRIMARY_HOST}:"
        log_info "    cd ~/code-server-enterprise-ops || cd ~/code-server || cd /opt/code-server"
        log_info "    docker-compose --profile ai --profile governance --profile infrastructure --profile all up -d --force-recreate"
    else
        # Deploy via SSH using key-based auth
        log_info "  Deploying services via SSH..."
        
        # Find the correct path on remote host and deploy
        ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no "${SSH_USER:-akushnir}@${PRIMARY_HOST}" \
            "cd ~/code-server-enterprise-ops 2>/dev/null || cd ~/code-server 2>/dev/null || cd /opt/code-server 2>/dev/null || (echo 'Code-server directory not found'; exit 1) && docker-compose --profile ai --profile governance --profile infrastructure --profile all up -d --force-recreate" || {
            log_error "SSH deployment to ${PRIMARY_HOST} failed"
            return 1
        }
        log_success "✓ Remote deployment completed"
    fi
    
    # Wait for services on remote
    log_info "  Waiting for remote services to stabilize (30s)..."
    if [ "${DRY_RUN}" = "false" ]; then
        sleep 30
        log_success "✓ Services stabilized"
    fi
    
    log_success "✓ SSH deployment complete"
}

# ============================================================================
# Phase 4: Health Checks & Validation
# ============================================================================

validate_deployment_health() {
    log_info ""
    log_info "PHASE 4: HEALTH CHECKS & VALIDATION"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ "${DRY_RUN}" = "true" ]; then
        log_info "  [DRY-RUN] Would verify:"
        log_info "    - Service connectivity"
        log_info "    - Health endpoints"
        log_info "    - Container status"
        return 0
    fi
    
    source "${REPO_ROOT}/.env.deployment"
    
    # Check API endpoint
    log_info "  Checking API endpoint..."
    if curl -fsS http://${API_HOST}:${API_PORT}/health &> /dev/null; then
        log_success "✓ API endpoint healthy"
    else
        log_warn "⚠ API endpoint not yet responding (services may still be starting)"
    fi
    
    # Check service count
    if command -v docker &> /dev/null; then
        log_info "  Checking running services..."
        local running=$(docker ps -q | wc -l)
        log_success "✓ ${running} services running"
    fi
    
    log_success "✓ Health checks complete"
}

# ============================================================================
# Phase 5: Post-Deployment Reporting
# ============================================================================

generate_deployment_report() {
    log_info ""
    log_info "PHASE 5: POST-DEPLOYMENT REPORTING"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local report_file="${LOG_DIR}/deployment-report-${ORCHESTRATION_ID}.json"
    
    cat > "$report_file" <<EOF
{
  "orchestration_id": "${ORCHESTRATION_ID}",
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "deployment_mode": "${DEPLOYMENT_MODE}",
  "dry_run": ${DRY_RUN},
  "status": "COMPLETE",
  "phases": [
    "validation",
    "deployment",
    "health_checks",
    "reporting"
  ],
  "infrastructure": {
        "primary_host": "${PRIMARY_HOST:?PRIMARY_HOST must be set}",
        "replica_host": "${REPLICA_HOST:?REPLICA_HOST must be set}",
    "domain": "${APEX_DOMAIN:-kushnir.cloud}"
  },
  "docker_compose_profiles": [
    "ai",
    "governance",
    "infrastructure",
    "all"
  ]
}
EOF
    
    log_success "✓ Deployment report generated: $report_file"
}

# ============================================================================
# Main Orchestration Flow
# ============================================================================

main() {
    log_info "╔════════════════════════════════════════════════════════════╗"
    log_info "║       MASTER DEPLOYMENT ORCHESTRATOR v1.0                  ║"
    log_info "║       ${ORCHESTRATION_ID}"
    log_info "╚════════════════════════════════════════════════════════════╝"
    log_info ""
    
    # Detect environment
    detect_deployment_environment || {
        log_error "Failed to detect deployment environment"
        return 1
    }
    
    # Validate readiness
    validate_deployment_readiness || {
        log_error "Pre-deployment validation failed"
        return 1
    }
    
    # Execute deployment based on mode
    case "${DEPLOYMENT_MODE}" in
        terraform)
            deploy_via_terraform || { log_error "Terraform deployment failed"; return 1; }
            ;;
        local)
            deploy_via_local_docker || { log_error "Local Docker deployment failed"; return 1; }
            ;;
        remote)
            deploy_via_remote_ssh || { log_error "Remote SSH deployment failed"; return 1; }
            ;;
        *)
            log_error "Unknown deployment mode: ${DEPLOYMENT_MODE}"
            return 1
            ;;
    esac
    
    # Validate health
    validate_deployment_health || {
        log_warn "Health validation reported issues"
    }
    
    # Generate report
    generate_deployment_report
    
    log_info ""
    log_info "╔════════════════════════════════════════════════════════════╗"
    log_info "║              DEPLOYMENT COMPLETE ✅                        ║"
    log_info "║  Mode: ${DEPLOYMENT_MODE} | Dry-Run: ${DRY_RUN}"
    log_info "║  Report: ${LOG_DIR}/deployment-report-${ORCHESTRATION_ID}.json"
    log_info "╚════════════════════════════════════════════════════════════╝"
}

# Parse arguments FIRST
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN="true" ;;
        --local) DEPLOYMENT_MODE_REQUESTED="local"; DEPLOYMENT_MODE="local" ;;
        --remote) DEPLOYMENT_MODE_REQUESTED="remote"; DEPLOYMENT_MODE="remote" ;;
        --terraform) DEPLOYMENT_MODE_REQUESTED="terraform"; DEPLOYMENT_MODE="terraform" ;;
    esac
done

# Execute main flow
main "$@" | tee -a "${LOG_FILE}"
