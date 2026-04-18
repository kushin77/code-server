#!/usr/bin/env bash
# @file        scripts/ci/test-git-credential-gsm.sh
# @module      governance/credential-tests
# @description Validate deterministic fallback, telemetry, and strict mode behavior for git-credential-gsm.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

HELPER="${REPO_ROOT}/scripts/git-credential-gsm"

pass() {
  log_info "PASS: $1"
}

fail() {
  log_fatal "FAIL: $1"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label (missing: $needle)"
  fi
}

run_with_mock() {
  local mode="$1"
  local env_extra="$2"

  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  cat > "$tmpdir/gcloud" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
secret=""
for arg in "$@"; do
  case "$arg" in
    --secret=*) secret="${arg#--secret=}" ;;
  esac
done

case "${MOCK_MODE:-}" in
  canonical)
    [[ "$secret" == "prod-github-token" ]] && { echo "CANONICAL_TOKEN"; exit 0; }
    exit 1
    ;;
  legacy)
    [[ "$secret" == "github-token" ]] && { echo "LEGACY_TOKEN"; exit 0; }
    exit 1
    ;;
  none)
    exit 1
    ;;
  *)
    exit 1
    ;;
esac
EOS
  chmod +x "$tmpdir/gcloud"

  local stdin_payload
  stdin_payload=$'protocol=https\nhost=github.com\n\n'

  local -a cmd
  cmd=(env "PATH=$tmpdir:$PATH" "MOCK_MODE=$mode")

  if [[ -n "$env_extra" ]]; then
    # env_extra contains KEY=VALUE pairs separated by spaces.
    read -r -a extra_env <<< "$env_extra"
    cmd+=("${extra_env[@]}")
  fi

  cmd+=("bash" "$HELPER" get)

  output=$("${cmd[@]}" <<< "$stdin_payload" 2>&1) || status=$?
  status=${status:-0}

  printf '%s\n' "$status"
  printf '%s\n' "$output"
}

# Case 1: Canonical secret selected, deterministic over env fallback.
res=$(run_with_mock "canonical" "GSM_SECRET_NAME=prod-github-token GH_TOKEN=STALE_ENV")
status=$(echo "$res" | sed -n '1p')
out=$(echo "$res" | sed -n '2,$p')
[[ "$status" == "0" ]] || fail "canonical resolution should succeed"
assert_contains "$out" "password=CANONICAL_TOKEN" "canonical token returned"
assert_contains "$out" "canonical_secret_selected" "canonical selection telemetry emitted"

# Case 2: Legacy fallback is used and logged.
res=$(run_with_mock "legacy" "GSM_SECRET_NAME=prod-github-token")
status=$(echo "$res" | sed -n '1p')
out=$(echo "$res" | sed -n '2,$p')
[[ "$status" == "0" ]] || fail "legacy fallback should succeed in non-strict mode"
assert_contains "$out" "password=LEGACY_TOKEN" "legacy token returned"
assert_contains "$out" "fallback_used" "fallback telemetry emitted"

# Case 3: Strict production mode blocks non-canonical source.
res=$(run_with_mock "legacy" "GSM_SECRET_NAME=prod-github-token GIT_CREDENTIAL_GSM_STRICT=true GIT_CREDENTIAL_GSM_ENV=production")
status=$(echo "$res" | sed -n '1p')
out=$(echo "$res" | sed -n '2,$p')
[[ "$status" != "0" ]] || fail "strict production should block legacy source"
assert_contains "$out" "strict_mode_block" "strict mode block telemetry emitted"

# Case 4: Env fallback works when GSM chain exhausted.
res=$(run_with_mock "none" "GSM_SECRET_NAME=prod-github-token GH_TOKEN=ENV_TOKEN_A GITHUB_TOKEN=ENV_TOKEN_B GIT_CREDENTIAL_GSM_ALLOW_ENV_FALLBACK=true GIT_CREDENTIAL_GSM_STRICT=false GIT_CREDENTIAL_GSM_ENV=dev")
status=$(echo "$res" | sed -n '1p')
out=$(echo "$res" | sed -n '2,$p')
[[ "$status" == "0" ]] || fail "env fallback should succeed when enabled"
assert_contains "$out" "password=ENV_TOKEN_A" "deterministic env fallback precedence (GH_TOKEN first)"
assert_contains "$out" "fallback_used" "env fallback telemetry emitted"

log_info "All git-credential-gsm tests passed"
