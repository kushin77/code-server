#!/usr/bin/env bash
# @file        scripts/ops/reconcile-setup-state.sh
# @module      ops/ide
# @description Autopilot setup-state reconciler — corrects stale "Finish Setup" prompts by
#              running capability probes and re-syncing persisted setup flags.
#              Implements AC from #641: capability probes → compare → auto-correct → remediate.
#
# Usage: bash scripts/ops/reconcile-setup-state.sh [--dry-run] [--fix]

set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"
FIX_MODE="${1:-}"
[[ "$FIX_MODE" == "--dry-run" ]] && DRY_RUN=1

_log()  { echo "[setup-reconcile] $*"; }
_warn() { echo "[setup-reconcile] WARN: $*" >&2; }

PASS=0; FAIL=0; FIXED=0
REPORT_FILE="${SETUP_RECONCILE_REPORT:-/tmp/setup-reconcile-report.json}"
RESULTS=()
FAILED_REASONS=()

probe() {
  local name="$1" status="$2" reason_code="$3" detail="${4:-}"
  RESULTS+=("{\"probe\":$(printf '%s' "$name" | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))"),\"status\":\"$status\",\"reason_code\":\"$reason_code\",\"detail\":$(printf '%s' "$detail" | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))")}")
  if [[ "$status" == "ok" ]]; then
    _log "OK    $name [$reason_code]${detail:+: $detail}"
    PASS=$(( PASS + 1 ))
  else
    _warn "FAIL  $name [$reason_code]${detail:+: $detail}"
    FAIL=$(( FAIL + 1 ))
    FAILED_REASONS+=("$reason_code")
  fi
}

# ── Capability Probes ─────────────────────────────────────────────────────────

# 1. Git credential helper registered
if git config --global --get credential.helper 2>/dev/null | grep -q "gsm\|credential"; then
  probe "git-credential-helper" "ok" "HEALTHY" "$(git config --global --get credential.helper)"
else
  probe "git-credential-helper" "fail" "AUTH_HELPER_MISSING" "credential.helper not set or not gsm-backed"
  if [[ "$FIX_MODE" == "--fix" && "$DRY_RUN" != "1" ]]; then
    git config --global credential.helper "$(command -v git-credential-gsm 2>/dev/null || echo /usr/local/bin/git-credential-gsm)"
    FIXED=$(( FIXED + 1 ))
    _log "FIX: set git credential.helper"
  fi
fi

# 2. Auth keepalive running
KEEPALIVE_BIN="${AUTH_KEEPALIVE_BIN:-$(command -v auth-keepalive 2>/dev/null || echo scripts/auth-keepalive)}"
if [[ -x "$KEEPALIVE_BIN" ]] && "$KEEPALIVE_BIN" status > /dev/null 2>&1; then
  probe "auth-keepalive" "ok" "HEALTHY" "daemon running"
else
  probe "auth-keepalive" "fail" "AUTH_KEEPALIVE_STOPPED" "daemon not running"
  if [[ "$FIX_MODE" == "--fix" && "$DRY_RUN" != "1" && -x "$KEEPALIVE_BIN" ]]; then
    "$KEEPALIVE_BIN" start && FIXED=$(( FIXED + 1 )) && _log "FIX: started auth-keepalive"
  fi
fi

# 3. GSM env canonical
if [[ "${GSM_PROJECT:-}" == "gcp-eiq" && "${GSM_SECRET_NAME:-}" == "github-token" ]]; then
  probe "gsm-env-canonical" "ok" "HEALTHY"
else
  probe "gsm-env-canonical" "fail" "AUTH_ENV_DRIFT" "GSM_PROJECT=${GSM_PROJECT:-<unset>} GSM_SECRET_NAME=${GSM_SECRET_NAME:-<unset>}"
fi

# 4. GITHUB_TOKEN available
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  probe "github-token" "ok" "HEALTHY" "[set]"
else
  probe "github-token" "fail" "AUTH_SCOPE_MISSING" "GITHUB_TOKEN not set — git push/fetch may fail"
