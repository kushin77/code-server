#!/usr/bin/env bash
# @file        scripts/ops/fix-replica-1-permissions.sh
# @module      ops/replica-sync
# @description Fix file permission issues on Replica 1 to enable git operations and deployments
# @owner       infrastructure
# @status      active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
REPLICA_HOST="${REPLICA_1_HOST:-192.168.168.31}"
# Note: DEPLOY_USER and DEPLOY_DIR are set as readonly by config.sh (via init.sh)
# We use them directly without reassigning
FIX_SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_onprem}"
FIX_SSH_OPTS="-i ${FIX_SSH_KEY} -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no"
DRY_RUN="${DRY_RUN:-0}"

log_info "Replica 1 Permission Remediation"
log_info "Host: $REPLICA_HOST"
log_info "User: $DEPLOY_USER"
log_info "Deploy dir: $DEPLOY_DIR"
log_info "Dry run: $([[ $DRY_RUN -eq 1 ]] && echo yes || echo no)"

# Verify SSH access
verify_ssh_access() {
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[dry-run] Skipping SSH verification in dry-run mode"
    return 0
  fi
  
  # SSH_OPTS is a string from config.sh with options separated by spaces
  if ! ssh $FIX_SSH_OPTS "${DEPLOY_USER}@${REPLICA_HOST}" true 2>/dev/null; then
    log_fatal "SSH access failed to ${DEPLOY_USER}@${REPLICA_HOST}"
  fi
  log_info "SSH access verified"
}

# Fix ownership recursively
fix_ownership() {
  local remote_cmd="drift_paths=\$(find \"${DEPLOY_DIR}\" -xdev \( -not -user \"${DEPLOY_USER}\" -o -not -group \"${DEPLOY_USER}\" \) -type f -print); if [[ -n \"\$drift_paths\" ]]; then while IFS= read -r path; do rel_path=\${path#\"${DEPLOY_DIR}/\"}; if git ls-files --error-unmatch -- \"\$rel_path\" >/dev/null 2>&1; then rm -f \"\$rel_path\" && git checkout -- \"\$rel_path\"; fi; done <<< \"\$drift_paths\"; fi"
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[dry-run] ssh $FIX_SSH_OPTS ${DEPLOY_USER}@${REPLICA_HOST} '$remote_cmd'"
    return 0
  fi
  
  log_info "Repairing tracked file ownership on $REPLICA_HOST..."
  if ! ssh $FIX_SSH_OPTS "${DEPLOY_USER}@${REPLICA_HOST}" "$remote_cmd"; then
    log_error "Failed to repair tracked file ownership."
    return 1
  fi
  log_info "Tracked file ownership repaired"
}

# Clean git state
clean_git_state() {
  local remote_cmd="cd ${DEPLOY_DIR} && git reset --hard origin/main"
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[dry-run] ssh $FIX_SSH_OPTS ${DEPLOY_USER}@${REPLICA_HOST} '$remote_cmd'"
    return 0
  fi
  
  log_info "Cleaning git state on $REPLICA_HOST..."
  if ! ssh $FIX_SSH_OPTS "${DEPLOY_USER}@${REPLICA_HOST}" "$remote_cmd"; then
    log_error "Git cleanup failed"
    return 1
  fi
  log_info "Git state cleaned"
}

# Pull latest and redeploy
redeploy() {
  local remote_cmd="cd ${DEPLOY_DIR} && git pull --ff-only origin main && docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d"
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[dry-run] ssh $FIX_SSH_OPTS ${DEPLOY_USER}@${REPLICA_HOST} '$remote_cmd'"
    return 0
  fi
  
  log_info "Redeploying on $REPLICA_HOST..."
  if ! ssh $FIX_SSH_OPTS "${DEPLOY_USER}@${REPLICA_HOST}" "$remote_cmd"; then
    log_error "Redeployment failed"
    return 1
  fi
  log_info "Redeployment completed"
}

# Verify git status
verify_git_status() {
  log_info "Verifying git status on $REPLICA_HOST..."
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[dry-run] Skipping verification in dry-run mode"
    return 0
  fi
  
  local commit_sha=$(ssh $FIX_SSH_OPTS "${DEPLOY_USER}@${REPLICA_HOST}" "cd ${DEPLOY_DIR} && git rev-parse --short HEAD")
  log_info "Replica 1 commit: $commit_sha"
  
  local main_sha=$(ssh $FIX_SSH_OPTS "${DEPLOY_USER}@${REPLICA_HOST}" "cd ${DEPLOY_DIR} && git rev-parse --short origin/main")
  log_info "Main branch commit: $main_sha"
  
  if [[ "$commit_sha" == "$main_sha" ]]; then
    log_info "✓ Replica 1 is synced with main"
    return 0
  else
    log_warn "Replica 1 may not be fully synced (local: $commit_sha, main: $main_sha)"
    return 1
  fi
}

# Main execution
verify_ssh_access
fix_ownership || exit 1
clean_git_state || exit 1
redeploy || exit 1
fix_ownership || exit 1
verify_git_status

log_info "Replica 1 remediation completed successfully"
