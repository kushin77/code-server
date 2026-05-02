#!/bin/bash
# @file phase-47-risk-quantification.sh
# @description Phase 47 — Risk Quantification & Threat Scoring
# @since 2026-05-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'rm -f /tmp/p47*.tmp 2>/dev/null || true' EXIT
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR

MODE="${1:-demo}"

cmd_demo() {
    log_info "PHASE 47: Risk Quantification & Threat Scoring Engine"
    echo ""
    "$PYTHON_CMD" <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.risk_quantification_engine import (
    RiskQuantificationEngine, ImpactCategory, RiskLevel, quantify_risk
)

engine = RiskQuantificationEngine()

targets = [
    ("api-gateway",   {"phase30_score": 91.0, "phase36_score": 88.0, "phase45_score": 93.0}),
    ("auth-service",  {"phase31_score": 94.0, "phase40_score": 87.0, "phase46_score": 92.0}),
    ("data-pipeline", {"phase34_score": 72.0, "phase38_score": 70.0}),
]

print("=== PHASE 47: Risk Quantification Dashboard ===")
print()
for target, signals in targets:
    rec = engine.create_assessment(target, signals)
    engine.set_business_impact(rec,
        financial_loss_usd=50000,
        downtime_hours=2.0,
        data_records_at_risk=10000,
    )
    engine.compute_trend(rec)
    lvl   = rec.overall_risk_level().value.upper()
    score = rec.composite_score()
    p47   = rec.phase47_score()
    top   = rec.top_factors(1)[0]
    print(f"  Target: {target}")
    print(f"    Composite Risk Score: {score:.2f}/100 [{lvl}]")
    print(f"    Phase 47 Posture:     {p47:.2f}/25")
    print(f"    Top Factor:           {top.name} ({top.risk_score():.1f})")
    if rec.impact:
        print(f"    Exposure (USD):       \${rec.impact.total_exposure_usd():,.0f}")
    engine.finalize(rec)
    print()

s = engine.summary()
print(f"  Platform Risk Score:  {s['avg_composite_score']:.2f}/100")
print(f"  Phase 47 Score:       {s['phase47_risk_score']:.2f}/25")
print(f"  Critical Targets:     {s['critical_targets']}")
PYEOF
}

cmd_summary() {
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.risk_quantification_engine import RiskQuantificationEngine, quantify_risk

engine = RiskQuantificationEngine()
rec = engine.create_assessment("platform", {})
engine.finalize(rec)
s = engine.summary()
print(json.dumps(s, indent=2))
PYEOF
}

cmd_assess() {
    local target="${2:-platform}"
    log_info "PHASE 47: Risk assessment for target: ${target}"
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.risk_quantification_engine import RiskQuantificationEngine

engine = RiskQuantificationEngine()
rec = engine.create_assessment("${target}", {})
report = engine.generate_report(rec)
print(json.dumps(report, indent=2))
print(f"Composite Risk: {rec.composite_score():.2f}/100")
print(f"Phase 47 Score: {rec.phase47_score():.2f}/25")
PYEOF
}

case "$MODE" in
    demo)    cmd_demo ;;
    summary) cmd_summary ;;
    assess)  cmd_assess "$@" ;;
    *)
        echo "Usage: $0 [demo|summary|assess [target]]"
        exit 1
        ;;
esac
