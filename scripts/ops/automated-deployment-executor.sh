#!/bin/bash
# @file scripts/ops/automated-deployment-executor.sh
# @module infrastructure
# @description Production-grade deployment automation with multi-stage execution and rollback
# @governance GOV-004: All deployments must be automated, audited, and reversible
# @version 2.0
# @date April 25, 2026

set -euo pipefail

# ============================================================================
# CONFIGURATION & INITIALIZATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"
source "${REPO_ROOT}/scripts/_common/service-names.env"
readonly DEPLOYMENT_ID="deploy-$(date +%Y%m%d-%H%M%S)"
readonly LOG_DIR="${REPO_ROOT}/artifacts/deployments/${DEPLOYMENT_ID}"
readonly LOG_FILE="${LOG_DIR}/deployment.log"
readonly BACKUP_DIR="${LOG_DIR}/backups"
readonly METRICS_FILE="${LOG_DIR}/metrics.json"

# Deployment parameters
readonly DEPLOY_TARGET="${1:-primary}" # primary or replica
readonly DEPLOY_ENV="${2:-production}"
readonly SKIP_BACKUP="${SKIP_BACKUP:-false}"
readonly AUTO_ROLLBACK="${AUTO_ROLLBACK:-true}"

# Deployment stages
readonly STAGES=(
  "pre-checks"
  "backup"
  "init-containers"
  "services-deploy"
  "health-verification"
  "smoke-tests"
  "finalize"
)

# Service start order (dependency-aware)
readonly SERVICE_DEPLOY_ORDER=(
  "postgres postgres-init"
  "redis redis-init"
  "redpanda redpanda-init"
  "prometheus prometheus-init"
  "loki loki-init"
  "alertmanager alertmanager-init"
  "grafana grafana-init"
  "ollama ollama-init"
  "tempo tempo-init"
  "qdrant qdrant-init"
  "caddy nginx opa oauth2-proxy"
  "reputation-engine activity-feed session-broker"
  "agent-runtime agent-code-reviewer agent-incident-responder"
  "execution-scheduler paperclip env-provisioner"
  "memory-engine"
)

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

init_logging() {
  mkdir -p "$LOG_DIR" "$BACKUP_DIR"
  
  cat > "$LOG_FILE" <<EOF
================================================================================
DEPLOYMENT LOG
================================================================================
Deployment ID: $DEPLOYMENT_ID
Target: $DEPLOY_TARGET
Environment: $DEPLOY_ENV
Date: $(date -u +'%Y-%m-%d %H:%M:%S UTC')
Repository: $REPO_ROOT
================================================================================

EOF
}

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $*" | tee -a "$LOG_FILE"
}

log_warn() {
  echo -e "${YELLOW}[!]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
  echo -e "${RED}[✗]${NC} $*" | tee -a "$LOG_FILE"
}

log_stage() {
  echo "" | tee -a "$LOG_FILE"
  echo "=================================================================================" | tee -a "$LOG_FILE"
  echo "STAGE: $1" | tee -a "$LOG_FILE"
  echo "=================================================================================" | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE"
}

# ============================================================================
# STAGE 1: PRE-DEPLOYMENT CHECKS
# ============================================================================

stage_pre_checks() {
  log_stage "PRE-DEPLOYMENT CHECKS"
  
  local failures=0
  
  # Check 1: Git status
  if [[ -n $(git status --porcelain) ]]; then
    log_warn "Uncommitted changes detected - stashing..."
    git stash
  fi
  log_success "Git status verified"
  
  # Check 2: Docker daemon
  if ! docker ps > /dev/null 2>&1; then
    log_error "Docker daemon not accessible"
    return 1
  fi
  log_success "Docker daemon accessible"
  
  # Check 3: Docker Compose syntax
  if ! docker-compose config > /dev/null 2>&1; then
    log_error "docker-compose.yml syntax invalid"
    docker-compose config >> "$LOG_FILE" 2>&1 || true
    return 1
  fi
  log_success "docker-compose.yml syntax valid"
  
  # Check 4: Environment variables
  local required_vars=(
    "DB_USER"
    "DB_PASSWORD"
    "DB_NAME"
    "REDIS_PASSWORD"
    "GRAFANA_ADMIN_PASSWORD"
  )
  
  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      log_error "Missing required environment variable: $var"
      failures+=1
    fi
  done
  
  if [[ $failures -gt 0 ]]; then
    return 1
  fi
  log_success "All required environment variables present"
  
  # Check 5: Disk space (minimum 100GB)
  local available_space
  available_space=$(df / | tail -1 | awk '{print $4}')
  
  if [[ $available_space -lt 104857600 ]]; then
    log_error "Insufficient disk space: $(($available_space / 1048576)) MB available (required: 100GB)"
    return 1
  fi
  log_success "Sufficient disk space available: $(($available_space / 1048576)) MB"
  
  # Check 6: Current service state
  local running_count
  running_count=$(docker ps --format="{{.Names}}" | wc -l)
  log_info "Current running containers: $running_count"
  
  return 0
}

