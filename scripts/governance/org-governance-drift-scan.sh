#!/usr/bin/env bash
# @file        scripts/governance/org-governance-drift-scan.sh
# @module      governance/github
# @description Scan org repositories for branch-protection drift against source-controlled baseline
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh" || {
  echo "FATAL: Cannot load _common/init.sh from $SCRIPT_DIR" >&2
  exit 1
}

ORG=""
BASELINE_FILE=""
REPORT_FILE=""
NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

usage() {
  cat <<'EOF'
Usage:
  scripts/governance/org-governance-drift-scan.sh --org <org> --baseline <path> --report <path>

Exit codes:
  0 - No drift
  1 - Script/runtime error
  2 - Drift detected
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)
      ORG="$2"
      shift 2
      ;;
    --baseline)
      BASELINE_FILE="$2"
      shift 2
      ;;
    --report)
      REPORT_FILE="$2"
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

if [[ -z "$ORG" || -z "$BASELINE_FILE" || -z "$REPORT_FILE" ]]; then
  log_error "Required flags missing"
  usage
  exit 1
fi

require_command "gh" "GitHub CLI is required"
require_command "jq" "jq is required"

if [[ ! -f "$BASELINE_FILE" ]]; then
  log_error "Baseline file not found: $BASELINE_FILE"
  exit 1
fi

required_checks_json="$(jq -c '.required_status_checks' "$BASELINE_FILE")"
required_reviews="$(jq -r '.required_approving_review_count' "$BASELINE_FILE")"
require_enforce_admins="$(jq -r '.enforce_admins' "$BASELINE_FILE")"
require_conv_resolution="$(jq -r '.required_conversation_resolution' "$BASELINE_FILE")"

repos="$(gh api orgs/"$ORG"/repos --paginate --jq '.[].name' 2>/dev/null || true)"
if [[ -z "$repos" ]]; then
  log_error "No repositories found or missing org access for $ORG"
  exit 1
fi

tmp_noncompliant="$(mktemp)"
tmp_compliant="$(mktemp)"
tmp_exceptions="$(mktemp)"
trap 'rm -f "$tmp_noncompliant" "$tmp_compliant" "$tmp_exceptions"' EXIT

while IFS= read -r repo; do
  [[ -z "$repo" ]] && continue

  if jq -e --arg repo "$repo" --arg now "$NOW_UTC" '.exceptions[]? | select(.repo == $repo and .waiver_issue > 0 and .expires_at > $now)' "$BASELINE_FILE" >/dev/null; then
    waiver_issue="$(jq -r --arg repo "$repo" '.exceptions[] | select(.repo == $repo) | .waiver_issue' "$BASELINE_FILE")"
    expires_at="$(jq -r --arg repo "$repo" '.exceptions[] | select(.repo == $repo) | .expires_at' "$BASELINE_FILE")"
    jq -n --arg repo "$repo" --arg waiver_issue "$waiver_issue" --arg expires_at "$expires_at" '{repo:$repo,waiver_issue:($waiver_issue|tonumber),expires_at:$expires_at}' >> "$tmp_exceptions"
    continue
  fi

  default_branch="$(gh api repos/"$ORG"/"$repo" --jq '.default_branch' 2>/dev/null || true)"
  if [[ -z "$default_branch" || "$default_branch" == "null" ]]; then
    jq -n --arg repo "$repo" '{repo:$repo,reasons:["unable_to_read_default_branch"]}' >> "$tmp_noncompliant"
    continue
  fi

  protection_json="$(gh api repos/"$ORG"/"$repo"/branches/"$default_branch"/protection 2>/dev/null || true)"
  if [[ -z "$protection_json" ]]; then
    jq -n --arg repo "$repo" --arg branch "$default_branch" '{repo:$repo,branch:$branch,reasons:["missing_branch_protection"]}' >> "$tmp_noncompliant"
    continue
  fi

  actual_checks_json="$(jq -c '.required_status_checks.contexts // []' <<<"$protection_json")"
  missing_checks="$(jq -n --argjson have "$actual_checks_json" --argjson want "$required_checks_json" '$want - $have')"

  actual_reviews="$(jq -r '.required_pull_request_reviews.required_approving_review_count // 0' <<<"$protection_json")"
  actual_enforce_admins="$(jq -r '.enforce_admins.enabled // false' <<<"$protection_json")"
  actual_conv_resolution="$(jq -r '.required_conversation_resolution.enabled // false' <<<"$protection_json")"

  reasons="[]"
  if [[ "$(jq 'length' <<<"$missing_checks")" -gt 0 ]]; then
    reasons="$(jq -n --argjson reasons "$reasons" --argjson missing "$missing_checks" '$reasons + [{missing_required_checks:$missing}]')"
  fi

  if [[ "$actual_reviews" != "$required_reviews" ]]; then
    reasons="$(jq -n --argjson reasons "$reasons" --arg expected "$required_reviews" --arg actual "$actual_reviews" '$reasons + [{required_reviews:{expected:($expected|tonumber),actual:($actual|tonumber)}}]')"
  fi

  if [[ "$actual_enforce_admins" != "$require_enforce_admins" ]]; then
    reasons="$(jq -n --argjson reasons "$reasons" --arg expected "$require_enforce_admins" --arg actual "$actual_enforce_admins" '$reasons + [{enforce_admins:{expected:($expected=="true"),actual:($actual=="true")}}]')"
  fi

  if [[ "$actual_conv_resolution" != "$require_conv_resolution" ]]; then
    reasons="$(jq -n --argjson reasons "$reasons" --arg expected "$require_conv_resolution" --arg actual "$actual_conv_resolution" '$reasons + [{conversation_resolution:{expected:($expected=="true"),actual:($actual=="true")}}]')"
  fi

  if [[ "$(jq 'length' <<<"$reasons")" -gt 0 ]]; then
    jq -n --arg repo "$repo" --arg branch "$default_branch" --argjson reasons "$reasons" '{repo:$repo,branch:$branch,reasons:$reasons}' >> "$tmp_noncompliant"
  else
    jq -n --arg repo "$repo" --arg branch "$default_branch" '{repo:$repo,branch:$branch}' >> "$tmp_compliant"
  fi
done <<< "$repos"

noncompliant_count="$(wc -l < "$tmp_noncompliant" | tr -d ' ')"
compliant_count="$(wc -l < "$tmp_compliant" | tr -d ' ')"
exception_count="$(wc -l < "$tmp_exceptions" | tr -d ' ')"

jq -n \
  --arg generated_at "$NOW_UTC" \
  --arg org "$ORG" \
  --arg baseline_file "$BASELINE_FILE" \
  --argjson noncompliant "$(jq -s '.' "$tmp_noncompliant")" \
  --argjson compliant "$(jq -s '.' "$tmp_compliant")" \
  --argjson exceptions "$(jq -s '.' "$tmp_exceptions")" \
  --argjson noncompliant_count "$noncompliant_count" \
  --argjson compliant_count "$compliant_count" \
  --argjson exception_count "$exception_count" \
  '{
    generated_at:$generated_at,
    organization:$org,
    baseline_file:$baseline_file,
    summary:{
      compliant_count:$compliant_count,
      noncompliant_count:$noncompliant_count,
      exception_count:$exception_count
    },
    noncompliant:$noncompliant,
    compliant:$compliant,
    exceptions:$exceptions
  }' > "$REPORT_FILE"

log_info "Drift scan complete: compliant=$compliant_count noncompliant=$noncompliant_count exceptions=$exception_count"

if [[ "$noncompliant_count" -gt 0 ]]; then
  exit 2
fi

exit 0
