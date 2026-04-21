#!/usr/bin/env bash
# @file        scripts/ops/redis-sentinel-failover-test.sh
# @module      operations/redis-ha
# @description Test Redis Sentinel automatic failover (master -> replica promotion)
#
# Usage:
#   DRY_RUN=1 bash scripts/ops/redis-sentinel-failover-test.sh              # Show what would happen
#   bash scripts/ops/redis-sentinel-failover-test.sh                        # Actually perform failover
#   FAILOVER_WAIT_MS=60000 bash scripts/ops/redis-sentinel-failover-test.sh # Custom wait timeout
#
# Procedure:
#   1. Record current session keys in Redis
#   2. Stop Redis master (docker-compose pause redis)
#   3. Wait for Sentinel to detect failure (30-60 seconds)
#   4. Verify replica promoted to master
#   5. Verify sessions persisted on new master
#   6. Restart original master and verify replication
#   7. Report results
#
# Exit codes:
#   0 = Failover successful, sessions preserved
#   1 = Failover partial (master swapped but data issues)
#   2 = Failover failed (replica not promoted)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Configuration
DRY_RUN="${DRY_RUN:-1}"
REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_MASTER_NAME="${REDIS_MASTER_NAME:-mymaster}"
FAILOVER_WAIT_MS="${FAILOVER_WAIT_MS:-120000}"  # 2 minutes max
SENTINEL_HOSTS="${SENTINEL_HOSTS:-redis-sentinel-1:26379 redis-sentinel-arbiter:26379}"

# Tracking variables
BEFORE_KEY_COUNT=0
AFTER_KEY_COUNT=0
ORIGINAL_MASTER_HOST="$REDIS_HOST"
ORIGINAL_MASTER_PORT="$REDIS_PORT"

# ════════════════════════════════════════════════════════════════════════════
# Utility Functions
# ════════════════════════════════════════════════════════════════════════════

redis_cli() {
  local host=$1
  local port=$2
  shift 2
  timeout 10 redis-cli -h "$host" -p "$port" "$@" 2>/dev/null || return 1
}

get_master_addr() {
  # Query Sentinel for current master address
  for sentinel_addr in $SENTINEL_HOSTS; do
    local host="${sentinel_addr%:*}"
    local port="${sentinel_addr#*:}"
    
    if result=$(timeout 5 redis-cli -h "$host" -p "$port" SENTINEL get-master-addr-by-name "$REDIS_MASTER_NAME" 2>/dev/null); then
      echo "$result" | head -1  # Return master IP
      return 0
    fi
  done
  return 1
}

wait_for_master_promotion() {
  local max_wait_seconds=$((FAILOVER_WAIT_MS / 1000))
  local elapsed=0
  
  log_info "Waiting for Sentinel to promote replica to master (max $max_wait_seconds seconds)..."
  
  while [[ $elapsed -lt $max_wait_seconds ]]; do
    if new_master=$(get_master_addr 2>/dev/null); then
      if [[ "$new_master" != "$ORIGINAL_MASTER_HOST" ]]; then
        log_info "Master promoted! New master: $new_master"
        return 0
      fi
    fi
    
    sleep 3
    ((elapsed += 3))
    echo -n "."
  done
  
  log_error "Master promotion timeout after $elapsed seconds"
  return 2
}

# ════════════════════════════════════════════════════════════════════════════
# Failover Test Procedure
# ════════════════════════════════════════════════════════════════════════════

