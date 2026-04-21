#!/usr/bin/env bash
# @file        scripts/ci/run-deterministic-e2e-suite.sh
# @module      ci/e2e
# @description Run an ephemeral E2E suite with deterministic flake classification and rerun policy.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

SUITE_NAME=""
OUTPUT_DIR="${E2E_FLAKE_OUTPUT_DIR:-artifacts/triage}"
SIGNATURES_FILE="${E2E_FLAKE_SIGNATURES_FILE:-config/test-flake-signatures.json}"
RERUN_LIMIT="${E2E_FLAKE_RERUN_LIMIT:-1}"
COMMAND=()

while (($#)); do
  case "$1" in
    --suite-name)
      SUITE_NAME="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --signatures-file)
      SIGNATURES_FILE="${2:-}"
      shift 2
      ;;
    --rerun-limit)
      RERUN_LIMIT="${2:-}"
      shift 2
      ;;
    --)
      shift
      COMMAND=("$@")
      break
      ;;
    *)
      log_fatal "Unknown argument: $1"
      ;;
  esac
done

if [[ -z "$SUITE_NAME" ]]; then
  log_fatal "--suite-name is required"
fi

if [[ ${#COMMAND[@]} -eq 0 ]]; then
  log_fatal "A suite command must be provided after --"
fi

require_command python3
require_file "$SIGNATURES_FILE"

mkdir -p "$OUTPUT_DIR"

command_display=$(printf '%q ' "${COMMAND[@]}")
manifest_file="$OUTPUT_DIR/${SUITE_NAME}-flake-attempts.tsv"
summary_json="$OUTPUT_DIR/${SUITE_NAME}-flake-report.json"
summary_md="$OUTPUT_DIR/${SUITE_NAME}-flake-report.md"
final_status="failed"
final_classification="unknown"
final_exit_code=1
attempt_count=0

: > "$manifest_file"

run_attempt() {
  local attempt_index=$1
  local attempt_log="$OUTPUT_DIR/${SUITE_NAME}-attempt-${attempt_index}.log"
  local classification_file="$OUTPUT_DIR/${SUITE_NAME}-attempt-${attempt_index}.classification.json"
  local exit_code=0

  log_info "Running $SUITE_NAME attempt $attempt_index"
  if "${COMMAND[@]}" 2>&1 | tee "$attempt_log"; then
    exit_code=0
  else
    exit_code=${PIPESTATUS[0]}
  fi

  local classification="passed"
  local recommend_rerun="false"

  if [[ "$exit_code" -ne 0 ]]; then
    python3 "$SCRIPT_DIR/classify-e2e-flakes.py" \
      --log-file "$attempt_log" \
      --signatures-file "$SIGNATURES_FILE" \
      --output-file "$classification_file"

    classification=$(python3 - "$classification_file" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
print(data.get('classification', 'unknown'))
PY
)

    recommend_rerun=$(python3 - "$classification_file" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
print('true' if data.get('recommendRerun') else 'false')
PY
)
  else
    python3 "$SCRIPT_DIR/classify-e2e-flakes.py" \
      --log-file "$attempt_log" \
      --signatures-file "$SIGNATURES_FILE" \
      --output-file "$classification_file" >/dev/null 2>&1 || true
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$attempt_index" \
    "$exit_code" \
    "$attempt_log" \
    "$classification_file" \
    "$classification" >> "$manifest_file"

  attempt_count=$attempt_index

  if [[ "$exit_code" -eq 0 ]]; then
    final_status="passed"
    final_classification="passed"
    final_exit_code=0
    return 0
  fi

  if [[ "$classification" == "flake" && "$attempt_index" -le "$RERUN_LIMIT" && "$recommend_rerun" == "true" ]]; then
    log_warn "$SUITE_NAME classified as flaky; rerunning deterministically (attempt $attempt_index of $RERUN_LIMIT)"
    return 2
  fi

  final_status="failed"
  final_classification="$classification"
  final_exit_code=$exit_code
  return 1
}

attempt_index=1
while :; do
  if run_attempt "$attempt_index"; then
    break
  else
    rc=$?
  fi

  if [[ "$rc" -eq 2 ]]; then
    attempt_index=$((attempt_index + 1))
    continue
  fi

  break
done

if [[ "$final_status" == "failed" && "$attempt_count" -gt 0 ]]; then
  last_classification_file="$OUTPUT_DIR/${SUITE_NAME}-attempt-${attempt_count}.classification.json"
  if [[ -f "$last_classification_file" ]]; then
    final_classification=$(python3 - "$last_classification_file" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
print(data.get('classification', 'unknown'))
PY
)
  fi
fi

python3 - "$manifest_file" "$summary_json" "$summary_md" "$SUITE_NAME" "$command_display" "$SIGNATURES_FILE" "$RERUN_LIMIT" "$final_status" "$final_classification" "$final_exit_code" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

manifest_path = Path(sys.argv[1])
summary_json = Path(sys.argv[2])
summary_md = Path(sys.argv[3])
suite_name = sys.argv[4]
command_display = sys.argv[5].strip()
signatures_file = sys.argv[6]
rerun_limit = int(sys.argv[7])
final_status = sys.argv[8]
final_classification = sys.argv[9]
final_exit_code = int(sys.argv[10])

attempts = []
for line in manifest_path.read_text(encoding='utf-8').splitlines():
    if not line.strip():
        continue
    attempt_index, exit_code, log_file, classification_file, classification = line.split('\t')
    classification_data = {}
    if classification_file and Path(classification_file).exists():
        classification_data = json.loads(Path(classification_file).read_text(encoding='utf-8'))

    attempts.append({
        'attempt': int(attempt_index),
        'exitCode': int(exit_code),
        'logFile': log_file,
        'classificationFile': classification_file,
        'classification': classification,
        'matchedSignatures': classification_data.get('matchedSignatures', []),
        'recommendRerun': classification_data.get('recommendRerun', False),
    })

report = {
    'suiteName': suite_name,
    'command': command_display,
    'signaturesFile': signatures_file,
    'rerunPolicy': {
        'enabled': rerun_limit > 0,
        'rerunLimit': rerun_limit,
        'rerunOn': ['flake'],
    },
    'finalStatus': final_status,
    'finalClassification': final_classification,
    'finalExitCode': final_exit_code,
    'attempts': attempts,
    'generatedAt': datetime.now(timezone.utc).isoformat(timespec='seconds'),
}

summary_json.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')

lines = [
    '# Deterministic E2E Flake Report',
    '',
    f'Suite: {suite_name}',
    f'Command: {command_display}',
    f'Final status: {final_status}',
    f'Final classification: {final_classification}',
    f'Final exit code: {final_exit_code}',
    f'Rerun limit: {rerun_limit}',
    '',
    '## Attempts',
    '',
    '| Attempt | Exit code | Classification | Log file |',
    '|---|---:|---|---|',
]

for attempt in attempts:
    lines.append(
        f"| {attempt['attempt']} | {attempt['exitCode']} | {attempt['classification']} | {attempt['logFile']} |"
    )

lines += [
    '',
    '## Matched Signatures',
    '',
]

matched_any = False
for attempt in attempts:
    if not attempt['matchedSignatures']:
        continue
    matched_any = True
    lines.append(f"### Attempt {attempt['attempt']}")
    for match in attempt['matchedSignatures']:
        lines.append(f"- {match['name']} ({match['decision']}) :: {match['snippet']}")
    lines.append('')

if not matched_any:
    lines.append('- No signatures matched.')

summary_md.write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY

if [[ "$final_status" == "passed" ]]; then
  log_info "$SUITE_NAME completed successfully"
else
  log_warn "$SUITE_NAME failed with classification '$final_classification' and exit code $final_exit_code"
fi

log_info "Flake report: $summary_json"

if [[ "$final_status" == "passed" ]]; then
  exit 0
fi

exit "$final_exit_code"