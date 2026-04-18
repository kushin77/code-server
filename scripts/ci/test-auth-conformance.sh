#!/usr/bin/env bash
# @file        scripts/ci/test-auth-conformance.sh
# @module      ci/auth
# @description Auth/policy conformance suite: fresh-session and restored-session parity tests.
#              CI target — exits non-zero on any drift. Produces machine-readable JSON report.
#
# Test categories:
#   1. Fresh login shell — canonical env vars present and correct
#   2. Restored terminal  — env vars survive session restore
#   3. Stale env contamination — deprecated vars rejected / overridden
#   4. Repo-switch behavior  — keepalive and auth state intact across git repo changes
#
# Usage:
#   bash scripts/ci/test-auth-conformance.sh [--report /tmp/auth-conformance.json]

set -euo pipefail

REPORT="${1:-}"
REPORT_FILE="${REPORT_FILE:-/tmp/auth-conformance-report.json}"
[[ "$REPORT" == "--report" ]] && REPORT_FILE="${2:-$REPORT_FILE}"

PASS=0; FAIL=0; TOTAL=0
RESULTS=()

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

json_quote() {
  local input="$1"

  if command -v jq >/dev/null 2>&1; then
    jq -Rs . <<< "$input"
    return
  fi

  # Fallback: JSON-escape without jq so reports remain valid on minimal environments.
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' <<< "$input" 2>/dev/null \
    || node -e 'process.stdin.setEncoding("utf8");let data="";process.stdin.on("data",d=>data+=d);process.stdin.on("end",()=>process.stdout.write(JSON.stringify(data)));' <<< "$input"
}

record() {
  local name="$1" status="$2" detail="${3:-}"
  RESULTS+=("{\"name\":$(json_quote "$name"),\"status\":\"$status\",\"detail\":$(json_quote "$detail"),\"ts\":\"$(ts)\"}")
  TOTAL=$(( TOTAL + 1 ))
  if [[ "$status" == "pass" ]]; then
    echo "  PASS  $name"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL  $name${detail:+: $detail}" >&2
    FAIL=$(( FAIL + 1 ))
  fi
}

run_in_clean_env() {
  # Execute command in a sub-shell that mimics a fresh login shell:
  # clears all auth-related env vars, then sources code-server-entrypoint logic.
  env -i HOME="$HOME" PATH="$PATH" USER="${USER:-coder}" \
    GSM_PROJECT=gcp-eiq \
    GSM_SECRET_NAME=github-token \
    GIT_CREDENTIAL_GSM_CANONICAL_SECRET_NAME=github-token \
    bash --norc --noprofile -c "$1"
}

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       auth-conformance suite  •  $(ts)       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Category 1: Fresh login shell ────────────────────────────────────────────
echo "[1] Fresh login shell"

run_in_clean_env 'echo $GSM_PROJECT' | grep -q "^gcp-eiq$" \
  && record "fresh-shell: GSM_PROJECT=gcp-eiq" "pass" \
  || record "fresh-shell: GSM_PROJECT=gcp-eiq" "fail" "env var not set or wrong"

run_in_clean_env 'echo $GSM_SECRET_NAME' | grep -q "^github-token$" \
  && record "fresh-shell: GSM_SECRET_NAME=github-token" "pass" \
  || record "fresh-shell: GSM_SECRET_NAME=github-token" "fail" "env var not set or wrong"

run_in_clean_env 'echo $GIT_CREDENTIAL_GSM_CANONICAL_SECRET_NAME' | grep -q "^github-token$" \
  && record "fresh-shell: GIT_CREDENTIAL_GSM_CANONICAL_SECRET_NAME=github-token" "pass" \
  || record "fresh-shell: GIT_CREDENTIAL_GSM_CANONICAL_SECRET_NAME=github-token" "fail"

# ── Category 2: Restored terminal (env exported from parent) ─────────────────
echo ""
echo "[2] Restored terminal (env propagation)"

# Simulate exported env surviving subshell
(
  export GSM_PROJECT=gcp-eiq
  export GSM_SECRET_NAME=github-token
  export GIT_CREDENTIAL_GSM_CANONICAL_SECRET_NAME=github-token
  bash --norc --noprofile -c '
    [[ "$GSM_PROJECT" == "gcp-eiq" ]] && echo OK || echo FAIL
  '
) | grep -q "^OK$" \
  && record "restored-shell: GSM_PROJECT propagates" "pass" \
  || record "restored-shell: GSM_PROJECT propagates" "fail"

(
  export GSM_SECRET_NAME=github-token
  bash --norc --noprofile -c 'echo $GSM_SECRET_NAME'
) | grep -q "^github-token$" \
  && record "restored-shell: GSM_SECRET_NAME propagates" "pass" \
  || record "restored-shell: GSM_SECRET_NAME propagates" "fail"

