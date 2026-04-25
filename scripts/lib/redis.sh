#!/usr/bin/env bash
# @file        scripts/lib/redis.sh
# @module      lib/cache
# @description Redis health monitoring, cache statistics, and configuration
# @governance  GOV-002: Immutable, version-controlled, no hardcoded secrets
# Issue #1536: Networking, DNS & Performance — Caching Strategy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/logging.sh"
source "${REPO_ROOT}/scripts/_common/_base-config.env"

# ── Configuration ─────────────────────────────────────────────────────────────
REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_DB="${REDIS_DB:-0}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

# Performance thresholds
REDIS_MAX_LATENCY_MS="${REDIS_MAX_LATENCY_MS:-50}"      # Alert if > 50ms
REDIS_MIN_HIT_RATE_PCT="${REDIS_MIN_HIT_RATE_PCT:-70}"  # Alert if < 70%
REDIS_MAX_MEMORY_PCT="${REDIS_MAX_MEMORY_PCT:-80}"      # Alert if > 80%

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
pass() { printf "${GREEN}  ✔  %s${NC}\n" "$*"; }
fail() { printf "${RED}  ✖  %s${NC}\n" "$*" >&2; }
warn() { printf "${YELLOW}  ⚠  %s${NC}\n" "$*" >&2; }

# ── Redis Connection Helpers ──────────────────────────────────────────────────

# Build redis-cli command with connection parameters
redis_cli_cmd() {
  local cmd="redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT}"
  if [ -n "${REDIS_PASSWORD}" ]; then
    cmd="${cmd} -a ${REDIS_PASSWORD}"
  fi
  echo "${cmd}"
}

# Test Redis connectivity
redis_ping() {
  local redis_cmd
  redis_cmd=$(redis_cli_cmd)

  if ${redis_cmd} PING >/dev/null 2>&1; then
    pass "Redis is reachable (${REDIS_HOST}:${REDIS_PORT})"
    return 0
  else
    fail "Redis is NOT reachable (${REDIS_HOST}:${REDIS_PORT})"
    return 1
  fi
}

# ── Cache Statistics ──────────────────────────────────────────────────────────

# Get cache hit rate
redis_cache_hit_rate() {
  local redis_cmd stats hits misses hit_rate
  redis_cmd=$(redis_cli_cmd)

  stats=$(${redis_cmd} INFO stats 2>/dev/null || echo "")
  hits=$(echo "${stats}" | grep "keyspace_hits:" | cut -d: -f2 | tr -d '[:space:]')
  misses=$(echo "${stats}" | grep "keyspace_misses:" | cut -d: -f2 | tr -d '[:space:]')

  if [ -z "${hits}" ] || [ -z "${misses}" ]; then
    fail "Could not retrieve cache statistics"
    return 1
  fi

  local total=$((hits + misses))
  if [ ${total} -eq 0 ]; then
    warn "No cache activity recorded"
    return 1
  fi

  hit_rate=$(( (hits * 100) / total ))

  if [ ${hit_rate} -ge ${REDIS_MIN_HIT_RATE_PCT} ]; then
    pass "Cache hit rate: ${hit_rate}% (threshold: ${REDIS_MIN_HIT_RATE_PCT}%)"
    return 0
  else
    warn "Cache hit rate LOW: ${hit_rate}% (threshold: ${REDIS_MIN_HIT_RATE_PCT}%)"
    return 1
  fi
}

# Get Redis memory usage
redis_memory_usage() {
  local redis_cmd memory_stats used_memory max_memory memory_pct
  redis_cmd=$(redis_cli_cmd)

  memory_stats=$(${redis_cmd} INFO memory 2>/dev/null || echo "")
  used_memory=$(echo "${memory_stats}" | grep "^used_memory:" | cut -d: -f2 | tr -d '[:space:]')
  max_memory=$(echo "${memory_stats}" | grep "^maxmemory:" | cut -d: -f2 | tr -d '[:space:]')

  if [ -z "${used_memory}" ]; then
    fail "Could not retrieve memory statistics"
    return 1
  fi

  local used_gb=$((used_memory / 1024 / 1024 / 1024))

  if [ -z "${max_memory}" ] || [ "${max_memory}" = "0" ]; then
    pass "Redis memory: ${used_gb}GB (no limit)"
    return 0
  fi

  local max_gb=$((max_memory / 1024 / 1024 / 1024))
  memory_pct=$(( (used_memory * 100) / max_memory ))

  if [ ${memory_pct} -lt ${REDIS_MAX_MEMORY_PCT} ]; then
    pass "Redis memory: ${used_gb}GB / ${max_gb}GB (${memory_pct}%)"
    return 0
  else
    warn "Redis memory HIGH: ${memory_pct}% (threshold: ${REDIS_MAX_MEMORY_PCT}%)"
    return 1
  fi
}

# Get Redis connected clients
redis_client_count() {
  local redis_cmd clients
  redis_cmd=$(redis_cli_cmd)

  clients=$(${redis_cmd} INFO clients 2>/dev/null | grep "^connected_clients:" | cut -d: -f2 | tr -d '[:space:]')

  if [ -z "${clients}" ]; then
    fail "Could not retrieve client count"
    return 1
  fi

  pass "Redis connected clients: ${clients}"
  return 0
}

# ── Latency Measurement ───────────────────────────────────────────────────────

