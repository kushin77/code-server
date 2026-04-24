#!/usr/bin/env bash
# @file        scripts/ops/verify-idempotent-deployment.sh
# @module      ops/deployment
# @description Verify that redeploying results in no changes (Idempotency Check)
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

REPLICAS="${REPLICAS:-}"
SSH_USER="${SSH_USER:-${DEPLOY_USER:-}}"

if [[ -z "$REPLICAS" ]]; then
    if [[ -n "${REPLICA_1_IP:-}" && -n "${REPLICA_2_IP:-}" ]]; then
        REPLICAS="${REPLICA_1_IP},${REPLICA_2_IP}"
    else
        log_fatal "Set REPLICAS or REPLICA_1_IP/REPLICA_2_IP before running idempotency verification"
    fi
fi

if [[ -z "$SSH_USER" ]]; then
    log_fatal "Set SSH_USER or DEPLOY_USER before running idempotency verification"
fi

################################################################################
# IDEMPOTENCY CHECK
################################################################################

check_node_idempotency() {
    local replica="$1"
    
    log_info "🧪 Testing deployment idempotency on $replica..."
    
    # Run docker compose up and check for "up-to-date" signals
    local out
    out=$(ssh "$SSH_USER@$replica" "cd code-server-enterprise && docker compose up -d 2>&1")
    
    if echo "$out" | grep -v "up-to-date" | grep -E "Created|Started|Restarted" > /dev/null; then
        log_warn "⚠️  NODE $replica NOT IDEMPOTENT: Services were modified!"
        echo "$out" | log_debug
    else
        log_info "✅ NODE $replica IS IDEMPOTENT"
    fi
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Starting Cluster Idempotency Sweep"
    
    local replica_array
    IFS=',' read -ra replica_array <<< "$REPLICAS"
    
    for replica in "${replica_array[@]}"; do
        check_node_idempotency "$replica"
    done
    
    log_info "✅ Idempotency sweep complete"
}

main "$@"
