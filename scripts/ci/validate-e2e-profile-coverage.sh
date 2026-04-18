#!/usr/bin/env bash
# @file        scripts/ci/validate-e2e-profile-coverage.sh
# @module      ci/e2e
# @description Validate the dedicated E2E service-account coverage profile.
#
# Usage: bash scripts/ci/validate-e2e-profile-coverage.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

PROFILE_FILE="${PROFILE_FILE:-config/e2e-service-account-profile.yml}"

require_file "$PROFILE_FILE"

required_capabilities=(
  "oauth-login"
  "credential-provisioning"
  "auth-keepalive"
  "policy-gate"
  "ide-settings-merge"
  "root-hygiene"
)

critical_capabilities=(
  "oauth-login"
  "credential-provisioning"
  "auth-keepalive"
)

require_pattern() {
  local pattern="$1"
  local description="$2"

  if grep -qE "$pattern" "$PROFILE_FILE"; then
    log_info "Verified: $description"
  else
    log_fatal "Missing required profile entry: $description"
  fi
}

log_info "Validating E2E service-account coverage profile: $PROFILE_FILE"

require_pattern '^version: "1"$' 'profile version'
require_pattern '^profile_id: "code-server-e2e-service-account"$' 'profile identifier'
require_pattern '^account: "e2e-service@kushnir\.cloud"' 'dedicated service account identity'
require_pattern '^vpn_required: true$' 'VPN requirement'
require_pattern '^release_gate:$' 'release gate block'
require_pattern '^  require_all_critical: true$' 'critical coverage enforcement'
require_pattern '^  require_coverage_for_new_features: true$' 'new feature coverage enforcement'
require_pattern '^  block_release_on_uncovered_critical: true$' 'release block on missing critical coverage'

for capability in "${required_capabilities[@]}"; do
  require_pattern "^[[:space:]]{2}${capability}:$" "capability ${capability}"
done

for capability in "${critical_capabilities[@]}"; do
  require_pattern "^[[:space:]]{2}${capability}:[[:space:]]*$" "critical capability block ${capability}"
  require_pattern "^[[:space:]]{4}critical: true$" "critical flag present for ${capability}"
done

log_info "E2E service-account coverage profile is valid"