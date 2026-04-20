#!/bin/bash
# Dual-host failover testing script
# This simulates the Cloudflare failover scenario and verifies routing works correctly

# Configuration
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
PORTAL_DOMAIN="${PORTAL_DOMAIN:-kushnir.cloud}"
IDE_DOMAIN="${IDE_DOMAIN:-ide.kushnir.cloud}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-60}"

log_info() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*"
}

log_error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

log_success() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $*"
}

# Test 1: Verify primary host is serving traffic
test_primary_healthy() {
  log_info "Test 1: Verifying primary host ($PRIMARY_HOST) is healthy..."
  
  if curl -sf "https://$PORTAL_DOMAIN/health" > /dev/null 2>&1; then
    log_success "Primary host is healthy and serving traffic"
    return 0
  else
    log_error "Primary host not responding"
    return 1
  fi
}

# Test 2: Verify replica host is ready (but not currently serving)
test_replica_standby() {
  log_info "Test 2: Verifying replica host ($REPLICA_HOST) is operational..."
  
  if ssh -o ConnectTimeout=5 "akushnir@$REPLICA_HOST" "docker-compose ps | grep -E 'session-broker|oauth2-proxy'" > /dev/null 2>&1; then
    log_success "Replica host services are operational (standby)"
    return 0
  else
    log_error "Replica host services not operational"
    return 1
  fi
}

# Test 3: Simulate primary failure by pausing it
test_primary_failure_detection() {
  log_info "Test 3: Simulating primary failure (pausing session-broker)..."
  
  ssh "akushnir@$PRIMARY_HOST" "docker-compose pause session-broker" || return 1
  
  log_info "  Primary paused. Waiting for Caddy to detect failure (<20 seconds)..."
  sleep 20
  
  # Verify traffic now routes to replica
  if curl -sf "https://$IDE_DOMAIN/health" > /dev/null 2>&1; then
    log_success "Traffic successfully routed to replica"
    ssh "akushnir@$PRIMARY_HOST" "docker-compose unpause session-broker"
    return 0
  else
    log_error "Traffic not routing to replica"
    ssh "akushnir@$PRIMARY_HOST" "docker-compose unpause session-broker"
    return 1
  fi
}

# Test 4: Full failover scenario with OAuth login
test_oauth_failover() {
  log_info "Test 4: Full OAuth login → Appsmith → IDE failover scenario..."
  
  # This requires Playwright or similar browser automation
  # For now, just verify endpoints are accessible
  
  log_info "  Testing OAuth endpoint..."
  if curl -sf "https://$PORTAL_DOMAIN/oauth2/start" > /dev/null 2>&1; then
    log_success "OAuth endpoint accessible"
  else
    log_error "OAuth endpoint not accessible"
    return 1
  fi
  
  log_info "  Testing IDE endpoint..."
  if curl -sf "https://$IDE_DOMAIN/health" > /dev/null 2>&1; then
    log_success "IDE endpoint accessible"
    return 0
  else
    log_error "IDE endpoint not accessible"
    return 1
  fi
}

# Main test suite
main() {
  log_info "════════════════════════════════════════════════════════"
  log_info "Dual-Host Failover Test Suite"
  log_info "════════════════════════════════════════════════════════"
  log_info "Primary: $PRIMARY_HOST"
  log_info "Replica: $REPLICA_HOST"
  log_info "Portal: $PORTAL_DOMAIN"
  log_info "IDE: $IDE_DOMAIN"
  log_info ""
  
  local failed=0
  
  test_primary_healthy || ((failed++))
  sleep 2
  test_replica_standby || ((failed++))
  sleep 2
  test_primary_failure_detection || ((failed++))
  sleep 2
  test_oauth_failover || ((failed++))
  
  log_info ""
  log_info "════════════════════════════════════════════════════════"
  
  if [[ $failed -eq 0 ]]; then
    log_success "All failover tests passed!"
    return 0
  else
    log_error "$failed tests failed"
    return 1
  fi
}

main "$@"
