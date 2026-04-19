#!/usr/bin/env bash
# @file        scripts/governance/export-waiver-inventory.sh
# @module      governance/waivers
# @description Export machine-readable and markdown waiver inventory artifacts for admin tooling
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh" || {
  echo "FATAL: Cannot load _common/init.sh from $SCRIPT_DIR" >&2
  exit 1
}

REGISTRY_FILE=""
VALIDATION_REPORT=""
OUT_JSON=""
OUT_MD=""
NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_EPOCH="$(date -u +%s)"

usage() {
  cat <<'EOF'
Usage:
  scripts/governance/export-waiver-inventory.sh \
    --registry <path> \
    --validation-report <path> \
    --out-json <path> \
    --out-md <path>
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry)
      REGISTRY_FILE="$2"
      shift 2
      ;;
    --validation-report)
      VALIDATION_REPORT="$2"
      shift 2
      ;;
    --out-json)
      OUT_JSON="$2"
      shift 2
      ;;
    --out-md)
      OUT_MD="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_error "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$REGISTRY_FILE" || -z "$VALIDATION_REPORT" || -z "$OUT_JSON" || -z "$OUT_MD" ]]; then
  log_error "Missing required flags"
  usage
  exit 1
fi

require_command "jq"
require_file "$REGISTRY_FILE"
require_file "$VALIDATION_REPORT"

mkdir -p "$(dirname "$OUT_JSON")"
mkdir -p "$(dirname "$OUT_MD")"

inventory_json="$(jq -n \
  --arg generated_at "$NOW_UTC" \
  --arg registry "$REGISTRY_FILE" \
  --argjson now_epoch "$NOW_EPOCH" \
  --slurpfile reg "$REGISTRY_FILE" \
  --slurpfile validation "$VALIDATION_REPORT" '
  def to_epoch($s): ($s | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime);
  def lifecycle($w; $now):
    if $w.status == "revoked" then "revoked"
    elif (to_epoch($w.expires_at) < $now) then "expired"
    elif (to_epoch($w.expires_at) <= ($now + 7*24*60*60)) then "expiring_7_days"
    else "active"
    end;

  ($reg[0].waivers // []) as $waivers
  | ($validation[0].summary // {}) as $summary
  | {
      generated_at: $generated_at,
      registry: $registry,
      summary: {
        waiver_count: ($waivers | length),
        active_count: ($waivers | map(select(.status == "active")) | length),
        invalid_count: ($summary.invalid_count // 0),
        expired_active_count: ($summary.expired_active_count // 0),
        expiring_7_days_count: (
          $waivers
          | map(select(.status == "active" and (to_epoch(.expires_at) >= $now_epoch) and (to_epoch(.expires_at) <= ($now_epoch + 7*24*60*60))))
          | length
        )
      },
      waivers: (
        $waivers
        | map({
            id,
            issue_number,
            policy_id,
            owner,
            approver,
            status,
            lifecycle_state: lifecycle(.; $now_epoch),
            approved_at: .approval.approved_at,
            signature: .approval.signature,
            rationale,
            scope: .scope,
            expires_at,
            linked_issue_url: ("https://github.com/kushin77/code-server/issues/" + (.issue_number | tostring))
          })
      )
    }
')"

printf '%s\n' "$inventory_json" > "$OUT_JSON"

jq -r '
  "# Governance Waiver Inventory",
  "",
  "Generated: " + .generated_at,
  "Registry: " + .registry,
  "",
  "## Summary",
  "",
  "| Metric | Value |",
  "|---|---:|",
  "| waiver_count | " + (.summary.waiver_count | tostring) + " |",
  "| active_count | " + (.summary.active_count | tostring) + " |",
  "| expiring_7_days_count | " + (.summary.expiring_7_days_count | tostring) + " |",
  "| expired_active_count | " + (.summary.expired_active_count | tostring) + " |",
  "| invalid_count | " + (.summary.invalid_count | tostring) + " |",
  "",
  "## Waivers",
  "",
  "| ID | Lifecycle | Policy | Owner | Approver | Expires | Issue |",
  "|---|---|---|---|---|---|---|",
  (
    if (.waivers | length) == 0 then
      "| none | none | none | none | none | none | none |"
    else
      (.waivers[] | "| " + .id + " | " + .lifecycle_state + " | " + .policy_id + " | " + .owner + " | " + .approver + " | " + .expires_at + " | #" + (.issue_number | tostring) + " |")
    end
  )
' "$OUT_JSON" > "$OUT_MD"

log_info "Generated waiver inventory JSON: $OUT_JSON"
log_info "Generated waiver inventory Markdown: $OUT_MD"
