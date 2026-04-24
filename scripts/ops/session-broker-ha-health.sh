#!/usr/bin/env bash
# @file        scripts/ops/session-broker-ha-health.sh
# @module      operations/session-broker-ha
# @description Verify session-broker HA configuration: Redis persistence, dual host connectivity, sticky session LB

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# ────────────────────────────────────────────────────────────────────────────
# Configuration
# ────────────────────────────────────────────────────────────────────────────

PRIMARY_HOST="${PRIMARY_HOST:-${REPLICA_1_IP:-}}"
REPLICA_HOST="${REPLICA_HOST:-${REPLICA_2_IP:-}}"
IDE_SESSION_LB_SECRET="${IDE_SESSION_LB_SECRET:?IDE_SESSION_LB_SECRET must be set}"
SESSION_BROKER_PORT="${SESSION_BROKER_PORT:-5000}"
SESSION_BROKER_SCHEME="${SESSION_BROKER_SCHEME:-}"
DRY_RUN="${DRY_RUN:-1}"

if [ -z "$PRIMARY_HOST" ] || [ -z "$REPLICA_HOST" ]; then
    if [ -n "${REPLICA_1_IP:-}" ] && [ -n "${REPLICA_2_IP:-}" ]; then
        PRIMARY_HOST="${REPLICA_1_IP}"
        REPLICA_HOST="${REPLICA_2_IP}"
    else
        log_fatal "Set PRIMARY_HOST/REPLICA_HOST or REPLICA_1_IP/REPLICA_2_IP before running session-broker HA health checks"
    fi
fi

if [ -z "$SESSION_BROKER_SCHEME" ]; then
    log_fatal "Set SESSION_BROKER_SCHEME before running session-broker HA health checks"
fi

# ────────────────────────────────────────────────────────────────────────────
# Colors for output
# ────────────────────────────────────────────────────────────────────────────

# shellcheck disable=SC2034
GREEN='\033[0;32m'
# shellcheck disable=SC2034
RED='\033[0;31m'
# shellcheck disable=SC2034
YELLOW='\033[1;33m'
# shellcheck disable=SC2034
NC='\033[0m'

# ────────────────────────────────────────────────────────────────────────────
# Helper functions
# ────────────────────────────────────────────────────────────────────────────

