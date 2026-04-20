#!/usr/bin/env bash
# @file        scripts/ci/verify-cloudflare-admin-access.sh
# @module      ci/security
# @description verify admin endpoints are protected by Cloudflare Access challenge or denial
# @owner       platform
# @status      active
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

BASE_URL="${ADMIN_BASE_URL:-https://ide.${APEX_DOMAIN:-kushnir.cloud}}"
EXPECTED_BLOCK_CODES="${EXPECTED_BLOCK_CODES:-302,401,403}"
RAW_PATHS="${ADMIN_ENDPOINT_PATHS:-/grafana/ /prometheus/ /alertmanager/ /jaeger/}"
REPORT_DIR="${REPORT_DIR:-artifacts/triage}"
REPORT_FILE="${REPORT_DIR}/cloudflare-admin-access-verify.md"

IFS=',' read -r -a EXPECTED_CODES <<< "$EXPECTED_BLOCK_CODES"
read -r -a ENDPOINT_PATHS <<< "$RAW_PATHS"

ensure_report_dir() {
  mkdir -p "$REPORT_DIR"
}

code_is_expected() {
  local code="$1"
  local expected
  for expected in "${EXPECTED_CODES[@]}"; do
    if [[ "$code" == "$expected" ]]; then
      return 0
    fi
  done
  return 1
}

probe_endpoint() {
  local path="$1"
  local url="${BASE_URL%/}${path}"
  local headers_file
  headers_file="$(mktemp)"

  local code
  code="$(curl -ksS -o /dev/null -D "$headers_file" -w '%{http_code}' "$url" || true)"

  local location
  location="$(grep -i '^location:' "$headers_file" | head -n1 | sed 's/^[Ll]ocation:[[:space:]]*//;s/\r$//' || true)"

  local access_markers
  access_markers="$(grep -Ei '^(cf-ray:|set-cookie:.*CF_Authorization|location:.*cdn-cgi/access)' "$headers_file" || true)"

  local outcome="FAIL"
  local reason="Returned unexpected status code"
  local auth_layer="unknown"

  if [[ "$location" == *"/cdn-cgi/access"* ]]; then
    auth_layer="cloudflare_access"
  elif [[ "$location" == *"/oauth2/start"* ]]; then
    auth_layer="oauth2_proxy"
  fi

  if code_is_expected "$code"; then
    outcome="PASS"
    reason="Returned expected block/challenge status code"
  elif [[ "$code" == "000" ]]; then
    reason="No HTTP response (network/DNS/edge unreachable)"
  fi

  rm -f "$headers_file"

  printf '%s|%s|%s|%s|%s|%s\n' "$path" "$code" "$outcome" "$reason" "$auth_layer" "$location"

  if [[ -n "$access_markers" ]]; then
    log_debug "Access markers for ${url}: ${access_markers//$'\n'/ ; }"
  fi
}

write_report_header() {
  cat > "$REPORT_FILE" <<EOF
# Cloudflare Admin Access Verification

- Timestamp (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')
- Base URL: ${BASE_URL}
- Expected block/challenge status codes: ${EXPECTED_BLOCK_CODES}

| Endpoint | HTTP | Result | Reason | Redirect/Location |
|---|---:|---|---|---|
EOF
}

main() {
  require_command curl

  ensure_report_dir
  write_report_header

  local failed=0
  local row

  log_info "Verifying Cloudflare Access protection for admin endpoints"
  for path in "${ENDPOINT_PATHS[@]}"; do
    row="$(probe_endpoint "$path")"
    IFS='|' read -r endpoint status result reason auth_layer location <<< "$row"

    echo "| ${endpoint} | ${status} | ${result} | ${reason} (${auth_layer}) | ${location:-n/a} |" >> "$REPORT_FILE"

    if [[ "$result" != "PASS" ]]; then
      failed=1
      log_error "${endpoint} returned ${status}: ${reason}"
    else
      log_info "${endpoint} returned ${status} (protected)"
    fi
  done

  if [[ $failed -ne 0 ]]; then
    log_error "Cloudflare admin access verification failed; see ${REPORT_FILE}"
    return 1
  fi

  log_info "Cloudflare admin access verification passed; report written to ${REPORT_FILE}"
  return 0
}

main "$@"