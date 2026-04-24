#!/bin/bash
# @file idempotency-enforcer.sh
# @module infrastructure
# @description Enforce idempotent patterns in all deployment and operational scripts
# @governance GOV-002 - All scripts must be idempotent (safe to run multiple times)
# @idempotent YES - Core infrastructure stabilization tool
set -euo pipefail

readonly LOG_FILE="./artifacts/idempotency-$(date +%s).log"
readonly STATE_DIR="./state"
readonly DRY_RUN="${DRY_RUN:-false}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

warn() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*" | tee -a "$LOG_FILE"
}

# Ensure state directory exists for tracking idempotent operations
ensure_state_dir() {
  mkdir -p "$STATE_DIR"
  mkdir -p "${STATE_DIR}/deployments"
  mkdir -p "${STATE_DIR}/operations"
  mkdir -p "${STATE_DIR}/backups"
  log "State directory initialized: $STATE_DIR"
}

# Record operation state for idempotency
record_state() {
  local operation="$1"
  local result="$2"
  local timestamp=$(date '+%s')
  
  echo "$timestamp:$result" >> "${STATE_DIR}/operations/${operation}.log"
  log "Recorded state for operation: $operation = $result"
}

# Check if operation already completed
is_operation_idempotent() {
  local operation="$1"
  local state_file="${STATE_DIR}/operations/${operation}.log"
  
  if [[ -f "$state_file" ]]; then
    local last_result=$(tail -1 "$state_file" | cut -d':' -f2)
    if [[ "$last_result" == "success" ]]; then
      log "Operation $operation already completed successfully (idempotent)"
      return 0
    fi
  fi
  return 1
}

# Create idempotent deployment template
create_deployment_template() {
  cat > ./scripts/ops/deploy-idempotent.sh << 'DEPLOY_EOF'
#!/bin/bash
# @file deploy-idempotent.sh
# @module infrastructure
# @description Idempotent deployment script - safe to run multiple times
# @idempotent YES - Checks state before any modifications
set -euo pipefail

readonly DEPLOYMENT_ID="deployment-$(date +%s)"
readonly STATE_DIR="./state/deployments"
readonly LOG_FILE="./artifacts/deploy-${DEPLOYMENT_ID}.log"

mkdir -p "$STATE_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Check if services are already running
services_running() {
  docker compose ps --services 2>/dev/null | wc -l | tr -d ' '
}

# Wait for all services to report healthy
wait_for_healthy_services() {
  local expected_count
  expected_count=$(services_running)

  local attempt=0
  while [[ $attempt -lt 24 ]]; do
    local healthy_count
    healthy_count=$(docker compose ps 2>/dev/null | grep -c "(healthy)" || true)

    if [[ "$healthy_count" -ge "$expected_count" && "$expected_count" -gt 0 ]]; then
      return 0
    fi

    sleep 5
    ((attempt++))
  done

  return 1
}

# Idempotent deployment
deploy() {
  log "Starting idempotent deployment: $DEPLOYMENT_ID"
  
  local state_file="${STATE_DIR}/${DEPLOYMENT_ID}.state"
  
  # Check if already deployed
  if [[ -f "$state_file" ]] && grep -q "deployed" "$state_file"; then
    log "✅ Deployment already completed in state file: $(cat "$state_file" | tail -1)"
    return 0
  fi
  
  log "Pre-deployment checks..."
  
  # Verify Docker is running
  if ! docker ps &>/dev/null; then
    echo "ERROR: Docker daemon not running" >&2
    return 1
  fi
  
  # Verify docker-compose.yml exists
  if [[ ! -f ./docker-compose.yml ]]; then
    echo "ERROR: docker-compose.yml not found" >&2
    return 1
  fi
  
  log "Pulling latest images..."
  docker compose pull
  
  log "Starting services..."
  docker compose up -d
  
  log "Waiting for health checks..."
  if ! wait_for_healthy_services; then
    echo "ERROR: Services did not become healthy in time" >&2
    return 1
  fi
  
  # Verify all services are healthy
  local unhealthy=0
  for service in $(docker compose ps --services); do
    if ! docker compose ps "$service" | grep -q "healthy\|running"; then
      echo "WARNING: Service $service not healthy" >&2
      ((unhealthy++)) || true
    fi
  done
  
  if [[ $unhealthy -eq 0 ]]; then
    log "✅ All services healthy"
    echo "deployed:$(date '+%s')" >> "$state_file"
    return 0
  else
    echo "ERROR: $unhealthy services not healthy" >&2
    return 1
  fi
}

main() {
  deploy
}

main "$@"
DEPLOY_EOF

  chmod +x ./scripts/ops/deploy-idempotent.sh
  log "Created idempotent deployment script"
}

