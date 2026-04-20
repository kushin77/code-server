#!/usr/bin/env bash
# @file        scripts/ops/redeploy-service.sh
# @module      ops/deployment
# @description Redeploy specific services (code-server, caddy, oauth2-proxy, etc.) without full IaC
# @usage       SERVICE=code-server [DRY_RUN=1] [GITHUB_ISSUE_NUMBER=963] bash scripts/ops/redeploy-service.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

# Configuration
SERVICE="${SERVICE:-}"
DRY_RUN="${DRY_RUN:-0}"
DEPLOY_HOST="${DEPLOY_HOST:-192.168.168.31}"
DEPLOY_USER="${DEPLOY_USER:-akushnir}"
GITHUB_ISSUE_NUMBER="${GITHUB_ISSUE_NUMBER:-}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-60}"
DEPLOYMENT_ID="$(date +%Y%m%d-%H%M%S)-$$"

# Allowed services
ALLOWED_SERVICES=("code-server" "caddy" "oauth2-proxy" "portal" "prometheus" "grafana" "alertmanager")

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
*Service Redeploy ID: $DEPLOYMENT_ID*" 2>/dev/null || log_warn "Failed to update issue #$GITHUB_ISSUE_NUMBER"
}

validate_service() {
    local svc="$1"
    for allowed in "${ALLOWED_SERVICES[@]}"; do
        [[ "$svc" == "$allowed" ]] && return 0
    done
    return 1
}

health_check_service() {
    local svc="$1"
    local timeout="$2"
    local elapsed=0
    local interval=5
    
    log_info "Health checking service: $svc (timeout: ${timeout}s)"
    
    while [ $elapsed -lt "$timeout" ]; do
        local status=$(ssh "$DEPLOY_USER@$DEPLOY_HOST" \
            "docker compose ps --format '{{.Names}}:{{.Status}}' 2>/dev/null | grep '^${svc}:' | cut -d: -f2" 2>/dev/null || echo "")
        
        if [[ "$status" == *"running"* ]] || [[ "$status" == *"Up"* ]]; then
            log_info "✅ Service $svc is healthy (status: $status)"
            return 0
        fi
        
        log_debug "Service $svc status: $status (elapsed: ${elapsed}s)"
        sleep "$interval"
        ((elapsed += interval))
    done
    
    log_error "❌ Service $svc did not become healthy within ${timeout}s"
    return 1
}

main() {
    log_stage "SERVICE REDEPLOY"
    
    # Validate service argument
    if [[ -z "$SERVICE" ]]; then
        log_error "SERVICE environment variable not set"
        log_info "Allowed services: ${ALLOWED_SERVICES[*]}"
        exit 1
    fi
    
    if ! validate_service "$SERVICE"; then
        log_error "Invalid service: $SERVICE"
        log_info "Allowed services: ${ALLOWED_SERVICES[*]}"
        exit 1
    fi
    
    log_info "Redeploy target: $SERVICE"
    log_info "Target host: $DEPLOY_USER@$DEPLOY_HOST"
    log_info "Dry-run mode: $([ $DRY_RUN -eq 1 ] && echo 'YES' || echo 'NO')"
    echo ""
    
    update_gh_issue "🚀 SERVICE_REDEPLOY_STARTING" "Service: **$SERVICE**
Deployment ID: **$DEPLOYMENT_ID**
Mode: $([ $DRY_RUN -eq 1 ] && echo 'DRY-RUN' || echo 'APPLY')"
    
    # === Step 1: Pre-redeploy gate ===
    log_stage "STEP 1: Pre-Redeploy Gate"
    update_gh_issue "⏳ GATE_CHECKING" "Running pre-redeploy validation checks..."
    
    if [ "$DRY_RUN" -eq 0 ]; then
        # Validate docker-compose.yml on remote host
        log_info "Validating docker-compose.yml..."
        if ! ssh "$DEPLOY_USER@$DEPLOY_HOST" "cd code-server-enterprise && docker compose config -q" 2>/dev/null; then
            log_error "❌ docker-compose.yml validation failed"
            update_gh_issue "❌ GATE_FAILED" "docker-compose.yml validation failed on $DEPLOY_HOST"
            exit 1
        fi
        log_info "✅ docker-compose.yml is valid"
        
        # Check if service is defined in compose file
        log_info "Checking if service $SERVICE is defined..."
        if ! ssh "$DEPLOY_USER@$DEPLOY_HOST" \
            "cd code-server-enterprise && docker compose config --format json 2>/dev/null | grep -q '\"$SERVICE\"'" 2>/dev/null; then
            log_error "❌ Service $SERVICE not found in docker-compose.yml"
            update_gh_issue "❌ GATE_FAILED" "Service $SERVICE not defined in docker-compose.yml"
            exit 1
        fi
        log_info "✅ Service $SERVICE is defined"
        
        # Check connectivity
        log_info "Checking SSH connectivity..."
        if ! ssh -o ConnectTimeout=5 "$DEPLOY_USER@$DEPLOY_HOST" "echo 'SSH OK'" &>/dev/null; then
            log_error "❌ Cannot reach $DEPLOY_USER@$DEPLOY_HOST"
            update_gh_issue "❌ GATE_FAILED" "SSH connectivity failed to $DEPLOY_HOST"
            exit 1
        fi
        log_info "✅ SSH connectivity verified"
    fi
    
    update_gh_issue "✅ GATE_PASSED" "All pre-redeploy checks passed."
    echo ""
    
    # === Step 2: Stop service ===
    log_stage "STEP 2: Stop Service"
    update_gh_issue "⏳ SERVICE_STOPPING" "Stopping service: $SERVICE"
    
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would stop service: $SERVICE"
    else
        log_info "Stopping service: $SERVICE..."
        ssh "$DEPLOY_USER@$DEPLOY_HOST" \
            "cd code-server-enterprise && docker compose stop $SERVICE" \
            || log_warn "Service stop returned non-zero (may be already stopped)"
        log_info "✅ Service stopped"
    fi
    echo ""
    
    # === Step 3: Rebuild and restart ===
    log_stage "STEP 3: Rebuild and Restart Service"
    update_gh_issue "⏳ SERVICE_RESTARTING" "Rebuilding and restarting service: $SERVICE"
    
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would run: docker compose up -d --build $SERVICE"
    else
        log_info "Pulling latest images and restarting service..."
        ssh "$DEPLOY_USER@$DEPLOY_HOST" \
            "cd code-server-enterprise && docker compose pull $SERVICE 2>/dev/null || true && docker compose up -d --build $SERVICE" \
            || { log_error "❌ Failed to restart service"; exit 1; }
        log_info "✅ Service started"
    fi
    echo ""
    
    # === Step 4: Health check ===
    log_stage "STEP 4: Health Check"
    update_gh_issue "⏳ HEALTH_CHECKING" "Verifying service health..."
    
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would health check: $SERVICE"
    else
        if health_check_service "$SERVICE" "$HEALTH_CHECK_TIMEOUT"; then
            update_gh_issue "✅ SERVICE_REDEPLOY_COMPLETE" "Service **$SERVICE** is healthy and operational.
Deployment ID: **$DEPLOYMENT_ID**"
            log_info "✅ Service redeploy complete"
        else
            log_error "❌ Service health check failed"
            update_gh_issue "❌ HEALTH_CHECK_FAILED" "Service **$SERVICE** failed health check after restart"
            exit 1
        fi
    fi
    
    log_stage "REDEPLOY COMPLETE"
}

main "$@"
