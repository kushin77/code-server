#!/usr/bin/env bash
# @file        scripts/ops/redis-sentinel-health.sh
# @module      operations/redis-ha
# @description Check Redis Sentinel HA health status and master/replica state
#
# Usage:
#   bash scripts/ops/redis-sentinel-health.sh                           # Check all sentinels and Redis
#   bash scripts/ops/redis-sentinel-health.sh -v                        # Verbose output with details
#   SENTINEL_HOSTS="sentinel-1:26379 sentinel-2:26379" bash scripts/ops/redis-sentinel-health.sh
#
# Checks:
#   - Sentinel processes running and responding to ping
#   - Redis master up and accepting connections
#   - Replication status (if replica available)
#   - Sentinel quorum status (2/3 required for promotion)
#   - Memory usage and key counts
#
# Exit codes:
#   0 = All healthy
#   1 = At least one component unhealthy
#   2 = Critical failure (no master or no quorum)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Configuration
SENTINEL_HOSTS="${SENTINEL_HOSTS:-redis-sentinel-1:26379 redis-sentinel-arbiter:26379}"
REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_MASTER_NAME="${REDIS_MASTER_NAME:-mymaster}"
VERBOSE="${VERBOSE:-0}"
TIMEOUT="${TIMEOUT:-5}"

# Status tracking
OVERALL_HEALTH=0
CRITICAL_FAILURE=0

# ════════════════════════════════════════════════════════════════════════════
# Utility Functions
# ════════════════════════════════════════════════════════════════════════════

redis_cli_cmd() {
  local host=$1
  local port=$2
  shift 2
  timeout "$TIMEOUT" redis-cli -h "$host" -p "$port" "$@" 2>/dev/null || return 1
}

log_check() {
  local status=$1
  local message=$2
  if [[ $status -eq 0 ]]; then
    log_info "✓ $message"
  else
    log_error "✗ $message"
    OVERALL_HEALTH=1
  fi
}

log_critical() {
  local message=$1
  log_fatal "✗ CRITICAL: $message"
  CRITICAL_FAILURE=1
  OVERALL_HEALTH=2
}

# ════════════════════════════════════════════════════════════════════════════
# Health Checks
# ════════════════════════════════════════════════════════════════════════════

check_redis_master() {
  log_info "Checking Redis Master ($REDIS_HOST:$REDIS_PORT)..."
  
  if ! redis_cli_cmd "$REDIS_HOST" "$REDIS_PORT" ping > /dev/null; then
    log_critical "Redis master unreachable at $REDIS_HOST:$REDIS_PORT"
    return 2
  fi
  log_check 0 "Redis master responding to ping"
  
  local info
  if ! info=$(redis_cli_cmd "$REDIS_HOST" "$REDIS_PORT" info server); then
    log_critical "Cannot fetch server info from master"
    return 2
  fi
  
  local role=$(echo "$info" | grep "^role:" | cut -d: -f2 | tr -d '\r')
  if [[ "$role" != "master" ]]; then
    log_critical "Redis role is '$role' (expected 'master')"
    return 2
  fi
  log_check 0 "Redis role is master"
  
  local version=$(echo "$info" | grep "^redis_version:" | cut -d: -f2 | tr -d '\r')
  log_info "  Redis version: $version"
  
  local connected_clients=$(redis_cli_cmd "$REDIS_HOST" "$REDIS_PORT" info clients | grep "^connected_clients:" | cut -d: -f2 | tr -d '\r')
  log_info "  Connected clients: $connected_clients"
  
  local used_memory=$(redis_cli_cmd "$REDIS_HOST" "$REDIS_PORT" info memory | grep "^used_memory_human:" | cut -d: -f2 | tr -d '\r')
  log_info "  Used memory: $used_memory"
  
  return 0
}

check_sentinel_nodes() {
  log_info "Checking Sentinel Nodes ($SENTINEL_HOSTS)..."
  
  local healthy_sentinels=0
  local total_sentinels=0
  
  for sentinel_addr in $SENTINEL_HOSTS; do
    local host="${sentinel_addr%:*}"
    local port="${sentinel_addr#*:}"
    ((total_sentinels++))
    
    if ! redis_cli_cmd "$host" "$port" ping > /dev/null 2>&1; then
      log_error "  Sentinel $sentinel_addr: unreachable"
      continue
    fi
    ((healthy_sentinels++))
    log_info "  Sentinel $sentinel_addr: ✓ responding"
    
    if [[ $VERBOSE -eq 1 ]]; then
      local info
      if info=$(redis_cli_cmd "$host" "$port" info server 2>/dev/null); then
        local version=$(echo "$info" | grep "^redis_version:" | cut -d: -f2 | tr -d '\r')
        log_info "    Version: $version"
      fi
    fi
  done
  
  log_check 0 "Sentinels healthy: $healthy_sentinels/$total_sentinels"
  
  # Check quorum (need 2/3)
  if [[ $healthy_sentinels -lt 2 ]]; then
    log_error "  WARNING: Quorum lost! Only $healthy_sentinels/$total_sentinels sentinels healthy"
    OVERALL_HEALTH=1
  fi
  
  return 0
}

