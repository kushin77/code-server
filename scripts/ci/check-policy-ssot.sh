#!/usr/bin/env bash
# @file        scripts/ci/check-policy-ssot.sh
# @module      ci/governance
# @description Detect duplicate and contradictory normative policy statements across governance docs
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOC_DIR="$ROOT_DIR/docs/governance"
REPORT_FILE="${1:-$ROOT_DIR/policy-ssot-report.json}"

if [[ ! -d "$DOC_DIR" ]]; then
  log_error "Governance docs directory not found: $DOC_DIR"
  exit 1
fi

log_info "Scanning governance docs recursively under: $DOC_DIR"

require_command "python3" "python3 is required for policy SSOT checks"

tmp_normative="$(mktemp)"
tmp_duplicates="$(mktemp)"
tmp_contradictions="$(mktemp)"
tmp_duplicate_entries="$(mktemp)"
trap 'rm -f "$tmp_normative" "$tmp_duplicates" "$tmp_contradictions" "$tmp_duplicate_entries"' EXIT

extract_normative() {
  local file="$1"
  awk -v f="$file" '
    {
      line=$0
      lower=tolower($0)
      if (lower ~ /(^|[^[:alnum:]_])(must not|shall not|must|shall|required)([^[:alnum:]_]|$)/) {
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
done < <(find "$DOC_DIR" -type f -name '*.md' | sort)

if [[ ! -s "$tmp_normative" ]]; then
  python3 - "$REPORT_FILE" <<'PY'
import json
import sys

report_path = sys.argv[1]
report = {
    "summary": {
        "normative_statements": 0,
        "duplicate_statements": 0,
        "contradictions": 0,
    },
    "duplicates": [],
    "contradictions": [],
}

with open(report_path, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2)
    f.write("\n")
PY
  log_info "No normative statements found"
  exit 0
fi

cut -f3 "$tmp_normative" | sort | uniq -d > "$tmp_duplicates" || true

while IFS= read -r dup_norm; do
  [[ -z "$dup_norm" ]] && continue
  grep -F "	$dup_norm" "$tmp_normative"
done < "$tmp_duplicates" > "$tmp_duplicate_entries" || true

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

python3 - \
  "$REPORT_FILE" \
  "$tmp_duplicate_entries" \
  "$tmp_contradictions" \
  "$normative_count" \
  "$duplicate_count" \
  "$contradiction_count" <<'PY'
import json
import sys

report_path = sys.argv[1]
duplicates_path = sys.argv[2]
contradictions_path = sys.argv[3]
normative_count = int(sys.argv[4])
duplicate_count = int(sys.argv[5])
contradiction_count = int(sys.argv[6])

def parse_tsv(path, fields):
    entries = []
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t")
            row = {}
            for i, key in enumerate(fields):
                row[key] = parts[i] if i < len(parts) else ""
            entries.append(row)
    return entries

report = {
    "summary": {
        "normative_statements": normative_count,
        "duplicate_statements": duplicate_count,
        "contradictions": contradiction_count,
    },
    "duplicates": parse_tsv(duplicates_path, ["file", "statement", "normalized"]),
    "contradictions": parse_tsv(contradictions_path, ["file", "statement", "contradicts_normalized"]),
}

with open(report_path, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2)
    f.write("\n")
PY

log_info "Policy SSOT report: $REPORT_FILE"
log_info "Normative statements: $normative_count"
log_info "Duplicate normalized statements: $duplicate_count"
log_info "Contradictions: $contradiction_count"

if [[ "$duplicate_count" -gt 0 || "$contradiction_count" -gt 0 ]]; then
  exit 1
fi

exit 0
