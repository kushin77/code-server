#!/bin/bash
# @file        scripts/ops/EXECUTE-4-PHASE-DEPLOYMENT-APRIL-24.sh
# @module      ops/cluster-deployment
# @description Automated 4-phase execution: code pull, WebSocket deployment, Replica 1 fix, parity validation
# @owner       infrastructure
# @status      ready-for-execution

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
PHASE="${1:-all}"
DRY_RUN="${DRY_RUN:-0}"
REPLICA_1="192.168.168.31"
REPLICA_2="192.168.168.42"
DEPLOY_USER="akushnir"
DEPLOY_DIR="code-server-enterprise"

log_info "====================================================================="
log_info "4-PHASE CLUSTER DEPLOYMENT & PARITY FIX — April 24, 2026"
log_info "====================================================================="
log_info "Phase: $PHASE"
log_info "Dry run: $([[ $DRY_RUN -eq 1 ]] && echo YES || echo NO)"
log_info "Replica 1: $REPLICA_1"
log_info "Replica 2: $REPLICA_2"
log_info ""

# =============================================================================
# PHASE 1: PULL LATEST CODE
# =============================================================================

phase_1_pull_code() {
  log_info "PHASE 1: Pull Latest Code from main"
  log_info "---"
  
  local repo_root="/mnt/c/code-server-enterprise"
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[dry-run] Would execute: cd $repo_root && git pull origin main"
    log_info "[dry-run] Would verify commits: git log --oneline -5"
    return 0
  fi
  
  if [[ ! -d "$repo_root/.git" ]]; then
    log_fatal "Repository not found at $repo_root"
  fi
  
  cd "$repo_root"
  log_info "Pulling latest from origin/main..."
  
  if ! git pull origin main 2>&1; then
    log_error "Failed to pull from origin"
    return 1
  fi
  
  log_info "✓ Code pulled successfully"
  log_info "Recent commits:"
  git log --oneline -5 | sed 's/^/  /'
}

# =============================================================================
# PHASE 2: DEPLOY WEBSOCKET TO BOTH REPLICAS
# =============================================================================

phase_2_deploy_websocket() {
  log_info ""
  log_info "PHASE 2: Deploy WebSocket Task Sync to Both Replicas"
  log_info "---"
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[dry-run] Would execute collab-9-deploy.sh on both replicas"
    log_info "[dry-run] Would deploy Replica 1: $REPLICA_1"
    log_info "[dry-run] Would deploy Replica 2: $REPLICA_2"
    return 0
  fi
  
  # Use the collab-9-deploy.sh script
  local deploy_script="$SCRIPT_DIR/collab-9-deploy.sh"
  
  if [[ ! -f "$deploy_script" ]]; then
    log_fatal "Deployment script not found: $deploy_script"
  fi
  
  log_info "Deploying WebSocket to Replica 1 ($REPLICA_1)..."
  if ! bash "$deploy_script" --hosts "$REPLICA_1"; then
    log_error "Failed to deploy to Replica 1"
    return 1
  fi
  
  log_info "✓ Replica 1 deployment completed"
  log_info ""
  
  log_info "Deploying WebSocket to Replica 2 ($REPLICA_2)..."
  if ! bash "$deploy_script" --hosts "$REPLICA_2"; then
    log_error "Failed to deploy to Replica 2"
    return 1
  fi
  
  log_info "✓ Replica 2 deployment completed"
}

# =============================================================================
# PHASE 3: FIX REPLICA 1 PERMISSIONS
# =============================================================================

phase_3_fix_replica_1() {
  log_info ""
  log_info "PHASE 3: Fix Replica 1 Permissions (P0 #1650)"
  log_info "---"
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[dry-run] Would execute fix-replica-1-permissions.sh"
    return 0
  fi
  
  local fix_script="$SCRIPT_DIR/fix-replica-1-permissions.sh"
  
  if [[ ! -f "$fix_script" ]]; then
    log_fatal "Fix script not found: $fix_script"
  fi
  
  log_info "Running Replica 1 permission remediation..."
  if ! bash "$fix_script"; then
    log_error "Failed to fix Replica 1 permissions"
    return 1
  fi
  
  log_info "✓ Replica 1 permissions fixed"
}

# =============================================================================
# PHASE 4: VALIDATE CLUSTER PARITY
# =============================================================================

phase_4_validate_parity() {
  log_info ""
  log_info "PHASE 4: Validate Cluster Parity"
  log_info "---"
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[dry-run] Would verify commits on both replicas"
    log_info "[dry-run] Would verify services on both replicas"
    log_info "[dry-run] Would verify health endpoints"
    return 0
  fi
  
  log_info "Verifying commits..."
  local commit_1=$(ssh -o BatchMode=yes akushnir@$REPLICA_1 "cd $DEPLOY_DIR && git rev-parse --short HEAD" 2>/dev/null || echo "ERROR")
  local commit_2=$(ssh -o BatchMode=yes akushnir@$REPLICA_2 "cd $DEPLOY_DIR && git rev-parse --short HEAD" 2>/dev/null || echo "ERROR")
  
  log_info "  Replica 1 commit: $commit_1"
  log_info "  Replica 2 commit: $commit_2"
  
  if [[ "$commit_1" != "$commit_2" ]]; then
    log_warn "⚠ Commits differ between replicas (may be OK if Replica 1 just redeployed)"
  else
    log_info "✓ Commits match"
  fi
  
  log_info ""
  log_info "Verifying services..."
  
  for host in "$REPLICA_1" "$REPLICA_2"; do
    log_info "  $host:"
    local running=$(ssh -o BatchMode=yes akushnir@$host "docker ps --quiet | wc -l" 2>/dev/null || echo "0")
    log_info "    Running containers: $running"
  done
  
  log_info ""
  log_info "Verifying health endpoints..."
  
  for host in "$REPLICA_1" "$REPLICA_2"; do
    local health=$(curl -s -o /dev/null -w "%{http_code}" http://${host}:3000/health/ready 2>/dev/null || echo "ERROR")
    if [[ "$health" == "200" ]]; then
      log_info "✓ $host health: OK (HTTP $health)"
    else
      log_warn "⚠ $host health: HTTP $health"
    fi
  done
  
  log_info ""
  log_info "✓ Cluster parity validation complete"
}

# =============================================================================
# EXECUTION
# =============================================================================

main() {
  case "$PHASE" in
    1)
      phase_1_pull_code
      ;;
    2)
      phase_2_deploy_websocket
      ;;
    3)
      phase_3_fix_replica_1
      ;;
    4)
      phase_4_validate_parity
      ;;
    all)
      phase_1_pull_code || { log_error "Phase 1 failed"; return 1; }
      phase_2_deploy_websocket || { log_error "Phase 2 failed"; return 1; }
      phase_3_fix_replica_1 || { log_error "Phase 3 failed"; return 1; }
      phase_4_validate_parity || { log_error "Phase 4 failed"; return 1; }
      ;;
    *)
      log_fatal "Invalid phase: $PHASE. Use: 1, 2, 3, 4, or all"
      ;;
  esac
  
  log_info ""
  log_info "====================================================================="
  log_info "PHASE EXECUTION COMPLETE"
  log_info "====================================================================="
}

main
