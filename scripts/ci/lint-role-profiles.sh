#!/usr/bin/env bash
# @file        scripts/ci/lint-role-profiles.sh
# @module      ci/lint
# @description Validates all role profile JSONs enforce enterprise extension recommendation policy.
#
# Fails if any role profile has recommendations enabled or ignoreRecommendations disabled.
# Used as a CI regression guard for #736/#737.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILES_DIR="${SCRIPT_DIR}/../../config/role-settings"

PASS=0
FAIL=0
ERRORS=()

for profile in "$PROFILES_DIR"/*.json; do
  role=$(basename "$profile" .json)

  # Parse with jq when available, otherwise fallback to Python.
  if command -v jq &>/dev/null; then
    rec_value=$(jq -r 'if (.settings | has("extensions.recommendations")) then .settings["extensions.recommendations"] else "missing" end' "$profile")
    ignore_value=$(jq -r 'if (.settings | has("extensions.ignoreRecommendations")) then .settings["extensions.ignoreRecommendations"] else "missing" end' "$profile")
  elif command -v python3 &>/dev/null; then
    rec_value=$(python3 -c 'import json,sys; p=json.load(open(sys.argv[1], encoding="utf-8")); print(p.get("settings",{}).get("extensions.recommendations","missing"))' "$profile" 2>/dev/null || echo "missing")
    ignore_value=$(python3 -c 'import json,sys; p=json.load(open(sys.argv[1], encoding="utf-8")); print(p.get("settings",{}).get("extensions.ignoreRecommendations","missing"))' "$profile" 2>/dev/null || echo "missing")
  elif command -v python &>/dev/null; then
    rec_value=$(python -c 'import json,sys; p=json.load(open(sys.argv[1])); print(p.get("settings",{}).get("extensions.recommendations","missing"))' "$profile" 2>/dev/null || echo "missing")
    ignore_value=$(python -c 'import json,sys; p=json.load(open(sys.argv[1])); print(p.get("settings",{}).get("extensions.ignoreRecommendations","missing"))' "$profile" 2>/dev/null || echo "missing")
  else
    echo "No JSON parser found (need jq or python3/python)" >&2
    exit 2
  fi

  rec_value="$(printf '%s' "$rec_value" | tr '[:upper:]' '[:lower:]')"
  ignore_value="$(printf '%s' "$ignore_value" | tr '[:upper:]' '[:lower:]')"

  ok=true

  if [[ "$rec_value" != "false" ]]; then
    ERRORS+=("$role: extensions.recommendations must be false (got: $rec_value)")
    ok=false
  fi

  if [[ "$ignore_value" != "true" ]]; then
    ERRORS+=("$role: extensions.ignoreRecommendations must be true (got: $ignore_value)")
    ok=false
  fi

  if [[ "$ok" == "true" ]]; then
    echo "  PASS  $role"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $role"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "Role profile lint: $PASS passed, $FAIL failed"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Errors:"
  for err in "${ERRORS[@]}"; do
    echo "  - $err"
  done
  exit 1
fi

exit 0
