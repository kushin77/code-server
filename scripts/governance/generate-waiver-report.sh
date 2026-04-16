#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <owner/repo> <canonical-issue-number>" >&2
  exit 1
fi

GH_BIN="gh"
if ! command -v "$GH_BIN" >/dev/null 2>&1; then
  if command -v gh.exe >/dev/null 2>&1; then
    GH_BIN="gh.exe"
  else
    echo "gh CLI is required" >&2
    exit 1
  fi
fi

JQ_BIN="jq"
if ! command -v "$JQ_BIN" >/dev/null 2>&1; then
  if command -v jq.exe >/dev/null 2>&1; then
    JQ_BIN="jq.exe"
  else
    echo "jq is required" >&2
    exit 1
  fi
fi

REPO="$1"
CANONICAL_ISSUE="$2"
NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TODAY="$(date -u +%Y-%m-%d)"
WEEK_LABEL="$(date -u +%G-W%V)"
OUT_DIR=".github/reports/governance"
METRICS_FILE="$OUT_DIR/governance_waiver_metrics_${WEEK_LABEL}.prom"
REPORT_FILE="$OUT_DIR/governance_waiver_report_${WEEK_LABEL}.md"
REGISTRY_FILE="docs/governance/WAIVERS.md"

mkdir -p "$OUT_DIR"

query_items() {
  "$GH_BIN" api \
    -X GET search/issues \
    -f q="repo:${REPO} is:issue is:open label:waiver" \
    -f per_page=100 \
    --jq '.items'
}

extract_field() {
  local body="$1"
  local prefix="$2"
  printf '%s\n' "$body" | awk -v prefix="$prefix" 'index($0, prefix) == 1 { print substr($0, length(prefix) + 1); exit }'
}

is_blank() {
  local value="$1"
  local compact="${value//[[:space:]]/}"
  [[ -z "$compact" || "$value" == \<*\> || "$value" =~ ^[Tt][Bb][Dd]$ || "$value" =~ ^[Pp]ending$ ]]
}

ISSUES_JSON="$(query_items)"
TOTAL_OPEN="$($JQ_BIN 'length' <<<"$ISSUES_JSON")"
REGISTRY_COUNT=0

if [[ -f "$REGISTRY_FILE" ]]; then
  REGISTRY_COUNT="$(grep -c '^### Waiver #' "$REGISTRY_FILE" || true)"
fi

ACTIVE=0
PENDING_APPROVAL=0
EXPIRED_OPEN=0
EXPIRING_7_DAYS=0
INCOMPLETE_REQUESTS=0
ROWS=""

while IFS= read -r issue_json; do
  [[ -z "$issue_json" ]] && continue

  number="$($JQ_BIN -r '.number' <<<"$issue_json")"
  title="$($JQ_BIN -r '.title' <<<"$issue_json")"
  url="$($JQ_BIN -r '.html_url' <<<"$issue_json")"
  body="$($JQ_BIN -r '.body // ""' <<<"$issue_json")"

  requested_by="$(extract_field "$body" '- Requested by: ')"
  policy_violated="$(extract_field "$body" '- Policy violated: ')"
  justification="$(extract_field "$body" '- Justification: ')"
  expiration="$(extract_field "$body" '- Expiration (YYYY-MM-DD): ')"
  impact="$(extract_field "$body" '- Impact: ')"
  approved_by="$(extract_field "$body" '- Approved by: ')"
  approval_date="$(extract_field "$body" '- Approval date (YYYY-MM-DD): ')"

  missing_request=0
  if is_blank "$requested_by" || is_blank "$policy_violated" || is_blank "$justification" || is_blank "$expiration" || is_blank "$impact"; then
    missing_request=1
    ((INCOMPLETE_REQUESTS+=1))
  fi

  approval_complete=1
  if is_blank "$approved_by" || is_blank "$approval_date"; then
    approval_complete=0
    ((PENDING_APPROVAL+=1))
  fi

  status="pending-approval"
  if [[ "$missing_request" -eq 1 ]]; then
    status="incomplete-request"
  elif [[ "$approval_complete" -eq 1 ]]; then
    expiration_ts="$(date -u -d "$expiration" +%s 2>/dev/null || echo 0)"
    today_ts="$(date -u -d "$TODAY" +%s)"
    seven_day_ts="$(date -u -d "$TODAY +7 days" +%s)"
    if [[ "$expiration_ts" -eq 0 ]]; then
      status="invalid-expiration"
    elif [[ "$expiration_ts" -lt "$today_ts" ]]; then
      status="expired"
      ((EXPIRED_OPEN+=1))
    else
      status="active"
      ((ACTIVE+=1))
      if [[ "$expiration_ts" -le "$seven_day_ts" ]]; then
        ((EXPIRING_7_DAYS+=1))
      fi
    fi
  fi

  ROWS+="| #${number} | ${status} | ${expiration:-missing} | ${approved_by:-pending} | [link](${url}) | ${title//$'\n'/ } |"$'\n'
