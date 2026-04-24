#!/usr/bin/env bash
# @file        scripts/ops/redeploy-with-gh-tracking.sh
# @module      ops/deployment
# @description Cluster redeploy with GitHub API tracking and status comments
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

REPLICAS="${REPLICAS:-${REPLICA_1_IP:-},${REPLICA_2_IP:-}}"
DEPLOY_USER="${DEPLOY_USER:-${SSH_USER:-}}"
REPO="kushin77/code-server"
ISSUE_NUMBER="${1:-}"

if [[ -z "$REPLICAS" || "$REPLICAS" == "," ]]; then
    log_fatal "Set REPLICAS or REPLICA_1_IP/REPLICA_2_IP"
fi

if [[ -z "$DEPLOY_USER" ]]; then
    log_fatal "Set DEPLOY_USER or SSH_USER"
fi

if [[ -z "$ISSUE_NUMBER" ]]; then
    log_fatal "Usage: $0 <issue_number>"
fi

################################################################################
# TRACKING LOGIC
################################################################################

post_gh_comment() {
    local body="$1"
    gh issue comment "$ISSUE_NUMBER" --repo "$REPO" --body "$body" || log_warn "Failed to post GH comment"
}

redeploy_with_tracking() {
    local replica="$1"
    
    log_info "🚀 Redeploying node $replica with GitHub tracking..."
    
    if ssh "$DEPLOY_USER@$replica" "cd code-server-enterprise && docker compose pull && docker compose up -d"; then
        log_info "✅ Node $replica deployment successful"
        return 0
    else
        log_error "✗ Node $replica deployment failed"
        return 1
    fi
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Starting Tracked Cluster Redeployment for Issue #$ISSUE_NUMBER"
    post_gh_comment "🚀 Starting cluster-wide deployment for issue #$ISSUE_NUMBER across $REPLICAS"
    
    local replica_array
    IFS=',' read -ra replica_array <<< "$REPLICAS"
    
    local fails=0
    for replica in "${replica_array[@]}"; do
        redeploy_with_tracking "$replica" || ((fails++))
    done
    
    if [[ $fails -eq 0 ]]; then
        log_info "✅ All nodes redeployed successfully"
        post_gh_comment "✅ Cluster deployment completed successfully for issue #$ISSUE_NUMBER"
    else
        log_error "✗ Deployment failed on $fails nodes"
        post_gh_comment "❌ Cluster deployment FAILED on $fails nodes for issue #$ISSUE_NUMBER"
        exit 1
    fi
}

main "$@"