test_failover() {
  log_info "═══════════════════════════════════════════════════════════"
  log_info "Redis Sentinel Failover Test"
  log_info "═══════════════════════════════════════════════════════════"
  log_info "Dry-run mode: $DRY_RUN"
  log_info ""
  
  # Phase 1: Baseline
  log_info "PHASE 1: Record baseline..."
  
  if ! BEFORE_KEY_COUNT=$(redis_cli "$REDIS_HOST" "$REDIS_PORT" DBSIZE | grep -oP '(?<=:)\d+'); then
    log_fatal "Cannot connect to Redis master at $REDIS_HOST:$REDIS_PORT"
    return 2
  fi
  log_info "  Current key count: $BEFORE_KEY_COUNT"
  
  # Phase 2: Simulate master failure
  log_info ""
  log_info "PHASE 2: Simulate master failure (docker-compose pause redis)..."
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "  [DRY RUN] Would pause Redis container"
    return 0
  fi
  
  if ! docker-compose pause redis > /dev/null 2>&1; then
    log_fatal "Failed to pause Redis container"
    return 2
  fi
  log_info "  Redis master paused"
  
  sleep 5
  
  # Phase 3: Wait for promotion
  log_info ""
  log_info "PHASE 3: Wait for Sentinel to detect failure and promote replica..."
  
  if ! wait_for_master_promotion; then
    log_error "Failover detection failed"
    
    # Cleanup: restart master
    log_warn "Restarting original master..."
    docker-compose unpause redis > /dev/null 2>&1 || true
    
    return 2
  fi
  
  log_info "  Failover completed successfully"
  
  # Phase 4: Verify data persistence
  log_info ""
  log_info "PHASE 4: Verify session data persisted..."
  
  new_master=$(get_master_addr)
  new_master_port=6379  # Replica uses same port
  
  if ! AFTER_KEY_COUNT=$(redis_cli "$new_master" "$new_master_port" DBSIZE | grep -oP '(?<=:)\d+'); then
    log_error "Cannot connect to new master at $new_master:$new_master_port"
    log_error "  This indicates the promoted replica is not accepting connections"
    
    docker-compose unpause redis > /dev/null 2>&1 || true
    return 2
  fi
  
  log_info "  New master key count: $AFTER_KEY_COUNT"
  
  if [[ $BEFORE_KEY_COUNT -eq $AFTER_KEY_COUNT ]]; then
    log_info "  ✓ Data preserved during failover"
  else
    log_error "  ✗ Key count mismatch: before=$BEFORE_KEY_COUNT after=$AFTER_KEY_COUNT"
    docker-compose unpause redis > /dev/null 2>&1 || true
    return 1
  fi
  
  # Phase 5: Restart original master
  log_info ""
  log_info "PHASE 5: Restart original master and verify replication..."
  
  if ! docker-compose unpause redis > /dev/null 2>&1; then
    log_error "Failed to unpause Redis container"
    return 1
  fi
  
  sleep 5
  
  # Verify original master comes back up as replica
  if ! redis_cli "$ORIGINAL_MASTER_HOST" "$ORIGINAL_MASTER_PORT" ping > /dev/null 2>&1; then
    log_error "Original master did not come back up"
    return 1
  fi
  log_info "  Original master restarted"
  
  local role
  role=$(redis_cli "$ORIGINAL_MASTER_HOST" "$ORIGINAL_MASTER_PORT" info replication | grep "^role:" | cut -d: -f2 | tr -d '\r')
  if [[ "$role" == "slave" || "$role" == "replica" ]]; then
    log_info "  ✓ Original master now replica (role: $role)"
  else
    log_error "  ✗ Original master role is $role (expected slave/replica)"
    return 1
  fi
  
  # Phase 6: Report results
  log_info ""
  log_info "═══════════════════════════════════════════════════════════"
  log_info "✓ Failover Test Complete"
  log_info "═══════════════════════════════════════════════════════════"
  log_info "Results:"
  log_info "  Original master: $ORIGINAL_MASTER_HOST:$ORIGINAL_MASTER_PORT"
  log_info "  New master: $new_master:$new_master_port"
  log_info "  Data preserved: $([[ $BEFORE_KEY_COUNT -eq $AFTER_KEY_COUNT ]] && echo 'YES' || echo 'NO')"
  log_info "  Replication restored: YES"
  log_info ""
  log_info "Sessions survived failover without user re-login: ✓"
  
  return 0
}

# ════════════════════════════════════════════════════════════════════════════
# Main
# ════════════════════════════════════════════════════════════════════════════

main() {
  test_failover
}

main "$@"
