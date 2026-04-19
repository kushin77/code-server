#!/usr/bin/env bash
# @file        scripts/ops/drift-detect.sh
# @module      ops/drift
# @description Detect local IDE/env drift against the admin portal policy contract.
#              Emits alerts for mutations in monitored paths and env vars.
#              Part of the thin-client enforcement: code-server must not silently drift.
#
# Usage: bash scripts/ops/drift-detect.sh [--report] [--fix]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/policy-bundle.sh" 2>/dev/null || true

DRIFT_LOG="${DRIFT_LOG:-/tmp/ide-drift-report.json}"
FIX_MODE="${1:-}"

_dr_log()  { echo "[drift-detect] $*"; }
_dr_warn() { echo "[drift-detect] WARN: $*" >&2; }

VIOLATIONS=0
RESULTS=()

check_env_var() {
  local name="$1" expected="$2"
  local actual="${!name:-}"
  if [[ "$actual" == "$expected" ]]; then
    RESULTS+=("{\"check\":\"env:$name\",\"status\":\"ok\",\"value\":\"$actual\"}")
    _dr_log "OK    env:$name = $actual"
  else
    RESULTS+=("{\"check\":\"env:$name\",\"status\":\"drift\",\"expected\":\"$expected\",\"actual\":\"$actual\"}")
    _dr_warn "DRIFT env:$name expected=$expected actual=${actual:-<unset>}"
    VIOLATIONS=$(( VIOLATIONS + 1 ))
  fi
}

check_deprecated_var() {
  local name="$1"
  local actual="${!name:-}"
  if [[ -n "$actual" ]]; then
    RESULTS+=("{\"check\":\"deprecated_env:$name\",\"status\":\"drift\",\"detail\":\"deprecated var still set\"}")
    _dr_warn "DRIFT deprecated var still set: $name=$actual — unset this"
    VIOLATIONS=$(( VIOLATIONS + 1 ))
  else
    RESULTS+=("{\"check\":\"deprecated_env:$name\",\"status\":\"ok\"}")
    _dr_log "OK    deprecated_env:$name (not set)"
  fi
}

check_file_contains() {
  local label="$1" file="$2" pattern="$3"
  if [[ -f "$file" ]] && grep -qF "$pattern" "$file" 2>/dev/null; then
    RESULTS+=("{\"check\":\"file:$label\",\"status\":\"ok\"}")
    _dr_log "OK    file:$label ($file contains '$pattern')"
  else
    RESULTS+=("{\"check\":\"file:$label\",\"status\":\"drift\",\"detail\":\"pattern not found or file missing\"}")
    _dr_warn "DRIFT file:$label ($file missing or does not contain '$pattern')"
    VIOLATIONS=$(( VIOLATIONS + 1 ))
  fi
}

echo ""
echo "[drift-detect] Checking IDE drift against canonical policy contract..."
echo ""

# ── Canonical env var checks ──────────────────────────────────────────────────
check_env_var "GSM_PROJECT" "gcp-eiq"
check_env_var "GSM_SECRET_NAME" "github-token"
check_env_var "GIT_CREDENTIAL_GSM_CANONICAL_SECRET_NAME" "github-token"
check_deprecated_var "GSM_GITHUB_TOKEN_SECRET"

# ── Git credential helper registration ───────────────────────────────────────
GITCONFIG="${HOME}/.gitconfig"
check_file_contains "git-credential-gsm" "$GITCONFIG" "git-credential-gsm"

# ── Keepalive daemon running ──────────────────────────────────────────────────
KEEPALIVE_BIN="${AUTH_KEEPALIVE_BIN:-$(command -v auth-keepalive 2>/dev/null || echo "scripts/auth-keepalive")}"
if [[ -x "$KEEPALIVE_BIN" ]]; then
  if "$KEEPALIVE_BIN" status > /dev/null 2>&1; then
    RESULTS+=("{\"check\":\"service:auth-keepalive\",\"status\":\"ok\"}")
    _dr_log "OK    service:auth-keepalive running"
  else
    RESULTS+=("{\"check\":\"service:auth-keepalive\",\"status\":\"drift\",\"detail\":\"daemon not running\"}")
    _dr_warn "DRIFT service:auth-keepalive is stopped"
    VIOLATIONS=$(( VIOLATIONS + 1 ))
    if [[ "$FIX_MODE" == "--fix" ]]; then
      "$KEEPALIVE_BIN" start && _dr_log "FIX: auth-keepalive started"
    fi
  fi
fi

# ── Policy gate config present ────────────────────────────────────────────────
check_file_contains "automation-policy" "config/automation-policy.yml" "kushin77/code-server"

# ── Report ────────────────────────────────────────────────────────────────────
echo ""
if (( VIOLATIONS > 0 )); then
  echo "[drift-detect] FAIL: $VIOLATIONS drift violation(s) detected"
  echo "[drift-detect] Run 'bash scripts/ops/drift-detect.sh --fix' to attempt auto-remediation"
else
  echo "[drift-detect] PASS: no drift detected"
fi

# Machine-readable JSON report
{
  echo "{"
  echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"violations\": $VIOLATIONS,"
  echo "  \"checks\": ["
  for i in "${!RESULTS[@]}"; do
    if (( i < ${#RESULTS[@]} - 1 )); then
      echo "    ${RESULTS[$i]},"
    else
      echo "    ${RESULTS[$i]}"
    fi
  done
  echo "  ]"
  echo "}"
} > "$DRIFT_LOG"

echo "[drift-detect] report: $DRIFT_LOG"
[[ $VIOLATIONS -eq 0 ]]
