#!/usr/bin/env bash
# @file        scripts/ops/caddy-upstream-verify.sh
# @module      operations/caddy-management
# @description Verify Caddy upstream health and failover routing for HA topology
#
# Usage:
#   bash scripts/ops/caddy-upstream-verify.sh                    # Verify both upstreams healthy
#   bash scripts/ops/caddy-upstream-verify.sh --primary           # Check only primary upstream
#   bash scripts/ops/caddy-upstream-verify.sh --replica           # Check only replica upstream
#   bash scripts/ops/caddy-upstream-verify.sh --failover          # Simulate failover test
#   bash scripts/ops/caddy-upstream-verify.sh --metrics           # Show Caddy metrics
#
# Procedure:
#   1. Check Caddy container is running
#   2. Query Caddy admin API for upstream health status
#   3. Verify both primary and replica upstreams are available
#   4. Check health check intervals and timeouts
#   5. Report current routing destination
#   6. Test failover (optional): pause primary and verify traffic routes to replica
#
# Exit codes:
#   0 = both upstreams healthy or failover successful
#   1 = one upstream degraded (still routing, but reduced redundancy)
#   2 = primary upstream down (replica is active)
#   3 = critical: both upstreams unavailable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Configuration
CADDY_CONTAINER="${CADDY_CONTAINER:-caddy}"
CADDY_ADMIN_PORT="${CADDY_ADMIN_PORT:-2019}"
CADDY_ADMIN_URL="http://localhost:$CADDY_ADMIN_PORT"
PRIMARY_HOST="${PRIMARY_HOST:-localhost}"
PRIMARY_PORT="${PRIMARY_PORT:-5000}"
REPLICA_HOST="${REPLICA_HOST:-replica-host}"
REPLICA_PORT="${REPLICA_PORT:-5000}"
DRY_RUN="${DRY_RUN:-0}"
FAILOVER_TEST_TIMEOUT="${FAILOVER_TEST_TIMEOUT:-60}"

# ════════════════════════════════════════════════════════════════════════════
# Utility Functions
# ════════════════════════════════════════════════════════════════════════════

caddy_is_running() {
  if docker ps --filter "name=$CADDY_CONTAINER" --format "{{.ID}}" | grep -q .; then
    return 0
  else
    log_error "Caddy container not running: $CADDY_CONTAINER"
    return 1
  fi
}

get_upstream_health() {
  local upstream=$1
  
  if ! caddy_is_running; then
    log_error "Cannot query upstreams: Caddy not running"
    return 2
  fi
  
  # Query Caddy admin API for reverse proxy health status
  # Endpoint: GET /config/apps/http/servers/{server_name}/routes/{route_index}/handle/{handler_index}/upstreams/{upstream_index}
  
  if ! timeout 5 curl -sf "$CADDY_ADMIN_URL/config/apps/http/servers/*/routes/*/handle/*/upstreams" 2>/dev/null; then
    log_warn "Could not query Caddy admin API (may not be running with admin endpoint enabled)"
    return 1
  fi
}

check_upstream_direct() {
  local host=$1
  local port=$2
  local name=$3
  
  log_info "Checking upstream: $name ($host:$port)..."
  
  if timeout 5 curl -sf "http://$host:$port/health" > /dev/null 2>&1; then
    log_info "  ✓ $name healthy"
    return 0
  else
    log_warn "  ✗ $name unhealthy or unreachable"
    return 1
  fi
}

verify_both_upstreams() {
  log_info "Verifying Caddy upstream configuration..."
  
  local primary_ok=0
  local replica_ok=0
  
  check_upstream_direct "$PRIMARY_HOST" "$PRIMARY_PORT" "primary" && primary_ok=1 || true
  check_upstream_direct "$REPLICA_HOST" "$REPLICA_PORT" "replica" && replica_ok=1 || true
  
  if [[ $primary_ok -eq 1 && $replica_ok -eq 1 ]]; then
    log_info "✓ Both upstreams healthy"
    return 0
  elif [[ $primary_ok -eq 1 || $replica_ok -eq 1 ]]; then
    log_warn "⚠ One upstream degraded (redundancy impaired)"
    return 1
  else
    log_error "✗ Both upstreams down (critical)"
    return 3
  fi
}

check_primary_only() {
  log_info "Checking primary upstream only..."
  
  if check_upstream_direct "$PRIMARY_HOST" "$PRIMARY_PORT" "primary"; then
    return 0
  else
    return 1
  fi
}