done < <($JQ_BIN -c '.[]' <<<"$ISSUES_JSON")

cat > "$METRICS_FILE" <<EOF
# HELP governance_waivers_open Number of open waiver issues.
# TYPE governance_waivers_open gauge
governance_waivers_open ${TOTAL_OPEN}
# HELP governance_waivers_active Number of approved, non-expired waiver issues.
# TYPE governance_waivers_active gauge
governance_waivers_active ${ACTIVE}
# HELP governance_waivers_pending_approval Number of open waiver issues missing approval metadata.
# TYPE governance_waivers_pending_approval gauge
governance_waivers_pending_approval ${PENDING_APPROVAL}
# HELP governance_waivers_expiring_7_days Number of approved waivers expiring within seven days.
# TYPE governance_waivers_expiring_7_days gauge
governance_waivers_expiring_7_days ${EXPIRING_7_DAYS}
# HELP governance_waivers_expired_open Number of open waivers whose expiration date is in the past.
# TYPE governance_waivers_expired_open gauge
governance_waivers_expired_open ${EXPIRED_OPEN}
# HELP governance_waiver_requests_incomplete Number of waiver issues missing required request metadata.
# TYPE governance_waiver_requests_incomplete gauge
governance_waiver_requests_incomplete ${INCOMPLETE_REQUESTS}
# HELP governance_waiver_registry_entries Number of waiver entries recorded in docs/governance/WAIVERS.md.
# TYPE governance_waiver_registry_entries gauge
governance_waiver_registry_entries ${REGISTRY_COUNT}
# HELP governance_waiver_report_timestamp_seconds Unix timestamp of waiver report generation.
# TYPE governance_waiver_report_timestamp_seconds gauge
governance_waiver_report_timestamp_seconds $(date -u +%s)
EOF

cat > "$REPORT_FILE" <<EOF
# Governance Waiver Audit Report (${WEEK_LABEL})

Generated: ${NOW_UTC}
Repository: ${REPO}
Canonical governance issue: #${CANONICAL_ISSUE}

## Summary

| Metric | Value |
|---|---:|
| Open waiver issues | ${TOTAL_OPEN} |
| Active approved waivers | ${ACTIVE} |
| Pending approval | ${PENDING_APPROVAL} |
| Expiring in 7 days | ${EXPIRING_7_DAYS} |
| Expired but still open | ${EXPIRED_OPEN} |
| Incomplete waiver requests | ${INCOMPLETE_REQUESTS} |
| Registry entries | ${REGISTRY_COUNT} |

## Open Waiver Issues

| Issue | Status | Expiration | Approved By | Link | Title |
|---|---|---|---|---|---|
${ROWS:-| none | none | none | none | none | none |}

## Notes

- `active` means approval metadata is present and expiration is today or later.
- `pending-approval` means request metadata exists but approval metadata is incomplete.
- `incomplete-request` means required request fields are still missing.
- `expired` indicates a still-open waiver whose expiration date is already in the past.
- Registry counts come from `docs/governance/WAIVERS.md` and should track approved waiver entries.
EOF

echo "Generated: $METRICS_FILE"
echo "Generated: $REPORT_FILE"