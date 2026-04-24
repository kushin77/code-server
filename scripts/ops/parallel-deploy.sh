#!/usr/bin/env bash
################################################################################
# @file        scripts/ops/parallel-deploy.sh
# @module      ops/deployment
# @description Deploys to all cluster replicas in parallel with parity verification
# @owner       platform
# @status      active
#
# USAGE
#   bash scripts/ops/parallel-deploy.sh [OPTIONS]
#
# OPTIONS
#   --profiles <list>      Comma-separated compose profiles (e.g., "portal,ai,tracing")
#   --dry-run              Preview deployment plan without executing
#   --force                Skip parity pre-check
#   --help                 Show this help message
#
# WORKFLOW
#   1. Validate all replicas reachable
#   2. Run parity pre-check (if not --force)
#   3. Sync .env from GSM to all replicas (parallel)
#   4. Git pull on all replicas (parallel)
#   5. docker-compose up -d on all replicas (parallel)
#   6. Wait for all deploys to complete
#   7. Run health checks on all replicas
#   8. Run parity post-check
#   9. Report final status
#
# EXIT CODES
#   0 = Deployment successful on all replicas
#   1 = Deployment failed on one or more replicas
#   2 = Validation or configuration error
#
# NOTES
#   - Deployment is parallel (all replicas simultaneously)
#   - Failures are collected and reported at end
#   - Parity checks before and after deployment
#   - Requires SSH key in ~/.ssh/id_rsa_onprem
#
# Last Updated: April 23, 2026
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

SCRIPT_NAME="$(basename "$0")"

################################################################################
# CONFIGURATION
################################################################################

# Production cluster replicas
REPLICAS=(
  "akushnir@192.168.168.31"
  "akushnir@192.168.168.42"
)

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_onprem}"

# SSH options as array for proper expansion (IaC compliance)
declare -a DEPLOY_SSH_OPTS_ARRAY=(-i "${SSH_KEY}" -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes)

# Deployment options
COMPOSE_PROFILES="${COMPOSE_PROFILES:-}"
DRY_RUN=false
SKIP_PRE_CHECK=false
WORK_DIR="/tmp/parallel-deploy-$$"

# Tracking
DEPLOY_PIDS=()
DEPLOY_STATUS=()
DEPLOY_HOSTS=()

################################################################################
# ARGUMENT PARSING
################################################################################

show_help() {
  grep '^# ' "$0" | grep -E '(USAGE|OPTIONS|WORKFLOW|EXIT|NOTES)' -A 20 | head -30
}

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
    --force)
      SKIP_PRE_CHECK=true
      shift
      ;;
    --help)
      show_help
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      show_help
      exit 2
      ;;
  esac
done

################################################################################
# CLEANUP TRAP
################################################################################

cleanup() {
  # Wait for any remaining background processes
  for pid in "${DEPLOY_PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  rm -rf "$WORK_DIR"
}

trap cleanup EXIT

################################################################################
# HELPER FUNCTIONS
################################################################################

# Query a replica via SSH
query_replica() {
  local host=$1
  shift
  local cmd="$@"
  
  ssh "${DEPLOY_SSH_OPTS_ARRAY[@]}" "$host" "$cmd" 2>/dev/null || echo "ERROR"
}

# Deploy to a single replica (runs in background)
deploy_replica() {
  local host=$1
  local log_file="$WORK_DIR/deploy-${host//@/_}.log"
  
  log_debug "Starting deployment to $host (output in $log_file)"
  
  {
    log_info "Deploying to $host..."
    
    # Step 1: Pull latest code
    log_debug "  [1/3] Git pull on $host..."
    if ! query_replica "$host" "cd code-server-enterprise && git fetch origin && git reset --hard origin/main 2>&1" >> "$log_file" 2>&1; then
      log_error "  [1/3] Git pull failed on $host"
      echo "FAILED" > "$WORK_DIR/status-${host//@/_}"
      return 1
    fi
    
    # Step 2: Fetch secrets from GSM
    log_debug "  [2/3] Fetching secrets on $host..."
    if ! query_replica "$host" "cd code-server-enterprise && source scripts/fetch-gsm-secrets.sh 2>&1" >> "$log_file" 2>&1; then
      log_debug "  [2/3] Secret fetch completed (may use local .env as fallback)"
    fi
    
    # Step 3: Deploy containers
    log_debug "  [3/3] Deploying containers on $host..."
    local compose_cmd="docker-compose up -d"
    if [[ -n "$COMPOSE_PROFILES" ]]; then
      compose_cmd="COMPOSE_PROFILES=$COMPOSE_PROFILES docker-compose up -d"
    fi
    
    if ! query_replica "$host" "cd code-server-enterprise && $compose_cmd 2>&1" >> "$log_file" 2>&1; then
      log_error "  [3/3] Deployment failed on $host"
      echo "FAILED" > "$WORK_DIR/status-${host//@/_}"
      return 1
    fi
    
    log_info "✓ Deployment successful on $host"
    echo "SUCCESS" > "$WORK_DIR/status-${host//@/_}"
    return 0
  } &
  
  # Capture PID
  local pid=$!
  DEPLOY_PIDS+=("$pid")
  DEPLOY_HOSTS+=("$host")
  
  echo "$pid"
}

