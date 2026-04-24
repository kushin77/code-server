#!/usr/bin/env bash
# @file        deploy-replica.sh
# @module      deployment/replica
# @description Replica host deployment orchestrator (192.168.168.42) - HA mirror of primary
# @owner       Infrastructure Team
# @status      ACTIVE
#
set -eo pipefail

# Deployment script for replica host (192.168.168.42)
# Mirrors primary (192.168.168.31) setup

cd code-server-enterprise

echo "Working directory: $(pwd)"
echo ""
echo "=== Cleanup Phase ==="
echo "Stopping all containers..."
docker-compose down -v --remove-orphans 2>/dev/null || true
sleep 2

echo "Removing all dangling networks..."
docker network prune -f 2>/dev/null || true
sleep 2

echo ""
echo "=== Loading Environment ==="
echo "Phase 1: Loading defaults..."
set -a
source .env.defaults 2>/dev/null || true
set +a

echo "Phase 2: Overlaying production config..."
set -a
source .env.production 2>/dev/null || true
set +a

# Fill in any missing values with defaults
echo "Phase 3: Setting missing values..."
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-${VAULT_GRAFANA_PASSWORD:-}}"
if [ -z "$GRAFANA_PASSWORD" ]; then
  echo "ERROR: GRAFANA_PASSWORD must be provided via environment or GSM-backed vault secret"
  exit 1
fi
CODE_SERVER_PASSWORD="${CODE_SERVER_PASSWORD:-${VAULT_CODE_SERVER_PASSWORD:-}}"
if [ -z "$CODE_SERVER_PASSWORD" ]; then
  echo "ERROR: CODE_SERVER_PASSWORD must be provided via environment or GSM-backed vault secret (VAULT_CODE_SERVER_PASSWORD)"
  exit 1
fi
OAUTH2_PROXY_COOKIE_SECRET="${OAUTH2_PROXY_COOKIE_SECRET:-${VAULT_OAUTH2_PROXY_COOKIE_SECRET:-}}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-${VAULT_POSTGRES_PASSWORD:-}}"
if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "ERROR: POSTGRES_PASSWORD must be provided via environment or GSM-backed vault secret (VAULT_POSTGRES_PASSWORD)"
  exit 1
fi
REDIS_PASSWORD="${REDIS_PASSWORD:-${VAULT_REDIS_PASSWORD:-}}"
if [ -z "$REDIS_PASSWORD" ]; then
  echo "ERROR: REDIS_PASSWORD must be provided via environment or GSM-backed vault secret (VAULT_REDIS_PASSWORD)"
  exit 1
fi
CODE_SERVER_IMAGE_ID="${CODE_SERVER_IMAGE_ID:-sha256:9fcd6ab4ad9f0bdb0f28b35006171961d0bebcaf1a9b97d76b58d750873fd814}"
SESSION_PROVENANCE_VERIFIED_AT="${SESSION_PROVENANCE_VERIFIED_AT:-$(date -u +%s)}"
SESSION_BROKER_SECRET_KEY="${SESSION_BROKER_SECRET_KEY:-default-dev-secret-key-not-secure}"
SESSION_BROKER_LOG_LEVEL="${SESSION_BROKER_LOG_LEVEL:-info}"
NAS_HOST="${NAS_HOST:-192.168.168.31}"
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"

# Export these so docker-compose can use them
export GRAFANA_PASSWORD CODE_SERVER_PASSWORD POSTGRES_PASSWORD REDIS_PASSWORD
export CODE_SERVER_IMAGE_ID SESSION_PROVENANCE_VERIFIED_AT
export SESSION_BROKER_SECRET_KEY SESSION_BROKER_LOG_LEVEL NAS_HOST
export PRIMARY_HOST REPLICA_HOST

echo "✓ Environment configured"
echo "  Primary: $PRIMARY_HOST"
echo "  Replica: $REPLICA_HOST"
echo ""
echo "=== Starting Deployment (Replica Host) ==="

# Deploy (must be run from code-server-enterprise directory)
docker-compose up --detach

# Wait for services
echo "Waiting for services to start..."
sleep 20

# Check status
echo ""
echo "=== Service Status ==="
docker-compose ps

echo ""
echo "✓ Replica Deployment Complete!"
echo ""
echo "Both hosts now active:"
echo "  - Primary:  192.168.168.31 (active)"
echo "  - Replica:  192.168.168.42 (standby/HA)"
echo ""
echo "Access points:"
echo "  - Code-server: http://code-server.192.168.168.31.nip.io:8080"
echo "  - Grafana: http://192.168.168.31:3000 (credentials via GSM)"
echo "  - Failover: Automatic via Caddy health checks + Sentinel"
