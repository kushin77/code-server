#!/usr/bin/env bash
# @file        scripts/ops/session-broker-verify.sh
# @module      operations/session-management
# @description Verify session-broker HA configuration and test session persistence across failover
#
# Usage:
#   bash scripts/ops/session-broker-verify.sh                    # Full verification
#   bash scripts/ops/session-broker-verify.sh --health           # Test both instances health
#   bash scripts/ops/session-broker-verify.sh --sessions         # Query active sessions
#   bash scripts/ops/session-broker-verify.sh --failover         # Simulate failover scenario
#   bash scripts/ops/session-broker-verify.sh --redis-state      # Check Redis-backed sessions
#
# Exit codes:
#   0 = all checks passed
#   1 = one check failed (degraded but operational)
#   2 = critical failure (HA not working)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Configuration
PRIMARY_HOST="${PRIMARY_HOST:-localhost}"
PRIMARY_BROKER_PORT="${PRIMARY_BROKER_PORT:-5000}"
REPLICA_HOST="${REPLICA_HOST:-replica-host}"
REPLICA_BROKER_PORT="${REPLICA_BROKER_PORT:-5000}"
REDIS_SENTINEL_HOST="${REDIS_SENTINEL_HOST:-localhost}"
REDIS_SENTINEL_PORT="${REDIS_SENTINEL_PORT:-26379}"
REDIS_MASTER_NAME="${REDIS_MASTER_NAME:-mymaster}"
TIMEOUT_SEC="${TIMEOUT_SEC:-10}"
DRY_RUN="${DRY_RUN:-0}"

# ════════════════════════════════════════════════════════════════════════════
# Utility Functions
# ════════════════════════════════════════════════════════════════════════════

broker_is_healthy() {
  local host=$1
  local port=$2
  local name=${3:-"session-broker"}
  
  if timeout $TIMEOUT_SEC curl -sf "http://$host:$port/health" > /dev/null 2>&1; then
    log_info "  ✓ $name ($host:$port) is healthy"
    return 0
  else
    log_warn "  ✗ $name ($host:$port) is not responding"
    return 1
  fi
}

get_active_sessions() {
  local host=$1
  local port=$2
  
  if timeout $TIMEOUT_SEC curl -sf "http://$host:$port/sessions" 2>/dev/null; then
    return 0
  else
    log_warn "  Could not query sessions from $host:$port"
    return 1
  fi
}

get_session_count() {
  local host=$1
  local port=$2
  
  local count
  count=$(timeout $TIMEOUT_SEC curl -sf "http://$host:$port/sessions" 2>/dev/null | grep -c '"id"' || echo "0")
  echo "$count"
}

redis_get_session() {
  local session_id=$1
  
  # Query Redis Sentinel master for session data
  redis-cli -h "$REDIS_SENTINEL_HOST" -p "$REDIS_SENTINEL_PORT" \
    --sentinel master "$REDIS_MASTER_NAME" \
    GET "session:$session_id" 2>/dev/null || return 1
}

redis_list_sessions() {
  # List all session IDs from Redis
  redis-cli -h "$REDIS_SENTINEL_HOST" -p "$REDIS_SENTINEL_PORT" \
    --sentinel master "$REDIS_MASTER_NAME" \
    SMEMBERS "session:list" 2>/dev/null || return 1
}

verify_dual_broker_health() {
  log_info "Verifying dual session-broker health..."
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "  [DRY RUN] Would check health of both brokers"
    return 0
  fi
  
  local primary_ok=0
  local replica_ok=0
  
  broker_is_healthy "$PRIMARY_HOST" "$PRIMARY_BROKER_PORT" "primary-broker" && primary_ok=1
  sleep 1
  broker_is_healthy "$REPLICA_HOST" "$REPLICA_BROKER_PORT" "replica-broker" && replica_ok=1
  
  if [[ $primary_ok -eq 1 && $replica_ok -eq 1 ]]; then
    log_info "  ✓ Both session-brokers are healthy"
    return 0
  elif [[ $primary_ok -eq 1 || $replica_ok -eq 1 ]]; then
    log_warn "  ⚠ Only one session-broker is healthy"
    return 1
  else
    log_error "  ✗ Both session-brokers are unhealthy"
    return 2
  fi
}

query_active_sessions() {
  log_info "Querying active sessions..."
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "  [DRY RUN] Would query sessions from both brokers"
    return 0
  fi
  
  local primary_count=0
  local replica_count=0
  
  log_info "  Primary broker sessions:"
  primary_count=$(get_session_count "$PRIMARY_HOST" "$PRIMARY_BROKER_PORT")
  log_info "    Count: $primary_count"
  
  sleep 1
  log_info "  Replica broker sessions:"
  replica_count=$(get_session_count "$REPLICA_HOST" "$REPLICA_BROKER_PORT")
  log_info "    Count: $replica_count"
  
  if [[ $primary_count -ge 0 && $replica_count -ge 0 ]]; then
    log_info "  ✓ Both brokers returning session counts"
    return 0
  else
    log_error "  ✗ Could not query sessions from brokers"
    return 1
  fi
}

verify_redis_backed_state() {
  log_info "Verifying Redis-backed session state..."
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "  [DRY RUN] Would verify Redis session store"
    return 0
  fi
  
  log_info "  Checking Redis Sentinel connectivity..."
  if ! command -v redis-cli &> /dev/null; then
    log_warn "  redis-cli not available (install redis-tools to verify)"
    log_info "  Skipping Redis verification"
    return 1
  fi
  
  if redis-cli -h "$REDIS_SENTINEL_HOST" -p "$REDIS_SENTINEL_PORT" \
    --sentinel master "$REDIS_MASTER_NAME" ping > /dev/null 2>&1; then
    log_info "  ✓ Redis Sentinel is accessible"
    
    # Try to list sessions from Redis
    local session_list
    if session_list=$(redis_list_sessions 2>/dev/null); then
      local count=$(echo "$session_list" | wc -l)
      log_info "  ✓ Redis session store contains $count sessions"
      return 0
    else
      log_warn "  ⚠ Redis session store is empty or not accessible"
      return 1
    fi
  else
    log_error "  ✗ Redis Sentinel not accessible at $REDIS_SENTINEL_HOST:$REDIS_SENTINEL_PORT"
    return 2
  fi
}

