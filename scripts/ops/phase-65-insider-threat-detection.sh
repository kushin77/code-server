#!/bin/bash
# @file phase-65-insider-threat-detection.sh
# @description Phase 65 — Insider Threat Detection & Behavior Risk

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..." >&2; rm -f /tmp/p65*.tmp 2>/dev/null || true' EXIT

MODE="${1:-demo}"

cmd_demo() {
  log_info "Running Phase 65 Insider Threat Detection demo"
  "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.insider_threat_detection_engine import (
    InsiderThreatDetectionEngine,
    EventType,
    make_baseline,
    make_event,
)

eng = InsiderThreatDetectionEngine()
eng.set_baseline(make_baseline('alice', expected_regions=['us-east-1'], allowed_resources=['repo-A', 'db-read'], max_daily_exports_gb=1.0, max_privilege_changes_per_day=1))

eng.ingest_event(make_event('alice', EventType.LOGIN, metadata={'region': 'us-east-1'}))
eng.ingest_event(make_event('alice', EventType.DATA_EXPORT, resource='repo-A', metadata={'export_gb': 4.2, 'region': 'us-east-1'}))
eng.ingest_event(make_event('alice', EventType.PRIVILEGE_CHANGE, resource='db-read'))
eng.ingest_event(make_event('alice', EventType.PRIVILEGE_CHANGE, resource='db-read'))

summary = eng.summary()
print('============================================================')
print('PHASE 65 — INSIDER THREAT DETECTION')
print('============================================================')
print(f"Total events: {summary['total_events']}")
print(f"Total alerts: {summary['total_alerts']}")
print(f"Active alerts: {summary['active_alerts']}")
print(f"Critical alerts: {summary['critical_alerts']}")
print(f"High alerts: {summary['high_alerts']}")
print(f"Phase 65 score: {summary['phase65_score']}/25")
PYEOF
}

cmd_summary() {
  "$PYTHON_CMD" - <<PYEOF
import json
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine

eng = InsiderThreatDetectionEngine()
print(json.dumps(eng.summary(), indent=2))
PYEOF
}

cmd_report() {
  "$PYTHON_CMD" - <<PYEOF
import json
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine

eng = InsiderThreatDetectionEngine()
print(json.dumps(eng.generate_report().to_dict(), indent=2))
PYEOF
}

cmd_persist() {
  "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine

eng = InsiderThreatDetectionEngine()
out = eng.persist_state('${PROJECT_ROOT}/artifacts/phase65/insider-threat-report.json')
print(f"State persisted to: {out}")
PYEOF
}

case "$MODE" in
  demo) cmd_demo ;;
  summary) cmd_summary ;;
  report) cmd_report ;;
  persist) cmd_persist ;;
  *)
    log_error "Unknown mode '$MODE'. Usage: $0 [demo|summary|report|persist]"
    exit 1
    ;;
esac
