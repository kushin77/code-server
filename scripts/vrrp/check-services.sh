#!/bin/bash
################################################################################
# scripts/vrrp/check-services.sh
# Health check script for Keepalived VRRP
# Returns 0 (healthy) or 1 (unhealthy)
# If unhealthy, Keepalived will demote this instance's priority
#
# Managed by: P2 #365 (VRRP Virtual IP Failover)
# Called by: Keepalived vrrp_script chk_services (every 2 seconds)
# Weight: -20 (priority reduction if any check fails)
################################################################################

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Health check configuration
# ─────────────────────────────────────────────────────────────────────────────

COMPOSE_DIR="${COMPOSE_DIR:-.}"
HEALTHCHECK_LOG="/var/log/vrrp-healthcheck.log"
TIMEOUT=5

# Services to monitor (docker-compose service names)
CRITICAL_SERVICES=(
    "oauth2-proxy"
    "postgres"
    "redis"
)

OPTIONAL_SERVICES=(
    "prometheus"
    "grafana"
)

# ─────────────────────────────────────────────────────────────────────────────
# Helper: Check if Docker service is running and healthy
# ─────────────────────────────────────────────────────────────────────────────
check_service_running() {
    local service=$1
    
    # Check if container exists and is running
    if ! docker-compose -f "$COMPOSE_DIR/docker-compose.yml" ps -q "$service" >/dev/null 2>&1; then
        echo "❌ Service $service is not running" >> "$HEALTHCHECK_LOG"
        return 1
    fi
    
    # Check if health status is healthy (if healthcheck defined)
    local health_status=$(docker inspect --format='{{.State.Health.Status}}' \
        "$(docker-compose -f "$COMPOSE_DIR/docker-compose.yml" ps -q "$service" 2>/dev/null)" 2>/dev/null || echo "none")
    
    if [[ "$health_status" != "healthy" && "$health_status" != "none" ]]; then
        echo "⚠️  Service $service is unhealthy (status: $health_status)" >> "$HEALTHCHECK_LOG"
        return 1
    fi
    
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Helper: Check service responds on its port/endpoint
# ─────────────────────────────────────────────────────────────────────────────
check_service_responsive() {
    local service=$1
    local port=$2
    local endpoint=${3:-/health}
    
    # Try to reach service endpoint
    if ! curl -sf --max-time "$TIMEOUT" "http://localhost:$port$endpoint" >/dev/null 2>&1; then
        echo "❌ Service $service ($endpoint on :$port) unresponsive" >> "$HEALTHCHECK_LOG"
        return 1
    fi
    
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Perform checks
# ─────────────────────────────────────────────────────────────────────────────

FAILURE_COUNT=0
FAILURE_REASON=""

# Check critical services (if any fail, we demote priority)
for service in "${CRITICAL_SERVICES[@]}"; do
    if ! check_service_running "$service"; then
        ((FAILURE_COUNT++))
        FAILURE_REASON+="$service not running; "
    fi
done

# Check service endpoints
# oauth2-proxy health check
if ! check_service_responsive "oauth2-proxy" 4180 "/oauth2/auth"; then
    ((FAILURE_COUNT++))
    FAILURE_REASON+="oauth2-proxy unresponsive; "
fi

# PostgreSQL health check
if ! check_service_responsive "postgres" 5432 ""; then
    # TCP connect is enough for postgres
    if ! timeout "$TIMEOUT" bash -c "cat </dev/null >/dev/tcp/localhost/5432" 2>/dev/null; then
        ((FAILURE_COUNT++))
        FAILURE_REASON+="postgres port 5432 unresponsive; "
    fi
fi

# Redis health check
if ! check_service_responsive "redis" 6379 ""; then
    # Use redis-cli PING
    if ! docker exec $(docker-compose -f "$COMPOSE_DIR/docker-compose.yml" ps -q redis) \
         redis-cli PING >/dev/null 2>&1; then
        ((FAILURE_COUNT++))
        FAILURE_REASON+="redis unresponsive; "
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Return health status
# ─────────────────────────────────────────────────────────────────────────────

if [[ $FAILURE_COUNT -gt 0 ]]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ❌ UNHEALTHY: $FAILURE_COUNT checks failed - $FAILURE_REASON" >> "$HEALTHCHECK_LOG"
    exit 1  # Unhealthy → Keepalived will reduce priority
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✅ All critical services healthy" >> "$HEALTHCHECK_LOG"
exit 0  # Healthy → Keepalived maintains normal priority
