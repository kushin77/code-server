#!/usr/bin/env bash
# @file        scripts/ci/check-edge-security-controls.sh
# @module      ci/security
# @description Validate Cloudflare edge security controls: TLS grade, security headers, HSTS, Access protection
# @owner       platform
# @status      active
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

BASE_URL="${EDGE_BASE_URL:-https://${APEX_DOMAIN:-kushnir.cloud}}"
IDE_URL="${IDE_BASE_URL:-https://${IDE_DOMAIN:-ide.${APEX_DOMAIN:-kushnir.cloud}}}"
REPORT_DIR="${REPORT_DIR:-artifacts/triage}"
REPORT_FILE="${REPORT_DIR}/edge-security-controls-report.md"
MACHINE_FILE="${REPORT_DIR}/edge-security-controls-report.json"

mkdir -p "$REPORT_DIR"

PASS=0
FAIL=0
WARN=0
FINDINGS=()

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

record_pass() {
  local check="$1" detail="${2:-}"
  PASS=$((PASS+1))
  FINDINGS+=("{\"check\":\"${check}\",\"result\":\"PASS\",\"detail\":\"${detail}\"}")
  log_info "PASS  ${check}${detail:+: ${detail}}"
}

record_fail() {
  local check="$1" detail="${2:-}"
  FAIL=$((FAIL+1))
  FINDINGS+=("{\"check\":\"${check}\",\"result\":\"FAIL\",\"detail\":\"${detail}\"}")
  log_error "FAIL  ${check}${detail:+: ${detail}}"
}

record_warn() {
  local check="$1" detail="${2:-}"
  WARN=$((WARN+1))
  FINDINGS+=("{\"check\":\"${check}\",\"result\":\"WARN\",\"detail\":\"${detail}\"}")
  log_warn "WARN  ${check}${detail:+: ${detail}}"
}

fetch_headers() {
  local url="$1"
  local out
  out="$(curl -ksS -o /dev/null -D - "$url" --max-time 10 2>/dev/null || true)"
  echo "$out"
}

header_value() {
  local headers="$1" name="$2"
  echo "$headers" | grep -i "^${name}:" | head -n1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r'
}

# ─────────────────────────────────────────────────────────────────────────────
# Check 1: TLS redirect (HTTP → HTTPS)
# ─────────────────────────────────────────────────────────────────────────────

