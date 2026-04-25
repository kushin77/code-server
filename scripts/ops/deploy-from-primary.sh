#!/bin/bash
################################################################################
# @file        scripts/ops/deploy-from-primary.sh
# @description Execute cluster sync deployment from primary node (no SSH needed)
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
#
# DEPLOYMENT METHOD: Execute directly on replica instead of SSH from primary
# 
# USAGE (From Primary Node 192.168.168.31):
#   # Step 1: SSH to replica
#   ssh akushnir@192.168.168.42
#
#   # Step 2: Pull deployment code
#   cd /code-server-enterprise
#
#   # Step 3: Execute deployment (this script)
#   bash scripts/ops/deploy-from-primary.sh
#
# ALTERNATIVE: Execute via single SSH command line
#   ssh akushnir@192.168.168.42 << 'EOF'
#   cd /code-server-enterprise
#   bash scripts/ops/deploy-from-primary.sh
#   EOF
#
# Or in one line:
#   ssh akushnir@192.168.168.42 'cd /code-server-enterprise && bash scripts/ops/deploy-from-primary.sh'
################################################################################

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly LOG_FILE="/var/log/cluster-sync-deployment-${TIMESTAMP}.log"
readonly BRANCH_NAME="${1:-feat/cluster-sync-fixes}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==============================================================================
# LOGGING FUNCTIONS
# ==============================================================================

log() {
  local level="$1"
  shift
  local message="$@"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  case "$level" in
    INFO)
      echo -e "${BLUE}[${timestamp}]${NC} ℹ️  $message" | tee -a "$LOG_FILE"
      ;;
    SUCCESS)
      echo -e "${GREEN}[${timestamp}]${NC} ✅ $message" | tee -a "$LOG_FILE"
      ;;
    WARN)
      echo -e "${YELLOW}[${timestamp}]${NC} ⚠️  $message" | tee -a "$LOG_FILE"
      ;;
    ERROR)
      echo -e "${RED}[${timestamp}]${NC} ❌ $message" | tee -a "$LOG_FILE"
      ;;
  esac
}

# ==============================================================================
# DEPLOYMENT PHASES
# ==============================================================================

# Phase 1: Pull Latest Code
phase_1_pull_updates() {
  log INFO "════════════════════════════════════════════════════"
  log INFO "Phase 1/5: Pulling Latest Code"
  log INFO "════════════════════════════════════════════════════"
  
  cd "$PROJECT_ROOT"
  
  log INFO "Current branch: $(git branch --show-current)"
  log INFO "Current commit: $(git rev-parse --short HEAD)"
  
  log INFO "Fetching from origin..."
  git fetch origin || {
    log ERROR "Git fetch failed"
    return 1
  }
  
  log INFO "Checking out branch: $BRANCH_NAME"
  git checkout "$BRANCH_NAME" || {
    log ERROR "Git checkout failed"
    return 1
  }
  
  log INFO "Pulling latest commits..."
  git pull origin "$BRANCH_NAME" || {
    log ERROR "Git pull failed"
    return 1
  }
  
  log SUCCESS "New commit: $(git rev-parse --short HEAD)"
  return 0
}

# Phase 2: Validate Cluster Sync
phase_2_validate_sync() {
  log INFO "════════════════════════════════════════════════════"
  log INFO "Phase 2/5: Validating Cluster Sync"
  log INFO "════════════════════════════════════════════════════"
  
  if [[ ! -f "scripts/ci/validate-cluster-sync.sh" ]]; then
    log ERROR "Validation script not found"
    return 1
  fi
  
  log INFO "Running validation checks..."
  bash scripts/ci/validate-cluster-sync.sh --verbose --report /tmp/pre-deployment-validation.json || {
    log ERROR "Validation failed"
    return 1
  }
  
  log SUCCESS "Validation passed"
  return 0
}

# Phase 3: Restart Services
phase_3_restart_services() {
  log INFO "════════════════════════════════════════════════════"
  log INFO "Phase 3/5: Restarting Services (DOWNTIME: ~2 minutes)"
  log INFO "════════════════════════════════════════════════════"
  
  cd "$PROJECT_ROOT"
  
  log WARN "Stopping all services..."
  docker compose down || {
    log WARN "Docker compose down had issues, continuing..."
  }
  
  sleep 2
  
  log INFO "Starting all services..."
  docker compose up -d || {
    log ERROR "Docker compose up failed"
    return 1
  }
  
  sleep 5
  
  log INFO "Verifying services..."
  docker compose ps || {
    log ERROR "Failed to get service status"
    return 1
  }
  
  log SUCCESS "All services restarted"
  return 0
}

# Phase 4: Install Sync Daemon
phase_4_install_daemon() {
  log INFO "════════════════════════════════════════════════════"
  log INFO "Phase 4/5: Installing Continuous Sync Daemon"
  log INFO "════════════════════════════════════════════════════"
  
  if [[ ! -f "scripts/ops/cluster-sync-daemon.sh" ]]; then
    log ERROR "Daemon script not found"
    return 1
  fi
  
  log INFO "Installing cron job..."
  bash scripts/ops/cluster-sync-daemon.sh --install-cron || {
    log ERROR "Daemon installation failed"
    return 1
  }
  
  log SUCCESS "Daemon installed"
  return 0
}

# Phase 5: Verify Deployment
phase_5_verify() {
  log INFO "════════════════════════════════════════════════════"
  log INFO "Phase 5/5: Verifying Deployment"
  log INFO "════════════════════════════════════════════════════"
  
  log INFO "Checking daemon status..."
  bash scripts/ops/cluster-sync-daemon.sh --status || {
    log WARN "Daemon status check had issues"
  }
  
  log INFO "Checking service status..."
  docker compose ps || {
    log ERROR "Service status check failed"
    return 1
  }
  
  log SUCCESS "Deployment verification complete"
  log SUCCESS ""
  log SUCCESS "🎉 CLUSTER SYNC DEPLOYMENT SUCCESSFUL 🎉"
  log SUCCESS ""
  log SUCCESS "What's Next:"
  log SUCCESS "  1. Monitor logs: tail -f /var/log/cluster-sync.log"
  log SUCCESS "  2. Verify first sync: tail -f /var/log/cluster-sync-audit.json"
  log SUCCESS "  3. Check cron: cat /etc/cron.d/cluster-sync"
  log SUCCESS ""
  log SUCCESS "Deployment log: $LOG_FILE"
  
  return 0
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
  log INFO ""
  log INFO "════════════════════════════════════════════════════"
  log INFO "CLUSTER SYNC DEPLOYMENT - DIRECT EXECUTION"
  log INFO "════════════════════════════════════════════════════"
  log INFO "Host: $(hostname)"
  log INFO "Branch: $BRANCH_NAME"
  log INFO "Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  log INFO "Log: $LOG_FILE"
  log INFO ""
  
  # Execute phases
  phase_1_pull_updates || {
    log ERROR "Phase 1 failed"
    exit 1
  }
  
  phase_2_validate_sync || {
    log ERROR "Phase 2 failed"
    exit 1
  }
  
  phase_3_restart_services || {
    log ERROR "Phase 3 failed"
    log WARN "Attempting rollback..."
    git reset --hard HEAD~1
    docker compose down && sleep 2 && docker compose up -d
    exit 1
  }
  
  phase_4_install_daemon || {
    log ERROR "Phase 4 failed"
    exit 1
  }
  
  phase_5_verify || {
    log ERROR "Phase 5 failed"
    exit 1
  }
  
  log SUCCESS "Deployment completed successfully"
  exit 0
}

main "$@"