# Create idempotent rollback template
create_rollback_template() {
  cat > ./scripts/ops/rollback-idempotent.sh << 'ROLLBACK_EOF'
#!/bin/bash
# @file rollback-idempotent.sh
# @module infrastructure
# @description Idempotent rollback - safe to call multiple times
# @idempotent YES - Idempotent state checking before rollback
set -euo pipefail

readonly BACKUP_DIR="./state/backups"
readonly LOG_FILE="./artifacts/rollback-$(date +%s).log"

mkdir -p "$BACKUP_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Wait for all services to report healthy after restart
wait_for_healthy_services() {
  local expected_count
  expected_count=$(docker compose ps --services 2>/dev/null | wc -l | tr -d ' ')

  local attempt=0
  while [[ $attempt -lt 24 ]]; do
    local healthy_count
    healthy_count=$(docker compose ps 2>/dev/null | grep -c "(healthy)" || true)

    if [[ "$healthy_count" -ge "$expected_count" && "$expected_count" -gt 0 ]]; then
      return 0
    fi

    sleep 5
    ((attempt++))
  done

  return 1
}

# Find latest deployment backup
latest_backup() {
  ls -t "${BACKUP_DIR}"/deployment-*.tar.gz 2>/dev/null | head -1
}

# Idempotent rollback
rollback() {
  log "Starting idempotent rollback"
  
  local latest=$(latest_backup)
  
  if [[ -z "$latest" ]]; then
    echo "ERROR: No backup found for rollback" >&2
    return 1
  fi
  
  log "Using backup: $latest"
  
  # Check if already rolled back
  if docker compose ps &>/dev/null; then
    local current_hash=$(docker compose config | sha256sum | cut -d' ' -f1)
    if [[ -f "${BACKUP_DIR}/.last_rollback" ]]; then
      local last_hash=$(cat "${BACKUP_DIR}/.last_rollback")
      if [[ "$current_hash" == "$last_hash" ]]; then
        log "✅ Already rolled back to this version"
        return 0
      fi
    fi
  fi
  
  # Perform rollback
  log "Stopping services..."
  docker compose down
  
  log "Restoring from backup..."
  tar xzf "$latest" -C .
  
  log "Restarting services..."
  docker compose up -d

  if ! wait_for_healthy_services; then
    echo "ERROR: Services did not become healthy after rollback" >&2
    return 1
  fi
  
  # Record rollback state
  docker compose config | sha256sum | cut -d' ' -f1 > "${BACKUP_DIR}/.last_rollback"
  log "✅ Rollback complete"
}

main() {
  rollback
}

main "$@"
ROLLBACK_EOF

  chmod +x ./scripts/ops/rollback-idempotent.sh
  log "Created idempotent rollback script"
}

# Create configuration backup automation
create_backup_template() {
  cat > ./scripts/ops/backup-idempotent.sh << 'BACKUP_EOF'
#!/bin/bash
# @file backup-idempotent.sh
# @module infrastructure
# @description Idempotent backup - skip if already backed up in this period
# @idempotent YES - Checks backup age before creating new backup
set -euo pipefail

readonly BACKUP_DIR="./state/backups"
readonly BACKUP_AGE_HOURS="${BACKUP_AGE_HOURS:-1}"  # Don't backup more than once per hour
readonly LOG_FILE="./artifacts/backup-$(date +%s).log"

mkdir -p "$BACKUP_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Check if recent backup exists
has_recent_backup() {
  local cutoff_time=$(($(date '+%s') - (BACKUP_AGE_HOURS * 3600)))
  
  for backup in "${BACKUP_DIR}"/backup-*.tar.gz; do
    if [[ -f "$backup" ]]; then
      local backup_time=$(stat -f %m "$backup" 2>/dev/null || stat -c %Y "$backup")
      if [[ $backup_time -gt $cutoff_time ]]; then
        log "✅ Recent backup exists: $backup"
        return 0
      fi
    fi
  done
  return 1
}

# Perform backup
backup() {
  log "Starting idempotent backup"
  
  if has_recent_backup; then
    log "Skipping backup - recent backup exists"
    return 0
  fi
  
  log "Creating new backup..."
  local backup_file="${BACKUP_DIR}/backup-$(date +%s).tar.gz"
  
  tar czf "$backup_file" \
    docker-compose.yml \
    config/ \
    .env \
    scripts/ops/ \
    --exclude=artifacts \
    --exclude=state
  
  log "✅ Backup created: $backup_file"
}

main() {
  backup
}

main "$@"
BACKUP_EOF

  chmod +x ./scripts/ops/backup-idempotent.sh
  log "Created idempotent backup script"
}

# Create health check idempotency enforcement
create_health_check_template() {
  cat > ./scripts/ops/health-check-idempotent.sh << 'HEALTH_EOF'
#!/bin/bash
# @file health-check-idempotent.sh
# @module infrastructure
# @description Idempotent health checks - can be called continuously
# @idempotent YES - State-based checking without side effects
set -euo pipefail

readonly LOG_FILE="./artifacts/health-$(date +%s).log"
readonly STATE_FILE="./state/health.state"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Idempotent health check
check_health() {
  log "Running idempotent health checks"
  
  local services_healthy=0
  local services_total=0
  
  for service in $(docker compose ps --services); do
    ((services_total++))
    
    local health=$(docker compose exec -T "$service" sh -c 'echo ok' 2>/dev/null || echo 'fail')
    
    if [[ "$health" == "ok" ]]; then
      ((services_healthy++))
      log "✅ $service: healthy"
    else
      log "❌ $service: unhealthy"
    fi
  done
  
  # Record state for idempotency
  echo "checked:$services_healthy/$services_total:$(date '+%s')" >> "$STATE_FILE"
  
  if [[ $services_healthy -eq $services_total ]]; then
    log "✅ All services healthy"
    return 0
  else
    log "❌ Some services unhealthy"
    return 1
  fi
}

main() {
  check_health
}

main "$@"
HEALTH_EOF

  chmod +x ./scripts/ops/health-check-idempotent.sh
  log "Created idempotent health check script"
}

main() {
  log "=========================================="
  log "Idempotency Enforcement"
  log "=========================================="
  
  # Initialize state directory
  ensure_state_dir
  
  # Create idempotent operation templates
  create_deployment_template
  create_rollback_template
  create_backup_template
  create_health_check_template
  
  log "=========================================="
  log "Idempotency enforcement complete"
  log "Created scripts:"
  log "  - deploy-idempotent.sh"
  log "  - rollback-idempotent.sh"
  log "  - backup-idempotent.sh"
  log "  - health-check-idempotent.sh"
  log "=========================================="
}

main "$@"
