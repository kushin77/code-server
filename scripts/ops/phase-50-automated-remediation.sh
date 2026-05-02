#!/bin/bash
# @file phase-50-automated-remediation.sh
# @description Phase 50 — Automated Remediation & Self-Healing Engine
# @since 2026-05-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'rm -f /tmp/p50*.tmp 2>/dev/null || true' EXIT
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR

MODE="${1:-demo}"

cmd_demo() {
    log_info "PHASE 50: Automated Remediation & Self-Healing Engine"
    echo ""
    "$PYTHON_CMD" <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.automated_remediation_engine import (
    AutomatedRemediationEngine, HealingTrigger, RemediationMode, healing_score
)

engine = AutomatedRemediationEngine(default_mode=RemediationMode.AUTO)

print("=== PHASE 50: Self-Healing Remediation Dashboard ===")
print()

# Triage compliance findings from Phase 46/49
findings = [
    {"title": "Stale TLS Certificate", "control_id": "ctrl-31",
     "severity": "critical", "phase_source": "phase_49"},
    {"title": "Compliance Gap: Threat Detection", "control_id": "ctrl-30",
     "severity": "medium", "phase_source": "phase_46"},
]
c_plans = engine.triage_compliance_findings(findings)
print(f"  Compliance Findings Triaged: {len(c_plans)} plans")
for p in c_plans:
    engine.execute_plan(p)
    print(f"    [{p.target}] {p.name} → success_rate={p.success_rate():.0%} "
          f"score={p.phase50_score():.1f}/25")
    engine.finalize_plan(p)

print()

# Triage risk factors from Phase 47
risk_factors = [
    {"name": "Undetected Threat Exposure", "risk_score": 65.0,
     "phase_source": "phase_47", "category": "operational"},
    {"name": "Low Risk Factor", "risk_score": 30.0,
     "phase_source": "phase_47", "category": "operational"},
]
r_plans = engine.triage_risk_factors(risk_factors, risk_threshold=50.0)
print(f"  Risk Factors Triaged: {len(r_plans)} plans (threshold ≥50)")
for p in r_plans:
    engine.execute_plan(p)
    print(f"    [{p.target}] {p.name} → success_rate={p.success_rate():.0%}")
    engine.finalize_plan(p)

print()

# Triage policy violations from Phase 49
violations = [
    {"rule_id": "rule-mfa-enforce", "severity": "critical", "phase_source": "phase_49"},
    {"rule_id": "rule-log-retention", "severity": "medium",  "phase_source": "phase_49"},
]
v_plans = engine.triage_policy_violations(violations)
print(f"  Policy Violations Triaged: {len(v_plans)} plans")
for p in v_plans:
    engine.execute_plan(p)
    print(f"    [{p.target}] {p.name} → success_rate={p.success_rate():.0%}")
    engine.finalize_plan(p)

print()
s = engine.summary()
print(f"  Total Healing Plans:    {s['total_plans']}")
print(f"  Completed Plans:        {s['completed_plans']}")
print(f"  Avg Success Rate:       {s['avg_success_rate']:.0%}")
print(f"  Phase 50 Healing Score: {s['phase50_healing_score']:.2f}/25")
PYEOF
}

cmd_summary() {
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.automated_remediation_engine import (
    AutomatedRemediationEngine, HealingTrigger, RemediationMode
)
engine = AutomatedRemediationEngine()
plan = engine.create_plan("Platform self-heal", "platform", HealingTrigger.SCHEDULED)
engine.add_action(plan, "Rotate certs",    "phase_49", handler_key="rotate_cert")
engine.add_action(plan, "Restart service", "phase_48", handler_key="restart_service")
engine.add_action(plan, "Enforce policy",  "phase_49", handler_key="enforce_policy")
engine.execute_plan(plan)
engine.finalize_plan(plan)
s = engine.summary()
print(json.dumps(s, indent=2))
PYEOF
}

cmd_heal() {
    local target="${2:-platform}"
    log_info "PHASE 50: Running self-heal for target: ${target}"
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.automated_remediation_engine import (
    AutomatedRemediationEngine, HealingTrigger, RemediationMode
)
engine = AutomatedRemediationEngine()
plan = engine.create_plan("On-demand heal: ${target}", "${target}", HealingTrigger.MANUAL)
engine.add_action(plan, "Rotate certs",   "phase_49", handler_key="rotate_cert")
engine.add_action(plan, "Apply policy",   "phase_49", handler_key="apply_policy")
engine.add_action(plan, "Restart service","phase_48", handler_key="restart_service")
engine.execute_plan(plan)
report = engine.generate_report(plan)
engine.finalize_plan(plan)
print(json.dumps(report, indent=2))
print(f"Phase 50 Score: {report['phase50_score']:.2f}/25")
PYEOF
}

case "$MODE" in
    demo)    cmd_demo ;;
    summary) cmd_summary ;;
    heal)    cmd_heal "$@" ;;
    *)
        echo "Usage: $0 [demo|summary|heal [target]]"
        exit 1
        ;;
esac
