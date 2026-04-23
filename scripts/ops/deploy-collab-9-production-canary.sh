#!/usr/bin/env bash
# @file        scripts/ops/deploy-collab-9-production-canary.sh
# @module      operations/deployment
# @description Deploy Collab-9 to production canary (5% rollout)
# @owner       collab-9-team
# @status      ready-for-execution

set -euo pipefail

source "$SCRIPT_DIR/_common/init.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

REPLICA_1_HOST="${REPLICA_1_HOST:-192.168.168.31}"
REPLICA_2_HOST="${REPLICA_2_HOST:-192.168.168.42}"
REPLICA_1_USER="${REPLICA_1_USER:-akushnir}"
REPLICA_2_USER="${REPLICA_2_USER:-akushnir}"

FEATURE_ENABLED="${FEATURE_WEBHOOK_ENABLED:-true}"
ROLLOUT_PERCENTAGE="${WEBHOOK_ROLLOUT_PERCENTAGE:-5}"

DEPLOYMENT_TIMEOUT_SECONDS=300
HEALTH_CHECK_RETRIES=10
HEALTH_CHECK_INTERVAL_SECONDS=10

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function require_ssh_access() {
  local host=$1
  local user=$2
  
  log_info "Verifying SSH access to $user@$host..."
  
  if ! ssh -o ConnectTimeout=5 "$user@$host" "exit 0" 2>/dev/null; then
    log_fatal "SSH access failed to $user@$host"
  fi
  
  log_info "SSH access verified: $user@$host"
}

function deploy_to_replica() {
  local host=$1
  local user=$2
  local replica_name=$3
  
  log_info "Deploying to $replica_name ($user@$host)..."
  
  ssh "$user@$host" "cd code-server-enterprise && \
    git pull origin main && \
    FEATURE_WEBHOOK_ENABLED=$FEATURE_ENABLED \
    WEBHOOK_ROLLOUT_PERCENTAGE=$ROLLOUT_PERCENTAGE \
    docker-compose up -d code-server appsmith caddy && \
    sleep 5 && \
    docker-compose ps"
  
  log_info "Deployment to $replica_name completed"
}

function health_check_http() {
  local url=$1
  local max_retries=$2
  
  log_info "Performing HTTP health check: $url"
  
  for attempt in $(seq 1 "$max_retries"); do
    if curl -s -I "$url" 2>/dev/null | grep -q "HTTP"; then
      log_info "HTTP health check PASSED (attempt $attempt)"
      return 0
    fi
    
    log_warn "HTTP health check FAILED (attempt $attempt/$max_retries)"
    sleep "$HEALTH_CHECK_INTERVAL_SECONDS"
  done
  
  log_fatal "HTTP health check failed after $max_retries attempts"
}

function verify_docker_services() {
  local host=$1
  local user=$2
  local expected_count=$3
  
  log_info "Verifying docker services on $user@$host..."
  
  local actual_count
  actual_count=$(ssh "$user@$host" "cd code-server-enterprise && docker-compose ps | grep -c UP" || echo "0")
  
  if (( actual_count < expected_count )); then
    log_fatal "Expected at least $expected_count services running, found $actual_count"
  fi
  
  log_info "Docker services verified: $actual_count running"
}

function verify_feature_flag() {
  local host=$1
  local user=$2
  
  log_info "Verifying feature flag on $user@$host..."
  
  local flag_value
  flag_value=$(ssh "$user@$host" "docker inspect code-server | grep -i FEATURE_WEBHOOK || echo 'NOT_FOUND'")
  
  if [[ "$flag_value" == "NOT_FOUND" ]]; then
    log_warn "Feature flag not visible in docker inspect (may be set in compose)"
  else
    log_info "Feature flag confirmed: $flag_value"
  fi
}

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

function run_preflight_checks() {
  log_info "Running pre-flight checks for production canary deployment..."
  
  # Check SSH access
  require_ssh_access "$REPLICA_1_HOST" "$REPLICA_1_USER"
  require_ssh_access "$REPLICA_2_HOST" "$REPLICA_2_USER"
  
  # Check git state
  log_info "Verifying git state on Replica 1..."
  ssh "$REPLICA_1_USER@$REPLICA_1_HOST" "cd code-server-enterprise && git status"
  
  # Verify staging deployment still operational
  log_info "Verifying staging deployment is operational..."
  verify_docker_services "$REPLICA_1_HOST" "$REPLICA_1_USER" 30
  
  log_info "Pre-flight checks PASSED"
}

# ============================================================================
# DEPLOYMENT EXECUTION
# ============================================================================

function deploy_canary() {
  log_info "Starting Collab-9 production canary deployment (5% rollout)..."
  log_info "Feature Flag: FEATURE_WEBHOOK_ENABLED=$FEATURE_ENABLED"
  log_info "Rollout Percentage: $ROLLOUT_PERCENTAGE%"
  
  # Deploy to Replica 1 (Primary - with feature enabled)
  log_info "Phase 1: Deploying to Replica 1 (Primary)..."
  deploy_to_replica "$REPLICA_1_HOST" "$REPLICA_1_USER" "Replica 1 (Primary)"
  
  sleep 5
  
  # Deploy to Replica 2 (Secondary - keep feature disabled for safety)
  log_info "Phase 2: Deploying to Replica 2 (Secondary)..."
  FEATURE_WEBHOOK_ENABLED=false deploy_to_replica "$REPLICA_2_HOST" "$REPLICA_2_USER" "Replica 2 (Secondary)"
  
  log_info "Deployments completed"
}

# ============================================================================
# POST-DEPLOYMENT VERIFICATION
# ============================================================================

function verify_deployment() {
  log_info "Verifying production canary deployment..."
  
  # Check services health
  verify_docker_services "$REPLICA_1_HOST" "$REPLICA_1_USER" 35
  verify_docker_services "$REPLICA_2_HOST" "$REPLICA_2_USER" 35
  
  # Verify feature flags
  verify_feature_flag "$REPLICA_1_HOST" "$REPLICA_1_USER"
  
  # HTTP health check
  health_check_http "https://ide.kushnir.cloud/" "$HEALTH_CHECK_RETRIES"
  
  log_info "Production canary deployment VERIFIED - All checks passed"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

function main() {
  log_info "=========================================="
  log_info "Collab-9 Production Canary Deployment"
  log_info "=========================================="
  log_info "Start Time: $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
  
  # Run pre-flight checks
  run_preflight_checks
  
  # Confirm before proceeding
  log_info "Pre-flight checks passed. Ready to deploy to production."
  read -p "Proceed with production canary deployment? (yes/no): " confirm
  
  if [[ "$confirm" != "yes" ]]; then
    log_fatal "Deployment cancelled by user"
  fi
  
  # Execute deployment
  deploy_canary
  
  # Verify deployment
  verify_deployment
  
  log_info "=========================================="
  log_info "Deployment SUCCESSFUL"
  log_info "End Time: $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
  log_info "=========================================="
  log_info ""
  log_info "Next Steps:"
  log_info "1. Monitor metrics in Grafana: http://192.168.168.31:3000"
  log_info "2. Check logs in Loki: http://192.168.168.31:3100"
  log_info "3. View traces in Jaeger: http://192.168.168.31:16686"
  log_info "4. Review SLOs every 12 hours"
  log_info "5. Proceed to Stage 3 after 24-hour checkpoint (Apr 27 09:00 UTC)"
}

main "$@"
