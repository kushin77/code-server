#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# scripts/deploy.sh — Production clean-rebuild deploy [REFACTORED]
# Target: ${DEPLOY_HOST} | NAS: ${NAS_PRIMARY_HOST}
# Steps : kill orphans → mount NAS → load secrets → rebuild all → healthcheck
# Usage : ./scripts/deploy.sh [--skip-nas] [--skip-pull]
# 
# PRODUCTION-FIRST: All configuration from config/_base-config.env
# No hardcoded values. Uses unified logging and config system.
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# ── Auto-load unified config and logging ─
source "$SCRIPT_DIR/_common/init.sh"

# ── Parse command-line arguments ─
SKIP_NAS=false
SKIP_PULL=false

for arg in "$@"; do
    case $arg in
        --skip-nas)  SKIP_NAS=true ;;
        --skip-pull) SKIP_PULL=true ;;
    esac
done

# ── Load configuration ─
config::load
NAS_HOST=$(config::get NAS_PRIMARY_HOST)
LOCAL_DATA_BASE=$(config::get LOCAL_DATA_BASE)
DEPLOY_HOST=$(config::get DEPLOY_HOST)

# Guard: Linux only
[[ "$(uname)" == "Linux" ]] || log::failure "Deploy must run on Linux at ${DEPLOY_HOST}" && exit 1

log::banner "Production Deployment"

# ── 1. Validate Configuration ────────────────────────────────────────────────
log::section "Configuration Validation"
config::validate DEPLOY_HOST NAS_PRIMARY_HOST LOCAL_DATA_BASE POSTGRES_PASSWORD REDIS_PASSWORD CODE_SERVER_PASSWORD
log::success "Configuration validated"

# ── 2. Load Secrets ──────────────────────────────────────────────────────────
log::task "Loading secrets from environment..."
if [[ -f "$SCRIPT_DIR/lib/secrets.sh" ]]; then
    # shellcheck source=scripts/lib/secrets.sh
    source "$SCRIPT_DIR/lib/secrets.sh"
    secrets_load_env 2>/dev/null || log::warn "Secrets file not found, using environment variables"
fi
log::success "Secrets loaded"

# ── 3. Mount NAS ─────────────────────────────────────────────────────────────
log::section "Infrastructure Setup"
NAS_MOUNT=$(config::get NAS_PRIMARY_MOUNT)
if [[ "$SKIP_NAS" == false ]]; then
    log::task "Mounting NAS from ${NAS_HOST}..."
    if mountpoint -q "$NAS_MOUNT"; then
        log::status "NAS Mount" "✅ Already mounted"
    else
        if [[ -f "$SCRIPT_DIR/nas-mount-31.sh" ]]; then
            sudo "$SCRIPT_DIR/nas-mount-31.sh" mount
            log::success "NAS mounted at $NAS_MOUNT"
        else
            log::warn "NAS mount script not found, skipping"
        fi
    fi
else
    log::task "Skipping NAS mount (--skip-nas flag)"
fi

# ── 4. Provision Local SSD Data Directories ──────────────────────────────────
log::task "Provisioning local SSD data directories..."
for dir in postgres redis; do
    mkdir -p "${LOCAL_DATA_BASE}/${dir}"
done
log::success "Local data directories provisioned: ${LOCAL_DATA_BASE}/{postgres,redis}"

# ── 5. Cleanup Containers ───────────────────────────────────────────────────
log::section "Container Cleanup"
log::task "Stopping all containers and removing orphans..."
cd "$REPO_DIR"

DOCKER_STOP_TIMEOUT=$(config::get DOCKER_STOP_TIMEOUT)
docker compose down --remove-orphans --timeout "$DOCKER_STOP_TIMEOUT" 2>/dev/null || true
log::success "Containers stopped"

log::task "Pruning dangling volumes..."
docker volume prune -f
log::success "Dangling volumes pruned"

