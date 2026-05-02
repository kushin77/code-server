#!/bin/bash
# @file phase-53-behavioral-anomaly-detection.sh
# @description Phase 53 — Behavioral Anomaly Detection Engine
# @since 2026-05-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'rm -f /tmp/p53*.tmp 2>/dev/null || true' EXIT
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR

MODE="${1:-demo}"

cmd_demo() {
    log_info "PHASE 53: Behavioral Anomaly Detection Engine"
    echo ""
    "$PYTHON_CMD" <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector

det = BehavioralAnomalyDetector()

print("=== PHASE 53: Behavioral Anomaly Detection Dashboard ===")
print()

# Simulate stable baseline for two phases, then inject anomalies
phases = {
    "phase_47": [18.0, 19.0, 17.5, 18.5, 18.0, 19.0, 17.0, 18.0, 19.5, 17.5],
    "phase_48": [20.0, 21.0, 19.5, 20.5, 20.0, 21.0, 19.0, 20.0, 21.5, 19.5],
}
for phase, scores in phases.items():
    for s in scores:
        det.observe(phase, s)

# Inject anomalies
anomalies = []
for phase, score in [("phase_47", 9.0), ("phase_48", 4.0), ("phase_47", 22.0)]:
    evt = det.observe(phase, score)
    if evt:
        anomalies.append(evt)

print(f"  Observations fed:   {det.observation_count}")
print(f"  Anomalies detected: {len(det.anomaly_log)}")
print()
for evt in det.anomaly_log:
    print(f"  [{evt.severity.value.upper():8s}] {evt.phase_source:12s} "
          f"score={evt.score:.1f}  z={evt.z_score:+.2f}  ({evt.mode.value})")
print()
s = det.summary()
print(f"  Phase 53 Score:     {s['phase53_score']:.2f}/25")
print(f"  Severity:           {s['severity_breakdown']}")
PYEOF
}

cmd_summary() {
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector

det = BehavioralAnomalyDetector()
import random; random.seed(42)
for _ in range(15):
    det.observe("phase_47", random.uniform(17.0, 20.0))
det.observe("phase_47", 8.0)
print(json.dumps(det.summary(), indent=2))
PYEOF
}

cmd_scan() {
    local phase_source="${2:-phase_51}"
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector

det = BehavioralAnomalyDetector()
# Seed baseline
for s in [18.0, 19.0, 17.5, 18.5, 18.0, 19.0, 17.0, 18.0, 19.5]:
    det.observe("${phase_source}", s)
# Inject low score
det.observe("${phase_source}", 6.0)
print(json.dumps(det.generate_report("${phase_source}"), indent=2))
PYEOF
}

case "$MODE" in
    demo)    cmd_demo ;;
    summary) cmd_summary ;;
    scan)    cmd_scan "$@" ;;
    *)
        echo "Usage: $0 [demo|summary|scan [phase_source]]"
        exit 1
        ;;
esac
