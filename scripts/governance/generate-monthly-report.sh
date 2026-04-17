#!/usr/bin/env bash
# @file        scripts/governance/generate-monthly-report.sh
# @module      governance/reporting
# @description Generate monthly governance report for repositories
# @status      active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

if [[ $# -ne 1 ]]; then
  log_error "Usage: $0 <owner/repo>"
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  log_error "gh CLI is required"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  log_error "jq is required"
  exit 1
fi

REPO="$1"
NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
MONTH_LABEL="$(date -u +%Y-%m)"
OUT_DIR=".github/reports/governance"
METRICS_FILE="$OUT_DIR/governance_metrics_${MONTH_LABEL}.prom"
REPORT_FILE="$OUT_DIR/governance_report_${MONTH_LABEL}.md"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if ! SCORE_OUTPUT="$(${REPO_ROOT}/scripts/governance/calculate-governance-score.sh --format env)"; then
  echo "Failed to calculate governance score" >&2
  exit 1
fi

while IFS='=' read -r key value; do
  case "$key" in
    GOVERNANCE_SCORE|JSCPD_VIOLATIONS|MISSING_HEADERS|HARDCODED_IPS|ACTIVE_SHIMS_WITH_FALLBACK)
      printf -v "$key" '%s' "$value"
      ;;
  esac
done <<< "$SCORE_OUTPUT"

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
# HELP governance_score Composite governance score for current repo snapshot.
# TYPE governance_score gauge
governance_score ${GOVERNANCE_SCORE}
# HELP governance_score_jscpd_violations jscpd duplicate clusters contributing to score penalty.
# TYPE governance_score_jscpd_violations gauge
governance_score_jscpd_violations ${JSCPD_VIOLATIONS}
# HELP governance_score_missing_headers Active MANIFEST scripts missing required metadata headers.
# TYPE governance_score_missing_headers gauge
governance_score_missing_headers ${MISSING_HEADERS}
# HELP governance_score_hardcoded_ips Active top-level scripts containing hardcoded IP addresses.
# TYPE governance_score_hardcoded_ips gauge
governance_score_hardcoded_ips ${HARDCODED_IPS}
# HELP governance_score_active_shims_with_fallback Active compatibility shims retaining fallback implementations.
# TYPE governance_score_active_shims_with_fallback gauge
governance_score_active_shims_with_fallback ${ACTIVE_SHIMS_WITH_FALLBACK}
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
| governance_score | ${GOVERNANCE_SCORE} |

## Governance Score Breakdown

| Signal | Count | Penalty |
|---|---:|---:|
| jscpd violations | ${JSCPD_VIOLATIONS} | $((JSCPD_VIOLATIONS * 5)) |
| missing headers | ${MISSING_HEADERS} | $((MISSING_HEADERS * 2)) |
| hardcoded IP files | ${HARDCODED_IPS} | $((HARDCODED_IPS * 10)) |
| active fallback shims | ${ACTIVE_SHIMS_WITH_FALLBACK} | $((ACTIVE_SHIMS_WITH_FALLBACK * 8)) |

## Inputs

| Source | Value |
|---|---:|
| duplicate_open | ${DUPLICATE_OPEN} |
| duplicate_closed | ${DUPLICATE_CLOSED} |
| canonical_open | ${CANONICAL_OPEN} |
| canonical_closed | ${CANONICAL_CLOSED} |

Formula:

```
score = max(0, 100
  - (jscpd_violations * 5)
  - (missing_headers * 2)
  - (hardcoded_ips * 10)
  - (active_shims_with_fallback * 8))
```

## Notes

- orphaned metric is heuristic and flags open duplicate issues missing issue-link references in body.
- consolidation ratio is derived from canonical_closed / (duplicate_open + duplicate_closed + canonical_open + canonical_closed).
EOF

echo "Generated: $METRICS_FILE"
echo "Generated: $REPORT_FILE"
