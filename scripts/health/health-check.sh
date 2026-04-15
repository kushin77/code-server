#!/bin/bash
################################################################################
# File:          health-check.sh
# Owner:         Platform Engineering
# Purpose:       Service health monitoring and availability verification
# Status:        ACTIVE
# Last Updated:  April 15, 2026
################################################################################
# Portable health check script — works from any directory
# Usage: ./health-check.sh [domain]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source logging library for structured logging
export LOG_FILE="${SCRIPT_DIR}/.logs/health-check.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || {
    echo "ERROR: Cannot source logging library at ${SCRIPT_DIR}/scripts/logging.sh"
    exit 1
}

COMPOSE_FILE="$(dirname "$0")/docker-compose.yml"
DOMAIN="${1:-localhost}"

log_section "CODE-SERVER ENTERPRISE HEALTH CHECK"

# Check Docker containers
log_info "Checking container status..."
docker compose -f "$COMPOSE_FILE" ps
log_success "Container status displayed"

log_info "Checking resource usage..."
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" \
  code-server oauth2-proxy caddy 2>/dev/null || log_warn "Some containers may not be running"

log_info "Testing network connectivity for ${DOMAIN}..."
if curl -sk --max-time 5 "https://${DOMAIN}" > /dev/null 2>&1; then
  log_success "HTTPS endpoint responding: https://${DOMAIN}"
else
  log_warn "HTTPS endpoint not responding: https://${DOMAIN}"
fi

if curl -sf --max-time 5 "http://localhost:4180/ping" > /dev/null 2>&1; then
  log_success "oauth2-proxy /ping endpoint: OK"
else
  log_warn "oauth2-proxy not responding"
fi

if curl -sf --max-time 5 "http://localhost:8080/healthz" > /dev/null 2>&1; then
  log_success "code-server /healthz endpoint: OK"
else
  log_warn "code-server not responding"
fi

log_info "Retrieving recent logs..."
docker compose -f "$COMPOSE_FILE" logs --tail=10 2>/dev/null || log_warn "No logs available"

log_success "HEALTH CHECK COMPLETE"