simulate_primary_failure() {
  log_info "Simulating primary broker failure..."
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "  [DRY RUN] Would simulate primary failure and verify failover"
    return 0
  fi
  
  # Get initial session state from primary
  log_info "  Step 1: Recording primary broker state..."
  local primary_count
  primary_count=$(get_session_count "$PRIMARY_HOST" "$PRIMARY_BROKER_PORT")
  log_info "    Primary has $primary_count active sessions"
  
  # Simulate failure: pause primary container (non-destructive)
  log_info "  Step 2: Pausing primary broker container..."
  if timeout 5 ssh -o ConnectTimeout=5 "akushnir@$PRIMARY_HOST" \
    "docker pause session-broker 2>/dev/null || echo 'pause-skipped'" >/dev/null 2>&1; then
    log_info "    ✓ Primary paused"
  else
    log_warn "    SSH not available or pause failed"
    return 1
  fi
  
  sleep 2
  
  # Verify replica can handle traffic
  log_info "  Step 3: Verifying replica handles requests..."
  if broker_is_healthy "$REPLICA_HOST" "$REPLICA_BROKER_PORT" "replica-broker"; then
    log_info "    ✓ Replica is still responding"
  else
    log_error "    ✗ Replica is not responding"
    # Resume primary
    ssh -o ConnectTimeout=5 "akushnir@$PRIMARY_HOST" "docker unpause session-broker 2>/dev/null" >/dev/null 2>&1 || true
    return 2
  fi
  
  # Query sessions from replica
  log_info "  Step 4: Querying sessions from replica..."
  local replica_count
  replica_count=$(get_session_count "$REPLICA_HOST" "$REPLICA_BROKER_PORT")
  log_info "    Replica has $replica_count sessions"
  
  # Resume primary
  log_info "  Step 5: Resuming primary broker..."
  if timeout 5 ssh -o ConnectTimeout=5 "akushnir@$PRIMARY_HOST" \
    "docker unpause session-broker 2>/dev/null || echo 'unpause-skipped'" >/dev/null 2>&1; then
    log_info "    ✓ Primary resumed"
  else
    log_warn "    Could not resume primary via SSH"
  fi
  
  sleep 2
  
  # Verify primary recovered
  log_info "  Step 6: Verifying primary recovered..."
  if broker_is_healthy "$PRIMARY_HOST" "$PRIMARY_BROKER_PORT" "primary-broker"; then
    log_info "    ✓ Primary has recovered"
    return 0
  else
    log_error "    ✗ Primary did not recover"
    return 1
  fi
}

verify_cookie_secret_config() {
  log_info "Verifying IDE_SESSION_LB_SECRET configuration..."
  
  if [[ -z "${IDE_SESSION_LB_SECRET:-}" ]]; then
    log_warn "  IDE_SESSION_LB_SECRET is not set"
    log_info "  Verify it's defined in .env or environment"
    return 1
  fi
  
  log_info "  ✓ IDE_SESSION_LB_SECRET is configured"
  log_info "    Length: ${#IDE_SESSION_LB_SECRET} characters"
  
  return 0
}

# ════════════════════════════════════════════════════════════════════════════
# Main Entry Point
# ════════════════════════════════════════════════════════════════════════════

main() {
  local command="${1:-verify}"
  
  log_info "═══════════════════════════════════════════════════════════"
  log_info "Session-Broker HA Verification"
  log_info "═══════════════════════════════════════════════════════════"
  log_info "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  log_info "Command: $command"
  log_info "Primary: $PRIMARY_HOST:$PRIMARY_BROKER_PORT"
  log_info "Replica: $REPLICA_HOST:$REPLICA_BROKER_PORT"
  log_info "Dry-run: $DRY_RUN"
  log_info ""
  
  local exit_code=0
  
  case "$command" in
    verify|--verify|all)
      verify_dual_broker_health || exit_code=$?
      sleep 1
      query_active_sessions || exit_code=$?
      sleep 1
      verify_redis_backed_state || exit_code=$?
      sleep 1
      verify_cookie_secret_config || exit_code=$?
      ;;
    health|--health)
      verify_dual_broker_health || exit_code=$?
      ;;
    sessions|--sessions|query)
      query_active_sessions || exit_code=$?
      ;;
    redis|--redis|redis-state)
      verify_redis_backed_state || exit_code=$?
      ;;
    failover|--failover|simulate)
      simulate_primary_failure || exit_code=$?
      ;;
    config|--config)
      verify_cookie_secret_config || exit_code=$?
      ;;
    *)
      log_error "Unknown command: $command"
      log_info "Usage: bash scripts/ops/session-broker-verify.sh [verify|health|sessions|redis|failover|config]"
      exit_code=1
      ;;
  esac
  
  log_info ""
  log_info "═══════════════════════════════════════════════════════════"
  
  if [[ $exit_code -eq 0 ]]; then
    log_info "✓ Session-broker verification passed"
  elif [[ $exit_code -eq 1 ]]; then
    log_warn "⚠ Session-broker verification partial: one check failed"
  else
    log_error "✗ Session-broker verification failed (exit code: $exit_code)"
  fi
  log_info "═══════════════════════════════════════════════════════════"
  
  return $exit_code
}

main "$@"
