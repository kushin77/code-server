#!/usr/bin/env bash
# @file        scripts/policy/generate-policy-version.sh
# @module      policy/runtime
# @description Regenerate policy-version.json SHA hashes from current policy files
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

POLICY_DIR="${POLICY_DIR:-$SCRIPT_DIR/../../config/code-server}"
POLICY_VERSION_FILE="$POLICY_DIR/policy-version.json"

require_command "jq" "jq is required"

sha256_of() {
  local file="$1"
  if command -v sha256sum &>/dev/null; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    log_fatal "No sha256sum or shasum available"
  fi
}

settings_sha="$(sha256_of "$POLICY_DIR/settings.json")"
manifest_sha="$(sha256_of "$POLICY_DIR/extensions/extensions-approved.json")"
today="$(date -u +%Y-%m-%d)"

# Bump patch version
current_version="$(jq -r '.policy_version // "1.0.0"' "$POLICY_VERSION_FILE" 2>/dev/null || echo "1.0.0")"
major="${current_version%%.*}"
rest="${current_version#*.}"
minor="${rest%.*}"
patch="${rest##*.}"
new_patch=$(( patch + 1 ))
new_version="${major}.${minor}.${new_patch}"

log_info "Regenerating policy-version.json: $current_version → $new_version"

jq \
  --arg version "$new_version" \
  --arg date "$today" \
  --arg settings_sha "$settings_sha" \
  --arg manifest_sha "$manifest_sha" \
  '.policy_version = $version |
   .policy_date = $date |
   .generated_by = "scripts/policy/generate-policy-version.sh" |
   .components.settings.sha256 = $settings_sha |
   .components.extension_manifest.sha256 = $manifest_sha' \
  "$POLICY_VERSION_FILE" > "${POLICY_VERSION_FILE}.tmp"

mv "${POLICY_VERSION_FILE}.tmp" "$POLICY_VERSION_FILE"
log_info "✅ policy-version.json updated (v$new_version, settings=$settings_sha)"
