#!/usr/bin/env bash
# @file        scripts/ops/verify-deployment-state.sh
# @module      ops/deployment
# @description Verify the deployment state across all cluster replicas
# @owner       platform
# @status      active
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"
init_repo

################################################################################
# CONFIGURATION
################################################################################

REPLICAS="${REPLICAS:-${DEPLOY_HOST},${STANDBY_HOST}}"
DEPLOY_USER="${DEPLOY_USER:-akushnir}"

################################################################################
# VERIFICATION LOGIC
################################################################################

verify_replica_state() {
    local replica="$1"
    
    log_info "🔍 Verifying state on $replica..."
    
    # 1. Check if git is clean and on latest
    local git_status
    git_status=$(ssh "$DEPLOY_USER@$replica" "cd code-server-enterprise && git status --short" 2>/dev/null)
    if [[ -n "$git_status" ]]; then
        log_warn "⚠️  Uncommitted changes detected on $replica"
    else
        log_info "✅ Git working directory is clean on $replica"
    fi
    
    # 2. Check docker compose status
    local container_count
    container_count=$(ssh "$DEPLOY_USER@$replica" "cd code-server-enterprise && docker compose ps --format json | grep -c 'running'" 2>/dev/null || echo "0")
    log_info "✅ $container_count containers running on $replica"
    
    # 3. Check disk space
    local disk_usage
    disk_usage=$(ssh "$DEPLOY_USER@$replica" "df -h / | tail -n 1 | awk '{print \$5}'")
    log_info "📊 Root disk usage on $replica: $disk_usage"
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Cluster Deployment State Verification"
    
    local replica_array
    IFS=',' read -ra replica_array <<< "$REPLICAS"
    
    for replica in "${replica_array[@]}"; do
        verify_replica_state "$replica"
    done
    
    log_info "✅ Cluster state verification complete"
}

main "$@"
