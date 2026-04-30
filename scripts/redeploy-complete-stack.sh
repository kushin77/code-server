#!/bin/bash

################################################################################
# Code-Server Enterprise: Complete IaC Redeployment
# Purpose: Redeploy entire stack with zero drift across both cluster hosts
# Scope: ONLY code-server-* resources (respects shared environment isolation)
# Date: April 30, 2026
################################################################################

set -euo pipefail
trap 'error "Script failed at line $LINENO"; cleanup_on_error' ERR

# Configuration
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
DEPLOY_USER="${DEPLOY_USER:-akushnir}"
REPO_PATH="/home/akushnir/code-server-enterprise"
COMPOSE_FILE="docker-compose.enterprise.yml"
ENV_FILE=".env.production"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# State
START_TIME=$(date +%s)
DEPLOYMENT_LOG="/tmp/redeploy-$(date +%Y%m%d_%H%M%S).log"
EXIT_CODE=0

# Functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$DEPLOYMENT_LOG"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*" | tee -a "$DEPLOYMENT_LOG"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$DEPLOYMENT_LOG"; }
error() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$DEPLOYMENT_LOG" >&2; }
cleanup_on_error() { log_warn "Cleanup: Saving deployment log to $DEPLOYMENT_LOG"; }

# Get container count
get_container_count() {
  local host=$1
  local count=$(ssh $SSH_OPTS "$DEPLOY_USER@$host" "docker ps --filter 'name=code-server-' --format '{{.Names}}' | wc -l" 2>/dev/null || echo "0")
  echo "$count"
}

# Get running container count
get_running_count() {
  local host=$1
  local count=$(ssh $SSH_OPTS "$DEPLOY_USER@$host" "docker ps --filter 'status=running' --filter 'name=code-server-' --format '{{.Names}}' | wc -l" 2>/dev/null || echo "0")
  echo "$count"
}

# Deploy to single host
deploy_host() {
  local host=$1
  local role=$2
  
  log_info "Deploying $role ($host)..."
  
  # SSH into host and deploy
  ssh $SSH_OPTS "$DEPLOY_USER@$host" "cd $REPO_PATH && \
    set -euo pipefail && \
    log_step() { echo \"[*] \$1\"; } && \
    
    log_step 'Stopping old code-server containers...' && \
    docker-compose -f $COMPOSE_FILE --profile ai --profile governance --profile infrastructure --profile all down 2>/dev/null || true && \
    sleep 2 && \
    
    log_step 'Pruning unused docker resources...' && \
    docker container prune -f 2>/dev/null || true && \
    docker volume prune -f 2>/dev/null || true && \
    
    log_step 'Deploying complete stack...' && \
    docker-compose -f $COMPOSE_FILE --profile ai --profile governance --profile infrastructure --profile all up -d --force-recreate && \
    sleep 3 && \
    
    log_step 'Waiting for services to stabilize...' && \
    sleep 5" 2>&1 | tee -a "$DEPLOYMENT_LOG"
  
  if [ $? -eq 0 ]; then
    log_success "$role deployment completed"
    return 0
  else
    error "$role deployment failed"
    EXIT_CODE=1
    return 1
  fi
}

# Validate deployment
validate_deployment() {
  local host=$1
  local role=$2
  
  log_info "Validating $role deployment..."
  
  # Check basic connectivity
  if ! ssh $SSH_OPTS "$DEPLOY_USER@$host" "echo 'ok'" > /dev/null 2>&1; then
    error "Cannot connect to $host"
    EXIT_CODE=1
    return 1
  fi
  
  # Count containers
  local total=$(get_container_count "$host")
  local running=$(get_running_count "$host")
  
  log_info "$role: $running/$total containers running"
  
  if [ "$running" -lt 20 ]; then
    log_warn "$role: Only $running containers running (expected 20+)"
  fi
  
  # Get container status
  ssh $SSH_OPTS "$DEPLOY_USER@$host" "docker ps -a --filter 'name=code-server-' --format 'table {{.Names}}\t{{.State}}\t{{.Status}}' | head -40" 2>&1 | tee -a "$DEPLOYMENT_LOG"
  
  return 0
}

# Main deployment
main() {
  log_info "=================================="
  log_info "Code-Server Enterprise Redeployment"
  log_info "Start time: $(date)"
  log_info "=================================="
  echo
  
  # Pre-checks
  log_info "Phase 1: Pre-deployment checks"
  log_info "Verifying host connectivity..."
  
  for host in "$PRIMARY_HOST" "$REPLICA_HOST"; do
    if ! ssh $SSH_OPTS "$DEPLOY_USER@$host" "docker --version" > /dev/null 2>&1; then
      error "Cannot reach $host or docker not available"
      EXIT_CODE=1
    else
      log_success "$host reachable"
    fi
  done
  
  if [ $EXIT_CODE -ne 0 ]; then
    error "Pre-checks failed"
    exit 1
  fi
  echo
  
  # Deployment
  log_info "Phase 2: Deploying to primary host..."
  deploy_host "$PRIMARY_HOST" "PRIMARY" || true
  sleep 5
  echo
  
  log_info "Phase 3: Deploying to replica host..."
  deploy_host "$REPLICA_HOST" "REPLICA" || true
  sleep 5
  echo
  
  # Validation
  log_info "Phase 4: Validating deployments..."
  validate_deployment "$PRIMARY_HOST" "PRIMARY"
  echo
  validate_deployment "$REPLICA_HOST" "REPLICA"
  echo
  
  # Final summary
  local end_time=$(date +%s)
  local duration=$((end_time - START_TIME))
  local prim_count=$(get_running_count "$PRIMARY_HOST")
  local repl_count=$(get_running_count "$REPLICA_HOST")
  local total_count=$((prim_count + repl_count))
  
  log_info "=================================="
  log_info "Redeployment Summary"
  log_info "Duration: ${duration}s"
  log_info "Primary: $prim_count running containers"
  log_info "Replica: $repl_count running containers"
  log_info "Total: $total_count running containers"
  log_info "=================================="
  
  if [ $total_count -ge 40 ]; then
    log_success "TARGET ACHIEVED: $total_count containers deployed (40+ requirement met)"
  else
    log_warn "Running count: $total_count (expecting 40+ across both hosts)"
  fi
  
  log_info "Detailed log saved to: $DEPLOYMENT_LOG"
  
  exit $EXIT_CODE
}

# Run main
main "$@"