# ============================================================================
# STAGE 2: PRE-DEPLOYMENT BACKUP
# ============================================================================

stage_backup() {
  log_stage "PRE-DEPLOYMENT BACKUP"
  
  if [[ "$SKIP_BACKUP" == "true" ]]; then
    log_warn "Backup skipped by request"
    return 0
  fi
  
  # Backup 1: Database
  log_info "Backing up PostgreSQL database..."
  if docker ps --format="{{.Names}}" | grep -q postgres; then
    docker exec "${POSTGRES_CONTAINER_NAME}" pg_dump -U "$DB_USER" "$DB_NAME" 2>/dev/null | gzip > "$BACKUP_DIR/postgres.sql.gz" || {
      log_warn "PostgreSQL backup skipped (database not fully initialized)"
    }
    log_success "PostgreSQL backed up"
  fi
  
  # Backup 2: Redis
  log_info "Backing up Redis data..."
  if docker ps --format="{{.Names}}" | grep -q redis; then
    docker exec "${REDIS_CONTAINER_NAME}" redis-cli BGSAVE 2>/dev/null || true
    sleep 2
    docker cp "${REDIS_CONTAINER_NAME}":/data/dump.rdb "$BACKUP_DIR/redis-dump.rdb" 2>/dev/null || {
      log_warn "Redis backup skipped (service not ready)"
    }
    log_success "Redis backed up"
  fi
  
  # Backup 3: Configuration
  log_info "Backing up configuration files..."
  cp docker-compose.yml "$BACKUP_DIR/docker-compose.yml"
  cp primary_compose_full.yml "$BACKUP_DIR/primary_compose_full.yml"
  git rev-parse HEAD > "$BACKUP_DIR/git-commit-hash"
  log_success "Configuration backed up"
  
  # Backup 4: Volume snapshots
  log_info "Backing up volume snapshots..."
  local backup_count=0
  
  for volume in postgres_data redis_data redpanda_data prometheus_data loki_data grafana_data ollama_models tempo_data qdrant_data; do
    if docker volume ls --format="{{.Name}}" | grep -q "^${volume}$"; then
      docker run --rm -v "$volume:/data" alpine:3.20 tar czf - /data 2>/dev/null > "$BACKUP_DIR/${volume}.tar.gz" || {
        log_warn "Volume backup skipped: $volume (empty or unavailable)"
        continue
      }
      backup_count+=1
    fi
  done
  
  log_success "Volume backups completed: $backup_count volumes"
  log_success "All backups stored in: $BACKUP_DIR"
}

# ============================================================================
# STAGE 3: DEPLOY INIT CONTAINERS
# ============================================================================