log::task "Pruning dangling images..."
docker image prune -f
log::success "Dangling images pruned"

# ── 6. Pull Latest Images ────────────────────────────────────────────────────
if [[ "$SKIP_PULL" == false ]]; then
    log::section "Image Pulling"
    log::task "Pulling latest pinned images..."
    docker compose pull --quiet
    log::success "Images pulled"
else
    log::task "Skipping image pull (--skip-pull flag)"
fi

# ── 7. Export Environment Variables for Docker Compose ──────────────────────
log::section "Environment Export"
log::task "Exporting configuration for docker-compose..."
export POSTGRES_PASSWORD REDIS_PASSWORD CODE_SERVER_PASSWORD
export GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET OAUTH2_PROXY_COOKIE_SECRET
export GRAFANA_ADMIN_PASSWORD GITHUB_TOKEN
export POSTGRES_VERSION REDIS_VERSION CODE_SERVER_VERSION OLLAMA_VERSION
export POSTGRES_DB POSTGRES_USER REDIS_PORT CODE_SERVER_PORT OLLAMA_PORT
export POSTGRES_MEMORY_LIMIT POSTGRES_CPU_LIMIT REDIS_MEMORY_LIMIT REDIS_CPU_LIMIT
export CODE_SERVER_MEMORY_LIMIT CODE_SERVER_CPU_LIMIT
export NAS_PRIMARY_MOUNT NAS_REPLICA_MOUNT
log::success "Environment variables exported"

# ── 8. Start All Services ────────────────────────────────────────────────────
log::section "Service Startup"
log::task "Starting all services..."
DOCKER_WAIT_TIMEOUT=$(config::get DOCKER_WAIT_TIMEOUT)
docker compose up -d --remove-orphans --wait --timeout "$DOCKER_WAIT_TIMEOUT"
log::success "Services started"

# ── 9. Health Checks ────────────────────────────────────────────────────────
log::section "Health Verification"
sleep 8

HEALTHCHECK_CURL_TIMEOUT=$(config::get HEALTHCHECK_CURL_TIMEOUT)

_check_endpoint() {
    local name="$1" url="$2"
    if curl -sf --max-time "$HEALTHCHECK_CURL_TIMEOUT" "$url" &>/dev/null; then
        log::status "$name" "✅ Healthy"
    else
        log::failure "$name" "Failed: $url"
        return 1
    fi
}

FAIL=0
_check_endpoint "code-server"  "http://localhost:8080/healthz" || FAIL=$((FAIL + 1))
_check_endpoint "ollama"       "http://localhost:11434/api/tags" || FAIL=$((FAIL + 1))
_check_endpoint "prometheus"   "http://localhost:9090/-/healthy" || FAIL=$((FAIL + 1))
_check_endpoint "grafana"      "http://localhost:3000/api/health" || FAIL=$((FAIL + 1))
_check_endpoint "alertmanager" "http://localhost:9093/-/healthy" || FAIL=$((FAIL + 1))
_check_endpoint "jaeger"       "http://localhost:16686/" || FAIL=$((FAIL + 1))

# ── 10. Summary ──────────────────────────────────────────────────────────────
log::section "Deployment Summary"
log::divider
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
log::divider

if [[ $FAIL -gt 0 ]]; then
    log::failure "Deployment Incomplete" "$FAIL health check(s) failed"
    log::task "Debug: docker compose logs <service>"
    exit 1
else
    log::banner "Deployment Successful ✅"
    exit 0
fi
fi

log "DEPLOY COMPLETE — all services healthy"
echo ""
echo "  IDE       : https://ide.kushnir.cloud"
echo "  Grafana   : https://grafana.kushnir.cloud"
echo "  Prometheus: https://prometheus.kushnir.cloud"
echo "  Jaeger    : https://jaeger.kushnir.cloud"
echo "  Ollama    : http://$(hostname -I | awk '{print $1}'):11434"
