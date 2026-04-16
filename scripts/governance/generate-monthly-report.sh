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
MONTH_LABEL="$(date -u +%Y-%m)"
OUT_DIR=".github/reports/governance"
METRICS_FILE="$OUT_DIR/governance_metrics_${MONTH_LABEL}.prom"
REPORT_FILE="$OUT_DIR/governance_report_${MONTH_LABEL}.md"

mkdir -p "$OUT_DIR"

query_count() {
  local q="$1"
  gh api \
    -X GET search/issues \
    -f q="$q" \
    --jq '.total_count'
}

DUPLICATE_OPEN=$(query_count "repo:${REPO} is:issue is:open duplicate in:title")
DUPLICATE_CLOSED=$(query_count "repo:${REPO} is:issue is:closed duplicate in:title")
CANONICAL_OPEN=$(query_count "repo:${REPO} is:issue is:open canonical in:title,body")
CANONICAL_CLOSED=$(query_count "repo:${REPO} is:issue is:closed canonical in:title,body")

# Heuristic orphaned tracker: duplicate-related open issues with no linked issue reference.
ORPHANED_OPEN=$(gh api \
  -X GET search/issues \
  -f q="repo:${REPO} is:issue is:open duplicate in:title" \
  --jq '[.items[] | select((.body // "") | test("#[0-9]+") | not)] | length')

TOTAL_TRACKED=$((DUPLICATE_OPEN + DUPLICATE_CLOSED + CANONICAL_OPEN + CANONICAL_CLOSED))
if [[ "$TOTAL_TRACKED" -eq 0 ]]; then
  CONSOLIDATION_RATIO=1
else
  CONSOLIDATION_RATIO=$(jq -n --arg c "$CANONICAL_CLOSED" --arg t "$TOTAL_TRACKED" '$c|tonumber / ($t|tonumber)')
fi

cat > "$METRICS_FILE" <<EOF
# HELP governance_duplicate_issues Number of open duplicate-labeled issue candidates.
# TYPE governance_duplicate_issues gauge
governance_duplicate_issues ${DUPLICATE_OPEN}
# HELP governance_orphaned_issues Number of open duplicate candidates missing canonical cross-link.
# TYPE governance_orphaned_issues gauge
governance_orphaned_issues ${ORPHANED_OPEN}
# HELP governance_consolidation_ratio Consolidation ratio based on canonical-closed issues over tracked duplicate/canonical universe.
# TYPE governance_consolidation_ratio gauge
governance_consolidation_ratio ${CONSOLIDATION_RATIO}
# HELP governance_report_timestamp_seconds Unix timestamp of governance report generation.
# TYPE governance_report_timestamp_seconds gauge
governance_report_timestamp_seconds $(date -u +%s)
EOF

cat > "$REPORT_FILE" <<EOF
# Governance Monthly Report (${MONTH_LABEL})

Generated: ${NOW_UTC}
Repository: ${REPO}

## Metrics

| Metric | Value |
|---|---:|
| governance_duplicate_issues | ${DUPLICATE_OPEN} |
| governance_orphaned_issues | ${ORPHANED_OPEN} |
| governance_consolidation_ratio | ${CONSOLIDATION_RATIO} |

## Inputs

| Source | Value |
|---|---:|
| duplicate_open | ${DUPLICATE_OPEN} |
| duplicate_closed | ${DUPLICATE_CLOSED} |
| canonical_open | ${CANONICAL_OPEN} |
| canonical_closed | ${CANONICAL_CLOSED} |

## Notes

- orphaned metric is heuristic and flags open duplicate issues missing issue-link references in body.
- consolidation ratio is derived from canonical_closed / (duplicate_open + duplicate_closed + canonical_open + canonical_closed).
EOF

echo "Generated: $METRICS_FILE"
echo "Generated: $REPORT_FILE"
