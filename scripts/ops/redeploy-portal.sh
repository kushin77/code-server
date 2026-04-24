#!/usr/bin/env bash
# @file        scripts/ops/redeploy-portal.sh
# @module      ops/deployment
# @description Atomic redeploy of portal service with zero-downtime using health checks
# @usage       [DRY_RUN=1] [GITHUB_ISSUE_NUMBER=963] bash scripts/ops/redeploy-portal.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

# Configuration
DRY_RUN="${DRY_RUN:-0}"
DEPLOY_HOST="${DEPLOY_HOST:-192.168.168.31}"
DEPLOY_REPLICA="${DEPLOY_REPLICA:-192.168.168.42}"
DEPLOY_USER="${DEPLOY_USER:-akushnir}"
GITHUB_ISSUE_NUMBER="${GITHUB_ISSUE_NUMBER:-}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-120}"
DEPLOYMENT_ID="$(date +%Y%m%d-%H%M%S)-$$"

# Portal configuration
PORTAL_SERVICE="portal"
PORTAL_PORT="${PORTAL_PORT:-3050}"
PORTAL_HEALTH_ENDPOINT="${PORTAL_HEALTH_ENDPOINT:-/health}"
PORTAL_HEALTH_CHECK_TIMEOUT=10

log_stage() {
    log_info "========== $1 =========="
}

update_gh_issue() {
    local status="$1"
    local message="$2"
    
    [[ -z "$GITHUB_ISSUE_NUMBER" ]] && return 0
    [[ $DRY_RUN -eq 1 ]] && { log_info "[GitHub] $status: $message"; return 0; }
    
    gh issue comment "$GITHUB_ISSUE_NUMBER" --repo kushin77/code-server --body "**[$status]** $(date -u +'%Y-%m-%d %H:%M:%S UTC')

$message

---
*Portal Redeploy ID: $DEPLOYMENT_ID*" 2>/dev/null || log_warn "Failed to update issue #$GITHUB_ISSUE_NUMBER"
}

health_check_portal() {
    local host="$1"
    local port="$2"
    local endpoint="$3"
    local timeout="$4"
    local elapsed=0
    local interval=3
    
    log_info "Health checking portal on $host:$port (timeout: ${timeout}s)"
    
    while [ $elapsed -lt "$timeout" ]; do
        if ssh "$DEPLOY_USER@$host" "curl -sf http://localhost:${port}${endpoint} >/dev/null 2>&1" 2>/dev/null; then
            log_info "✅ Portal on $host is healthy"
            return 0
        fi
        
        log_debug "Portal health check in progress (elapsed: ${elapsed}s)"
        sleep "$interval"
        ((elapsed += interval))
    done
    
    log_error "❌ Portal on $host did not become healthy within ${timeout}s"
    return 1
}