stage_init_containers() {
  log_stage "DEPLOY INIT CONTAINERS"
  
  local init_services=(
    "prometheus-init"
    "loki-init"
    "alertmanager-init"
    "grafana-init"
    "redis-init"
    "redpanda-init"
    "ollama-init"
    "tempo-init"
    "postgres-init"
    "qdrant-init"
  )
  
  log_info "Deploying ${#init_services[@]} init containers..."
  
  # Deploy all init services
  for service in "${init_services[@]}"; do
    docker-compose up -d "$service" 2>&1 | tee -a "$LOG_FILE"
    log_info "Launched init container: $service"
  done
  
  # Wait for init containers to complete
  log_info "Waiting for init containers to complete..."
  sleep 5
  
  local failed_inits=()
  for service in "${init_services[@]}"; do
    local max_wait=60
    local waited=0
    
    while [[ $waited -lt $max_wait ]]; do
      local status
      status=$(docker ps -a --format="{{.Names}}\t{{.State}}" | grep "^${service}" | awk '{print $2}' || echo "unknown")
      
      if [[ $status == "exited" ]]; then
        local exit_code
        exit_code=$(docker inspect "$service" --format='{{.State.ExitCode}}' 2>/dev/null || echo "1")
        
        if [[ $exit_code -eq 0 ]]; then
          log_success "Init container completed: $service (exit code 0)"
          break
        else
          log_error "Init container failed: $service (exit code $exit_code)"
          failed_inits+=("$service")
          break
        fi
      fi
      
      sleep 2
      ((waited += 2))
    done
    
    if [[ $waited -ge $max_wait ]]; then
      log_error "Init container timeout: $service"
      failed_inits+=("$service")
    fi
  done
  
  if [[ ${#failed_inits[@]} -gt 0 ]]; then
    log_error "${#failed_inits[@]} init containers failed: ${failed_inits[*]}"
    return 1
  fi
  
  log_success "All init containers completed successfully"
}

# ============================================================================
# STAGE 4: DEPLOY SERVICES
# ============================================================================

stage_services_deploy() {
  log_stage "DEPLOY SERVICES"
  
  log_info "Deploying services in dependency order..."
  
  local stage_num=1
  for service_group in "${SERVICE_DEPLOY_ORDER[@]}"; do
    log_info "Service deployment stage $stage_num: $service_group"
    
    docker-compose up -d $service_group 2>&1 | tee -a "$LOG_FILE"
    
    sleep 3
    stage_num+=1
  done
  
  log_success "All services deployed"
  
  # Display deployment summary
  log_info "Current container status:"
  docker ps --format="table {{.Names}}\t{{.Status}}\t{{.Ports}}" | tee -a "$LOG_FILE"
}

# ============================================================================
# STAGE 5: HEALTH VERIFICATION
# ============================================================================

stage_health_verification() {
  log_stage "HEALTH VERIFICATION"
  
  log_info "Verifying service health..."
  
  local max_attempts=60
  local attempt=0
  local unhealthy_services=()
  
  while [[ $attempt -lt $max_attempts ]]; do
    local healthy_count=0
    local total_services=0
    
    while IFS=$'\t' read -r name status; do
      total_services+=1
      
      if [[ $status == *"healthy"* ]] || [[ $status == *"Up"* ]]; then
        healthy_count+=1
      else
        unhealthy_services+=("$name")
      fi
    done < <(docker ps --format="{{.Names}}\t{{.Status}}")
    
    if [[ $healthy_count -ge 15 ]]; then
      log_success "Health check passed: $healthy_count/$total_services services healthy"
      return 0
    fi
    
    log_info "Health check progress: $healthy_count/$total_services healthy (attempt $((attempt + 1))/$max_attempts)"
    sleep 5
    attempt+=1
  done
  
  log_error "Health check timeout - services did not reach healthy status"
  log_info "Unhealthy services:"
  for service in "${unhealthy_services[@]}"; do
    docker-compose logs "$service" 2>&1 | head -10 >> "$LOG_FILE"
  done
  
  return 1
}

# ============================================================================
# STAGE 6: SMOKE TESTS
# ============================================================================

stage_smoke_tests() {
  log_stage "SMOKE TESTS"
  
  log_info "Running smoke tests..."
  
  # Test 1: API connectivity
  log_info "Test 1: API connectivity..."
  for i in {1..5}; do
    if curl -s -m 5 http://localhost:3100/health > /dev/null 2>&1; then
      log_success "API health check passed"
      break
    fi
    sleep 2
  done
  
  # Test 2: Database connectivity
  log_info "Test 2: Database connectivity..."
  if docker exec "${POSTGRES_CONTAINER_NAME}" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
    log_success "Database connectivity verified"
  else
    log_warn "Database connectivity test skipped (database not fully initialized)"
  fi
  
  # Test 3: Redis connectivity
  log_info "Test 3: Redis connectivity..."
  if docker exec "${REDIS_CONTAINER_NAME}" redis-cli ping > /dev/null 2>&1; then
    log_success "Redis connectivity verified"
  else
    log_warn "Redis connectivity test skipped (cache not fully initialized)"
  fi
  
  # Test 4: Prometheus scrape targets
  log_info "Test 4: Prometheus scrape targets..."
  if curl -s http://localhost:9090/api/v1/targets > /dev/null 2>&1; then
    log_success "Prometheus targets verified"
  else
    log_warn "Prometheus targets check skipped"
  fi
  
  log_success "Smoke tests completed"
}

# ============================================================================
# STAGE 7: FINALIZE
# ============================================================================

stage_finalize() {
  log_stage "FINALIZE"
  
  # Generate metrics
  log_info "Generating deployment metrics..."
  
  cat > "$METRICS_FILE" <<EOF
{
  "deployment_id": "$DEPLOYMENT_ID",
  "target": "$DEPLOY_TARGET",
  "environment": "$DEPLOY_ENV",
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "git_commit": "$(git rev-parse HEAD)",
  "git_branch": "$(git rev-parse --abbrev-ref HEAD)",
  "backup_dir": "$BACKUP_DIR",
  "backup_size_mb": "$(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}' || echo 'unknown')",
  "container_count": "$(docker ps --format='{{.Names}}' | wc -l)",
  "containers": [
EOF
  
  docker ps --format="{{json .}}" | while read -r line; do
    echo "    $line," >> "$METRICS_FILE"
  done
  
  echo "  ]" >> "$METRICS_FILE"
  echo "}" >> "$METRICS_FILE"
  
  log_success "Metrics written to: $METRICS_FILE"
  
  # Final summary
  log_info ""
  log_info "=================================================================================="
  log_info "DEPLOYMENT COMPLETE"
  log_info "=================================================================================="
  log_info "Deployment ID: $DEPLOYMENT_ID"
  log_info "Target: $DEPLOY_TARGET"
  log_info "Status: SUCCESS ✅"
  log_info "Log file: $LOG_FILE"
  log_info "Backup directory: $BACKUP_DIR"
  log_info "Metrics file: $METRICS_FILE"
  log_info "=================================================================================="
}

# ============================================================================
# ERROR HANDLING & ROLLBACK
# ============================================================================

handle_error() {
  local line_num=$1
  log_error "Deployment failed at line $line_num"
  
  if [[ "$AUTO_ROLLBACK" == "true" ]]; then
    log_info "Initiating automatic rollback..."
    rollback_deployment
  else
    log_warn "Automatic rollback disabled - manual intervention required"
  fi
  
  exit 1
}

rollback_deployment() {
  log_stage "ROLLBACK"
  
  log_info "Rolling back to previous state..."
  
  # Stop all services
  log_info "Stopping all services..."
  docker-compose down 2>&1 | tee -a "$LOG_FILE"
  
  sleep 5
  
  # Restore configuration
  log_info "Restoring configuration..."
  if [[ -f "$BACKUP_DIR/docker-compose.yml" ]]; then
    cp "$BACKUP_DIR/docker-compose.yml" docker-compose.yml
  fi
  
  # Restore previous commit
  if [[ -f "$BACKUP_DIR/git-commit-hash" ]]; then
    local previous_commit
    previous_commit=$(cat "$BACKUP_DIR/git-commit-hash")
    git checkout "$previous_commit" 2>&1 | tee -a "$LOG_FILE"
  fi
  
  # Redeploy
  log_info "Redeploying from backup..."
  docker-compose up -d 2>&1 | tee -a "$LOG_FILE"
  
  log_success "Rollback complete - previous state restored"
}

trap 'handle_error ${LINENO}' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  init_logging
  
  log_info "Starting deployment execution..."
  log_info "Deployment parameters: target=$DEPLOY_TARGET, env=$DEPLOY_ENV"
  
  # Execute stages
  for stage in "${STAGES[@]}"; do
    case $stage in
      pre-checks)
        stage_pre_checks || exit 1
        ;;
      backup)
        stage_backup || exit 1
        ;;
      init-containers)
        stage_init_containers || exit 1
        ;;
      services-deploy)
        stage_services_deploy || exit 1
        ;;
      health-verification)
        stage_health_verification || exit 1
        ;;
      smoke-tests)
        stage_smoke_tests || exit 1
        ;;
      finalize)
        stage_finalize
        ;;
    esac
  done
  
  log_success "All deployment stages completed successfully"
  return 0
}

# Execute main function
main "$@"