check_sentinel_master_info() {
  log_info "Checking Sentinel Master State ($REDIS_MASTER_NAME)..."
  
  # Get master info from first reachable sentinel
  local master_info=""
  for sentinel_addr in $SENTINEL_HOSTS; do
    local host="${sentinel_addr%:*}"
    local port="${sentinel_addr#*:}"
    
    if master_info=$(redis_cli_cmd "$host" "$port" SENTINEL masters 2>/dev/null); then
      break
    fi
  done
  
  if [[ -z "$master_info" ]]; then
    log_error "  Could not fetch master info from any Sentinel"
    return 1
  fi
  
  # Parse master state (array format)
  log_info "  Master name: $REDIS_MASTER_NAME"
  
  if echo "$master_info" | grep -q "mymaster"; then
    log_check 0 "Sentinel tracking master '$REDIS_MASTER_NAME'"
  else
    log_error "  Master '$REDIS_MASTER_NAME' not tracked by Sentinels"
    OVERALL_HEALTH=1
  fi
  
  # Check replica count
  for sentinel_addr in $SENTINEL_HOSTS; do
    local host="${sentinel_addr%:*}"
    local port="${sentinel_addr#*:}"
    
    if replicas=$(redis_cli_cmd "$host" "$port" SENTINEL replicas mymaster 2>/dev/null); then
      local replica_count=$(echo "$replicas" | wc -l)
      log_info "  Replicas tracked by $host: $(($replica_count / 2))"
    fi
  done
  
  return 0
}

check_persistence() {
  log_info "Checking Redis Persistence..."
  
  local info
  if ! info=$(redis_cli_cmd "$REDIS_HOST" "$REDIS_PORT" info persistence); then
    log_error "  Could not fetch persistence info"
    return 1
  fi
  
  local rdb_last_save=$(echo "$info" | grep "^rdb_last_save_time:" | cut -d: -f2 | tr -d '\r')
  local aof_enabled=$(echo "$info" | grep "^aof_enabled:" | cut -d: -f2 | tr -d '\r')
  
  log_info "  AOF enabled: $aof_enabled"
  if [[ "$aof_enabled" == "0" ]]; then
    log_error "  WARNING: AOF persistence is disabled!"
    OVERALL_HEALTH=1
  fi
  
  log_info "  Last RDB save: $rdb_last_save ($(date -d @"$rdb_last_save" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'unknown'))"
  
  return 0
}

check_oauth2_proxy_connections() {
  log_info "Checking oauth2-proxy connections to Redis..."
  
  local client_list
  if ! client_list=$(redis_cli_cmd "$REDIS_HOST" "$REDIS_PORT" CLIENT LIST 2>/dev/null); then
    log_error "  Could not fetch client list"
    return 1
  fi
  
  local oauth_clients=$(echo "$client_list" | grep -c "oauth2" || true)
  if [[ $oauth_clients -gt 0 ]]; then
    log_check 0 "oauth2-proxy clients connected: $oauth_clients"
  else
    log_error "  WARNING: No oauth2-proxy clients connected to Redis!"
    OVERALL_HEALTH=1
  fi
  
  return 0
}

# ════════════════════════════════════════════════════════════════════════════
# Main
# ════════════════════════════════════════════════════════════════════════════

main() {
  log_info "═══════════════════════════════════════════════════════════"
  log_info "Redis Sentinel Health Check"
  log_info "═══════════════════════════════════════════════════════════"
  log_info "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  log_info ""
  
  check_redis_master || true
  log_info ""
  
  check_sentinel_nodes || true
  log_info ""
  
  check_sentinel_master_info || true
  log_info ""
  
  check_persistence || true
  log_info ""
  
  check_oauth2_proxy_connections || true
  log_info ""
  
  log_info "═══════════════════════════════════════════════════════════"
  if [[ $CRITICAL_FAILURE -eq 1 ]]; then
    log_fatal "CRITICAL: Service degradation detected"
    return 2
  elif [[ $OVERALL_HEALTH -eq 1 ]]; then
    log_warn "DEGRADED: Minor issues detected (see above)"
    return 1
  else
    log_info "✓ All systems healthy"
    return 0
  fi
}

main "$@"
