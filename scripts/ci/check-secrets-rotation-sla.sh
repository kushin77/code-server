#!/usr/bin/env bash
# @file        scripts/ci/check-secrets-rotation-sla.sh
# @module      ci/security
# @description Alert when quarterly secrets rotation evidence is missing or stale
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REPORT_FILE="${REPORT_FILE:-artifacts/security/secrets-rotation-report.json}"
MAX_AGE_DAYS="${MAX_AGE_DAYS:-90}"

if [[ ! -f "$REPORT_FILE" ]]; then
  log_fatal "Missing rotation report: $REPORT_FILE"
fi

ts=""
if command -v jq >/dev/null 2>&1; then
  ts="$(jq -r '.timestamp_utc // empty' "$REPORT_FILE")"
elif command -v python3 >/dev/null 2>&1; then
  ts="$(REPORT_FILE="$REPORT_FILE" python3 - <<'PY'
import json
import os
from pathlib import Path
data = json.loads(Path(os.environ["REPORT_FILE"]).read_text(encoding="utf-8"))
print(data.get("timestamp_utc", ""))
PY
)"
else
  log_fatal "Neither jq nor python3 is available to parse $REPORT_FILE"
fi

if [[ -z "$ts" ]]; then
  log_fatal "Rotation report missing timestamp_utc: $REPORT_FILE"
fi

report_epoch="$(date -u -d "$ts" +%s 2>/dev/null || true)"
now_epoch="$(date -u +%s)"

if [[ -z "$report_epoch" ]]; then
  log_fatal "Invalid timestamp in rotation report: $ts"
fi

age_days=$(( (now_epoch - report_epoch) / 86400 ))

if (( age_days > MAX_AGE_DAYS )); then
  log_fatal "Secrets rotation evidence is stale: ${age_days}d > ${MAX_AGE_DAYS}d"
fi

log_info "Secrets rotation evidence age is within SLA: ${age_days}d <= ${MAX_AGE_DAYS}d"
