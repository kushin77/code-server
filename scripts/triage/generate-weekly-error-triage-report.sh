#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <owner/repo>" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

REPO="$1"
NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
WEEK_LABEL="$(date -u +%G-W%V)"
OUT_DIR=".github/reports/error-triage"
METRICS_FILE="$OUT_DIR/error_triage_metrics_${WEEK_LABEL}.prom"
REPORT_FILE="$OUT_DIR/error_triage_report_${WEEK_LABEL}.md"

mkdir -p "$OUT_DIR"

query_count() {
  local q="$1"
  gh api \
    -X GET search/issues \
    -f q="$q" \
    --jq '.total_count'
}

TOTAL_OPEN=$(query_count "repo:${REPO} is:issue is:open label:error-triage")
TOTAL_CLOSED=$(query_count "repo:${REPO} is:issue is:closed label:error-triage")
FALSE_POSITIVES=$(query_count "repo:${REPO} is:issue label:error-triage label:false_positive")
FALSE_MERGES=$(query_count "repo:${REPO} is:issue label:error-triage label:false-merge")
P0_OPEN=$(query_count "repo:${REPO} is:issue is:open label:error-triage label:P0")
P1_OPEN=$(query_count "repo:${REPO} is:issue is:open label:error-triage label:P1")

LAST_WEEK_OPEN=$(query_count "repo:${REPO} is:issue is:open label:error-triage created:<$(date -u +%Y-%m-%d)")
WEEKLY_CREATED=$(query_count "repo:${REPO} is:issue label:error-triage created:>=$(date -u -d '7 days ago' +%Y-%m-%d)")

DUPLICATE_REDUCTION=$(jq -n --arg current "$TOTAL_OPEN" --arg prior "$LAST_WEEK_OPEN" '
  if ($prior|tonumber) == 0 then 0
  else ((($prior|tonumber) - ($current|tonumber)) / ($prior|tonumber)) * 100 end')

FALSE_POSITIVE_RATE=$(jq -n --arg fp "$FALSE_POSITIVES" --arg total "$((TOTAL_OPEN + TOTAL_CLOSED))" '
  if ($total|tonumber) == 0 then 0 else ($fp|tonumber) / ($total|tonumber) end')

FALSE_MERGE_RATE=$(jq -n --arg fm "$FALSE_MERGES" --arg total "$((TOTAL_OPEN + TOTAL_CLOSED))" '
  if ($total|tonumber) == 0 then 0 else ($fm|tonumber) / ($total|tonumber) end')

SLA_CRITICAL_BREACHES=$(gh api \
  -X GET search/issues \
  -f q="repo:${REPO} is:issue is:open label:error-triage label:P0 created:<$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --jq '.total_count')

SLA_HIGH_BREACHES=$(gh api \
  -X GET search/issues \
  -f q="repo:${REPO} is:issue is:open label:error-triage label:P1 created:<$(date -u -d '4 hours ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --jq '.total_count')

cat > "$METRICS_FILE" <<EOF
# HELP error_triage_open_issues Number of open automated error triage issues.
# TYPE error_triage_open_issues gauge
error_triage_open_issues ${TOTAL_OPEN}
# HELP error_triage_created_weekly Number of triage issues created in the last 7 days.
# TYPE error_triage_created_weekly gauge
error_triage_created_weekly ${WEEKLY_CREATED}
# HELP error_triage_duplicate_reduction_percent Heuristic week-over-week open-triage reduction percentage.
# TYPE error_triage_duplicate_reduction_percent gauge
error_triage_duplicate_reduction_percent ${DUPLICATE_REDUCTION}
# HELP error_triage_sla_critical_breaches Open P0 triage issues older than 30 minutes.
# TYPE error_triage_sla_critical_breaches gauge
error_triage_sla_critical_breaches ${SLA_CRITICAL_BREACHES}
# HELP error_triage_sla_high_breaches Open P1 triage issues older than 4 hours.
# TYPE error_triage_sla_high_breaches gauge
error_triage_sla_high_breaches ${SLA_HIGH_BREACHES}
# HELP error_triage_false_positive_rate Fraction of triage issues labeled false_positive.
# TYPE error_triage_false_positive_rate gauge
error_triage_false_positive_rate ${FALSE_POSITIVE_RATE}
# HELP error_triage_false_merge_rate Fraction of triage issues labeled false-merge.
# TYPE error_triage_false_merge_rate gauge
error_triage_false_merge_rate ${FALSE_MERGE_RATE}
# HELP error_triage_report_timestamp_seconds Unix timestamp of weekly triage report generation.
# TYPE error_triage_report_timestamp_seconds gauge
error_triage_report_timestamp_seconds $(date -u +%s)
EOF

cat > "$REPORT_FILE" <<EOF
# Error Triage Weekly Report (${WEEK_LABEL})

Generated: ${NOW_UTC}
Repository: ${REPO}

## Summary

| Metric | Value |
|---|---:|
| Open triage issues | ${TOTAL_OPEN} |
| Closed triage issues | ${TOTAL_CLOSED} |
| Weekly created | ${WEEKLY_CREATED} |
| Duplicate reduction (%) | ${DUPLICATE_REDUCTION} |
| P0 open | ${P0_OPEN} |
| P1 open | ${P1_OPEN} |
| SLA critical breaches | ${SLA_CRITICAL_BREACHES} |
| SLA high breaches | ${SLA_HIGH_BREACHES} |
| False positive rate | ${FALSE_POSITIVE_RATE} |
| False merge rate | ${FALSE_MERGE_RATE} |

## Notes

- Duplicate reduction is a week-over-week heuristic based on current open triage issues versus prior open-triage volume.
- SLA breach counts follow config/error-triage-config.yml thresholds: P0 > 30m, P1 > 4h.
- False-positive and false-merge rates are driven by labels (`false_positive`, `false-merge`) on triage issues.
- Weekly report supports issue #378 acceptance criteria for duplicate reduction and SLA compliance visibility.
EOF

echo "Generated: $METRICS_FILE"
echo "Generated: $REPORT_FILE"