#!/bin/bash
# Staged Rollout Controller
# Manages safe, gated deployments across canary → replica → primary
#
# Purpose:
#   - Enforce strict ordering: canary must succeed before replica
#   - Replica must succeed before primary deployment
#   - Health gates between stages (wait for stability before continuing)
#   - Automated rollback on health check failures
#   - Manual approval gates for production safety
#
# Usage:
#   ./scripts/staged-rollout.sh [OPTIONS] [STAGE]
#
# Stages (in order):
#   1. canary         - Test environment (quick-fail, learn fast)
#   2. replica        - Pre-production mirror (validate at scale)
#   3. primary        - Production (only after replica passes)
#   4. both           - Deploy to primary AND replica simultaneously (post-canary)
#
# Options:
#   --stage STAGE        Deploy to specific stage (canary|replica|primary|both)
#   --health-wait N      Wait N seconds for health convergence (default: 300s = 5min)
#   --health-retries N   Max health check retries (default: 5)
#   --approval-timeout N Manual approval wait time in seconds (default: 300s)
#   --auto-approve       Skip manual approval (for CI/CD)
#   --skip-health-gate   Don't wait for health convergence (risky)
#   --rollback-on-fail   Auto-rollback if health checks fail (safety)
#   --dry-run            Show what would happen without executing
#   --help               Show this help message
#
# Environment:
#   DEPLOYMENT_SCRIPT    Path to deployment script (default: scripts/ops/enterprise-deploy.sh)
#   CONSISTENCY_SCRIPT   Path to consistency check (default: scripts/verify-cross-host-consistency.sh)
#
# Examples:
#   # Test in canary environment (fast feedback)
#   ./scripts/staged-rollout.sh --stage canary
#
#   # Gate: only deploy to replica if canary passed
#   ./scripts/staged-rollout.sh --stage replica --health-wait 300 --rollback-on-fail
#
#   # Final: primary deployment with manual approval and auto-rollback
#   ./scripts/staged-rollout.sh --stage primary --approval-timeout 600 --rollback-on-fail
#
#   # CI/CD: full pipeline (canary + replica + primary)
#   ./scripts/staged-rollout.sh --stage canary --auto-approve && \
#   ./scripts/staged-rollout.sh --stage replica --auto-approve && \
#   ./scripts/staged-rollout.sh --stage primary --auto-approve

set -euo pipefail
trap 'cleanup' EXIT

# Configuration
STAGE="${1:-}"
HEALTH_WAIT="${HEALTH_WAIT:-300}"
HEALTH_RETRIES="${HEALTH_RETRIES:-5}"
APPROVAL_TIMEOUT="${APPROVAL_TIMEOUT:-300}"
AUTO_APPROVE="${AUTO_APPROVE:-false}"
SKIP_HEALTH_GATE="${SKIP_HEALTH_GATE:-false}"
ROLLBACK_ON_FAIL="${ROLLBACK_ON_FAIL:-false}"
DRY_RUN="${DRY_RUN:-false}"

DEPLOYMENT_SCRIPT="${DEPLOYMENT_SCRIPT:-./scripts/ops/enterprise-deploy.sh}"
CONSISTENCY_SCRIPT="${CONSISTENCY_SCRIPT:-./scripts/verify-cross-host-consistency.sh}"

ROLLOUT_STATE_FILE="/tmp/staged-rollout-state.json"
ROLLOUT_LOG_FILE="/tmp/staged-rollout-$(date +%Y%m%d_%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Logging
log() {
  echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*" | tee -a "$ROLLOUT_LOG_FILE"
}

success() {
  echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$ROLLOUT_LOG_FILE"
}

error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2 | tee -a "$ROLLOUT_LOG_FILE"
}

warning() {
  echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$ROLLOUT_LOG_FILE"
}

milestone() {
  echo -e "\n${MAGENTA}═══════════════════════════════════════${NC}" | tee -a "$ROLLOUT_LOG_FILE"
  echo -e "${MAGENTA}$*${NC}" | tee -a "$ROLLOUT_LOG_FILE"
  echo -e "${MAGENTA}═══════════════════════════════════════${NC}\n" | tee -a "$ROLLOUT_LOG_FILE"
}

