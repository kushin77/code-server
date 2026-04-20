#!/usr/bin/env bash
# @file        scripts/ops/route-security-audit-events.sh
# @module      ops/security
# @description Export audit log events to JSONL and route security findings into GitHub Issues.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "$REPO_ROOT/scripts/_common/init.sh"
source "$REPO_ROOT/scripts/audit-logging.sh"

GH_REPO="${GH_REPO:-kushin77/code-server}"
SOURCE_LOG="${SOURCE_LOG:-${AUDIT_LOG_FILE}}"
OUTPUT_JSONL="${OUTPUT_JSONL:-}"
AUTO_OUTPUT_JSONL="false"
DRY_RUN="false"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ops/route-security-audit-events.sh [--source-log <file>] [--repo owner/repo] [--output-jsonl <file>] [--dry-run]

Options:
  --source-log     Audit log file to export from. Defaults to scripts/audit-logging.sh's audit.jsonl path.
  --output-jsonl   Output JSONL file to generate before routing. Defaults to a temp file.
  --repo          GitHub repository in owner/repo form.
  --dry-run       Export and preview routing without creating or updating issues.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-log)
      SOURCE_LOG="${2:-}"
      shift 2
      ;;
    --output-jsonl)
      OUTPUT_JSONL="${2:-}"
      shift 2
      ;;
    --repo)
      GH_REPO="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_fatal "Unknown argument: $1"
      ;;
  esac
done

if [[ -z "$OUTPUT_JSONL" ]]; then
  OUTPUT_JSONL="$(mktemp "${TMPDIR:-/tmp}/security-audit-events.XXXXXX.jsonl")"
  AUTO_OUTPUT_JSONL="true"
fi

cleanup() {
  if [[ "$AUTO_OUTPUT_JSONL" == "true" && -n "${OUTPUT_JSONL:-}" && -f "$OUTPUT_JSONL" ]]; then
    rm -f "$OUTPUT_JSONL"
  fi
}
trap cleanup EXIT

if [[ ! -f "$SOURCE_LOG" ]]; then
  log_warn "No audit log found at $SOURCE_LOG; nothing to route"
  exit 0
fi

require_command python3

mkdir -p "$(dirname "$OUTPUT_JSONL")"

python3 - "$SOURCE_LOG" "$OUTPUT_JSONL" <<'PY'
import json
import pathlib
import sys

source_path = pathlib.Path(sys.argv[1])
output_path = pathlib.Path(sys.argv[2])
text = source_path.read_text(encoding="utf-8")
decoder = json.JSONDecoder()
index = 0
selected = 0

security_event_types = {
    "SHELL_VIOLATION",
    "SHELL_BLOCKED",
    "FILE_WRITE_ATTEMPT",
    "FILE_DELETE_ATTEMPT",
    "FILE_DOWNLOAD_ATTEMPT",
    "GIT_VIOLATION",
    "RATE_LIMIT_EXCEEDED",
    "SECURITY_ALERT",
    "SECURITY_POLICY_VIOLATION",
    "policy.denied",
}

with output_path.open("w", encoding="utf-8") as output_handle:
    while True:
        while index < len(text) and text[index].isspace():
            index += 1
        if index >= len(text):
            break

        try:
            record, index = decoder.raw_decode(text, index)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"Failed to parse audit log JSON near offset {index}: {exc}") from exc

        event_type = str(record.get("event_type") or "")
        status = str(record.get("status") or "")
        component = str(record.get("component") or "")

        is_security_event = (
            event_type in security_event_types
            or component.lower() == "security"
            or status in {"blocked", "denied"}
        )

        if not is_security_event:
            continue

        output_handle.write(json.dumps(record, separators=(",", ":")) + "\n")
        selected += 1

if selected == 0:
    output_path.write_text("", encoding="utf-8")
PY

selected_count="$(wc -l < "$OUTPUT_JSONL" | tr -d '[:space:]')"

if [[ "$selected_count" == "0" ]]; then
  log_info "No security events found in $SOURCE_LOG"
  exit 0
fi

log_info "Exported ${selected_count} security event(s) from ${SOURCE_LOG}"

TRIAGE_ARGS=("$REPO_ROOT/scripts/ops/security-scan-triage.sh" --tool audit-log --audit-jsonl "$OUTPUT_JSONL" --repo "$GH_REPO")
if [[ "$DRY_RUN" == "true" ]]; then
  TRIAGE_ARGS+=(--dry-run)
fi

"${TRIAGE_ARGS[@]}"