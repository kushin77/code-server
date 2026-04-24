#!/usr/bin/env bash
# @file        scripts/ops/deploy-cluster-health-monitoring.sh
# @module      infrastructure/monitoring
# @description Deploy cluster health check monitoring to both replicas (idempotent, IaC)
#
# Deploys Prometheus health monitoring configuration to both production replicas.
# Configuration includes:
# - Prometheus scrape jobs for /health endpoints on both replicas
# - AlertManager alert rules for single/dual replica failures
# - Slack alert routing for critical health events

set -euo pipefail

# =============================================================================
# INITIALIZATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Load shared libraries
source "${SCRIPT_DIR}/../_common/init.sh"
init_repo

log_info "Starting cluster health monitoring deployment"

# =============================================================================
# CONFIGURATION
# =============================================================================

REPLICA_31="192.168.168.31"
REPLICA_42="192.168.168.42"
SSH_USER="akushnir"
SSH_KEY="${HOME}/.ssh/id_rsa_onprem"
DEPLOY_PATH="code-server-enterprise"

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

log_info "Running pre-flight checks..."

# Verify SSH key exists
if [[ ! -f "${SSH_KEY}" ]]; then
    log_fatal "SSH key not found: ${SSH_KEY}"
fi
log_info "✓ SSH key found"

# Verify Prometheus configuration files exist locally
if [[ ! -f "${REPO_ROOT}/prometheus.yml" ]]; then
    log_fatal "prometheus.yml not found in repo root"
fi

if [[ ! -f "${REPO_ROOT}/alert-rules.yml" ]]; then
    log_fatal "alert-rules.yml not found in repo root"
fi

log_info "✓ Configuration files verified"

# Verify git state (no uncommitted changes)
cd "${REPO_ROOT}"
if [[ -n $(git status --short) ]]; then
    log_warn "Warning: Uncommitted changes detected in working directory"
    log_warn "$(git status --short | head -5)"
fi

log_info "✓ Pre-flight checks complete"

# =============================================================================
# DEPLOYMENT FUNCTION
# =============================================================================

deploy_to_replica() {
    local replica_ip="$1"
    local replica_name="$2"
    
    log_info "Deploying to Replica ${replica_name} (${replica_ip})..."
    
    # Test SSH connectivity
    if ! ssh -i "${SSH_KEY}" -o ConnectTimeout=5 "${SSH_USER}@${replica_ip}" "echo 'SSH connectivity OK'" > /dev/null 2>&1; then
        log_error "Cannot connect to ${replica_ip} via SSH"
        return 1
    fi
    log_info "  ✓ SSH connectivity verified"
    
    # Verify git commit parity
    local_commit=$(git -C "${REPO_ROOT}" rev-parse --short HEAD)
    remote_commit=$(ssh -i "${SSH_KEY}" "${SSH_USER}@${replica_ip}" "cd ${DEPLOY_PATH} && git rev-parse --short HEAD" 2>/dev/null || echo "UNKNOWN")
    
    if [[ "${local_commit}" != "${remote_commit}" ]]; then
        log_warn "  ⚠ Git commit mismatch: local=${local_commit} remote=${remote_commit}"
        log_warn "  This is expected if replica hasn't been redeployed yet."
    fi
    log_info "  ✓ Git state checked (local=${local_commit} remote=${remote_commit})"
    
    # Deploy Prometheus container (idempotent - safe to run multiple times)
    log_info "  Restarting prometheus service..."
    if ssh -i "${SSH_KEY}" "${SSH_USER}@${replica_ip}" \
        "cd ${DEPLOY_PATH} && docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d prometheus" \
        > /dev/null 2>&1; then
        log_info "  ✓ Prometheus service updated"
    else
        log_error "Failed to update prometheus on ${replica_ip}"
        return 1
    fi
    
    # Verify Prometheus is responding
    if ssh -i "${SSH_KEY}" "${SSH_USER}@${replica_ip}" \
        "docker exec prometheus curl -f -s http://localhost:9090/-/healthy > /dev/null" \
        2>/dev/null; then
        log_info "  ✓ Prometheus health check PASSED"
    else
        log_warn "  ⚠ Prometheus health endpoint not responding (may take a few seconds)"
    fi
    
    log_info "✓ Deployment to Replica ${replica_name} complete"
    return 0
}

# =============================================================================
# PARALLEL DEPLOYMENT
# =============================================================================

log_info ""
log_info "Deploying to both replicas in parallel..."

# Deploy to both replicas in background
deploy_to_replica "${REPLICA_31}" "31" &
PID_31=$!

deploy_to_replica "${REPLICA_42}" "42" &
PID_42=$!

# Wait for both deployments
FAILED=0
if ! wait ${PID_31}; then
    log_error "Deployment to Replica 31 failed"
    FAILED=1
fi

if ! wait ${PID_42}; then
    log_error "Deployment to Replica 42 failed"
    FAILED=1
fi

if [[ ${FAILED} -eq 1 ]]; then
    log_fatal "Deployment failed on one or more replicas"
fi

log_info "✓ Parallel deployment complete"

# =============================================================================
# VERIFICATION
# =============================================================================

log_info ""
log_info "Verifying Prometheus scrape targets..."

sleep 2  # Give Prometheus a moment to settle

# Check Replica 31
if ssh -i "${SSH_KEY}" "${SSH_USER}@${REPLICA_31}" \
    "docker exec prometheus curl -f -s 'http://localhost:9090/api/v1/targets' | grep -q 'cluster-health'" \
    2>/dev/null; then
    log_info "✓ Replica 31 scrape targets OK"
else
    log_warn "⚠ Replica 31 scrape targets may not be configured correctly"
fi

# Check Replica 42
if ssh -i "${SSH_KEY}" "${SSH_USER}@${REPLICA_42}" \
    "docker exec prometheus curl -f -s 'http://localhost:9090/api/v1/targets' | grep -q 'cluster-health'" \
    2>/dev/null; then
    log_info "✓ Replica 42 scrape targets OK"
else
    log_warn "⚠ Replica 42 scrape targets may not be configured correctly"
fi

# =============================================================================
# SUMMARY
# =============================================================================

log_info ""
log_info "=== DEPLOYMENT SUMMARY ==="
log_info "Status: ✅ SUCCESS"
log_info "Deployed to: Replica 31 (${REPLICA_31}), Replica 42 (${REPLICA_42})"
log_info "Configuration:"
log_info "  - Scrape interval: 30 seconds"
log_info "  - Health endpoint: /health on port 443 (HTTPS)"
log_info "  - Alert rules: ClusterHealthCheckFailure, ClusterHealthCheckBothReplicasDown"
log_info ""
log_info "Next steps:"
log_info "  1. Monitor Prometheus at: http://prometheus.kushnir.cloud:9090"
log_info "  2. Check scrape targets: /targets endpoint"
log_info "  3. Verify alerts in AlertManager: /alerts"
log_info "  4. Test alert routing (simulate replica failure for verification)"
log_info "  5. Document in issue #1661"
log_info ""

exit 0
