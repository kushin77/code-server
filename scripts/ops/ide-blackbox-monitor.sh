#!/usr/bin/env bash
# @file        scripts/ops/ide-blackbox-monitor.sh
# @module      ops/monitoring
# @description Blackbox probe for ide.kushnir.cloud failover continuity and LB cookie health.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

IDE_BASE_URL="${IDE_BASE_URL:-https://ide.kushnir.cloud}"
REQUEST_TIMEOUT_SECONDS="${REQUEST_TIMEOUT_SECONDS:-20}"
REQUIRE_LB_COOKIE="${REQUIRE_LB_COOKIE:-1}"

headers_root="$(mktemp)"
headers_oauth="$(mktemp)"
trap 'rm -f "$headers_root" "$headers_oauth"' EXIT

probe() {
  local url="$1"
  local out_file="$2"
  curl -kfsS -D "$out_file" -o /dev/null --max-time "$REQUEST_TIMEOUT_SECONDS" "$url"
  awk 'NR==1 {print $2}' "$out_file"
}

assert_status_in() {
  local status="$1"
  shift
  local allowed=("$@")
  local ok=1
  for code in "${allowed[@]}"; do
    if [[ "$status" == "$code" ]]; then
      ok=0
      break
    fi
  done

  if [[ "$ok" -ne 0 ]]; then
    log_fatal "Unexpected status code '$status' (allowed: ${allowed[*]})"
  fi
}

log_info "Blackbox probe start: $IDE_BASE_URL"

root_status="$(probe "$IDE_BASE_URL/" "$headers_root")"
assert_status_in "$root_status" "200" "302" "303" "401" "403"

oauth_start_status="$(probe "$IDE_BASE_URL/oauth2/start?rd=/" "$headers_oauth")"
assert_status_in "$oauth_start_status" "302" "303"

if [[ "$REQUIRE_LB_COOKIE" == "1" ]]; then
  if ! grep -iq '^set-cookie: ide_lb_shared=' "$headers_root" && ! grep -iq '^set-cookie: ide_lb_shared=' "$headers_oauth"; then
    log_fatal "Sticky LB cookie ide_lb_shared was not observed in response headers"
  fi
fi

log_info "Blackbox probe passed: root=$root_status oauth_start=$oauth_start_status"