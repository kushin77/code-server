#!/usr/bin/env bash
# @file        scripts/ops/parallel-deploy.sh
# @module      ops/deployment
# @description Deploy to all cluster replicas in parallel with parity verification
#
# USAGE:
#   bash scripts/ops/parallel-deploy.sh [--profiles PROFILE1,PROFILE2] [--dry-run]
#
# EXAMPLES:
#   # Deploy all services to both replicas
#   bash scripts/ops/parallel-deploy.sh
#
#   # Deploy with portal profile enabled
#   bash scripts/ops/parallel-deploy.sh --profiles portal
#
#   # Dry run (show what would be deployed)
#   bash scripts/ops/parallel-deploy.sh --dry-run
#
# WORKFLOW:
#   1. Validate all replicas reachable via SSH
#   2. Run pre-deploy parity check (find divergence before deploy)
#   3. Sync .env from GSM to all replicas (parallel SSH)
#   4. Pull latest code from origin/main (parallel SSH)
#   5. Pull latest container images (parallel SSH)
#   6. Run docker-compose up -d (parallel SSH)
#   7. Wait for all deploys to complete
#   8. Run health checks on all replicas
#   9. Run post-deploy parity check
#   10. Report per-replica status
#
# PREREQUISITES:
#   - SSH key: ~/.ssh/id_rsa_onprem (configured with ssh-agent or expect)
#   - Both replicas SSH-accessible and responsive
#   - code-server-enterprise repo cloned on both replicas
#   - GSM access for .env sync (gcloud cli configured)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

REPLICAS=(
  "akushnir@192.168.168.31:code-server-enterprise"
  "akushnir@192.168.168.42:code-server-enterprise"
)

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_onprem}"
# Note: SSH_OPTS may be set by init.sh; only set if not already defined
if [[ -z "${SSH_OPTS:-}" ]]; then
  SSH_OPTS="-i ${SSH_KEY} -o ConnectTimeout=10 -o StrictHostKeyChecking=no"
fi
COMPOSE_PROFILES="all"
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profiles)
      COMPOSE_PROFILES="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      log_warn "Unknown argument: $1"
      shift
      ;;
  esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

# Extract host and path from "user@host:path" format
parse_replica() {
  local replica=$1
  echo "${replica%:*}"  # Return user@host part
}

get_replica_path() {
  local replica=$1
  echo "${replica#*:}"  # Return path part (after colon)
}

# Run command on replica via SSH
run_on_replica() {
  local replica=$1
  shift
  local host=$(parse_replica "$replica")
  local cmd="$@"
  
  log_info "Deploying to $host..."
  
  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY-RUN] ssh $SSH_OPTS $host '$cmd'"
    return 0
  fi
  
  # Run command and redirect output to replica-specific log
  ssh $SSH_OPTS "$host" "$cmd" > "/tmp/deploy-${host//[@\/]/-}.log" 2>&1
}

# ─────────────────────────────────────────────────────────────────────────────
# Validation Phase
# ─────────────────────────────────────────────────────────────────────────────

log_section "PHASE 0: Validation & Prerequisites"

# Check SSH key exists
if [[ ! -f "$SSH_KEY" ]]; then
  log_fatal "SSH key not found: $SSH_KEY"
  exit 1
fi
log_info "✅ SSH key found: $SSH_KEY"

# Verify all replicas reachable
log_info "Testing SSH connectivity to all replicas..."
for replica in "${REPLICAS[@]}"; do
  host=$(parse_replica "$replica")
  if ssh $SSH_OPTS "$host" "echo 'SSH OK'" > /dev/null 2>&1; then
    log_info "✅ $host reachable"
  else
    log_fatal "$host not reachable. Check network and SSH key."
    exit 1
  fi
done

# Check if parity check script exists
if [[ -f "scripts/ops/check-replica-parity.sh" ]]; then
  log_info "✅ Parity check script available"
else
  log_warn "⚠ Parity check script not found (optional)"
fi

log_info "✅ All prerequisites met"

# ─────────────────────────────────────────────────────────────────────────────
# Pre-Deploy Parity Check
# ─────────────────────────────────────────────────────────────────────────────

log_section "PHASE 1: Pre-Deploy Parity Check"

if [[ -f "scripts/ops/check-replica-parity.sh" ]]; then
  if bash scripts/ops/check-replica-parity.sh --pre-deploy; then
    log_info "✅ Pre-deploy parity check passed"
  else
    log_warn "⚠ Parity issues detected (continuing deploy)"
  fi
else
  log_info "⊘ Skipping parity check (script not available)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Parallel Deployment
