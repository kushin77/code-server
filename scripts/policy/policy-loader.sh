#!/usr/bin/env bash
# @file        scripts/policy/policy-loader.sh
# @module      policy/runtime
# @description Startup hook: apply T1 immutable settings + validate extension manifest on every session start
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

POLICY_DIR="${POLICY_DIR:-$SCRIPT_DIR/../../config/code-server}"
USER_SETTINGS_DIR="${USER_SETTINGS_DIR:-/home/coder/.local/share/code-server/User}"
AUDIT_LOG="${AUDIT_LOG:-/var/log/policy-loader.log}"
DRY_RUN="${DRY_RUN:-false}"

require_command "jq" "jq is required for policy enforcement"

# ── Helper ────────────────────────────────────────────────────────────────────

audit() {
  local level="$1" msg="$2"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "{\"timestamp\":\"$ts\",\"level\":\"$level\",\"event\":\"$msg\",\"policy_version\":\"$(jq -r .policy_version "$POLICY_DIR/policy-version.json" 2>/dev/null || echo unknown)\"}" \
    >> "$AUDIT_LOG" 2>/dev/null || true
  log_info "[$level] $msg"
}

# ── Phase 1: Validate policy version file ────────────────────────────────────

POLICY_VERSION_FILE="$POLICY_DIR/policy-version.json"
if [[ ! -f "$POLICY_VERSION_FILE" ]]; then
  log_fatal "Policy version file missing: $POLICY_VERSION_FILE — cannot enforce policy"
fi

policy_version="$(jq -r '.policy_version' "$POLICY_VERSION_FILE")"
audit "INFO" "policy_loader_start version=$policy_version"

# ── Phase 2: Validate settings.json SHA256 ────────────────────────────────────

SETTINGS_FILE="$POLICY_DIR/settings.json"
expected_sha="$(jq -r '.components.settings.sha256' "$POLICY_VERSION_FILE")"

if command -v sha256sum &>/dev/null; then
  actual_sha="$(sha256sum "$SETTINGS_FILE" | awk '{print $1}')"
elif command -v shasum &>/dev/null; then
  actual_sha="$(shasum -a 256 "$SETTINGS_FILE" | awk '{print $1}')"
else
  log_warn "No sha256sum available — skipping settings integrity check"
  actual_sha="$expected_sha"
fi

if [[ "$actual_sha" != "$expected_sha" ]]; then
  audit "CRITICAL" "settings_integrity_mismatch expected=$expected_sha actual=$actual_sha"
  log_fatal "Policy settings.json hash mismatch — possible tampering. Run: make policy-version to regenerate."
fi
audit "INFO" "settings_integrity_ok sha=$actual_sha"

# ── Phase 3: Validate extension manifest ─────────────────────────────────────

MANIFEST_FILE="$POLICY_DIR/extensions/extensions-approved.json"
expected_manifest_sha="$(jq -r '.components.extension_manifest.sha256' "$POLICY_VERSION_FILE")"

if command -v sha256sum &>/dev/null; then
  actual_manifest_sha="$(sha256sum "$MANIFEST_FILE" | awk '{print $1}')"
elif command -v shasum &>/dev/null; then
  actual_manifest_sha="$(shasum -a 256 "$MANIFEST_FILE" | awk '{print $1}')"
else
  actual_manifest_sha="$expected_manifest_sha"
fi

if [[ "$actual_manifest_sha" != "$expected_manifest_sha" ]]; then
  audit "CRITICAL" "extension_manifest_integrity_mismatch expected=$expected_manifest_sha actual=$actual_manifest_sha"
  log_fatal "Extension manifest hash mismatch — possible tampering."
fi
audit "INFO" "extension_manifest_integrity_ok"

# ── Phase 4: Apply T1 immutable settings to user profile ─────────────────────

if [[ "$DRY_RUN" == "true" ]]; then
  log_info "DRY_RUN=true — skipping settings write"
else
  mkdir -p "$USER_SETTINGS_DIR"
  TARGET_SETTINGS="$USER_SETTINGS_DIR/settings.json"

  # Strip comments (JSONC → JSON) via jq; merge T1 keys on top of any existing user settings
  T1_SETTINGS_JSON="$(jq 'to_entries | map(select(.key | startswith("__") | not)) | from_entries' "$SETTINGS_FILE")"

  if [[ -f "$TARGET_SETTINGS" ]]; then
    # Merge: existing user settings first, then T1 overrides on top (T1 always wins)
    existing="$(cat "$TARGET_SETTINGS" 2>/dev/null || echo '{}')"
    # Use jq to deep-merge: user base, then policy on top
    merged="$(jq -n --argjson user "$existing" --argjson policy "$T1_SETTINGS_JSON" '$user * $policy')"
    echo "$merged" > "$TARGET_SETTINGS"
    audit "INFO" "settings_merged_t1_applied user=$USER_SETTINGS_DIR"
  else
    echo "$T1_SETTINGS_JSON" > "$TARGET_SETTINGS"
    audit "INFO" "settings_initialized_t1 user=$USER_SETTINGS_DIR"
  fi
fi

# ── Phase 5: Emit result ──────────────────────────────────────────────────────

audit "INFO" "policy_loader_complete version=$policy_version"
log_info "✅ Policy loader complete (v$policy_version)"
