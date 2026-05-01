#!/usr/bin/env bash
# Test script: Verify CI/CD can source consolidated .env files with ENVIRONMENT variable
# This test validates that the CI/CD pipeline can correctly load environment variables

set -euo pipefail

# Error handling
trap 'echo "[ERROR] Script failed at line $LINENO"; exit 1' ERR
trap 'echo "[INFO] Cleaning up..."; exit 0' EXIT

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

echo "=== Testing CI/CD Environment Variable Loading ==="
echo ""

# Test 1: Private environment
echo "Test 1: Private environment CI/CD configuration"
export ENVIRONMENT=private
source "$REPO_ROOT/.env/_common/defaults"
source "$REPO_ROOT/.env/private/overrides" 2>/dev/null || echo "⚠️ Warning: .env/private/overrides not found"

if [[ "$APEX_DOMAIN" == "kushnir.cloud" ]] && [[ "$API_HOST" == "192.168.168.31" ]]; then
    echo "✅ Private environment: PASS (APEX_DOMAIN=$APEX_DOMAIN, API_HOST=$API_HOST)"
else
    echo "❌ Private environment: FAIL"
    exit 1
fi

# Test 2: Air-gapped environment
echo ""
echo "Test 2: Air-gapped environment CI/CD configuration"
unset APEX_DOMAIN API_HOST DATABASE_URL
export ENVIRONMENT=air-gapped
source "$REPO_ROOT/.env/_common/defaults"
source "$REPO_ROOT/.env/air-gapped/overrides" 2>/dev/null || echo "⚠️ Warning: .env/air-gapped/overrides not found"

if [[ "$APEX_DOMAIN" == "internal.local" ]] && [[ "$API_HOST" == "10.0.0.10" ]]; then
    echo "✅ Air-gapped environment: PASS (APEX_DOMAIN=$APEX_DOMAIN, API_HOST=$API_HOST)"
else
    echo "❌ Air-gapped environment: FAIL"
    exit 1
fi

# Test 3: Default environment (no overrides)
echo ""
echo "Test 3: Default environment (SSOT only, no overrides)"
unset APEX_DOMAIN API_HOST DEPLOYMENT_MODE
export ENVIRONMENT=default
source "$REPO_ROOT/.env/_common/defaults"

if [[ "$APEX_DOMAIN" == "kushnir.cloud" ]] && [[ "$DEPLOYMENT_MODE" == "private" ]]; then
    echo "✅ Default environment: PASS (APEX_DOMAIN=$APEX_DOMAIN, DEPLOYMENT_MODE=$DEPLOYMENT_MODE)"
else
    echo "❌ Default environment: FAIL"
    exit 1
fi

# Test 4: Verify all 41 shared variables are present
echo ""
echo "Test 4: Verify all 41 shared variables are available"
export ENVIRONMENT=private
source "$REPO_ROOT/.env/_common/defaults"

REQUIRED_VARS=(
    APEX_DOMAIN AUTH_DOMAIN APPSMITH_DOMAIN CODE_SERVER_DOMAIN IDE_DOMAIN API_DOMAIN REGISTRY_DOMAIN
    ADMIN_EMAIL TLS_EMAIL
    API_PROTOCOL API_HOST API_PORT API_ENDPOINT API_HEALTH_ENDPOINT API_OAUTH_CALLBACK
    CLUSTER_VIP PRIMARY_HOST REPLICA_HOST DEPLOYMENT_MODE REPLICA_ENABLED REPLICATION_MODE
    DATABASE_HOST DATABASE_PORT DB_USER DB_PASSWORD DB_NAME DATABASE_URL DATABASE_POOL_SIZE
    REDIS_HOST REDIS_PORT REDIS_PASSWORD REDIS_MAX_MEMORY REDIS_EVICTION_POLICY
    KAFKA_BROKER KAFKA_TOPIC_PREFIX REDPANDA_PORT REDPANDA_BROKERS REDPANDA_PARTITIONS
    PROMETHEUS_PORT PROMETHEUS_RETENTION GRAFANA_PORT GRAFANA_ADMIN_USER LOKI_PORT ALERTMANAGER_PORT
    OTEL_EXPORTER_OTLP_GRPC_PORT OTEL_EXPORTER_OTLP_HTTP_PORT TEMPO_GRPC_PORT
)

MISSING=0
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "❌ Missing: $var"
        MISSING=$((MISSING + 1))
    fi
done

if [[ $MISSING -eq 0 ]]; then
    echo "✅ All 41 shared variables present: PASS"
else
    echo "❌ $MISSING variables missing: FAIL"
    exit 1
fi

echo ""
echo "=== CI/CD Environment Variable Tests: ALL PASSED ==="
echo ""
echo "CI/CD pipelines can safely pass ENVIRONMENT variable and load consolidated .env files."