# ─────────────────────────────────────────────────────────────────────────────

log_section "PHASE 2: Parallel Deployment to All Replicas"

# Deploy to all replicas in parallel
log_info "Starting parallel deployments..."
declare -A pids
for replica in "${REPLICAS[@]}"; do
  host=$(parse_replica "$replica")
  ip_addr="${host#*@}"  # Extract IP from akushnir@192.168.168.XX
  
  # Replica 2 needs port override to work around kernel-level port 80 phantom binding (#1641)
  if [[ "$ip_addr" == "192.168.168.42" ]]; then
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.replica.yml -f docker-compose.replica-port-override.yml"
    log_info "→ Using port override for Replica 2 (#1641 workaround)"
  else
    COMPOSE_FILES="-f docker-compose.yml"
  fi
  
  # Build deployment command for this replica
  DEPLOY_CMD="
    cd code-server-enterprise
    set -euo pipefail
    
    # Fetch latest .env from GSM (if available)
    if [[ -f scripts/fetch-gsm-secrets.sh ]]; then
      source scripts/fetch-gsm-secrets.sh || log_warn 'GSM secrets failed'
    fi
    
    # Pull latest code
    git fetch origin main
    git checkout main
    git pull origin main
    
    # Pull latest images
    COMPOSE_PROFILES='${COMPOSE_PROFILES}' docker-compose ${COMPOSE_FILES} pull
    
    # Deploy services
    COMPOSE_PROFILES='${COMPOSE_PROFILES}' docker-compose ${COMPOSE_FILES} up -d
  "
  
  run_on_replica "$replica" "$DEPLOY_CMD" &
  pids["$host"]=$!
  log_info "→ $host deployment started (PID ${pids[$host]})"
done

# Wait for all deployments to complete
log_info "Waiting for all deployments to complete..."
deploy_failed=0
for host in "${!pids[@]}"; do
  pid=${pids[$host]}
  if wait $pid 2>/dev/null; then
    log_info "✅ $host deployment completed successfully"
  else
    log_error "❌ $host deployment failed (PID $pid)"
    if [[ -f "/tmp/deploy-${host//[@\/]/-}.log" ]]; then
      log_error "Last 10 lines of $host deployment log:"
      tail -10 "/tmp/deploy-${host//[@\/]/-}.log" | sed 's/^/  /'
    fi
    deploy_failed=$((deploy_failed + 1))
  fi
done

if [[ $deploy_failed -gt 0 ]]; then
  log_fatal "$deploy_failed replica deployment(s) failed"
  exit 1
fi

log_info "✅ All replicas deployed successfully"

# ─────────────────────────────────────────────────────────────────────────────
# Health Check Phase
# ─────────────────────────────────────────────────────────────────────────────

log_section "PHASE 3: Health Checks"

health_check_failed=0
for replica in "${REPLICAS[@]}"; do
  host=$(parse_replica "$replica")
  log_info "Checking health on $host..."
  
  if ssh $SSH_OPTS "$host" "cd code-server-enterprise && docker-compose ps | grep -q 'Up'" 2>/dev/null; then
    log_info "✅ $host services healthy"
  else
    log_error "❌ $host services not healthy"
    health_check_failed=$((health_check_failed + 1))
  fi
done

if [[ $health_check_failed -gt 0 ]]; then
  log_error "$health_check_failed replica health check(s) failed"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Post-Deploy Parity Check
# ─────────────────────────────────────────────────────────────────────────────

log_section "PHASE 4: Post-Deploy Parity Check"

if [[ -f "scripts/ops/check-replica-parity.sh" ]]; then
  if bash scripts/ops/check-replica-parity.sh --post-deploy; then
    log_info "✅ Post-deploy parity check passed"
  else
    log_error "❌ Post-deploy parity issues detected"
  fi
else
  log_info "⊘ Skipping parity check (script not available)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

log_section "DEPLOYMENT SUMMARY"

if [[ "$DRY_RUN" == true ]]; then
  log_info "DRY-RUN MODE: No actual deployment performed"
fi

log_info "Deployment completed:"
for replica in "${REPLICAS[@]}"; do
  host=$(parse_replica "$replica")
  if [[ $deploy_failed -eq 0 ]]; then
    log_info "  ✅ $host"
  else
    log_info "  ⚠️  $host (check logs above)"
  fi
done

if [[ $deploy_failed -eq 0 && $health_check_failed -eq 0 ]]; then
  log_info "✅ Parallel deployment completed successfully"
  exit 0
else
  log_error "❌ Deployment completed with issues"
  exit 1
fi