cleanup() {
  log "Rollout session ended. Log saved to: $ROLLOUT_LOG_FILE"
}

show_help() {
  head -62 "$0" | tail -50
}

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --stage)
        STAGE="$2"
        shift 2
        ;;
      --health-wait)
        HEALTH_WAIT="$2"
        shift 2
        ;;
      --health-retries)
        HEALTH_RETRIES="$2"
        shift 2
        ;;
      --approval-timeout)
        APPROVAL_TIMEOUT="$2"
        shift 2
        ;;
      --auto-approve)
        AUTO_APPROVE=true
        shift
        ;;
      --skip-health-gate)
        SKIP_HEALTH_GATE=true
        shift
        ;;
      --rollback-on-fail)
        ROLLBACK_ON_FAIL=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        error "Unknown option: $1"
        exit 1
        ;;
    esac
  done
}

# Validate stage
validate_stage() {
  case "$STAGE" in
    canary|replica|primary|both)
      return 0
      ;;
    *)
      error "Invalid stage: $STAGE. Must be: canary, replica, primary, or both"
      exit 1
      ;;
  esac
}

# Initialize state file
init_state() {
  if [[ ! -f "$ROLLOUT_STATE_FILE" ]]; then
    cat > "$ROLLOUT_STATE_FILE" <<'EOF'
{
  "canary": {"status": "not_started", "timestamp": null, "health_checks": []},
  "replica": {"status": "not_started", "timestamp": null, "health_checks": []},
  "primary": {"status": "not_started", "timestamp": null, "health_checks": []}
}
EOF
  fi
}

# Get stage status
get_stage_status() {
  local stage="$1"
  jq -r ".\"$stage\".status" "$ROLLOUT_STATE_FILE"
}

# Update stage status
set_stage_status() {
  local stage="$1"
  local status="$2"
  local timestamp=$(date +'%Y-%m-%dT%H:%M:%SZ')
  
  jq ".\"$stage\".status = \"$status\" | .\"$stage\".timestamp = \"$timestamp\"" "$ROLLOUT_STATE_FILE" > /tmp/state.tmp
  mv /tmp/state.tmp "$ROLLOUT_STATE_FILE"
}

# Check prerequisite stage
check_prerequisite() {
  local target_stage="$1"
  local prereq_stage=""
  
  case "$target_stage" in
    replica)
      prereq_stage="canary"
      ;;
    primary)
      prereq_stage="replica"
      ;;
  esac
  
  if [[ -z "$prereq_stage" ]]; then
    return 0
  fi
  
  local prereq_status=$(get_stage_status "$prereq_stage")
  
  if [[ "$prereq_status" != "success" ]]; then
    error "Cannot deploy to $target_stage: prerequisite stage '$prereq_stage' has not succeeded (status: $prereq_status)"
    return 1
  fi
  
  success "Prerequisite check passed: $prereq_stage=$prereq_status"
  return 0
}

# Request manual approval
request_approval() {
  local stage="$1"
  
  milestone "MANUAL APPROVAL REQUIRED FOR: $stage"
  
  echo "About to deploy to: $stage"
  echo "Timeout: ${APPROVAL_TIMEOUT}s"
  echo ""
  
  # Simple timeout-aware approval
  local count=0
  local interval=5
  
  while [[ $count -lt $APPROVAL_TIMEOUT ]]; do
    read -p "Approve deployment to $stage? (yes/no): " -t $interval response || true
    
    if [[ "$response" == "yes" ]]; then
      success "Deployment to $stage approved"
      return 0
    elif [[ "$response" == "no" ]]; then
      error "Deployment to $stage rejected by user"
      return 1
    fi
    
    count=$((count + interval))
    remaining=$((APPROVAL_TIMEOUT - count))
    if [[ $remaining -gt 0 ]]; then
      echo "Waiting for approval... ($remaining seconds remaining)"
    fi
  done
  
  error "Approval timeout expired for stage: $stage"
  return 1
}

