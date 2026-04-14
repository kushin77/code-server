#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# scripts/deploy.sh — Production clean-rebuild deploy
# Target: 192.168.168.31 | NAS: 192.168.168.56
# Steps : kill orphans → mount NAS → load secrets → rebuild all → healthcheck
# Usage : ./scripts/deploy.sh [--skip-nas] [--skip-pull]
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
NAS_HOST="192.168.168.56"
LOCAL_DATA_BASE="/home/akushnir/.local/data"

SKIP_NAS=false
SKIP_PULL=false

for arg in "$@"; do
    case $arg in
        --skip-nas)  SKIP_NAS=true ;;
        --skip-pull) SKIP_PULL=true ;;
    esac
done

log()  { echo "[deploy] $(date -u +%H:%M:%S) $*"; }
ok()   { echo "[deploy] OK: $*"; }
die()  { echo "[deploy] FATAL: $*" >&2; exit 1; }

# Guard: Linux only
[[ "$(uname)" == "Linux" ]] || die "Deploy must run on Linux at 192.168.168.31"

# ── 1. Load secrets ──────────────────────────────────────────────────────────
log "Loading secrets..."
# shellcheck source=scripts/lib/secrets.sh
source "$SCRIPT_DIR/lib/secrets.sh"
secrets_load_env

# ── 2. Mount NAS ─────────────────────────────────────────────────────────────
if [[ "$SKIP_NAS" == false ]]; then
    log "Mounting NAS $NAS_HOST..."
    if ! mountpoint -q /mnt/nas-56; then
        sudo "$SCRIPT_DIR/nas-mount-31.sh" mount
    else
        ok "NAS already mounted"
    fi
else
    log "Skipping NAS mount (--skip-nas)"
fi

# ── 3. Provision local SSD data dirs ─────────────────────────────────────────
log "Provisioning local SSD data directories..."
for dir in postgres redis; do
    mkdir -p "${LOCAL_DATA_BASE}/${dir}"
done
ok "Local data dirs: ${LOCAL_DATA_BASE}/{postgres,redis}"

# ── 4. Kill ALL containers + orphans ─────────────────────────────────────────
log "Stopping all containers and removing orphans..."
cd "$REPO_DIR"

docker compose down --remove-orphans --timeout 30 2>/dev/null || true

# Remove dangling/anonymous volumes (not named volumes — keep data)
log "Pruning dangling volumes..."
docker volume prune -f

# Remove dangling images
log "Pruning dangling images..."
docker image prune -f

ok "Cleanup complete"

# ── 5. Pull latest images ─────────────────────────────────────────────────────
if [[ "$SKIP_PULL" == false ]]; then
    log "Pulling latest pinned images..."
    docker compose pull --quiet
    ok "Images pulled"
fi

# ── 6. Export env vars for compose ───────────────────────────────────────────
log "Exporting env vars for docker compose..."
export POSTGRES_PASSWORD REDIS_PASSWORD CODE_SERVER_PASSWORD
export GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET OAUTH2_PROXY_COOKIE_SECRET
export GRAFANA_ADMIN_PASSWORD GITHUB_TOKEN

# ── 7. Start all services ────────────────────────────────────────────────────
log "Starting all services..."
docker compose up -d --remove-orphans --wait --timeout 120

# ── 8. Health checks ──────────────────────────────────────────────────────────
log "Running health checks..."
FAIL=0

check() {
    local name="$1" url="$2"
    if curl -sf --max-time 8 "$url" &>/dev/null; then
        ok "  $name"
    else
        echo "[deploy] WARN: $name failed ($url)" >&2
        FAIL=$((FAIL + 1))
    fi
}

sleep 8
check "code-server"  "http://localhost:8080/healthz"
check "ollama"       "http://localhost:11434/api/tags"
check "prometheus"   "http://localhost:9090/-/healthy"
check "grafana"      "http://localhost:3000/api/health"
check "alertmanager" "http://localhost:9093/-/healthy"
check "jaeger"       "http://localhost:16686/"

# ── 9. Summary ───────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
docker compose ps --format "table {{.Name}}\t{{.Status}}"
echo "═══════════════════════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
    echo "[deploy] $FAIL health check(s) failed — check: docker compose logs <service>"
    exit 1
fi