fi

# 5. code-server-auth doctor (if available)
if command -v code-server-auth >/dev/null 2>&1; then
  if code-server-auth doctor > /dev/null 2>&1; then
    probe "code-server-auth-doctor" "ok" "HEALTHY"
  else
    probe "code-server-auth-doctor" "fail" "AUTH_ENV_DRIFT" "auth doctor reported drift"
  fi
fi

# 6. Policy bundle/portal reachable (best-effort)
PORTAL="${POLICY_PORTAL_URL:-https://kushnir.cloud}"
if command -v curl >/dev/null 2>&1; then
  if curl -sf --max-time 3 "$PORTAL/health" > /dev/null 2>&1 || \
     curl -sf --max-time 3 "$PORTAL" > /dev/null 2>&1; then
    probe "admin-portal-reachable" "ok" "HEALTHY" "$PORTAL"
  else
    probe "admin-portal-reachable" "fail" "PORTAL_UNREACHABLE" "$PORTAL unreachable (fail-safe may apply)"
  fi
fi

# ── Auto-correct stale setup flags ────────────────────────────────────────────
SETUP_STATE_FILE="${HOME}/.local/share/code-server/User/globalStorage/github.copilot-chat/state.json"
if [[ -f "$SETUP_STATE_FILE" ]]; then
  _log "checking persisted setup state: $SETUP_STATE_FILE"
  # Detect 'finishSetup' flags that are stuck
  STALE=$(python3 -c "
import json, sys
try:
    with open('$SETUP_STATE_FILE') as f:
        d = json.load(f)
    flags = [k for k, v in d.items() if 'Finish' in k or 'setup' in k.lower() or 'Setup' in k]
    print(','.join(flags) if flags else '')
except Exception:
    print('')
" 2>/dev/null)
  if [[ -n "$STALE" ]]; then
    probe "setup-state-flags" "fail" "STATE_CACHE_STALE" "stale flags detected: $STALE"
    if [[ "$FIX_MODE" == "--fix" && "$DRY_RUN" != "1" && $FAIL -eq 0 ]]; then
      # Only auto-correct if all capability probes passed
      _log "FIX: all capabilities OK — clearing stale setup flags"
      python3 -c "
import json
try:
    with open('$SETUP_STATE_FILE') as f:
        d = json.load(f)
    keys_to_remove = [k for k, v in d.items() if 'Finish' in k]
    for k in keys_to_remove:
        del d[k]
    with open('$SETUP_STATE_FILE', 'w') as f:
        json.dump(d, f, indent=2)
    print(f'removed: {keys_to_remove}')
except Exception as e:
    print(f'error: {e}')
" && FIXED=$(( FIXED + 1 ))
    fi
  else
    probe "setup-state-flags" "ok" "HEALTHY" "no stale flags"
  fi
fi

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║  setup-state reconciler results           ║"
echo "╚═══════════════════════════════════════════╝"
echo "  probes: $((PASS + FAIL)) total — $PASS ok, $FAIL failing, $FIXED fixed"
if (( FAIL > 0 && FIXED < FAIL )); then
  echo "  STATUS: setup has $((FAIL - FIXED)) unresolved capability gap(s)"
  echo "  ACTION: run --fix to attempt auto-remediation"
  if (( ${#FAILED_REASONS[@]} > 0 )); then
    printf '  reason-codes: %s\n' "$(printf '%s\n' "${FAILED_REASONS[@]}" | sort -u | paste -sd ',' -)"
  fi
else
  echo "  STATUS: all capabilities healthy — setup state should resolve"
fi

# JSON report
{
  echo "{"
  echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"pass\": $PASS, \"fail\": $FAIL, \"fixed\": $FIXED,"
  echo "  \"probes\": [$(IFS=,; echo "${RESULTS[*]}")]"
  echo "}"
} > "$REPORT_FILE"
echo ""
echo "  report: $REPORT_FILE"

[[ $FAIL -eq 0 || $FIXED -ge $FAIL ]]
