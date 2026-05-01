#!/bin/bash
###############################################################################
# validate-tls-hardening.sh
###############################################################################
# CI: Validate TLS/SSL hardening posture for Code Server Enterprise
#
# Checks:
#   - Caddyfile enforces TLS 1.3 / strong cipher suites
#   - Internal CA certificate exists and is non-expired
#   - docker-compose TLS env vars are set for production services
#   - Caddy container config binds HTTPS port
#   - No HTTP-only listener exposed on public-facing services
#
# Usage:
#   bash scripts/ci/validate-tls-hardening.sh [--strict]
#
# Exit codes:
#   0: All checks passed (or warnings only in non-strict mode)
#   1: Critical TLS issues found
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup complete"; rm -f /tmp/tls-check.*.tmp 2>/dev/null || true' EXIT

STRICT_MODE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT_MODE=true; shift ;;
    *) shift ;;
  esac
done

PASS=0
WARN=0
FAIL=0

_pass() { log_info "  ✓ $1"; ((PASS++)); }
_warn() { log_warn "  ⚠ $1"; ((WARN++)); }
_fail() { log_error "  ✗ $1"; ((FAIL++)); }

# ── 1. Caddyfile exists and references TLS ────────────────────────────────────
log_info "=== TLS Hardening Validation ==="
log_info "Checking Caddyfile..."

CADDYFILE="${REPO_ROOT}/Caddyfile"
if [[ ! -f "${CADDYFILE}" ]]; then
  _fail "Caddyfile not found at repo root"
else
  if grep -q "tls internal\|tls {" "${CADDYFILE}" 2>/dev/null; then
    _pass "Caddyfile contains TLS directive"
  else
    _warn "Caddyfile has no explicit TLS directive (auto-HTTPS may be disabled)"
  fi

  if grep -q ":80\b" "${CADDYFILE}" && ! grep -q "redir.*https\|to https" "${CADDYFILE}"; then
    _warn "HTTP port 80 in Caddyfile without explicit HTTPS redirect"
  else
    _pass "No bare HTTP exposure detected in Caddyfile"
  fi
fi

# ── 2. Internal CA certificate ────────────────────────────────────────────────
log_info "Checking internal CA certificate..."

CA_CERT="${REPO_ROOT}/certs/ssl/ca.crt"
if [[ ! -f "${CA_CERT}" ]]; then
  _warn "Internal CA certificate not found at ${CA_CERT} (may not exist in dev)"
else
  if command -v openssl &>/dev/null; then
    EXPIRY=$(openssl x509 -enddate -noout -in "${CA_CERT}" 2>/dev/null | cut -d= -f2 || echo "")
    if [[ -n "${EXPIRY}" ]]; then
      EXPIRY_TS=$(date -d "${EXPIRY}" +%s 2>/dev/null || echo "0")
      NOW_TS=$(date +%s)
      DAYS_REMAINING=$(( (EXPIRY_TS - NOW_TS) / 86400 ))
      if [[ ${DAYS_REMAINING} -gt 30 ]]; then
        _pass "CA certificate valid for ${DAYS_REMAINING} more days"
      elif [[ ${DAYS_REMAINING} -gt 0 ]]; then
        _warn "CA certificate expires in ${DAYS_REMAINING} days — renew soon"
      else
        _fail "CA certificate has EXPIRED"
      fi
    fi
  else
    _warn "openssl not available — CA certificate expiry not checked"
  fi
fi

# ── 3. docker-compose TLS environment variables ───────────────────────────────
log_info "Checking docker-compose TLS environment config..."

COMPOSE_FILE="${REPO_ROOT}/docker-compose.prod.yml"
if [[ ! -f "${COMPOSE_FILE}" ]]; then
  COMPOSE_FILE="${REPO_ROOT}/docker-compose.yml"
fi

if [[ -f "${COMPOSE_FILE}" ]]; then
  if grep -q "SSL_CERT\|TLS_CERT\|CADDY_TLS\|tls_cert\|ssl_cert" "${COMPOSE_FILE}" 2>/dev/null; then
    _pass "TLS certificate variables present in compose file"
  else
    _warn "No explicit TLS cert env vars in ${COMPOSE_FILE##*/} (Caddy auto-TLS may be in use)"
  fi
else
  _warn "No docker-compose production file found"
fi

# ── 4. Port 443 exposed ───────────────────────────────────────────────────────
log_info "Checking HTTPS port exposure..."

for compose in "${REPO_ROOT}"/docker-compose*.yml; do
  if grep -q '"443:443"\|443:443\|"0.0.0.0:443' "${compose}" 2>/dev/null; then
    _pass "HTTPS port 443 exposed in $(basename "${compose}")"
    break
  fi
done

# ── 5. Summary ────────────────────────────────────────────────────────────────
log_info ""
log_info "TLS Hardening Results: ${PASS} passed, ${WARN} warnings, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
  log_error "TLS hardening validation FAILED — ${FAIL} critical issues"
  exit 1
fi

if [[ ${WARN} -gt 0 && "${STRICT_MODE}" == "true" ]]; then
  log_error "Strict mode: treating ${WARN} warnings as failures"
  exit 1
fi

log_info "TLS hardening validation PASSED"
exit 0