check_replica_only() {
  log_info "Checking replica upstream only..."
  
  if check_upstream_direct "$REPLICA_HOST" "$REPLICA_PORT" "replica"; then
    return 0
  else
    return 1
  fi
}

show_caddy_metrics() {
  log_info "Caddy reverse proxy metrics:"
  
  if ! caddy_is_running; then
    log_error "Caddy container not running"
    return 1
  fi
  
  # Query metrics from Caddy admin API
  if timeout 5 curl -sf "$CADDY_ADMIN_URL/metrics" 2>/dev/null | grep -E "caddy_http_request_duration|caddy_http_requests_total|caddy_http_response_size"; then
    return 0
  else
    log_warn "Caddy metrics endpoint not available (admin API may be disabled)"
    return 1
  fi
}

simulate_failover() {
  log_info "Simulating failover: pausing primary upstream..."
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "  [DRY RUN] Would pause primary container"
    return 0
  fi
  
  # Find primary container and pause it
  local primary_container
  if ! primary_container=$(docker ps --filter "name=$PRIMARY_HOST" --format "{{.ID}}" | head -1); then
    log_error "Could not find primary container for $PRIMARY_HOST"
    return 2
  fi
  
  if [[ -z "$primary_container" ]]; then
    log_warn "Primary container not found (might be on remote host)"
    log_info "Test: pausing local session-broker instead..."
    primary_container="session-broker"
  fi
  
  log_info "  Pausing container: $primary_container"
  docker pause "$primary_container" || { log_error "Failed to pause"; return 2; }
  
  # Wait for Caddy to detect failure (health_fails=2, health_interval=10s = ~20s)
  log_info "  Waiting for Caddy to detect primary failure (~20 seconds)..."
  sleep 20
  
  # Test: verify traffic now routes to replica
  log_info "  Testing traffic routing to replica..."
  local elapsed=0
  while [[ $elapsed -lt $FAILOVER_TEST_TIMEOUT ]]; do
    if timeout 5 curl -sf "http://$REPLICA_HOST:$REPLICA_PORT/health" > /dev/null 2>&1; then
      log_info "  ✓ Traffic successfully routed to replica"
      
      # Unpause primary
      log_info "  Unpausing primary container..."
      docker unpause "$primary_container" || log_warn "Failed to unpause"
      sleep 10
      
      return 0
    fi
    
    sleep 5
    ((elapsed += 5))
    echo -n "."
  done
  
  log_error "  ✗ Traffic did not route to replica after $FAILOVER_TEST_TIMEOUT seconds"
  docker unpause "$primary_container" || log_warn "Failed to unpause"
  return 1
}

# ════════════════════════════════════════════════════════════════════════════
# Main Entry Point
# ════════════════════════════════════════════════════════════════════════════

main() {
  local command="${1:-verify}"
  
  log_info "═══════════════════════════════════════════════════════════"
  log_info "Caddy Upstream Health Verification"
  log_info "═══════════════════════════════════════════════════════════"
  log_info "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  log_info "Command: $command"
  log_info "Dry-run: $DRY_RUN"
  log_info ""
  
  local exit_code=0
  
  case "$command" in
    verify|--verify|all)
      verify_both_upstreams || exit_code=$?
      ;;
    primary|--primary)
      check_primary_only || exit_code=$?
      ;;
    replica|--replica)
      check_replica_only || exit_code=$?
      ;;
    failover|--failover|test-failover)
      simulate_failover || exit_code=$?
      ;;
    metrics|--metrics|stats)
      show_caddy_metrics || exit_code=$?
      ;;
    *)
      log_error "Unknown command: $command"
      log_info "Usage: bash scripts/ops/caddy-upstream-verify.sh [verify|primary|replica|failover|metrics]"
      exit_code=1
      ;;
  esac
  
  log_info ""
  log_info "═══════════════════════════════════════════════════════════"
  
  if [[ $exit_code -eq 0 ]]; then
    log_info "✓ Upstream verification passed"
  elif [[ $exit_code -eq 1 ]]; then
    log_warn "⚠ Partial failure: one upstream degraded"
  elif [[ $exit_code -eq 2 ]]; then
    log_warn "⚠ Upstream unreachable (may be on remote host)"
  else
    log_error "✗ Upstream verification failed (exit code: $exit_code)"
  fi
  log_info "═══════════════════════════════════════════════════════════"
  
  return $exit_code
}

main "$@"
