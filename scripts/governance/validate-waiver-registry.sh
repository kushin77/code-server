#!/usr/bin/env bash
# @file        scripts/governance/validate-waiver-registry.sh
# @module      governance/waivers
# @description Validate centralized waiver registry, detect expiry drift, and emit audit events
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh" || {
  echo "FATAL: Cannot load _common/init.sh from $SCRIPT_DIR" >&2
  exit 1
}

REGISTRY_FILE=""
REPORT_FILE=""
EVENTS_FILE=""
EXPIRED_FILE=""
NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_EPOCH="$(date -u +%s)"

usage() {
  cat <<'EOF'
Usage:
  scripts/governance/validate-waiver-registry.sh \
    --registry <path> \
    --report <path> \
    --events <path> \
    --expired <path>

Exit codes:
  0 = valid registry, no expired active waivers
  2 = expired active waivers detected
  3 = invalid registry entries
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry)
      REGISTRY_FILE="$2"
      shift 2
      ;;
    --report)
      REPORT_FILE="$2"
      shift 2
      ;;
    --events)
      EVENTS_FILE="$2"
      shift 2
      ;;
    --expired)
      EXPIRED_FILE="$2"
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

if [[ -z "$REGISTRY_FILE" || -z "$REPORT_FILE" || -z "$EVENTS_FILE" || -z "$EXPIRED_FILE" ]]; then
  log_error "Missing required flags"
  usage
  exit 1
fi

require_command "jq" "jq is required"

if [[ ! -f "$REGISTRY_FILE" ]]; then
  log_error "Registry file not found: $REGISTRY_FILE"
  exit 1
fi

tmp_invalid="$(mktemp)"
tmp_expired="$(mktemp)"
trap 'rm -f "$tmp_invalid" "$tmp_expired"' EXIT

waiver_count="$(jq '.waivers | length' "$REGISTRY_FILE" 2>/dev/null || echo -1)"
if [[ "$waiver_count" -lt 0 ]]; then
  log_error "Invalid JSON in waiver registry"
  exit 3
fi

jq -r '.waivers[] | @base64' "$REGISTRY_FILE" | while IFS= read -r row; do
  [[ -z "$row" ]] && continue
  _jq() {
    printf '%s' "$row" | base64 -d | jq -r "$1"
  }

  id="$(_jq '.id // empty')"
  issue_number="$(_jq '.issue_number // 0')"
  policy_id="$(_jq '.policy_id // empty')"
  owner="$(_jq '.owner // empty')"
  approver="$(_jq '.approver // empty')"
  scope_repo_count="$(_jq '.scope.repositories // [] | length')"
  scope_path_count="$(_jq '.scope.paths // [] | length')"
  rationale="$(_jq '.rationale // empty')"
  expires_at="$(_jq '.expires_at // empty')"
  status="$(_jq '.status // empty')"
  approved_at="$(_jq '.approval.approved_at // empty')"
  signature="$(_jq '.approval.signature // empty')"

  invalid_reasons=()

  [[ "$id" =~ ^WVR-[0-9]{4}-[0-9]{3}$ ]] || invalid_reasons+=("invalid_id")
  [[ "$issue_number" =~ ^[0-9]+$ ]] || invalid_reasons+=("invalid_issue_number")
  [[ -n "$policy_id" ]] || invalid_reasons+=("missing_policy_id")
  [[ "$owner" =~ ^@[A-Za-z0-9-]+$ ]] || invalid_reasons+=("invalid_owner")
  [[ "$approver" =~ ^@[A-Za-z0-9-]+$ ]] || invalid_reasons+=("invalid_approver")
  [[ "$scope_repo_count" -gt 0 ]] || invalid_reasons+=("missing_scope_repositories")
  [[ "$scope_path_count" -gt 0 ]] || invalid_reasons+=("missing_scope_paths")
  [[ ${#rationale} -ge 10 ]] || invalid_reasons+=("weak_rationale")
  [[ "$status" =~ ^(active|revoked|expired)$ ]] || invalid_reasons+=("invalid_status")
  [[ "$signature" =~ ^sha256:[a-f0-9]{64}$ ]] || invalid_reasons+=("invalid_signature")

  exp_epoch="$(date -u -d "$expires_at" +%s 2>/dev/null || echo 0)"
  [[ "$exp_epoch" -gt 0 ]] || invalid_reasons+=("invalid_expires_at")

  appr_epoch="$(date -u -d "$approved_at" +%s 2>/dev/null || echo 0)"
  [[ "$appr_epoch" -gt 0 ]] || invalid_reasons+=("invalid_approved_at")

  if [[ ${#invalid_reasons[@]} -gt 0 ]]; then
    jq -n --arg id "$id" --argjson issue_number "$issue_number" --argjson reasons "$(printf '%s\n' "${invalid_reasons[@]}" | jq -R -s -c 'split("\n") | map(select(length>0))')" '{id:$id,issue_number:$issue_number,reasons:$reasons}' >> "$tmp_invalid"
    continue
  fi

  if [[ "$status" == "active" && "$exp_epoch" -lt "$NOW_EPOCH" ]]; then
    jq -n --arg id "$id" --argjson issue_number "$issue_number" --arg expires_at "$expires_at" '{id:$id,issue_number:$issue_number,expires_at:$expires_at,auto_action:"revoke_required"}' >> "$tmp_expired"
  fi
done

invalid_count="$(wc -l < "$tmp_invalid" | tr -d ' ')"
expired_count="$(wc -l < "$tmp_expired" | tr -d ' ')"
active_count="$(jq '[.waivers[] | select(.status=="active")] | length' "$REGISTRY_FILE")"

jq -n \
  --arg generated_at "$NOW_UTC" \
  --arg registry "$REGISTRY_FILE" \
  --argjson waiver_count "$waiver_count" \
  --argjson active_count "$active_count" \
  --argjson invalid_count "$invalid_count" \
  --argjson expired_active_count "$expired_count" \
  --argjson invalid_entries "$(jq -s '.' "$tmp_invalid")" \
  --argjson expired_active_entries "$(jq -s '.' "$tmp_expired")" \
  '{
    generated_at:$generated_at,
    registry:$registry,
    summary:{
      waiver_count:$waiver_count,
      active_count:$active_count,
      invalid_count:$invalid_count,
      expired_active_count:$expired_active_count
    },
    invalid_entries:$invalid_entries,
    expired_active_entries:$expired_active_entries
  }' > "$REPORT_FILE"

jq -s '.' "$tmp_expired" > "$EXPIRED_FILE"

{
  jq -n --arg ts "$NOW_UTC" --arg event "waiver_registry_validation" --argjson waiver_count "$waiver_count" --argjson invalid_count "$invalid_count" --argjson expired_active_count "$expired_count" '{timestamp:$ts,event_type:$event,waiver_count:$waiver_count,invalid_count:$invalid_count,expired_active_count:$expired_active_count}'
  if [[ "$expired_count" -gt 0 ]]; then
    jq -c '.[]' "$EXPIRED_FILE" | while IFS= read -r e; do
      jq -n --arg ts "$NOW_UTC" --arg event "expired_waiver_detected" --argjson payload "$e" '{timestamp:$ts,event_type:$event,payload:$payload}'
    done
  fi
} > "$EVENTS_FILE"

if [[ "$invalid_count" -gt 0 ]]; then
  log_error "Invalid waiver entries detected: $invalid_count"
  exit 3
fi

if [[ "$expired_count" -gt 0 ]]; then
  log_warn "Expired active waivers detected: $expired_count"
  exit 2
fi

log_info "Waiver registry validation passed"
exit 0
