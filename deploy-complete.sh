#!/usr/bin/env bash
set -eo pipefail

# Find and navigate to the ops directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OPS_DIR="$SCRIPT_DIR"

# If we're in the repo root, navigate to ops subdirectory
if [ ! -f "docker-compose.yml" ] && [ -d "code-server-enterprise-ops" ]; then
  OPS_DIR="$SCRIPT_DIR/code-server-enterprise-ops"
fi

cd "$OPS_DIR"

echo "Working directory: $(pwd)"
echo ""
echo "=== Cleanup Phase ==="
echo "Stopping all containers..."
docker-compose down -v --remove-orphans 2>/dev/null || true
sleep 2

echo "Removing all dangling networks..."
docker network prune -f 2>/dev/null || true
sleep 2

echo "Force removing conflicting networks..."
docker network ls --quiet | xargs -I {} docker network inspect {} 2>/dev/null | grep -B 1 '"net-' | grep Network | awk -F'["]' '{print $2}' | sort -u | xargs -I {} docker network rm {} 2>/dev/null || true
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
CODE_SERVER_PASSWORD="${CODE_SERVER_PASSWORD:-${VAULT_CODE_SERVER_PASSWORD:-code123}}"
OAUTH2_PROXY_COOKIE_SECRET="${OAUTH2_PROXY_COOKIE_SECRET:-${VAULT_OAUTH2_PROXY_COOKIE_SECRET:-}}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-${VAULT_POSTGRES_PASSWORD:-postgres123}}"
REDIS_PASSWORD="${REDIS_PASSWORD:-${VAULT_REDIS_PASSWORD:-redis123}}"
CODE_SERVER_IMAGE_ID="${CODE_SERVER_IMAGE_ID:-a7c1eb39d243}"
SESSION_PROVENANCE_VERIFIED_AT="${SESSION_PROVENANCE_VERIFIED_AT:-$(date -u +%s)}"
SESSION_BROKER_SECRET_KEY="${SESSION_BROKER_SECRET_KEY:-default-dev-secret-key-not-secure}"
SESSION_BROKER_LOG_LEVEL="${SESSION_BROKER_LOG_LEVEL:-info}"
NAS_HOST="${NAS_HOST:-192.168.168.31}"

# Export these so docker-compose can use them
export GRAFANA_PASSWORD CODE_SERVER_PASSWORD POSTGRES_PASSWORD REDIS_PASSWORD
export CODE_SERVER_IMAGE_ID SESSION_PROVENANCE_VERIFIED_AT
export SESSION_BROKER_SECRET_KEY SESSION_BROKER_LOG_LEVEL NAS_HOST

echo "✓ Environment configured"
echo ""
echo "=== Starting Deployment ==="

# Deploy (must be run from OPS_DIR)
docker-compose up --detach

# Wait for services
echo "Waiting for services to start..."
sleep 20

# Check status
echo ""
echo "=== Service Status ==="
docker-compose ps

echo ""
echo "✓ Deployment Complete!"
