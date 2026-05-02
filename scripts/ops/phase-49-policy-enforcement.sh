#!/bin/bash
# @file phase-49-policy-enforcement.sh
# @description Phase 49 — Automated Policy Enforcement & Governance Engine ops script
# @since 2026-05-01

set -euo pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p49*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

MODE="${1:-demo}"

run_python() {
    "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.policy_enforcement_engine import (
    PolicyEnforcementEngine, PolicySeverity, GovernanceTier
)

engine = PolicyEnforcementEngine()

# Simulate realistic phase scores for all phases 30-48
scores = {
    'phase30': 22.0, 'phase31': 18.5, 'phase32': 20.0, 'phase33': 17.0,
    'phase34': 19.0, 'phase35': 21.0, 'phase36': 20.5, 'phase37': 18.0,
    'phase38': 19.5, 'phase39': 17.5, 'phase40': 16.0, 'phase41': 22.5,
    'phase42': 23.0, 'phase43': 21.0, 'phase44': 19.0, 'phase45': 18.5,
    'phase46': 22.0, 'phase47': 20.5, 'phase48': 19.0,
}
engine.ingest_phase_scores(scores)
report = engine.enforce()
$1
PYEOF
}

case "$MODE" in
    demo)
        echo "============================================================"
        echo "PHASE 49: AUTOMATED POLICY ENFORCEMENT & GOVERNANCE ENGINE"
        echo "============================================================"
        echo ""
        run_python '
import json
s = engine.summary()
rules   = s.get("rules_registered", 0)
enf     = s.get("enforced", 0)
vio     = s.get("violated", 0)
exm     = s.get("exempted", 0)
rate    = s.get("compliance_rate_pct", 0)
remeds  = s.get("open_remediations", 0)
score   = s.get("governance_score", 0)
print("Rules registered :", rules)
print("Enforced         :", enf)
print("Violated         :", vio)
print("Exempted         :", exm)
print("Compliance rate  :", str(rate) + "%")
print("Open remediations:", remeds)
print("Governance score :", str(score) + "/25")
print("")
print("Violations by severity:")
for sev, cnt in s.get("violations_by_severity", {}).items():
    if cnt:
        print("  " + sev + ":", cnt)
print("")
print("Phase 49 gate contribution:", score, "/ 25")
'
        ;;
    summary)
        run_python 'import json; print(json.dumps(engine.summary(), indent=2))'
        ;;
    report)
        TIER="${2:-}"
        run_python "
import json
tier = None
if '$TIER' == 'regulatory': tier = GovernanceTier.REGULATORY
elif '$TIER' == 'operational': tier = GovernanceTier.OPERATIONAL
elif '$TIER' == 'engineering': tier = GovernanceTier.ENGINEERING
print(json.dumps(engine.generate_report(tier=tier), indent=2))
"
        ;;
    persist)
        run_python "path = engine.persist_state(); print('State persisted to:', path)"
        ;;
    *)
        echo "Usage: $0 [demo|summary|report [regulatory|operational|engineering]|persist]"
        exit 1
        ;;
esac