# Measure Redis command latency
redis_latency() {
  local redis_cmd start_time end_time latency_ms
  redis_cmd=$(redis_cli_cmd)

  start_time=$(date +%s%N)
  ${redis_cmd} PING >/dev/null 2>&1 || return 1
  end_time=$(date +%s%N)

  latency_ms=$(( (end_time - start_time) / 1000000 ))

  if [ ${latency_ms} -lt ${REDIS_MAX_LATENCY_MS} ]; then
    pass "Redis latency: ${latency_ms}ms (threshold: ${REDIS_MAX_LATENCY_MS}ms)"
    return 0
  else
    warn "Redis latency HIGH: ${latency_ms}ms (threshold: ${REDIS_MAX_LATENCY_MS}ms)"
    return 1
  fi
}

# ── Cache Configuration ───────────────────────────────────────────────────────

# Get Redis configuration parameter
redis_config_get() {
  local param redis_cmd
  param="${1}"
  redis_cmd=$(redis_cli_cmd)

  ${redis_cmd} CONFIG GET "${param}" | tail -1
}

# Set Redis configuration parameter
redis_config_set() {
  local param value redis_cmd
  param="${1}"
  value="${2}"
  redis_cmd=$(redis_cli_cmd)

  ${redis_cmd} CONFIG SET "${param}" "${value}" || return 1
  pass "Redis config: ${param} = ${value}"
}

# Show full Redis configuration (useful for diagnostics)
redis_config_info() {
  local redis_cmd
  redis_cmd=$(redis_cli_cmd)

  echo ""
  echo "=== Redis Configuration ==="
  ${redis_cmd} CONFIG GET '*' | paste - - | column -t
  echo ""
}

# ── Health Check ──────────────────────────────────────────────────────────────

# Comprehensive Redis health check
redis_health_check() {
  echo ""
  echo "=== Redis Health Check ==="
  echo ""

  local health_status="HEALTHY"
  local failed_checks=0

  # Check 1: Connectivity
  if ! redis_ping; then
    health_status="CRITICAL"
    ((failed_checks++))
  fi

  # Check 2: Latency
  if ! redis_latency; then
    health_status="DEGRADED"
    ((failed_checks++))
  fi

  # Check 3: Memory
  if ! redis_memory_usage; then
    health_status="DEGRADED"
    ((failed_checks++))
  fi

  # Check 4: Cache hit rate
  if ! redis_cache_hit_rate; then
    health_status="DEGRADED"
    ((failed_checks++))
  fi

  # Check 5: Connected clients
  redis_client_count || true

  echo ""
  if [ ${failed_checks} -eq 0 ]; then
    pass "Redis Health: ${health_status}"
    return 0
  else
    warn "Redis Health: ${health_status} (${failed_checks} check(s) failed)"
    return 1
  fi
}

# ── Cache Flushing ───────────────────────────────────────────────────────────

# Flush entire Redis cache (USE WITH CAUTION)
redis_flush_all() {
  local redis_cmd response
  redis_cmd=$(redis_cli_cmd)

  read -p "WARNING: This will delete ALL cache data. Continue? (y/N) " -n 1 -r response
  echo ""

  if [[ ! ${response} =~ ^[Yy]$ ]]; then
    echo "Aborted"
    return 1
  fi

  ${redis_cmd} FLUSHALL || return 1
  pass "Cache flushed successfully"
  return 0
}

# Flush specific Redis database
redis_flush_db() {
  local db="${1:-${REDIS_DB}}"
  local redis_cmd
  redis_cmd=$(redis_cli_cmd)

  ${redis_cmd} -n "${db}" FLUSHDB || return 1
  pass "Database ${db} flushed successfully"
  return 0
}

# ── Metrics Export (for Prometheus) ───────────────────────────────────────────

# Export Redis metrics in Prometheus format
redis_metrics_prometheus() {
  local redis_cmd stats memory_stats
  redis_cmd=$(redis_cli_cmd)

  stats=$(${redis_cmd} INFO stats 2>/dev/null || echo "")
  memory_stats=$(${redis_cmd} INFO memory 2>/dev/null || echo "")

  local hits=$(echo "${stats}" | grep "keyspace_hits:" | cut -d: -f2 | tr -d '[:space:]' || echo "0")
  local misses=$(echo "${stats}" | grep "keyspace_misses:" | cut -d: -f2 | tr -d '[:space:]' || echo "0")
  local used_memory=$(echo "${memory_stats}" | grep "^used_memory:" | cut -d: -f2 | tr -d '[:space:]' || echo "0")
  local max_memory=$(echo "${memory_stats}" | grep "^maxmemory:" | cut -d: -f2 | tr -d '[:space:]' || echo "0")

  local hit_rate=0
  if [ $((hits + misses)) -gt 0 ]; then
    hit_rate=$(( (hits * 100) / (hits + misses) ))
  fi

  # Output Prometheus metrics
  cat <<EOF
# HELP redis_cache_hits Total cache hits
# TYPE redis_cache_hits counter
redis_cache_hits${hits}

# HELP redis_cache_misses Total cache misses
# TYPE redis_cache_misses counter
redis_cache_misses${misses}

# HELP redis_cache_hit_rate Cache hit rate percentage
# TYPE redis_cache_hit_rate gauge
redis_cache_hit_rate${hit_rate}

# HELP redis_memory_used_bytes Used memory in bytes
# TYPE redis_memory_used_bytes gauge
redis_memory_used_bytes ${used_memory}

# HELP redis_memory_max_bytes Maximum memory limit in bytes
# TYPE redis_memory_max_bytes gauge
redis_memory_max_bytes ${max_memory}
EOF
}

# ── Export Functions ───────────────────────────────────────────────────────────

export -f redis_ping
export -f redis_cache_hit_rate
export -f redis_memory_usage
export -f redis_client_count
export -f redis_latency
export -f redis_config_get
export -f redis_config_set
export -f redis_config_info
export -f redis_health_check
export -f redis_flush_db
export -f redis_flush_all
export -f redis_metrics_prometheus
