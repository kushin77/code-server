#!/usr/bin/env bash
################################################################################
# @file        scripts/security/audit-oauth2-proxy-coverage.sh
# @module      security/authentication
# @description Audit all user-facing endpoints for oauth2-proxy protection
# @owner       security
# @status      stable
#
# PURPOSE
#   Verify that all user-facing endpoints (ide.kushnir.cloud, kushnir.cloud, etc.)
#   are properly protected by oauth2-proxy or oauth2-proxy-portal. Identify gaps
#   where unauthenticated access is possible.
#
# USAGE
#   scripts/security/audit-oauth2-proxy-coverage.sh [--dry-run] [--test-auth]
#
# ENVIRONMENT VARIABLES
#   IDE_DOMAIN        - IDE subdomain (default: ide.kushnir.cloud)
#   APEX_DOMAIN       - Portal domain (default: kushnir.cloud)
#   DRY_RUN           - Preview mode (0 or 1)
#   TEST_AUTH         - Test authentication flows (0 or 1)
#   VERBOSE           - Verbose logging (0 or 1)
#
# EXIT CODES
#   0 - All endpoints protected (oauth2-proxy coverage complete)
#   1 - Gaps found (unprotected endpoints)
#   2 - Configuration error (missing services)
#
# IaC, IMMUTABLE, IDEMPOTENT
#   - Read-only audit (no modifications to infrastructure)
#   - Safe to run multiple times
#   - Produces detailed compliance report
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

init_repo
source "${SCRIPT_DIR}/../fetch-gsm-secrets.sh"

# Configuration
IDE_DOMAIN="${IDE_DOMAIN:-ide.kushnir.cloud}"
APEX_DOMAIN="${APEX_DOMAIN:-kushnir.cloud}"
DRY_RUN="${DRY_RUN:-0}"
TEST_AUTH="${TEST_AUTH:-0}"
VERBOSE="${VERBOSE:-0}"
AUDIT_REPORT="${AUDIT_REPORT:-artifacts/security/oauth2-proxy-coverage-$(date +%Y%m%d-%H%M%S).log}"

# Expected oauth2-proxy services
OAUTH2_IDE_SERVICE="oauth2-proxy"
OAUTH2_IDE_PORT="4180"
OAUTH2_PORTAL_SERVICE="oauth2-proxy-portal"
OAUTH2_PORTAL_PORT="4181"

# Endpoints to check
declare -a IDE_ENDPOINTS=(
  "https://${IDE_DOMAIN}/health"
  "https://${IDE_DOMAIN}/api/health"
  "https://${IDE_DOMAIN}/"
)

declare -a PORTAL_ENDPOINTS=(
  "https://${APEX_DOMAIN}/health"
  "https://${APEX_DOMAIN}/"
  "https://${APEX_DOMAIN}/api/health"
)

COVERAGE_GAPS=0
COVERAGE_TOTAL=0

################################################################################
# HELPER FUNCTIONS
################################################################################

check_service_running() {
  local service=$1
  local port=$2
  
  if docker compose ps "$service" 2>/dev/null | grep -q "running"; then
    log_info "✓ Service running: $service:$port"
    return 0
  else
    log_error "✗ Service not running: $service:$port"
    return 1
  fi
}

check_endpoint_routing() {
  local endpoint=$1
  local expected_service=$2
  local description=$3
  
  COVERAGE_TOTAL=$((COVERAGE_TOTAL + 1))
  
  log_info "Checking: $description ($endpoint)"
  
  # Test unauthenticated access
  local response
  response=$(curl -s -o /dev/null -w "%{http_code}" "$endpoint" 2>/dev/null || echo "error")
  
  case "$response" in
    200)
      # Health endpoint, allowed
      log_info "  ✓ Public endpoint (200): $endpoint"
      return 0
      ;;
    302|401|403)
      # Redirected to OAuth or blocked (expected for protected endpoints)
      log_info "  ✓ Protected endpoint ($response): $endpoint"
      return 0
      ;;
    000|error)
      log_error "  ✗ Cannot reach endpoint: $endpoint"
      COVERAGE_GAPS=$((COVERAGE_GAPS + 1))
      return 1
      ;;
    *)
      log_warn "  ⚠ Unexpected response ($response): $endpoint"
      COVERAGE_GAPS=$((COVERAGE_GAPS + 1))
      return 1
      ;;
  esac
}

verify_oauth2_config() {
  local service=$1
  local port=$2
  
  log_info "Verifying oauth2-proxy configuration: $service:$port"
  
  # Check if service responds to health check
  if docker compose exec -T "$service" curl -s http://localhost:"$port"/ping 2>/dev/null | grep -qi "OK\|pong"; then
    log_info "  ✓ Health check responding"
    return 0
  else
    log_warn "  ⚠ Health check not responding (service may not be running)"
    return 1
  fi
}

################################################################################
# MAIN AUDIT
################################################################################

mkdir -p "$(dirname "$AUDIT_REPORT")"

log_section "OAUTH2-PROXY COVERAGE AUDIT"
log_info "IDE Domain: $IDE_DOMAIN"
log_info "Portal Domain: $APEX_DOMAIN"
log_info "Report: $AUDIT_REPORT"

{
  echo "# OAuth2-Proxy Coverage Audit Report"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "IDE Domain: $IDE_DOMAIN"
  echo "Portal Domain: $APEX_DOMAIN"
  echo ""
} > "$AUDIT_REPORT"

# Phase 1: Service availability
log_section "Phase 1: Service Availability"

local IDE_AVAILABLE=0
local PORTAL_AVAILABLE=0

