#!/usr/bin/env bash
# @file        scripts/ci/validate-autopilot-setup-state-reconciler.sh
# @module      ci/ide
# @description Validate the Autopilot setup-state reconciler contract, regression matrix, and report schema.
#
# Usage: bash scripts/ci/validate-autopilot-setup-state-reconciler.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

RCA_FILE="${RCA_FILE:-docs/ops/AUTOPILOT-SETUP-STATE-RCA.md}"
RUNBOOK_FILE="${RUNBOOK_FILE:-docs/ops/AUTOPILOT-SETUP-STATE-RUNBOOK.md}"
MATRIX_FILE="${MATRIX_FILE:-docs/ops/AUTOPILOT-SETUP-STATE-REGRESSION-MATRIX.md}"
RECONCILER_FILE="${RECONCILER_FILE:-scripts/ops/reconcile-setup-state.sh}"
DRIFT_GUARD_FILE="${DRIFT_GUARD_FILE:-scripts/ci/check-autopilot-setup-drift.sh}"

require_literal() {
  local file_path="$1"
  local pattern="$2"
  local description="$3"

  if grep -qF -- "$pattern" "$file_path"; then
    log_info "Verified: $description"
  else
    log_fatal "Missing required contract text: $description ($pattern) in $file_path"
  fi
}

require_file "$RCA_FILE"
require_file "$RUNBOOK_FILE"
require_file "$MATRIX_FILE"
require_file "$RECONCILER_FILE"
require_file "$DRIFT_GUARD_FILE"

require_literal "$RCA_FILE" 'reason codes' 'RCA reason-code evidence'
require_literal "$RCA_FILE" 'started_at' 'RCA timing telemetry'
require_literal "$RCA_FILE" 'finished_at' 'RCA timing telemetry end'
require_literal "$RCA_FILE" 'elapsed_seconds' 'RCA elapsed telemetry'
require_literal "$RUNBOOK_FILE" 'reason-codes' 'runbook reason-code guidance'
require_literal "$MATRIX_FILE" 'STATE_CACHE_STALE' 'stale cache reason code'
require_literal "$MATRIX_FILE" 'AUTH_ENV_DRIFT' 'auth env drift reason code'
require_literal "$MATRIX_FILE" 'AUTH_SCOPE_MISSING' 'missing auth scope reason code'
require_literal "$MATRIX_FILE" 'PORTAL_UNREACHABLE' 'portal unreachable reason code'
require_literal "$MATRIX_FILE" 'AUTH_KEEPALIVE_STOPPED' 'keepalive stopped reason code'
require_literal "$MATRIX_FILE" 'HEALTHY' 'healthy baseline reason code'

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPORT_FILE="$TMP_DIR/setup-reconcile-report.json"

log_info "Running reconciler dry-run for report contract validation"
SETUP_RECONCILE_REPORT="$REPORT_FILE" bash "$RECONCILER_FILE" --dry-run >/dev/null

python3 - "$REPORT_FILE" <<'PY'
import json
import sys

report_path = sys.argv[1]
with open(report_path, encoding='utf-8') as handle:
    report = json.load(handle)

required_keys = {'timestamp', 'started_at', 'finished_at', 'elapsed_seconds', 'pass', 'fail', 'fixed', 'probes'}
missing = sorted(required_keys - set(report))
if missing:
    print('Missing report keys: ' + ', '.join(missing), file=sys.stderr)
    sys.exit(1)

if not isinstance(report['probes'], list) or not report['probes']:
    print('Report probes missing or empty', file=sys.stderr)
    sys.exit(1)

for probe in report['probes']:
    for key in ('probe', 'status', 'reason_code', 'detail'):
        if key not in probe:
            print(f'Missing probe key: {key}', file=sys.stderr)
            sys.exit(1)

print('Report schema ok')
PY

log_info "Running drift guard regression check"
bash "$DRIFT_GUARD_FILE"

log_info "Autopilot setup-state reconciler validation passed"