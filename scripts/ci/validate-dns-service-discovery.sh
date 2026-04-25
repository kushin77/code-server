#!/usr/bin/env bash
# @file        scripts/ci/validate-dns-service-discovery.sh
# @module      ci/networking
# @description Validate DNS service discovery — no hardcoded IPs in inter-service config
# @governance  GOV-002: Immutable, idempotent, version-controlled
# Issue #1536: Networking, DNS & Performance — DNS Service Discovery
#
# Checks:
#   1. No hardcoded IPs (192.168.168.x) in non-doc source files
#   2. All inter-service DATABASE_URL/REDIS_URL use service names, not IPs
#   3. Docker Compose service names resolve in the services network
#      (runtime check — requires containers to be running, skipped in CI dry-run)
#
# Usage:
#   bash scripts/ci/validate-dns-service-discovery.sh            # CI mode
#   bash scripts/ci/validate-dns-service-discovery.sh --runtime  # + live nslookup
#   DRY_RUN=1 bash scripts/ci/validate-dns-service-discovery.sh  # Report only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RUNTIME_CHECK="${1:-}"
DRY_RUN="${DRY_RUN:-0}"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass() { printf "${GREEN}  ✔  %s${NC}\n" "$*"; }
fail() { printf "${RED}  ✖  %s${NC}\n" "$*" >&2; }
warn() { printf "${YELLOW}  ⚠  %s${NC}\n" "$*" >&2; }
info() { printf "     %s\n" "$*"; }

PASS_COUNT=0
FAIL_COUNT=0

check_pass() { pass "$*"; (( PASS_COUNT++ )) || true; }
check_fail() { fail "$*"; (( FAIL_COUNT++ )) || true; }

# ── Check 1: No hardcoded IPs in source files ─────────────────────────────────
echo ""
echo "=== Check 1: No hardcoded IPs in source files ==="

IP_PATTERN='192\.168\.168\.(31|42|56)'
EXCLUDE_DIRS=('.git' '.backups' 'test-results' 'htmlcov' '__pycache__' 'node_modules' '.venv')

build_exclude_args() {
  local args=()
  for d in "${EXCLUDE_DIRS[@]}"; do
    args+=("--exclude-dir=${d}")
  done
  printf '%s ' "${args[@]}"
}

EXCLUDE_ARGS="$(build_exclude_args)"

HARDCODED_IN_SOURCE=$(
  # shellcheck disable=SC2086
  grep -rn ${EXCLUDE_ARGS} -E "${IP_PATTERN}" \
    --include='*.sh' \
    --include='*.yml' \
    --include='*.yaml' \
    --include='*.tf' \
    --include='*.tfvars' \
    --include='*.env' \
    --include='Caddyfile' \
    "${REPO_ROOT}" 2>/dev/null | \
    grep -v '\.md:' | \
    grep -v '^\s*#' | \
    grep -v ': *#' | \
    grep -v '_epic-1536-network-config\.env:' | \
    grep -v 'epic-1536-phase1-eliminate-hardcoding\.sh:' | \
    grep -v 'audit-network-hardcoding\.sh:' || true
)

if [ -z "${HARDCODED_IN_SOURCE}" ]; then
  check_pass "No hardcoded IPs (192.168.168.x) found in source files"
else
  check_fail "Hardcoded IPs found in source files:"
  while IFS= read -r line; do
    info "  ${line}"
  done <<< "${HARDCODED_IN_SOURCE}"
fi

# ── Check 2: Inter-service URLs use Docker service names ─────────────────────
echo ""
echo "=== Check 2: Inter-service URLs use Docker service names ==="

# Pattern: value should be a service name, not an IP
INTER_SERVICE_URLS=$(
  grep -n 'DATABASE_URL\|REDIS_URL\|LOKI_URL\|PROMETHEUS_URL\|TEMPO_URL' \
    "${REPO_ROOT}/docker-compose.yml" \
    "${REPO_ROOT}/docker-compose.observability.yml" \
    "${REPO_ROOT}/docker-compose.ai.yml" \
    2>/dev/null || true
)

IP_IN_SERVICE_URLS=$(
  echo "${INTER_SERVICE_URLS}" | \
    grep -E '=http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true
)

if [ -z "${IP_IN_SERVICE_URLS}" ]; then
  check_pass "All inter-service URLs use Docker service names (no IPs)"