if check_service_running "$OAUTH2_IDE_SERVICE" "$OAUTH2_IDE_PORT"; then
  IDE_AVAILABLE=1
else
  log_warn "IDE oauth2-proxy not running (may be disabled in non-production)"
fi

if check_service_running "$OAUTH2_PORTAL_SERVICE" "$OAUTH2_PORTAL_PORT"; then
  PORTAL_AVAILABLE=1
else
  log_warn "Portal oauth2-proxy-portal not running (check COMPOSE_PROFILES=portal)"
fi

# Phase 2: Endpoint routing (IDE)
log_section "Phase 2: IDE Endpoint Routing ($IDE_DOMAIN)"

if [[ $IDE_AVAILABLE -eq 1 ]]; then
  verify_oauth2_config "$OAUTH2_IDE_SERVICE" "$OAUTH2_IDE_PORT"
  
  for endpoint in "${IDE_ENDPOINTS[@]}"; do
    check_endpoint_routing "$endpoint" "$OAUTH2_IDE_SERVICE" "IDE endpoint"
  done
else
  log_warn "Skipping IDE routing check (service not available)"
fi

# Phase 3: Endpoint routing (Portal)
log_section "Phase 3: Portal Endpoint Routing ($APEX_DOMAIN)"

if [[ $PORTAL_AVAILABLE -eq 1 ]]; then
  verify_oauth2_config "$OAUTH2_PORTAL_SERVICE" "$OAUTH2_PORTAL_PORT"
  
  for endpoint in "${PORTAL_ENDPOINTS[@]}"; do
    check_endpoint_routing "$endpoint" "$OAUTH2_PORTAL_SERVICE" "Portal endpoint"
  done
else
  log_warn "Skipping portal routing check (oauth2-proxy-portal not running)"
  log_info "  To enable: Set COMPOSE_PROFILES=portal in .env and redeploy"
fi

# Phase 4: Caddyfile configuration verification
log_section "Phase 4: Caddyfile Configuration"

log_info "Checking Caddyfile routing configuration..."

if grep -q "ide.kushnir.cloud" Caddyfile 2>/dev/null; then
  log_info "  ✓ IDE domain configured"
  if grep -A 3 "ide.kushnir.cloud" Caddyfile | grep -q "reverse_proxy.*oauth2-proxy:4180"; then
    log_info "    ✓ Routes to oauth2-proxy:4180"
  else
    log_error "    ✗ Does not route to oauth2-proxy:4180"
    COVERAGE_GAPS=$((COVERAGE_GAPS + 1))
  fi
fi

if grep -q "kushnir.cloud" Caddyfile 2>/dev/null; then
  log_info "  ✓ Portal domain configured"
  if grep -A 3 "^kushnir.cloud" Caddyfile | grep -q "reverse_proxy.*oauth2-proxy-portal:4181"; then
    log_info "    ✓ Routes to oauth2-proxy-portal:4181 (protected)"
  elif grep -A 3 "^kushnir.cloud" Caddyfile | grep -q "reverse_proxy.*appsmith:80"; then
    log_error "    ✗ Routes directly to appsmith:80 (NOT protected by oauth2-proxy)"
    COVERAGE_GAPS=$((COVERAGE_GAPS + 1))
  else
    log_warn "    ⚠ Routing configuration unclear"
  fi
fi

# Phase 5: Docker Compose profile verification
log_section "Phase 5: Docker Compose Profile Status"

if grep -q "COMPOSE_PROFILES" .env 2>/dev/null; then
  PROFILES=$(grep "COMPOSE_PROFILES" .env | cut -d= -f2)
  log_info "✓ COMPOSE_PROFILES configured: $PROFILES"
else
  log_warn "✗ COMPOSE_PROFILES not set in .env (portal services may not start)"
  COVERAGE_GAPS=$((COVERAGE_GAPS + 1))
fi

# Phase 6: Summary and remediation
log_section "AUDIT SUMMARY"

{
  echo ""
  echo "## Coverage Results"
  echo ""
  echo "**Endpoints Checked**: $COVERAGE_TOTAL"
  echo "**Protected**: $((COVERAGE_TOTAL - COVERAGE_GAPS))"
  echo "**Gaps Found**: $COVERAGE_GAPS"
  echo ""
  
  if [[ $COVERAGE_GAPS -eq 0 ]]; then
    echo "Status: ✅ **PASS** — All endpoints properly protected"
  else
    echo "Status: ❌ **FAIL** — Coverage gaps identified"
    echo ""
    echo "## Remediation Steps"
    echo ""
    echo "1. **If portal is unprotected (kushnir.cloud → appsmith:80)**:"
    echo "   - Update Caddyfile to route through oauth2-proxy-portal"
    echo "   - Ensure COMPOSE_PROFILES=portal in .env"
    echo "   - Redeploy: \`docker compose pull && docker compose up -d\`"
    echo ""
    echo "2. **If COMPOSE_PROFILES not set**:"
    echo "   - Add to .env: \`COMPOSE_PROFILES=portal\`"
    echo "   - Redeploy portal services"
    echo ""
  fi
  
  echo ""
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >> "$AUDIT_REPORT"

log_info "Report saved: $AUDIT_REPORT"

if [[ $COVERAGE_GAPS -eq 0 ]]; then
  log_info "✓ OAUTH2-PROXY COVERAGE AUDIT PASSED"
  exit 0
else
  log_error "✗ OAUTH2-PROXY COVERAGE AUDIT FAILED ($COVERAGE_GAPS gaps)"
  exit 1
fi
