#!/bin/bash
# @file phase-51-platform-convergence.sh
# @description Phase 51 — Unified Security Orchestration & Platform Convergence ops script
# @since 2026-05-01

set -euo pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p51*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

MODE="${1:-demo}"

run_python() {
    "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.platform_convergence_engine import PlatformConvergenceEngine

engine = PlatformConvergenceEngine()

# Realistic phase scores for all 20 phases (30-49)
scores = {
    'phase30': 22.0, 'phase31': 19.0, 'phase32': 20.5, 'phase33': 17.5,
    'phase34': 21.0, 'phase35': 22.5, 'phase36': 20.0, 'phase37': 18.5,
    'phase38': 19.5, 'phase39': 18.0, 'phase40': 17.0, 'phase41': 23.0,
    'phase42': 22.0, 'phase43': 21.5, 'phase44': 19.5, 'phase45': 18.5,
    'phase46': 22.0, 'phase47': 21.0, 'phase48': 20.0, 'phase49': 21.5,
}
engine.ingest_phase_scores(scores)
engine.converge()
$1
PYEOF
}

case "$MODE" in
    demo)
        echo "============================================================"
        echo "PHASE 51: UNIFIED SECURITY ORCHESTRATION & PLATFORM"
        echo "          CONVERGENCE ENGINE  (MILESTONE PHASE)"
        echo "============================================================"
        echo ""
        run_python '
import json
s = engine.summary()
ci       = s.get("composite_index", 0)
health   = s.get("overall_health", "unknown")
score    = s.get("phase50_score", 0)
phases   = s.get("phases_ingested", 0)
domains  = s.get("domains_active", 0)
cycles   = s.get("convergence_cycles", 0)
risks    = ", ".join(s.get("top_risks", []))
strong_c = s.get("strong_correlations", 0)
print("Platform Composite Index :", str(ci) + "/100")
print("Overall Health           :", health.upper())
print("Phase 50 Gate Score      :", str(score) + "/25")
print("Phases Ingested          :", phases, "(Phases 30-49)")
print("Domains Active           :", domains)
print("Convergence Cycles       :", cycles)
print("Strong Correlations      :", strong_c)
print("Top Risks                :", risks if risks else "none")
print("")
print("Domain Health Map:")
for dom, h in s.get("domain_health", {}).items():
    print("  " + dom + ": " + h)
print("")
print("Phase 51 gate contribution:", score, "/ 25")
'
        ;;
    summary)
        run_python 'import json; print(json.dumps(engine.summary(), indent=2))'
        ;;
    report)
        VIEW="${2:-full}"
        run_python "import json; print(json.dumps(engine.generate_report(view='${VIEW}'), indent=2))"
        ;;
    persist)
        run_python "path = engine.persist_state(); print('State persisted to:', path)"
        ;;
    *)
        echo "Usage: $0 [demo|summary|report [executive|domain|full]|persist]"
        exit 1
        ;;
esac
