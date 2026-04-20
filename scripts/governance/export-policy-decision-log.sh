#!/usr/bin/env bash
# @file        scripts/governance/export-policy-decision-log.sh
# @module      governance/policy-logging
# @description Export normalized policy decision logs and summary metrics for OPA decision-plane operations
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

INPUT_LOG=""
OUT_JSONL=""
OUT_SUMMARY=""

usage() {
  cat <<'EOF'
Usage:
  scripts/governance/export-policy-decision-log.sh --input <path> --out-jsonl <path> --out-summary <path>
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      INPUT_LOG="$2"
      shift 2
      ;;
    --out-jsonl)
      OUT_JSONL="$2"
      shift 2
      ;;
    --out-summary)
      OUT_SUMMARY="$2"
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

if [[ -z "$INPUT_LOG" || -z "$OUT_JSONL" || -z "$OUT_SUMMARY" ]]; then
  log_error "Missing required arguments"
  usage
  exit 1
fi

require_command "python3" "python3 is required"
require_file "$INPUT_LOG"
mkdir -p "$(dirname "$OUT_JSONL")"
mkdir -p "$(dirname "$OUT_SUMMARY")"

# Normalize to JSONL where every line has timestamp, decision, policy_domain, and actor.
# Supported input:
# 1) Existing JSONL lines
# 2) plain text lines that include POLICY_DECISION allow|deny

python3 - "$INPUT_LOG" "$OUT_JSONL" "$OUT_SUMMARY" <<'PY'
import json
import re
import sys
from datetime import datetime, timezone

input_path = sys.argv[1]
out_jsonl_path = sys.argv[2]
out_summary_path = sys.argv[3]

records = []
decision_re = re.compile(r"POLICY_DECISION\s+(allow|deny)", re.IGNORECASE)

with open(input_path, "r", encoding="utf-8") as f:
  for raw in f:
    line = raw.strip()
    if not line:
      continue

    parsed = None
    try:
      parsed = json.loads(line)
    except json.JSONDecodeError:
      parsed = None

    if isinstance(parsed, dict):
      records.append(
        {
          "timestamp": parsed.get("timestamp") or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
          "decision": parsed.get("decision") or parsed.get("result") or "unknown",
          "policy_domain": parsed.get("policy_domain") or parsed.get("domain") or "unknown",
          "actor": parsed.get("actor") or parsed.get("user") or "unknown",
          "source": parsed.get("source") or "runtime",
        }
      )
      continue

    m = decision_re.search(line)
    if m:
      records.append(
        {
          "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
          "decision": m.group(1).lower(),
          "policy_domain": "runtime",
          "actor": "unknown",
          "source": "text-log",
        }
      )

with open(out_jsonl_path, "w", encoding="utf-8") as out_jsonl:
  for rec in records:
    out_jsonl.write(json.dumps(rec, separators=(",", ":")) + "\n")

allow_count = sum(1 for r in records if r.get("decision") == "allow")
deny_count = sum(1 for r in records if r.get("decision") == "deny")
summary = {
  "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "input": input_path,
  "output": out_jsonl_path,
  "summary": {
    "total": len(records),
    "allow": allow_count,
    "deny": deny_count,
  },
}

with open(out_summary_path, "w", encoding="utf-8") as out_summary:
  json.dump(summary, out_summary, indent=2)
  out_summary.write("\n")
PY

log_info "Exported decision logs: $OUT_JSONL"
log_info "Summary written: $OUT_SUMMARY"
