#!/usr/bin/env bash
# @file        scripts/ci/validate-policy-version.sh
# @module      ci/policy
# @description CI gate: verify policy-version.json hashes match actual files; fail-closed
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
POLICY_DIR="$REPO_ROOT/config/code-server"
POLICY_VERSION_FILE="$POLICY_DIR/policy-version.json"

failures=0

check() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "✅  $label: $actual"
  else
    echo "::error::$label SHA mismatch — expected=$expected actual=$actual"
    echo "    Run: bash scripts/policy/generate-policy-version.sh && git commit"
    (( failures++ )) || true
  fi
}

sha256_of() {
  local f="$1"
  if command -v sha256sum &>/dev/null; then sha256sum "$f" | awk '{print $1}'
  elif command -v shasum &>/dev/null; then shasum -a 256 "$f" | awk '{print $1}'
  else echo "UNAVAILABLE"; fi
}

if [[ ! -f "$POLICY_VERSION_FILE" ]]; then
  echo "::error::policy-version.json not found: $POLICY_VERSION_FILE"
  exit 1
fi

echo "Policy version: $(jq -r .policy_version "$POLICY_VERSION_FILE")"
echo "Policy date:    $(jq -r .policy_date "$POLICY_VERSION_FILE")"
echo ""

# ── Check settings.json ───────────────────────────────────────────────────────
expected_settings="$(jq -r '.components.settings.sha256' "$POLICY_VERSION_FILE")"
actual_settings="$(sha256_of "$POLICY_DIR/settings.json")"
check "settings.json SHA256" "$expected_settings" "$actual_settings"

# ── Check extensions-approved.json ───────────────────────────────────────────
expected_manifest="$(jq -r '.components.extension_manifest.sha256' "$POLICY_VERSION_FILE")"
actual_manifest="$(sha256_of "$POLICY_DIR/extensions/extensions-approved.json")"
check "extensions-approved.json SHA256" "$expected_manifest" "$actual_manifest"

# ── Check required fields ─────────────────────────────────────────────────────
for field in policy_version policy_date enforcement.tier1_settings_immutable enforcement.gallery_blocked enforcement.manifest_signature_required; do
  val="$(jq -r ".$field // empty" "$POLICY_VERSION_FILE")"
  if [[ -z "$val" ]]; then
    echo "::error::policy-version.json missing required field: $field"
    (( failures++ )) || true
  fi
done

echo ""
if [[ "$failures" -gt 0 ]]; then
  echo "::error::Policy version validation failed ($failures failure(s))"
  exit 1
fi
echo "✅ Policy version validation passed"
