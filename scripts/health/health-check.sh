#!/bin/bash
# scripts/health/health-check.sh
# Part of Phase 7d-003: Health Checks & Automatic Failover

set -e

FAILED_SERVICES=()
HEALTH_STATUS="HEALTHY"

check_http() {
  local name=$1
  local url=$2
  local expected=${3:-200}
  
  if ! curl -sfL --max-time 5 "$url" > /dev/null; then
    echo "[FAIL] $name ($url) is down"
    FAILED_SERVICES+=("$name")
    HEALTH_STATUS="DEGRADED"
  else
    echo "[PASS] $name is healthy"
  fi
}

check_container() {
  local name=$1
  if ! docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
    echo "[FAIL] Container $name not running"
    FAILED_SERVICES+=("$name")
    HEALTH_STATUS="DEGRADED"
  fi
}

echo "--- Health Check: $(date) ---"

# Infrastructure Services
check_container "postgres"
check_container "redis"
check_container "haproxy"

# App Services
check_http "code-server" "http://localhost:8080/healthz"
check_http "prometheus" "http://localhost:9090/-/healthy"
check_http "grafana" "http://localhost:3000/api/health"

if [[ "${#FAILED_SERVICES[@]}" -gt 0 ]]; then
  echo "Result: $HEALTH_STATUS (Failed: ${FAILED_SERVICES[*]})"
  exit 1
fi

echo "Result: $HEALTH_STATUS"
exit 0