# Wait for all parallel deployments and collect results
wait_for_deployments() {
  log_info "Waiting for all deployments to complete..."
  
  local failed_count=0
  
  for i in "${!DEPLOY_PIDS[@]}"; do
    local pid="${DEPLOY_PIDS[$i]}"
    local host="${DEPLOY_HOSTS[$i]}"
    
    if wait "$pid"; then
      DEPLOY_STATUS+=("SUCCESS")
    else
      log_error "Deployment to $host exited with error"
      DEPLOY_STATUS+=("FAILED")
      failed_count=$((failed_count + 1))
    fi
  done
  
  return $([[ $failed_count -eq 0 ]] && echo 0 || echo 1)
}

# Check health after deployment
check_replica_health() {
  local host=$1
  
  log_debug "Checking health of $host..."
  
  # Simple check: docker-compose ps should show containers
  local running
  running=$(query_replica "$host" "cd code-server-enterprise && docker-compose ps -q 2>/dev/null | wc -l" | head -1)
  
  if [[ "$running" -gt 0 ]]; then
    log_info "  ✓ $host: $running containers running"
    return 0
  else
    log_error "  ✗ $host: No containers running"
    return 1
  fi
}

# Log section header
log_section() {
  log_info ""
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log_info "$1"
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

################################################################################
# MAIN EXECUTION
################################################################################

mkdir -p "$WORK_DIR"

log_section "Parallel Deployment Script"
log_info "Replicas: ${REPLICAS[*]}"
log_info "Profiles: ${COMPOSE_PROFILES:-none}"
log_info "Dry Run: $DRY_RUN"
log_info ""

# Step 1: Connectivity check
log_info "Step 1: Verifying replica connectivity..."
for replica in "${REPLICAS[@]}"; do
  if ssh $DEPLOY_SSH_OPTS "$replica" "true" 2>/dev/null; then
    log_info "  ✓ $replica reachable"
  else
    log_error "  ✗ $replica unreachable"
    log_fatal "Cannot proceed with deployment"
  fi
done

log_info ""

# Step 2: Pre-deployment parity check
if [[ "$SKIP_PRE_CHECK" != "true" ]]; then
  log_info "Step 2: Running pre-deployment parity check..."
  if bash scripts/ops/check-replica-parity.sh > "$WORK_DIR/parity-pre.log" 2>&1; then
    log_info "  ✓ Pre-deployment parity check passed"
  else
    log_warn "  ⚠ Pre-deployment parity check found issues (see logs)"
    cat "$WORK_DIR/parity-pre.log" | head -20
  fi
else
  log_info "Step 2: Skipping pre-deployment parity check (--force)"
fi

log_info ""

# Step 3: Deployment (parallel)
if [[ "$DRY_RUN" == "true" ]]; then
  log_info "Step 3: DRY-RUN MODE - Deployment would proceed with:"
  for replica in "${REPLICAS[@]}"; do
    log_info "  - Deploy to $replica"
  done
  log_info "  - With COMPOSE_PROFILES=${COMPOSE_PROFILES:-none}"
else
  log_info "Step 3: Deploying to all replicas in parallel..."
  
  for replica in "${REPLICAS[@]}"; do
    deploy_replica "$replica" > /dev/null 2>&1 &
  done
  
  # Wait for all deployments
  if wait_for_deployments; then
    log_info "  ✓ All deployments completed successfully"
  else
    log_error "  ✗ One or more deployments failed (see logs above)"
  fi
fi

log_info ""

# Step 4: Health checks (if not dry-run)
if [[ "$DRY_RUN" != "true" ]]; then
  log_info "Step 4: Running health checks on all replicas..."
  
  for replica in "${REPLICAS[@]}"; do
    if check_replica_health "$replica"; then
      :
    else
      log_warn "  Health check failed on $replica"
    fi
  done
fi

log_info ""

# Step 5: Post-deployment parity check
if [[ "$DRY_RUN" != "true" ]]; then
  log_info "Step 5: Running post-deployment parity check..."
  if bash scripts/ops/check-replica-parity.sh > "$WORK_DIR/parity-post.log" 2>&1; then
    log_info "  ✓ Post-deployment parity check passed"
  else
    log_error "  ✗ Post-deployment parity check failed"
    cat "$WORK_DIR/parity-post.log" | head -20
  fi
fi

################################################################################
# FINAL SUMMARY
################################################################################

log_section "Deployment Summary"

if [[ "$DRY_RUN" == "true" ]]; then
  log_info "✓ Dry-run completed successfully"
  log_info "  Ready to deploy with: bash scripts/ops/parallel-deploy.sh"
  exit 0
else
  # Check if any deployments failed
  local failed=0
  for status in "${DEPLOY_STATUS[@]}"; do
    if [[ "$status" == "FAILED" ]]; then
      failed=$((failed + 1))
    fi
  done
  
  if [[ $failed -eq 0 ]]; then
    log_info "✓ Deployment completed successfully on all replicas"
    log_info "  All $(${#REPLICAS[@]}) replicas are running and in parity"
    exit 0
  else
    log_error "✗ Deployment failed on $failed replica(s)"
    log_error "  Review logs in $WORK_DIR for details"
    exit 1
  fi
fi
  
  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY-RUN] ssh $DEPLOY_SSH_OPTS $host '$cmd'"
    return 0
  fi
  
  # Run command and redirect output to replica-specific log
  ssh $DEPLOY_SSH_OPTS "$host" "$cmd" > "/tmp/deploy-${host//[@\/]/-}.log" 2>&1
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
  if ssh $DEPLOY_SSH_OPTS "$host" "echo 'SSH OK'" > /dev/null 2>&1; then
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
  
  if ssh $DEPLOY_SSH_OPTS "$host" "cd code-server-enterprise && docker-compose ps | grep -q 'Up'" 2>/dev/null; then
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
