#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# scripts/deploy.sh — Production clean-rebuild deploy
# Target: ${DEPLOY_HOST} | NAS: 192.168.168.56
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
[[ "$(uname)" == "Linux" ]] || die "Deploy must run on Linux at ${DEPLOY_HOST}"

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