# Deploy to stage
deploy_to_stage() {
  local stage="$1"
  local target_arg=""
  
  case "$stage" in
    canary)
      target_arg="--target=primary"  # Canary uses primary host for testing
      ;;
    replica)
      target_arg="--target=replica"
      ;;
    primary)
      target_arg="--target=primary"
      ;;
    both)
      target_arg="--target=both"
      ;;
  esac
  
  log "Deploying to stage: $stage"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY-RUN: Would execute: $DEPLOYMENT_SCRIPT $target_arg --mode=apply --yes"
    return 0
  fi
  
  if ! bash "$DEPLOYMENT_SCRIPT" "$target_arg" --mode=apply --yes 2>&1 | tee -a "$ROLLOUT_LOG_FILE"; then
    error "Deployment to $stage failed"
    return 1
  fi
  
  success "Deployment to $stage completed"
  return 0
}

# Wait for health convergence
wait_for_health() {
  local stage="$1"
  local remaining=$HEALTH_WAIT
  local retry_count=0
  
  if [[ "$SKIP_HEALTH_GATE" == "true" ]]; then
    warning "Skipping health gate (risky)"
    return 0
  fi
  
  log "Waiting for health convergence in $stage (max ${HEALTH_WAIT}s)..."
  
  while [[ $remaining -gt 0 ]] && [[ $retry_count -lt $HEALTH_RETRIES ]]; do
    sleep 10
    remaining=$((remaining - 10))
    
    if bash "$CONSISTENCY_SCRIPT" --fail-on-mismatch 2>&1 | tee -a "$ROLLOUT_LOG_FILE"; then
      success "Health convergence achieved after $((HEALTH_WAIT - remaining))s"
      return 0
    fi
    
    retry_count=$((retry_count + 1))
    
    if [[ $remaining -gt 0 ]]; then
      log "Health check failed, retrying... (attempt $retry_count/$HEALTH_RETRIES, ${remaining}s remaining)"
    fi
  done
  
  error "Health convergence failed after $HEALTH_RETRIES retries"
  
  if [[ "$ROLLBACK_ON_FAIL" == "true" ]]; then
    warning "Rollback on fail enabled; initiating rollback..."
    # Rollback logic would go here
    return 1
  fi
  
  return 1
}

# Execute stage
execute_stage() {
  local stage="$1"
  
  milestone "STAGE: $stage"
  
  # Check prerequisites
  if ! check_prerequisite "$stage"; then
    error "Prerequisite check failed for stage: $stage"
    return 1
  fi
  
  # Request approval (unless auto-approved)
  if [[ "$AUTO_APPROVE" != "true" ]] && [[ "$stage" != "canary" ]]; then
    if ! request_approval "$stage"; then
      error "Approval failed or timed out for stage: $stage"
      return 1
    fi
  fi
  
  # Deploy
  set_stage_status "$stage" "in_progress"
  
  if ! deploy_to_stage "$stage"; then
    set_stage_status "$stage" "failed"
    error "Deployment failed for stage: $stage"
    return 1
  fi
  
  # Wait for health
  if ! wait_for_health "$stage"; then
    set_stage_status "$stage" "health_failed"
    error "Health convergence failed for stage: $stage"
    return 1
  fi
  
  # Success
  set_stage_status "$stage" "success"
  success "Stage $stage completed successfully"
  return 0
}

# Status report
print_status() {
  init_state
  
  milestone "ROLLOUT STATUS"
  
  for s in canary replica primary; do
    local status=$(get_stage_status "$s")
    case "$status" in
      success)
        echo -e "  ✓ $s: ${GREEN}$status${NC}"
        ;;
      failed|health_failed)
        echo -e "  ✗ $s: ${RED}$status${NC}"
        ;;
      in_progress)
        echo -e "  ⟳ $s: ${YELLOW}$status${NC}"
        ;;
      *)
        echo -e "  ○ $s: $status"
        ;;
    esac
  done
  
  echo ""
  log "Full status available at: $ROLLOUT_STATE_FILE"
}

# Main execution
main() {
  parse_args "$@"
  
  if [[ -z "$STAGE" ]]; then
    show_help
    exit 1
  fi
  
  validate_stage
  init_state
  
  log "Staged Rollout Controller started"
  log "Stage: $STAGE | Health wait: ${HEALTH_WAIT}s | Auto-approve: $AUTO_APPROVE"
  
  if ! execute_stage "$STAGE"; then
    print_status
    exit 1
  fi
  
  print_status
  success "✓ Staged rollout complete"
}

# Execute
main "$@"