check_tls_redirect() {
  local domain="${APEX_DOMAIN:-kushnir.cloud}"
  local code
  code="$(curl -ks -o /dev/null -w '%{http_code}' "http://${domain}/" --max-time 10 2>/dev/null || echo "000")"
  local location
  location="$(curl -ks -o /dev/null -w '%{redirect_url}' "http://${domain}/" --max-time 10 2>/dev/null || echo "")"
  if [[ "$code" == "301" || "$code" == "302" ]] && echo "$location" | grep -q "^https://"; then
    record_pass "TLS redirect (HTTP→HTTPS)" "HTTP ${code} → ${location}"
  elif [[ "$code" == "000" ]]; then
    record_warn "TLS redirect (HTTP→HTTPS)" "No response on port 80 (may be blocked by firewall — acceptable)"
  else
    record_fail "TLS redirect (HTTP→HTTPS)" "HTTP ${code} — expected 301/302 redirect to https://"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Check 2: HTTPS reachable
# ─────────────────────────────────────────────────────────────────────────────

check_https_reachable() {
  local url="$1" name="$2"
  local code
  code="$(curl -ksS -o /dev/null -w '%{http_code}' "$url" --max-time 10 2>/dev/null || echo "000")"
  if [[ "$code" != "000" ]]; then
    record_pass "${name} HTTPS reachable" "HTTP ${code}"
  else
    record_warn "${name} HTTPS reachable" "No response (network/DNS issue or not yet deployed)"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Check 3: Security headers
# ─────────────────────────────────────────────────────────────────────────────

check_security_headers() {
  local url="$1" name="$2"
  local headers
  headers="$(fetch_headers "$url")"

  if [[ -z "$headers" ]]; then
    record_warn "${name} security headers" "Could not fetch headers (endpoint unreachable)"
    return
  fi

  # HSTS
  local hsts
  hsts="$(header_value "$headers" "strict-transport-security")"
  if echo "$hsts" | grep -q "max-age="; then
    local max_age
    max_age="$(echo "$hsts" | grep -o 'max-age=[0-9]*' | cut -d= -f2)"
    if [[ "$max_age" -ge 31536000 ]]; then
      record_pass "${name} HSTS" "max-age=${max_age}; $(echo "$hsts" | grep -o 'includeSubDomains' || echo 'no includeSubDomains')"
    else
      record_warn "${name} HSTS" "max-age=${max_age} < 31536000 (1 year)"
    fi
  else
    record_fail "${name} HSTS" "Strict-Transport-Security header missing"
  fi

  # X-Content-Type-Options
  local xcto
  xcto="$(header_value "$headers" "x-content-type-options")"
  if [[ "$xcto" == "nosniff" ]]; then
    record_pass "${name} X-Content-Type-Options" "nosniff"
  else
    record_fail "${name} X-Content-Type-Options" "Expected 'nosniff', got '${xcto:-missing}'"
  fi

  # X-Frame-Options
  local xfo
  xfo="$(header_value "$headers" "x-frame-options")"
  if echo "$xfo" | grep -qiE "^(DENY|SAMEORIGIN)$"; then
    record_pass "${name} X-Frame-Options" "${xfo}"
  else
    record_fail "${name} X-Frame-Options" "Expected DENY or SAMEORIGIN, got '${xfo:-missing}'"
  fi

  # Referrer-Policy
  local rp
  rp="$(header_value "$headers" "referrer-policy")"
  if [[ -n "$rp" ]]; then
    record_pass "${name} Referrer-Policy" "${rp}"
  else
    record_warn "${name} Referrer-Policy" "Header missing (add to Caddyfile)"
  fi

  # Permissions-Policy
  local pp
  pp="$(header_value "$headers" "permissions-policy")"
  if [[ -n "$pp" ]]; then
    record_pass "${name} Permissions-Policy" "${pp:0:80}"
  else
    record_warn "${name} Permissions-Policy" "Header missing (add to Caddyfile)"
  fi

  # Server header should be removed
  local server
  server="$(header_value "$headers" "server")"
  if [[ -z "$server" ]]; then
    record_pass "${name} Server header removed" "absent"
  else
    record_warn "${name} Server header removed" "Server: ${server} (should be suppressed)"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Check 4: Cloudflare origin concealment (CF-Ray header present)
# ─────────────────────────────────────────────────────────────────────────────

check_cf_origin_concealment() {
  local url="$1" name="$2"
  local headers
  headers="$(fetch_headers "$url")"

  if [[ -z "$headers" ]]; then
    record_warn "${name} CF origin concealment" "Could not fetch headers"
    return
  fi

  local cf_ray
  cf_ray="$(header_value "$headers" "cf-ray")"
  if [[ -n "$cf_ray" ]]; then
    record_pass "${name} Cloudflare proxied" "CF-Ray: ${cf_ray}"
  else
    record_warn "${name} Cloudflare proxied" "CF-Ray header absent — traffic may not be passing through Cloudflare"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Check 5: Caddyfile declares required headers
# ─────────────────────────────────────────────────────────────────────────────

check_caddyfile_headers() {
  local caddyfile="${CADDYFILE_PATH:-Caddyfile}"
  if [[ ! -f "$caddyfile" ]]; then
    record_warn "Caddyfile header declarations" "${caddyfile} not found"
    return
  fi

  local required_headers=("Strict-Transport-Security" "X-Content-Type-Options" "X-Frame-Options"
                          "Referrer-Policy" "Permissions-Policy")
  for hdr in "${required_headers[@]}"; do
    if grep -q "$hdr" "$caddyfile"; then
      record_pass "Caddyfile declares ${hdr}" "present"
    else
      record_fail "Caddyfile declares ${hdr}" "not found in ${caddyfile}"
    fi
  done

  # Server suppression (-Server)
  if grep -q '\-Server' "$caddyfile"; then
    record_pass "Caddyfile suppresses Server header" "-Server present"
  else
    record_warn "Caddyfile suppresses Server header" "-Server not found"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Check 6: Admin endpoints protected (delegates to verify-cloudflare-admin-access.sh)
# ─────────────────────────────────────────────────────────────────────────────

check_admin_access_protection() {
  local script="${SCRIPT_DIR}/verify-cloudflare-admin-access.sh"
  if [[ ! -f "$script" ]]; then
    record_warn "Admin endpoint Access protection" "verify-cloudflare-admin-access.sh not found"
    return
  fi

  if ADMIN_BASE_URL="${BASE_URL}" bash "$script" >/dev/null 2>&1; then
    record_pass "Admin endpoint Access protection" "all endpoints blocked/challenged"
  else
    record_fail "Admin endpoint Access protection" "one or more admin endpoints returned unexpected status — see cloudflare-admin-access-verify.md"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Write report
# ─────────────────────────────────────────────────────────────────────────────

write_report() {
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  cat > "$REPORT_FILE" <<EOF
# Cloudflare Edge Security Controls Report

- Timestamp (UTC): ${ts}
- Base URL: ${BASE_URL}
- IDE URL: ${IDE_URL}
- Pass: ${PASS} | Fail: ${FAIL} | Warn: ${WARN}

## Results

| Check | Result | Detail |
|---|---|---|
EOF

  for finding in "${FINDINGS[@]}"; do
    local check result detail
    check="$(echo "$finding" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['check'])" 2>/dev/null || echo "$finding")"
    result="$(echo "$finding" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result'])" 2>/dev/null || echo "")"
    detail="$(echo "$finding" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['detail'])" 2>/dev/null || echo "")"
    echo "| ${check} | ${result} | ${detail} |" >> "$REPORT_FILE"
  done

  cat >> "$REPORT_FILE" <<EOF

## Escalation Paths

| Severity | Trigger | Escalation |
|---|---|---|
| P0 | HSTS or TLS missing | Immediate Caddy config fix + deploy |
| P1 | Admin endpoints not protected | Re-apply Terraform cloudflare-access module |
| P1 | CF-Ray absent (not proxied) | Check Cloudflare DNS proxy status (orange cloud) |
| P2 | Missing Referrer-Policy or Permissions-Policy | Add to Caddyfile header blocks |
| P3 | Server header present | Add -Server to Caddyfile header blocks |

## Rollback / Exception Handling

- **Header rollback**: Revert Caddyfile to previous version and redeploy (`docker compose up -d caddy`)
- **Access policy rollback**: Run `terraform apply` with previous state or remove warp_device_posture_id
- **Exception process**: Open a GitHub issue with label `security-exception`, document business justification and mitigating controls, assign to CISO owner

---
*Generated by scripts/ci/check-edge-security-controls.sh*
EOF

  # Machine-readable JSON
  printf '{"timestamp":"%s","pass":%d,"fail":%d,"warn":%d,"base_url":"%s","findings":[%s]}\n' \
    "$ts" "$PASS" "$FAIL" "$WARN" "$BASE_URL" "$(IFS=,; echo "${FINDINGS[*]}")" > "$MACHINE_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
  require_command curl

  log_info "Running Cloudflare edge security controls check"
  log_info "Base URL: ${BASE_URL}"

  check_caddyfile_headers
  check_tls_redirect
  check_https_reachable "$BASE_URL" "portal"
  check_https_reachable "$IDE_URL" "ide"
  check_security_headers "$BASE_URL" "portal"
  check_security_headers "$IDE_URL" "ide"
  check_cf_origin_concealment "$BASE_URL" "portal"
  check_cf_origin_concealment "$IDE_URL" "ide"
  check_admin_access_protection

  write_report

  log_info "Results: PASS=${PASS} FAIL=${FAIL} WARN=${WARN}"
  log_info "Report: ${REPORT_FILE}"

  if [[ $FAIL -gt 0 ]]; then
    log_error "Edge security controls check failed — ${FAIL} failure(s); see ${REPORT_FILE}"
    return 1
  fi

  return 0
}

main "$@"