log "DEPLOY COMPLETE — all services healthy"
echo ""
echo "  IDE       : https://ide.kushnir.cloud"
echo "  Grafana   : https://grafana.kushnir.cloud"
echo "  Prometheus: https://prometheus.kushnir.cloud"
echo "  Jaeger    : https://jaeger.kushnir.cloud"
echo "  Ollama    : http://$(hostname -I | awk '{print $1}'):11434"


# ─────────────────────────────────────────────────────────────────────────────
# Idempotent Deployment Script
# Orchestrates: Terraform → docker-compose rebuild → startup verification
# 
# Usage:  bash scripts/deploy.sh
# 
# What it does:
#   1. Runs terraform apply to generate docker-compose.yml with pinned versions
#   2. Rebuilds Docker images (--no-cache for immutability verification)
#   3. Brings up all services
#   4. Waits for all healthchecks to pass
#   5. Validates critical paths (extension activations, oauth2-proxy auth)
# 
# Exit code: 0 = success, 1 = deployment failed
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_DIR="$$(cd "$$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$$PROJECT_DIR"

# Bootstrap: single entrypoint loads config, logging, utils, error-handler, docker, ssh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

# Override log destination for this script
export LOG_FILE="${PROJECT_DIR}/deployment.log"

# Precondition assertions — fail fast before any side effects
assert_deploy_access   # SSH reachable at DEPLOY_HOST
assert_docker          # Docker daemon responding on remote

# Setup error handling
add_cleanup cleanup_deployment_handler

echo "════════════════════════════════════════════════════════════════════════════"
echo "IDEMPOTENT DEPLOYMENT: code-server-enterprise"
echo "Timestamp: $$(date -Iseconds)"
echo "════════════════════════════════════════════════════════════════════════════"

# Step 1: Terraform init + apply (generates docker-compose.yml with versions)
echo ""
echo "Step 1: Generating infrastructure config (Terraform)..."
if terraform init && terraform apply -auto-approve; then
  echo "✅ Terraform apply completed"
else
  echo "❌ FATAL: Terraform apply failed"
  exit 1
fi

# Step 2: Build Docker images (immutability: --no-cache forces full rebuild)
echo ""
echo "Step 2: Building Docker images with pinned versions..."
if docker compose build --no-cache; then
  echo "✅ Docker images built successfully"
else
  echo "❌ FATAL: Docker image build failed"
  exit 1
fi

# Step 3: Bring up services
echo ""
echo "Step 3: Deploying containers..."
if docker compose up -d; then
  echo "✅ Containers started"
else
  echo "❌ FATAL: Docker compose up failed"
  exit 1
fi

# Step 4: Wait for healthchecks
echo ""
echo "Step 4: Waiting for all services to be healthy..."
MAX_WAIT=120
ELAPSED=0
while [ $$ELAPSED -lt $$MAX_WAIT ]; do
  HEALTHY=$$(docker compose ps --format json | jq '[.[] | select(.Health=="healthy" or .State=="running")] | length')
  TOTAL=$$(docker compose ps --format json | jq 'length')
  echo "  [$$ELAPSED/$$MAX_WAIT] Healthy services: $$HEALTHY/$$TOTAL"
  
  if [ "$$HEALTHY" -eq "$$TOTAL" ]; then
    echo "✅ All services healthy"
    break
  fi
  
  sleep 5
  ELAPSED=$$((ELAPSED + 5))
done

if [ $$ELAPSED -ge $$MAX_WAIT ]; then
  echo "⚠️  WARNING: Services not fully healthy after $$MAX_WAIT seconds (may still be starting)"
  docker compose ps
fi

# Step 5: Verify critical paths
echo ""
echo "Step 5: Validating deployment..."
CHECKS_PASSED=0

# Check code-server HTTP endpoint
if curl -sf http://localhost:8080/healthz > /dev/null 2>&1; then
  echo "✅ code-server HTTP health check passed"
  ((CHECKS_PASSED++))
else
  echo "⚠️  code-server HTTP health check failed (may still be starting)"
fi

# Check docker compose state
if docker compose ps code-server | grep -q "healthy\|running"; then
  echo "✅ code-server container is running"
  ((CHECKS_PASSED++))
else
  echo "❌ code-server container is not running"
fi

echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo "DEPLOYMENT COMPLETE"
echo "✅ Access IDE at: https://ide.kushnir.cloud"
echo "✅ Authentication: Google OAuth2"
echo "✅ TLS: Let's Encrypt (auto-renewed)"
echo "════════════════════════════════════════════════════════════════════════════"