else
  check_fail "Inter-service URLs with hardcoded IPs:"
  while IFS= read -r line; do
    info "  ${line}"
  done <<< "${IP_IN_SERVICE_URLS}"
fi

# ── Check 3: Required env vars are declared in _base-config.env ──────────────
echo ""
echo "=== Check 3: Host env vars declared in SSOT config ==="

BASE_CONFIG="${REPO_ROOT}/scripts/_common/_base-config.env"
REQUIRED_VARS=("PRIMARY_HOST" "REPLICA_HOST" "NAS_HOST" "APEX_DOMAIN" "IDE_DOMAIN")

for var in "${REQUIRED_VARS[@]}"; do
  if grep -q "${var}" "${BASE_CONFIG}" 2>/dev/null; then
    check_pass "${var} declared in _base-config.env"
  else
    check_fail "${var} MISSING from _base-config.env"
  fi
done

# ── Check 4: hosts.sh exists and exports helper functions ─────────────────────
echo ""
echo "=== Check 4: hosts.sh service-discovery library ==="

HOSTS_SH="${REPO_ROOT}/scripts/_common/hosts.sh"
if [ -f "${HOSTS_SH}" ]; then
  check_pass "hosts.sh exists at scripts/_common/hosts.sh"

  for fn in ssh_primary ssh_replica ssh_all_hosts check_host_connectivity; do
    if grep -q "^${fn}()\|^${fn} ()" "${HOSTS_SH}" 2>/dev/null || \
       grep -q "${fn}()" "${HOSTS_SH}" 2>/dev/null; then
      check_pass "  Function ${fn}() defined in hosts.sh"
    else
      warn "  Function ${fn}() not found in hosts.sh"
    fi
  done
else
  check_fail "hosts.sh missing from scripts/_common/"
fi

# ── Check 5: Caddy config uses env vars for domains ───────────────────────────
echo ""
echo "=== Check 5: Caddyfile uses domain env vars ==="

for caddyfile in "${REPO_ROOT}/Caddyfile" "${REPO_ROOT}/Caddyfile.tpl"; do
  if [ -f "${caddyfile}" ]; then
    filename="$(basename "${caddyfile}")"
    # Check for hardcoded domain (kushnir.cloud should only appear in template comments)
    HARDCODED_DOMAIN=$(
      grep -n 'kushnir\.cloud' "${caddyfile}" | grep -v '^\s*#' || true
    )
    if [ -z "${HARDCODED_DOMAIN}" ]; then
      check_pass "${filename}: no hardcoded domains (uses env vars)"
    else
      warn "${filename}: kushnir.cloud appears outside comments (may be intentional in .tpl):"
      while IFS= read -r line; do
        info "  ${line}"
      done <<< "${HARDCODED_DOMAIN}"
    fi
  fi
done

# ── Check 6 (Runtime): Live Docker DNS resolution ─────────────────────────────
if [ "${RUNTIME_CHECK}" = "--runtime" ] && [ "${DRY_RUN}" != "1" ]; then
  echo ""
  echo "=== Check 6: Live Docker DNS resolution ==="

  SERVICES_TO_CHECK=("postgres" "redis" "caddy" "loki" "grafana" "prometheus")
  CADDY_CONTAINER=$(docker ps --filter name=caddy --format '{{.Names}}' 2>/dev/null | head -1 || echo "")

  if [ -z "${CADDY_CONTAINER}" ]; then
    warn "Caddy container not running — skipping live DNS check"
  else
    for svc in "${SERVICES_TO_CHECK[@]}"; do
      if docker exec "${CADDY_CONTAINER}" nslookup "${svc}" >/dev/null 2>&1; then
        check_pass "DNS: '${svc}' resolves inside Caddy container"
      else
        check_fail "DNS: '${svc}' does NOT resolve inside Caddy container"
      fi
    done
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "======================================="
echo "  DNS Service Discovery Audit Summary"
echo "======================================="
printf "${GREEN}  PASSED: %d${NC}\n" "${PASS_COUNT}"
printf "${RED}  FAILED: %d${NC}\n" "${FAIL_COUNT}"
echo ""

if [ "${FAIL_COUNT}" -gt 0 ]; then
  echo "DNS service discovery validation FAILED — ${FAIL_COUNT} issue(s) require attention."
  exit 1
fi

echo "DNS service discovery validation PASSED."
exit 0
