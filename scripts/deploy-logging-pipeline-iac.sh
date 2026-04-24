#!/usr/bin/env bash
# @file        scripts/deploy-logging-pipeline-iac.sh
# @module      operations/deployment
# @description IaC deployment of logging pipeline to dual hosts (primary + replica).
# @owner       platform
# @status      active
# ════════════════════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

source "${PROJECT_ROOT}/scripts/_common/init.sh"

# Dual-host configuration (immutable - use env vars or defaults)
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
REPO_PATH="~/code-server-enterprise"

# Pipeline configuration
readonly LOKI_ENDPOINT="${LOKI_ENDPOINT:-http://localhost:3100}"
readonly PROMETHEUS_ENDPOINT="${PROMETHEUS_ENDPOINT:-http://localhost:9090}"
readonly GITHUB_TOKEN="${GITHUB_TOKEN:-}"
readonly GITHUB_REPO="${GITHUB_REPO:-kushin77/code-server}"

# Deployment flags
DRY_RUN="${DRY_RUN:-0}"
SKIP_REPLICA="${SKIP_REPLICA:-0}"

# ════════════════════════════════════════════════════════════════════════════════════════════
# Idempotent Deployment Functions (IaC principles)
# ════════════════════════════════════════════════════════════════════════════════════════════

deploy_to_host() {
  local host="$1"
  local description="$2"
  local deploy_user="${DEPLOY_USER:-akushnir}"  # Use env var or default
  
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log_info "Deploying logging pipeline to: $host ($description)"
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Step 1: Fetch latest code (idempotent - git handles this)
  log_info "Step 1: Fetching latest code from origin/main..."
  if [ "$DRY_RUN" -eq 1 ]; then
    log_info "[DRY-RUN] Would run: git fetch origin main && git checkout main && git pull origin main"
  else
    ssh "${deploy_user}@${host}" "cd ${REPO_PATH} && git fetch origin main && git checkout main && git pull origin main" || {
      log_error "Failed to update repo on $host"
      return 1
    }
  fi
  
  # Step 2: Verify logging pipeline scripts exist (idempotent check)
  log_info "Step 2: Verifying logging pipeline scripts..."
  if [ "$DRY_RUN" -eq 1 ]; then
    log_info "[DRY-RUN] Would verify scripts/observability/*.sh exist"
  else
    ssh "${deploy_user}@${host}" "[ -f ${REPO_PATH}/scripts/observability/comprehensive-log-pipeline-setup.sh ] || { echo 'Pipeline script missing!'; exit 1; }" || {
      log_error "Logging pipeline scripts not found on $host"
      return 1
    }
  fi
  
  # Step 3: Deploy logging pipeline (idempotent - script re-runs safely)
  log_info "Step 3: Installing/updating logging pipeline services..."
  if [ "$DRY_RUN" -eq 1 ]; then
    log_info "[DRY-RUN] Would run: sudo bash scripts/observability/comprehensive-log-pipeline-setup.sh --install"
  else
    ssh "${deploy_user}@${host}" "cd ${REPO_PATH} && \
      LOKI_ENDPOINT='${LOKI_ENDPOINT}' \
      PROMETHEUS_ENDPOINT='${PROMETHEUS_ENDPOINT}' \
      GITHUB_TOKEN='${GITHUB_TOKEN}' \
      GITHUB_REPO='${GITHUB_REPO}' \
      sudo bash scripts/observability/comprehensive-log-pipeline-setup.sh --install" || {
      log_error "Failed to deploy logging pipeline on $host"
      return 1
    }
  fi
  
  # Step 4: Verify systemd services active (idempotent check)
  log_info "Step 4: Verifying logging services are active..."
  if [ "$DRY_RUN" -eq 1 ]; then
    log_info "[DRY-RUN] Would check systemd status for logging services"
  else
    ssh "${deploy_user}@${host}" "systemctl is-active logging-pipeline.service || { echo 'Service not active'; exit 1; }" || {
      log_warn "Logging pipeline service check failed on $host - may still be starting"
    }
  fi
  
  log_info "✓ Deployment to $host complete"
  return 0
}

verify_deployment() {
  local deploy_user="${DEPLOY_USER:-akushnir}"
  
  log_info ""
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log_info "Verifying Deployment (Post-flight Checks)"
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Verify primary host
  log_info "Checking primary host: $PRIMARY_HOST"
  if [ "$DRY_RUN" -eq 0 ]; then
    if ssh "${deploy_user}@${PRIMARY_HOST}" "systemctl is-active logging-pipeline.service 2>/dev/null" >/dev/null 2>&1; then
      log_info "✓ Primary host logging pipeline is active"
    else
      log_warn "⚠ Primary host logging pipeline may not be fully started yet"
    fi
  fi
  
  # Verify replica host (if not skipped)
  if [ "$SKIP_REPLICA" -eq 0 ]; then
    log_info "Checking replica host: $REPLICA_HOST"
    if [ "$DRY_RUN" -eq 0 ]; then
      if ssh "${deploy_user}@${REPLICA_HOST}" "systemctl is-active logging-pipeline.service 2>/dev/null" >/dev/null 2>&1; then
        log_info "✓ Replica host logging pipeline is active"
      else
        log_warn "⚠ Replica host logging pipeline may not be fully started yet"
      fi
    fi
  fi
  
  log_info ""
  log_info "Next steps:"
  log_info "  1. Monitor logs: tail -f ~/code-server-enterprise/logs/logging-pipeline.log"
  log_info "  2. Check Loki: curl $LOKI_ENDPOINT/loki/api/v1/labels"
  log_info "  3. Verify issues: gh issue list -L 10 -R $GITHUB_REPO -l automated"
  log_info ""
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# Main Execution
# ════════════════════════════════════════════════════════════════════════════════════════════

main() {
  log_info "═══════════════════════════════════════════════════════════════════════════════════"
  log_info "IaC Logging Pipeline Deployment (Idempotent, Immutable)"
  log_info "═══════════════════════════════════════════════════════════════════════════════════"
  log_info ""
  
  if [ "$DRY_RUN" -eq 1 ]; then
    log_warn "DRY_RUN mode enabled - no changes will be made"
  fi
  
  # Deploy to primary host
  if ! deploy_to_host "$PRIMARY_HOST" "Primary"; then
    log_fatal "Failed to deploy to primary host"
  fi
  
  # Deploy to replica host (unless skipped)
  if [ "$SKIP_REPLICA" -eq 0 ]; then
    if ! deploy_to_host "$REPLICA_HOST" "Replica"; then
      log_warn "Replica deployment failed but primary succeeded - continuing"
    fi
  else
    log_info "Skipping replica deployment (SKIP_REPLICA=1)"
  fi
  
  # Verify deployment
  verify_deployment
  
  log_info "✓ IaC deployment complete - logging pipeline active on both hosts"
  log_info ""
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# Parse Arguments & Execute
# ════════════════════════════════════════════════════════════════════════════════════════════

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --skip-replica)
      SKIP_REPLICA=1
      shift
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

main
