#!/usr/bin/env bash
# @file        scripts/lib/policy-bundle.sh
# @module      policy/bundle
# @description Fetch, cache, and validate admin-portal policy bundle for the current session.
#              Implements fail-safe: deny-mutating when portal is unreachable.
#
# Usage: source scripts/lib/policy-bundle.sh
#        policy_bundle_load [user_email]   # fetch and cache bundle
#        policy_bundle_check_revocation    # check if session is still valid
#        policy_bundle_assert_not_revoked  # exit 1 if session is revoked

POLICY_PORTAL_URL="${POLICY_PORTAL_URL:-https://kushnir.cloud}"
POLICY_BUNDLE_CACHE="${POLICY_BUNDLE_CACHE:-/tmp/policy-bundle-$$.json}"
POLICY_CACHE_TTL="${POLICY_CACHE_TTL:-300}"   # seconds
POLICY_FAIL_SAFE="${POLICY_FAIL_SAFE:-deny-mutating}"

_pb_log()  { echo "[policy-bundle] $*"; }
_pb_warn() { echo "[policy-bundle] WARN: $*" >&2; }

# Determine cache age in seconds
_cache_age() {
  local cache_file="$1"
  local now ref_time
  now=$(date +%s)
  if [[ -f "$cache_file" ]]; then
    ref_time=$(stat -c %Y "$cache_file" 2>/dev/null || date +%s)
    echo $(( now - ref_time ))
  else
    echo 9999
  fi
}

policy_bundle_load() {
  local user="${1:-${WORKSPACE_USER:-unknown}}"
  local age
  age=$(_cache_age "$POLICY_BUNDLE_CACHE")

  # Return cached bundle if fresh
  if [[ "$age" -lt "$POLICY_CACHE_TTL" && -s "$POLICY_BUNDLE_CACHE" ]]; then
    _pb_log "using cached policy bundle (age=${age}s, ttl=${POLICY_CACHE_TTL}s)"
    return 0
  fi

  # Attempt to fetch from admin portal
  if command -v curl >/dev/null 2>&1; then
    local response
    response=$(curl -sf --max-time 5 \
      -H "Authorization: Bearer ${GITHUB_TOKEN:-}" \
      -H "X-Workspace-User: $user" \
      "${POLICY_PORTAL_URL}/api/v1/policy-bundle?user=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$user" 2>/dev/null || echo "$user")" \
      2>/dev/null || echo "")

    if [[ -n "$response" ]]; then
      echo "$response" > "$POLICY_BUNDLE_CACHE"
      _pb_log "policy bundle fetched from portal for $user"
      return 0
    fi
  fi

  # Portal unreachable — apply fail-safe
  _pb_warn "admin portal unreachable — fail_safe_mode=$POLICY_FAIL_SAFE"
  if [[ -s "$POLICY_BUNDLE_CACHE" ]]; then
    _pb_warn "using stale cached bundle (fail-safe)"
  fi

  if [[ "$POLICY_FAIL_SAFE" == "deny-all" ]]; then
    _pb_log "FAIL_SAFE=deny-all: IDE access denied while portal is unreachable"
    return 2
  fi

  # deny-mutating or read-only-cache: proceed with limitations
  return 0
}

policy_bundle_check_revocation() {
  local user="${1:-${WORKSPACE_USER:-unknown}}"
  local revoke_url="${POLICY_PORTAL_URL}/api/v1/session/revoked?user=${user}"

  if command -v curl >/dev/null 2>&1; then
    local status
    status=$(curl -sf --max-time 3 \
      -H "Authorization: Bearer ${GITHUB_TOKEN:-}" \
      "$revoke_url" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print('revoked' if d.get('revoked') else 'active')
except Exception:
    print('unknown')
" 2>/dev/null || echo "unknown")

    case "$status" in
      revoked)
        _pb_log "session REVOKED by admin portal for $user"
        return 1 ;;
      active)
        return 0 ;;
      *)
        _pb_warn "could not determine revocation status — treating as active"
        return 0 ;;
    esac
  fi

  return 0
}

policy_bundle_assert_not_revoked() {
  policy_bundle_check_revocation "$@" || {
    echo "[policy-bundle] FATAL: session has been revoked — exiting" >&2
    exit 1
  }
}
