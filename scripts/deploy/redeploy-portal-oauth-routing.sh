#!/usr/bin/env bash
# scripts/deploy/redeploy-portal-oauth-routing.sh
# Redeploy the portal + oauth2 routing after Caddy template updates.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

: "${APEX_DOMAIN:?APEX_DOMAIN must be set}"

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
fi

log_info "Portal + OAuth routing redeploy"
log_info "APEX_DOMAIN=${APEX_DOMAIN}"
log_info "IDE_DOMAIN=${IDE_DOMAIN:-ide.${APEX_DOMAIN}}"
log_info "API_DOMAIN=${API_DOMAIN:-api.${APEX_DOMAIN}}"
log_info "AUTH_DOMAIN=${AUTH_DOMAIN:-auth.${APEX_DOMAIN}}"

export IDE_DOMAIN="${IDE_DOMAIN:-ide.${APEX_DOMAIN}}"
export API_DOMAIN="${API_DOMAIN:-api.${APEX_DOMAIN}}"
export AUTH_DOMAIN="${AUTH_DOMAIN:-auth.${APEX_DOMAIN}}"

if ${DRY_RUN}; then
  log_info "Dry run: validating Caddy config generation only"
  bash "${REPO_ROOT}/scripts/ops/generate-caddy-config.sh" generate
  caddy validate --config "${REPO_ROOT}/config/caddy/Caddyfile"
  log_success "Dry run completed successfully"
  exit 0
fi

bash "${REPO_ROOT}/scripts/ops/generate-caddy-config.sh" generate

if docker ps --format '{{.Names}}' | grep -q '^caddy-gateway$'; then
  log_info "Reloading running Caddy instance"
  docker exec caddy-gateway caddy reload --config /etc/caddy/Caddyfile
  log_success "Caddy reloaded successfully"
else
  log_info "Caddy is not running; start docker compose to apply the new config"
fi
