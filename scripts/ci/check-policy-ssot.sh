#!/usr/bin/env bash
# @file        scripts/ci/check-policy-ssot.sh
# @module      ci/governance
# @description Detect duplicate and contradictory normative policy statements across governance docs
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC_DIR="$ROOT_DIR/docs/governance"
REPORT_FILE="${1:-$ROOT_DIR/policy-ssot-report.json}"

if [[ ! -d "$DOC_DIR" ]]; then
  echo "Governance docs directory not found: $DOC_DIR" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for policy SSOT checks" >&2
  exit 1
fi

tmp_normative="$(mktemp)"
tmp_duplicates="$(mktemp)"
tmp_contradictions="$(mktemp)"
trap 'rm -f "$tmp_normative" "$tmp_duplicates" "$tmp_contradictions"' EXIT

extract_normative() {
  local file="$1"
  awk -v f="$file" '
    {
      line=$0
      lower=tolower($0)
      if (lower ~ /\b(must|must not|shall|shall not|required)\b/) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        norm=tolower(line)
        gsub(/[[:space:]]+/, " ", norm)
        print f "\t" line "\t" norm
      }
    }
  ' "$file"
}

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  extract_normative "$file" >> "$tmp_normative"
done < <(find "$DOC_DIR" -maxdepth 1 -type f -name '*.md' | sort)

if [[ ! -s "$tmp_normative" ]]; then
  jq -n '{summary:{normative_statements:0,duplicate_statements:0,contradictions:0},duplicates:[],contradictions:[]}' > "$REPORT_FILE"
  echo "No normative statements found"
  exit 0
fi

cut -f3 "$tmp_normative" | sort | uniq -d > "$tmp_duplicates" || true

while IFS= read -r dup_norm; do
  [[ -z "$dup_norm" ]] && continue
  grep -F "	$dup_norm" "$tmp_normative"
done < "$tmp_duplicates" > "$tmp_duplicates.entries" || true

while IFS=$'\t' read -r file original norm; do
  if [[ "$norm" == *" must not "* ]]; then
    pos="${norm/ must not / must }"
    if grep -F "	$pos" "$tmp_normative" >/dev/null; then
      printf '%s\t%s\t%s\n' "$file" "$original" "$pos" >> "$tmp_contradictions"
    fi
  fi
  if [[ "$norm" == *" shall not "* ]]; then
    pos="${norm/ shall not / shall }"
    if grep -F "	$pos" "$tmp_normative" >/dev/null; then
      printf '%s\t%s\t%s\n' "$file" "$original" "$pos" >> "$tmp_contradictions"
    fi
  fi
done < "$tmp_normative"

normative_count="$(wc -l < "$tmp_normative" | tr -d ' ')"
duplicate_count="$(wc -l < "$tmp_duplicates" | tr -d ' ')"
contradiction_count="$(wc -l < "$tmp_contradictions" | tr -d ' ')"

jq -n \
  --argjson normative_count "$normative_count" \
  --argjson duplicate_count "$duplicate_count" \
  --argjson contradiction_count "$contradiction_count" \
  --argjson duplicates "$(
    awk -F'\t' '{print $1 "\t" $2 "\t" $3}' "$tmp_duplicates.entries" \
      | jq -R -s -c 'split("\n") | map(select(length>0)) | map(split("\t") | {file: .[0], statement: .[1], normalized: .[2]})'
  )" \
  --argjson contradictions "$(
    awk -F'\t' '{print $1 "\t" $2 "\t" $3}' "$tmp_contradictions" \
      | jq -R -s -c 'split("\n") | map(select(length>0)) | map(split("\t") | {file: .[0], statement: .[1], contradicts_normalized: .[2]})'
  )" \
  '{
    summary: {
      normative_statements: $normative_count,
      duplicate_statements: $duplicate_count,
      contradictions: $contradiction_count
    },
    duplicates: $duplicates,
    contradictions: $contradictions
  }' > "$REPORT_FILE"

echo "Policy SSOT report: $REPORT_FILE"
echo "Normative statements: $normative_count"
echo "Duplicate normalized statements: $duplicate_count"
echo "Contradictions: $contradiction_count"

if [[ "$duplicate_count" -gt 0 || "$contradiction_count" -gt 0 ]]; then
  exit 1
fi

exit 0