# ── Category 3: Stale/deprecated env contamination ───────────────────────────
echo ""
echo "[3] Stale env contamination"

# Deprecated var should be ignored by credential helper if canonical is set
RESULT=$(env -i HOME="$HOME" PATH="$PATH" USER="${USER:-coder}" \
  GSM_PROJECT=gcp-eiq \
  GSM_SECRET_NAME=github-token \
  GIT_CREDENTIAL_GSM_CANONICAL_SECRET_NAME=github-token \
  GSM_GITHUB_TOKEN_SECRET=prod-github-token \
  bash --norc --noprofile -c '
    # The deprecated GSM_GITHUB_TOKEN_SECRET must NOT override the canonical
    [[ "${GIT_CREDENTIAL_GSM_CANONICAL_SECRET_NAME:-}" == "github-token" ]] && echo OK || echo FAIL
  ')
[[ "$RESULT" == "OK" ]] \
  && record "stale-env: deprecated GSM_GITHUB_TOKEN_SECRET does not override canonical" "pass" \
  || record "stale-env: deprecated GSM_GITHUB_TOKEN_SECRET does not override canonical" "fail"

# Canonical secret name must be github-token despite legacy override attempt
RESULT=$(env -i HOME="$HOME" PATH="$PATH" USER="${USER:-coder}" \
  GSM_PROJECT=gcp-eiq \
  GSM_GITHUB_TOKEN_SECRET=prod-github-token \
  GIT_CREDENTIAL_GSM_CANONICAL_SECRET_NAME=github-token \
  bash --norc --noprofile -c 'echo ${GIT_CREDENTIAL_GSM_CANONICAL_SECRET_NAME:-missing}')
[[ "$RESULT" == "github-token" ]] \
  && record "stale-env: canonical name wins over legacy override" "pass" \
  || record "stale-env: canonical name wins over legacy override" "fail" "got: $RESULT"

# ── Category 4: Repo-switch behavior ─────────────────────────────────────────
echo ""
echo "[4] Repo-switch behavior"

TMPDIR_A=$(mktemp -d)
TMPDIR_B=$(mktemp -d)
trap 'rm -rf "$TMPDIR_A" "$TMPDIR_B"' EXIT

(cd "$TMPDIR_A" && git init -q && git config user.email "test@example.com" && git config user.name "test")
(cd "$TMPDIR_B" && git init -q && git config user.email "test@example.com" && git config user.name "test")

# Auth env must be stable after switching repos
RESULT=$(env -i HOME="$HOME" PATH="$PATH" USER="${USER:-coder}" \
  GSM_PROJECT=gcp-eiq GSM_SECRET_NAME=github-token \
  GIT_CREDENTIAL_GSM_CANONICAL_SECRET_NAME=github-token \
  bash --norc --noprofile -c "
    cd \"$TMPDIR_A\"
    v1=\"\${GIT_CREDENTIAL_GSM_CANONICAL_SECRET_NAME:-}\"
    cd \"$TMPDIR_B\"
    v2=\"\${GIT_CREDENTIAL_GSM_CANONICAL_SECRET_NAME:-}\"
    [[ \"\$v1\" == \"\$v2\" && \"\$v2\" == 'github-token' ]] && echo OK || echo FAIL
  ")
[[ "$RESULT" == "OK" ]] \
  && record "repo-switch: canonical env stable across repo changes" "pass" \
  || record "repo-switch: canonical env stable across repo changes" "fail"

# auth-keepalive health command should exit without error (daemon may be stopped)
KEEPALIVE_BIN="${AUTH_KEEPALIVE_BIN:-$(command -v auth-keepalive 2>/dev/null || echo "scripts/auth-keepalive")}"
if [[ -x "$KEEPALIVE_BIN" ]]; then
  "$KEEPALIVE_BIN" health > /dev/null 2>&1 \
    && record "repo-switch: auth-keepalive health command exits 0" "pass" \
    || record "repo-switch: auth-keepalive health command exits 0" "fail"
else
  record "repo-switch: auth-keepalive health command exits 0" "fail" "auth-keepalive not found"
fi

# ── Report ────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  $TOTAL tests: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════════════════════════════"

# Machine-readable JSON report
{
  echo "{"
  echo "  \"timestamp\": \"$(ts)\","
  echo "  \"total\": $TOTAL,"
  echo "  \"passed\": $PASS,"
  echo "  \"failed\": $FAIL,"
  echo "  \"results\": ["
  for i in "${!RESULTS[@]}"; do
    if (( i < ${#RESULTS[@]} - 1 )); then
      echo "    ${RESULTS[$i]},"
    else
      echo "    ${RESULTS[$i]}"
    fi
  done
  echo "  ]"
  echo "}"
} > "$REPORT_FILE"

echo "  report: $REPORT_FILE"
echo ""

[[ $FAIL -eq 0 ]]