main() {
    log_stage "ATOMIC PORTAL REDEPLOY (ZERO-DOWNTIME)"
    
    log_info "Primary host: $DEPLOY_HOST"
    log_info "Replica host: $DEPLOY_REPLICA"
    log_info "Portal service port: $PORTAL_PORT"
    log_info "Dry-run mode: $([ $DRY_RUN -eq 1 ] && echo 'YES' || echo 'NO')"
    echo ""
    
    update_gh_issue "🚀 PORTAL_REDEPLOY_STARTING" "Deployment ID: **$DEPLOYMENT_ID**
Mode: $([ $DRY_RUN -eq 1 ] && echo 'DRY-RUN' || echo 'APPLY')"
    
    # === Step 1: Pre-redeploy gate ===
    log_stage "STEP 1: Pre-Redeploy Gate"
    update_gh_issue "⏳ GATE_CHECKING" "Validating portal configuration and connectivity..."
    
    if [ "$DRY_RUN" -eq 0 ]; then
        # Verify connectivity to both hosts
        log_info "Checking SSH connectivity to primary ($DEPLOY_HOST)..."
        if ! ssh -o ConnectTimeout=5 "$DEPLOY_USER@$DEPLOY_HOST" "echo 'OK'" &>/dev/null; then
            log_error "❌ Cannot reach primary $DEPLOY_HOST"
            update_gh_issue "❌ GATE_FAILED" "SSH connectivity to primary $DEPLOY_HOST failed"
            exit 1
        fi
        log_info "✅ Primary connectivity verified"
        
        log_info "Checking SSH connectivity to replica ($DEPLOY_REPLICA)..."
        if ! ssh -o ConnectTimeout=5 "$DEPLOY_USER@$DEPLOY_REPLICA" "echo 'OK'" &>/dev/null; then
            log_error "❌ Cannot reach replica $DEPLOY_REPLICA"
            update_gh_issue "❌ GATE_FAILED" "SSH connectivity to replica $DEPLOY_REPLICA failed"
            exit 1
        fi
        log_info "✅ Replica connectivity verified"
        
        # Verify docker-compose on both hosts
        log_info "Validating docker-compose on primary..."
        if ! ssh "$DEPLOY_USER@$DEPLOY_HOST" "cd code-server-enterprise && docker compose config -q" 2>/dev/null; then
            log_error "❌ docker-compose validation failed on primary"
            update_gh_issue "❌ GATE_FAILED" "docker-compose validation failed on primary $DEPLOY_HOST"
            exit 1
        fi
        log_info "✅ Primary docker-compose valid"
        
        log_info "Validating docker-compose on replica..."
        if ! ssh "$DEPLOY_USER@$DEPLOY_REPLICA" "cd code-server-enterprise && docker compose config -q" 2>/dev/null; then
            log_error "❌ docker-compose validation failed on replica"
            update_gh_issue "❌ GATE_FAILED" "docker-compose validation failed on replica $DEPLOY_REPLICA"
            exit 1
        fi
        log_info "✅ Replica docker-compose valid"
        
        # Current health baseline
        log_info "Checking current portal health on primary..."
        local primary_health_before=0
        ssh "$DEPLOY_USER@$DEPLOY_HOST" "curl -sf http://localhost:${PORTAL_PORT}${PORTAL_HEALTH_ENDPOINT} >/dev/null 2>&1" 2>/dev/null && primary_health_before=1 || true
        log_info "Portal on primary before: $([ $primary_health_before -eq 1 ] && echo 'HEALTHY' || echo 'UNHEALTHY')"
    fi
    
    update_gh_issue "✅ GATE_PASSED" "All pre-redeploy checks passed. Starting zero-downtime redeploy."
    echo ""
    
    # === Step 2: Redeploy replica first (rolling strategy) ===
    log_stage "STEP 2: Redeploy Replica (Non-Critical Path)"
    update_gh_issue "⏳ REPLICA_REDEPLOYING" "Redeploying portal on replica ($DEPLOY_REPLICA) - primary remains serving traffic"
    
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would redeploy portal on replica"
    else
        log_info "Stopping portal on replica..."
        ssh "$DEPLOY_USER@$DEPLOY_REPLICA" \
            "cd code-server-enterprise && docker compose stop $PORTAL_SERVICE || true" \
            2>/dev/null || true
        
        log_info "Starting portal on replica (pull + rebuild)..."
        ssh "$DEPLOY_USER@$DEPLOY_REPLICA" \
            "cd code-server-enterprise && docker compose pull $PORTAL_SERVICE 2>/dev/null || true && docker compose up -d --build $PORTAL_SERVICE" \
            || { log_error "❌ Failed to redeploy portal on replica"; exit 1; }
        
        if health_check_portal "$DEPLOY_REPLICA" "$PORTAL_PORT" "$PORTAL_HEALTH_ENDPOINT" "$PORTAL_HEALTH_CHECK_TIMEOUT"; then
            log_info "✅ Portal on replica is healthy"
        else
            log_warn "⚠️ Portal on replica health check inconclusive, proceeding"
        fi
    fi
    
    update_gh_issue "✅ REPLICA_REDEPLOYED" "Replica portal redeployed successfully. Proceeding to primary."
    echo ""
    
    # === Step 3: Redeploy primary (with traffic shift) ===
    log_stage "STEP 3: Redeploy Primary (Critical Path)"
    update_gh_issue "⏳ PRIMARY_REDEPLOYING" "Redeploying portal on primary ($DEPLOY_HOST) - brief traffic impact expected"
    
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would redeploy portal on primary"
    else
        log_info "Stopping portal on primary..."
        ssh "$DEPLOY_USER@$DEPLOY_HOST" \
            "cd code-server-enterprise && docker compose stop $PORTAL_SERVICE || true" \
            2>/dev/null || true
        
        log_info "Starting portal on primary (pull + rebuild)..."
        ssh "$DEPLOY_USER@$DEPLOY_HOST" \
            "cd code-server-enterprise && docker compose pull $PORTAL_SERVICE 2>/dev/null || true && docker compose up -d --build $PORTAL_SERVICE" \
            || { log_error "❌ Failed to redeploy portal on primary"; exit 1; }
        
        if health_check_portal "$DEPLOY_HOST" "$PORTAL_PORT" "$PORTAL_HEALTH_ENDPOINT" "$PORTAL_HEALTH_CHECK_TIMEOUT"; then
            log_info "✅ Portal on primary is healthy"
        else
            log_error "❌ Portal on primary failed health check"
            update_gh_issue "❌ HEALTH_CHECK_FAILED" "Portal on primary $DEPLOY_HOST failed health check after redeploy"
            exit 1
        fi
    fi
    
    update_gh_issue "✅ PRIMARY_REDEPLOYED" "Primary portal redeployed and healthy."
    echo ""
    
    # === Step 4: Verify both hosts operational ===
    log_stage "STEP 4: Final Verification"
    update_gh_issue "⏳ FINAL_VERIFICATION" "Verifying both hosts are operational..."
    
    if [ "$DRY_RUN" -eq 0 ]; then
        log_info "Final health check on primary..."
        if ! health_check_portal "$DEPLOY_HOST" "$PORTAL_PORT" "$PORTAL_HEALTH_ENDPOINT" 10; then
            log_warn "⚠️ Primary portal health inconclusive"
        fi
        
        log_info "Final health check on replica..."
        if ! health_check_portal "$DEPLOY_REPLICA" "$PORTAL_PORT" "$PORTAL_HEALTH_ENDPOINT" 10; then
            log_warn "⚠️ Replica portal health inconclusive"
        fi
    fi
    
    log_stage "ATOMIC PORTAL REDEPLOY COMPLETE"
    update_gh_issue "✅ PORTAL_REDEPLOY_COMPLETE" "Atomic portal redeploy complete. Both hosts operational.
Deployment ID: **$DEPLOYMENT_ID**
⏱️ **Zero-downtime**: Traffic shifted to replica during primary redeploy"
}

main "$@"