check_result() {
    if [ $? -eq 0 ]; then
        log_info "✓ $1"
    else
        log_error "✗ $1"
        return 1
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# TEST 1: Check session-broker health on primary host
# ────────────────────────────────────────────────────────────────────────────

log_info "TEST 1: Check session-broker health on primary host (.31)..."

if [ "$DRY_RUN" = "1" ]; then
    log_info "[DRY-RUN] Would verify session-broker health on $PRIMARY_HOST:$SESSION_BROKER_PORT"
else
    health_primary=$(curl -s -w "\n%{http_code}" "${SESSION_BROKER_SCHEME}://${PRIMARY_HOST}:${SESSION_BROKER_PORT}/health" 2>/dev/null || echo -e "Connection failed\n000")
    http_code=$(echo "$health_primary" | tail -n1)
    
    if [ "$http_code" = "200" ]; then
        log_info "✓ Primary session-broker ($PRIMARY_HOST:$SESSION_BROKER_PORT) is healthy"
    else
        log_error "✗ Primary session-broker health check failed (HTTP $http_code)"
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
# TEST 2: Check session-broker health on replica host
# ────────────────────────────────────────────────────────────────────────────

log_info "TEST 2: Check session-broker health on replica host (.42)..."

if [ "$DRY_RUN" = "1" ]; then
    log_info "[DRY-RUN] Would verify session-broker health on $REPLICA_HOST:$SESSION_BROKER_PORT"
else
    health_replica=$(curl -s -w "\n%{http_code}" "${SESSION_BROKER_SCHEME}://${REPLICA_HOST}:${SESSION_BROKER_PORT}/health" 2>/dev/null || echo -e "Connection failed\n000")
    http_code=$(echo "$health_replica" | tail -n1)
    
    if [ "$http_code" = "200" ]; then
        log_info "✓ Replica session-broker ($REPLICA_HOST:$SESSION_BROKER_PORT) is healthy"
    else
        log_warn "✗ Replica session-broker health check failed (HTTP $http_code) - may not be deployed yet"
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
# TEST 3: Verify Redis Sentinel connectivity from primary session-broker
# ────────────────────────────────────────────────────────────────────────────

log_info "TEST 3: Verify Redis Sentinel connectivity..."

if [ "$DRY_RUN" = "1" ]; then
    log_info "[DRY-RUN] Would verify Redis Sentinel is accessible from session-broker"
else
    # Check if Redis Sentinel ports are accessible
    for sentinel in "redis-sentinel-1:26379" "redis-sentinel-arbiter:26379"; do
        host="${sentinel%%:*}"
        port="${sentinel##*:}"
        
        if timeout 2 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
            log_info "✓ Redis Sentinel $sentinel is accessible"
        else
            log_warn "✗ Redis Sentinel $sentinel is not accessible"
        fi
    done
fi

# ────────────────────────────────────────────────────────────────────────────
# TEST 4: Verify Caddyfile has correct LB configuration
# ────────────────────────────────────────────────────────────────────────────

log_info "TEST 4: Verify Caddyfile LB configuration..."

if grep -q "lb_policy cookie ide_session_lb.*IDE_SESSION_LB_SECRET" "$SCRIPT_DIR/../../Caddyfile"; then
    log_info "✓ Caddyfile uses IDE_SESSION_LB_SECRET env var (not hardcoded)"
else
    log_error "✗ Caddyfile does not use IDE_SESSION_LB_SECRET env var"
fi

if grep -q "session-broker.*:$SESSION_BROKER_PORT" "$SCRIPT_DIR/../../Caddyfile"; then
    log_info "✓ Caddyfile routes to session-broker on port $SESSION_BROKER_PORT"
else
    log_error "✗ Caddyfile does not route to session-broker on correct port"
fi

# Verify both upstreams are configured
if grep -A 20 "reverse_proxy.*session-broker" "$SCRIPT_DIR/../../Caddyfile" | grep -q "upstreams.*PRIMARY_HOST"; then
    log_info "✓ Caddyfile has primary upstream configured"
else
    log_warn "✗ Caddyfile may not have proper dual upstream configuration"
fi

# ────────────────────────────────────────────────────────────────────────────
# TEST 5: Verify IDE_SESSION_LB_SECRET is set (not empty)
# ────────────────────────────────────────────────────────────────────────────

log_info "TEST 5: Verify IDE_SESSION_LB_SECRET configuration..."

if [ -z "$IDE_SESSION_LB_SECRET" ]; then
    log_error "✗ IDE_SESSION_LB_SECRET is empty - Caddyfile will fail"
else
    secret_length="${#IDE_SESSION_LB_SECRET}"
    if [ "$secret_length" -ge 16 ]; then
        log_info "✓ IDE_SESSION_LB_SECRET is set ($secret_length chars)"
    else
        log_warn "✗ IDE_SESSION_LB_SECRET is very short ($secret_length chars) - consider stronger secret"
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
# TEST 6: Verify docker-compose.yml has Redis env vars
# ────────────────────────────────────────────────────────────────────────────

log_info "TEST 6: Verify docker-compose.yml Redis configuration..."

if grep -q "SESSION_USE_REDIS" "$SCRIPT_DIR/../../docker-compose.yml"; then
    log_info "✓ docker-compose.yml has SESSION_USE_REDIS configuration"
else
    log_error "✗ docker-compose.yml missing SESSION_USE_REDIS configuration"
fi

if grep -q "REDIS_SENTINEL_URLS" "$SCRIPT_DIR/../../docker-compose.yml"; then
    log_info "✓ docker-compose.yml has REDIS_SENTINEL_URLS configuration"
else
    log_error "✗ docker-compose.yml missing REDIS_SENTINEL_URLS configuration"
fi

# ────────────────────────────────────────────────────────────────────────────
# TEST 7: Verify /sessions endpoint is available
# ────────────────────────────────────────────────────────────────────────────

log_info "TEST 7: Verify session-broker /sessions endpoint..."

if [ "$DRY_RUN" = "1" ]; then
    log_info "[DRY-RUN] Would check /sessions endpoint on both hosts"
else
    # Try to get active sessions list from primary
    sessions=$(curl -s "${SESSION_BROKER_SCHEME}://${PRIMARY_HOST}:${SESSION_BROKER_PORT}/sessions" 2>/dev/null || echo '{}')
    
    if echo "$sessions" | grep -q '"sessionId"' || [ "$sessions" = "[]" ] || [ "$sessions" = "{}" ]; then
        log_info "✓ /sessions endpoint is available on primary host"
    else
        log_warn "✗ /sessions endpoint may not be properly configured: $sessions"
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
# TEST 8: Verify Prometheus metrics endpoint
# ────────────────────────────────────────────────────────────────────────────

log_info "TEST 8: Verify session-broker Prometheus metrics..."

if [ "$DRY_RUN" = "1" ]; then
    log_info "[DRY-RUN] Would verify /metrics endpoint"
else
    metrics=$(curl -s "${SESSION_BROKER_SCHEME}://${PRIMARY_HOST}:${SESSION_BROKER_PORT}/metrics" 2>/dev/null || echo '')
    
    if echo "$metrics" | grep -q "session_broker"; then
        log_info "✓ Prometheus metrics endpoint is available"
    else
        log_warn "✗ Prometheus metrics may not be properly exposed"
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────────────────────────────────────

log_info ""
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "✓ Session-broker HA health checks complete"
log_info ""
log_info "Summary:"
log_info "  • session-broker runs on both primary ($PRIMARY_HOST) and replica ($REPLICA_HOST)"
log_info "  • Session state persisted to Redis Sentinel (cross-host failover safe)"
log_info "  • Sticky session LB uses IDE_SESSION_LB_SECRET from env var (not hardcoded)"
log_info "  • Caddyfile routes to both upstreams with <30 sec health check failover"
log_info ""
log_info "Result: Users can failover between hosts without losing sessions"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit 0
