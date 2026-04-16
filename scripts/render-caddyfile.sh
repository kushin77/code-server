#!/bin/bash
# File: scripts/render-caddyfile.sh
# Purpose: Render Caddyfile variants from Caddyfile.tpl template
# Status: active
# Usage: ./scripts/render-caddyfile.sh [prod|onprem|simple|all]

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(dirname "$SCRIPT_DIR")"
readonly TEMPLATE_FILE="${REPO_ROOT}/config/caddy/Caddyfile.tpl"
readonly OUTPUT_DIR="${REPO_ROOT}/config/caddy"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}✓${NC} $*"
}

log_error() {
  echo -e "${RED}✗${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $*"
}

# Check template exists
if [[ ! -f "$TEMPLATE_FILE" ]]; then
  log_error "Template not found: $TEMPLATE_FILE"
  exit 1
fi

# Load .env if it exists (for production defaults)
if [[ -f "${REPO_ROOT}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a
  source "${REPO_ROOT}/.env" 2>/dev/null || true
  set +a
fi

# Render production variant
render_prod() {
  local output="${OUTPUT_DIR}/Caddyfile"
  
  log_info "Rendering $output (production) from template..."
  
  CADDY_DOMAIN="${CADDY_DOMAIN:-ide.kushnir.cloud}" \
  CADDY_TLS_BLOCK="${CADDY_TLS_BLOCK:-tls internal}" \
  CADDY_LOG_LEVEL="${CADDY_LOG_LEVEL:-info}" \
  CODE_SERVER_UPSTREAM="${CODE_SERVER_UPSTREAM:-oauth2-proxy:4180}" \
  GRAFANA_PORT="${GRAFANA_PORT:-3000}" \
  PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}" \
  ALERTMANAGER_PORT="${ALERTMANAGER_PORT:-9093}" \
  JAEGER_PORT="${JAEGER_PORT:-16686}" \
  APEX_DOMAIN="${APEX_DOMAIN:-kushnir.cloud}" \
  DOMAIN="${CADDY_DOMAIN:-ide.kushnir.cloud}" \
  ENABLE_TELEMETRY="${ENABLE_TELEMETRY:-false}" \
  ENABLE_TRACING="${ENABLE_TRACING:-false}" \
  envsubst < "$TEMPLATE_FILE" > "$output"
  
  log_info "$output rendered"
}

# Render on-prem variant
render_onprem() {
  local output="${OUTPUT_DIR}/Caddyfile.onprem"
  
  log_info "Rendering $output (on-premises) from template..."
  
  CADDY_DOMAIN=":80" \
  CADDY_TLS_BLOCK="" \
  CADDY_LOG_LEVEL="info" \
  CODE_SERVER_UPSTREAM="oauth2-proxy:4180" \
  GRAFANA_PORT="3001" \
  PROMETHEUS_PORT="9090" \
  ALERTMANAGER_PORT="9093" \
  JAEGER_PORT="16686" \
  APEX_DOMAIN=":8080" \
  DOMAIN=":80" \
  ENABLE_TELEMETRY="false" \
  ENABLE_TRACING="false" \
  envsubst < "$TEMPLATE_FILE" > "$output"
  
  log_info "$output rendered"
}

# Render simple variant
render_simple() {
  local output="${OUTPUT_DIR}/Caddyfile.simple"
  
  log_info "Rendering $output (simple dev) from template..."
  
  CADDY_DOMAIN=":80" \
  CADDY_TLS_BLOCK="" \
  CADDY_LOG_LEVEL="debug" \
  CODE_SERVER_UPSTREAM="code-server:8080" \
  GRAFANA_PORT="3001" \
  PROMETHEUS_PORT="9090" \
  ALERTMANAGER_PORT="9093" \
  JAEGER_PORT="16686" \
  APEX_DOMAIN=":8080" \
  DOMAIN=":80" \
  ENABLE_TELEMETRY="false" \
  ENABLE_TRACING="false" \
  envsubst < "$TEMPLATE_FILE" > "$output"
  
  log_info "$output rendered"
}

# Validate Caddyfile syntax
validate_caddyfile() {
  local caddyfile="$1"
  
  if [[ ! -f "$caddyfile" ]]; then
    log_error "Caddyfile not found: $caddyfile"
    return 1
  fi
  
  if command -v caddy &> /dev/null; then
    if caddy validate --config "$caddyfile" &> /dev/null; then
      log_info "Caddyfile syntax valid: $caddyfile"
      return 0
    else
      log_error "Caddyfile syntax invalid: $caddyfile"
      caddy validate --config "$caddyfile"
      return 1
    fi
  else
    log_warn "caddy command not found - skipping syntax validation"
    return 0
  fi
}

# Main
main() {
  local target="${1:-all}"
  
  case "$target" in
    prod)
      render_prod
      validate_caddyfile "${OUTPUT_DIR}/Caddyfile"
      ;;
    onprem)
      render_onprem
      validate_caddyfile "${OUTPUT_DIR}/Caddyfile.onprem"
      ;;
    simple)
      render_simple
      validate_caddyfile "${OUTPUT_DIR}/Caddyfile.simple"
      ;;
    all)
      render_prod
      render_onprem
      render_simple
      log_info "All Caddyfile variants rendered"
      ;;
    validate)
      validate_caddyfile "${OUTPUT_DIR}/Caddyfile"
      ;;
    *)
      log_error "Unknown target: $target"
      echo "Usage: $0 [prod|onprem|simple|all|validate]"
      exit 1
      ;;
  esac
}

main "$@"
