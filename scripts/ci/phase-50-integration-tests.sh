#!/bin/bash
# @file phase-50-integration-tests.sh
# @description Integration tests for Phase 50 — Automated Remediation & Self-Healing
# @since 2026-05-01

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p50*.* /tmp/p50_reg49.log 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

PASS=0; FAIL=0; TOTAL=0

run_test() {
    local name="$1" cmd="$2"
    ((TOTAL++)) || true
    if eval "$cmd" > /tmp/p50_last.out 2>&1; then
        echo "  ✓ $name"; ((PASS++)) || true
    else
        echo "  ✗ $name"; ((FAIL++)) || true
        [[ -s /tmp/p50_last.out ]] && head -5 /tmp/p50_last.out | sed 's/^/    /'
    fi
}

py() {
    "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
$1
PYEOF
}

echo ""
echo "============================================================"
echo "  PHASE 50 — AUTOMATED REMEDIATION & SELF-HEALING ENGINE"
echo "============================================================"
echo ""

# -----------------------------------------------------------------------
# GROUP 1: Module imports
# -----------------------------------------------------------------------
echo "GROUP 1: Module imports"

run_test "AutomatedRemediationEngine importable" \
    "py 'from security_ai.automated_remediation_engine import AutomatedRemediationEngine; print(\"ok\")' | grep -q ok"

run_test "HealingPlan importable" \
    "py 'from security_ai.automated_remediation_engine import HealingPlan; print(\"ok\")' | grep -q ok"

run_test "RemediationAction importable" \
    "py 'from security_ai.automated_remediation_engine import RemediationAction; print(\"ok\")' | grep -q ok"

run_test "RemediationStatus has 6 values" \
    "py '
from security_ai.automated_remediation_engine import RemediationStatus
vals = [s.value for s in RemediationStatus]
assert set(vals) == {\"pending\",\"in_progress\",\"succeeded\",\"failed\",\"skipped\",\"rolled_back\"}, vals
print(\"ok\")
' | grep -q ok"

run_test "RemediationMode has 3 values" \
    "py '
from security_ai.automated_remediation_engine import RemediationMode
assert len(list(RemediationMode)) == 3
print(\"ok\")
' | grep -q ok"

run_test "HealingTrigger has 6 values" \
    "py '
from security_ai.automated_remediation_engine import HealingTrigger
assert len(list(HealingTrigger)) == 6
print(\"ok\")
' | grep -q ok"

run_test "healing_score importable" \
    "py 'from security_ai.automated_remediation_engine import healing_score; print(\"ok\")' | grep -q ok"

run_test "POLICY_VIOLATION trigger exists" \
    "py '
from security_ai.automated_remediation_engine import HealingTrigger
assert HealingTrigger.POLICY_VIOLATION.value == \"policy_violation\"
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 2: RemediationAction behaviour
# -----------------------------------------------------------------------
echo ""
echo "GROUP 2: RemediationAction behaviour"

run_test "Action starts PENDING" \
    "py '
from security_ai.automated_remediation_engine import RemediationAction, RemediationStatus, HealingTrigger
a = RemediationAction(action_id=\"a1\",name=\"t\",phase_source=\"p49\",trigger=HealingTrigger.MANUAL,target=\"svc\")
assert a.status == RemediationStatus.PENDING
print(\"ok\")
' | grep -q ok"

run_test "No-op handler returns True and SUCCEEDED" \
    "py '
from security_ai.automated_remediation_engine import RemediationAction, RemediationStatus, HealingTrigger
a = RemediationAction(action_id=\"a2\",name=\"t\",phase_source=\"p49\",trigger=HealingTrigger.MANUAL,target=\"svc\")
assert a.execute() is True
assert a.status == RemediationStatus.SUCCEEDED
print(\"ok\")
' | grep -q ok"

run_test "DRY_RUN mode simulates success" \
    "py '
from security_ai.automated_remediation_engine import RemediationAction, RemediationStatus, HealingTrigger, RemediationMode
a = RemediationAction(action_id=\"a3\",name=\"t\",phase_source=\"p48\",trigger=HealingTrigger.DASHBOARD_ALERT,
                      target=\"platform\",mode=RemediationMode.DRY_RUN)
assert a.execute() is True
assert a.status == RemediationStatus.SUCCEEDED
assert \"DRY-RUN\" in a.result_detail
print(\"ok\")
' | grep -q ok"

run_test "False handler → FAILED status" \
    "py '
from security_ai.automated_remediation_engine import RemediationAction, RemediationStatus, HealingTrigger
a = RemediationAction(action_id=\"a4\",name=\"t\",phase_source=\"p47\",trigger=HealingTrigger.RISK_THRESHOLD,
                      target=\"rf-1\",handler=lambda ctx: False)
assert a.execute() is False
assert a.status == RemediationStatus.FAILED
print(\"ok\")
' | grep -q ok"

run_test "Exception in handler → FAILED + detail" \
    "py '
from security_ai.automated_remediation_engine import RemediationAction, RemediationStatus, HealingTrigger
def bad(ctx): raise RuntimeError(\"boom\")
a = RemediationAction(action_id=\"a5\",name=\"t\",phase_source=\"p49\",trigger=HealingTrigger.MANUAL,
                      target=\"svc\",handler=bad)
assert a.execute() is False
assert \"exception\" in a.result_detail
print(\"ok\")
' | grep -q ok"

run_test "duration_seconds set after execute" \
    "py '
from security_ai.automated_remediation_engine import RemediationAction, HealingTrigger
a = RemediationAction(action_id=\"a6\",name=\"t\",phase_source=\"p49\",trigger=HealingTrigger.MANUAL,target=\"svc\")
a.execute()
d = a.duration_seconds()
assert d is not None and d >= 0.0
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 3: HealingPlan metrics
# -----------------------------------------------------------------------
echo ""
echo "GROUP 3: HealingPlan metrics"

run_test "Empty plan: success_rate=0, not complete" \
    "py '
from security_ai.automated_remediation_engine import HealingPlan, HealingTrigger
p = HealingPlan(plan_id=\"p1\",name=\"t\",target=\"svc\",trigger=HealingTrigger.MANUAL)
assert p.success_rate() == 0.0 and not p.is_complete()
print(\"ok\")
' | grep -q ok"

run_test "All SUCCEEDED → rate=1.0, complete=True" \
    "py '
from security_ai.automated_remediation_engine import HealingPlan, HealingTrigger, RemediationAction, RemediationStatus
p = HealingPlan(plan_id=\"p2\",name=\"t\",target=\"svc\",trigger=HealingTrigger.MANUAL)
for i in range(2):
    a = RemediationAction(action_id=f\"a{i}\",name=\"t\",phase_source=\"p49\",trigger=HealingTrigger.MANUAL,target=\"svc\")
    a.status = RemediationStatus.SUCCEEDED
    p.actions.append(a)
assert p.success_rate() == 1.0 and p.is_complete()
print(\"ok\")
' | grep -q ok"

run_test "1 success 1 fail → rate=0.5" \
    "py '
from security_ai.automated_remediation_engine import HealingPlan, HealingTrigger, RemediationAction, RemediationStatus
p = HealingPlan(plan_id=\"p3\",name=\"t\",target=\"svc\",trigger=HealingTrigger.MANUAL)
a1 = RemediationAction(action_id=\"a1\",name=\"t\",phase_source=\"p49\",trigger=HealingTrigger.MANUAL,target=\"svc\")
a2 = RemediationAction(action_id=\"a2\",name=\"t\",phase_source=\"p49\",trigger=HealingTrigger.MANUAL,target=\"svc\")
a1.status = RemediationStatus.SUCCEEDED
a2.status = RemediationStatus.FAILED
p.actions = [a1, a2]
assert p.success_rate() == 0.5
print(\"ok\")
' | grep -q ok"

run_test "100% success → phase50_score=25.0" \
    "py '
from security_ai.automated_remediation_engine import HealingPlan, HealingTrigger, RemediationAction, RemediationStatus
p = HealingPlan(plan_id=\"p4\",name=\"t\",target=\"svc\",trigger=HealingTrigger.MANUAL)
a = RemediationAction(action_id=\"a1\",name=\"t\",phase_source=\"p49\",trigger=HealingTrigger.MANUAL,target=\"svc\")
a.status = RemediationStatus.SUCCEEDED
p.actions = [a]
assert p.phase50_score() == 25.0, p.phase50_score()
print(\"ok\")
' | grep -q ok"

run_test "action_summary counts correctly" \
    "py '
from security_ai.automated_remediation_engine import HealingPlan, HealingTrigger, RemediationAction, RemediationStatus
p = HealingPlan(plan_id=\"p5\",name=\"t\",target=\"svc\",trigger=HealingTrigger.MANUAL)
a = RemediationAction(action_id=\"a1\",name=\"t\",phase_source=\"p49\",trigger=HealingTrigger.MANUAL,target=\"svc\")
a.status = RemediationStatus.SUCCEEDED
p.actions = [a]
s = p.action_summary()
assert s[\"succeeded\"] == 1 and s[\"pending\"] == 0
print(\"ok\")
' | grep -q ok"

run_test "PENDING actions → is_complete=False" \
    "py '
from security_ai.automated_remediation_engine import HealingPlan, HealingTrigger, RemediationAction
p = HealingPlan(plan_id=\"p6\",name=\"t\",target=\"svc\",trigger=HealingTrigger.MANUAL)
a = RemediationAction(action_id=\"a1\",name=\"t\",phase_source=\"p49\",trigger=HealingTrigger.MANUAL,target=\"svc\")
p.actions = [a]
assert not p.is_complete()
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 4: Engine plan lifecycle
# -----------------------------------------------------------------------
echo ""
echo "GROUP 4: Engine plan lifecycle"

run_test "create_plan registers in engine.plans" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine, HealingTrigger
e = AutomatedRemediationEngine()
p = e.create_plan(\"t\",\"svc\",HealingTrigger.MANUAL)
assert p.plan_id in e.plans
print(\"ok\")
' | grep -q ok"

run_test "add_action appends to plan" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine, HealingTrigger
e = AutomatedRemediationEngine()
p = e.create_plan(\"t\",\"svc\",HealingTrigger.MANUAL)
a = e.add_action(p, \"step1\", \"p49\", handler_key=\"rotate_cert\")
assert len(p.actions) == 1 and a.name == \"step1\"
print(\"ok\")
' | grep -q ok"

run_test "execute_plan runs actions to SUCCEEDED" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine, HealingTrigger, RemediationStatus
e = AutomatedRemediationEngine()
p = e.create_plan(\"t\",\"svc\",HealingTrigger.MANUAL)
e.add_action(p, \"step1\", \"p49\", handler_key=\"rotate_cert\")
ok = e.execute_plan(p)
assert ok is True and p.actions[0].status == RemediationStatus.SUCCEEDED
print(\"ok\")
' | grep -q ok"

run_test "stop_on_failure skips remaining" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine, HealingTrigger, RemediationStatus
e = AutomatedRemediationEngine()
p = e.create_plan(\"t\",\"svc\",HealingTrigger.MANUAL)
e.add_action(p, \"fail\", \"p49\", handler=lambda ctx: False)
e.add_action(p, \"skip\", \"p49\", handler_key=\"flush_cache\")
e.execute_plan(p, stop_on_failure=True)
assert p.actions[0].status == RemediationStatus.FAILED
assert p.actions[1].status == RemediationStatus.SKIPPED
print(\"ok\")
' | grep -q ok"

run_test "rollback_plan sets ROLLED_BACK" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine, HealingTrigger, RemediationStatus
e = AutomatedRemediationEngine()
p = e.create_plan(\"t\",\"svc\",HealingTrigger.MANUAL)
e.add_action(p, \"step1\", \"p49\", handler_key=\"rotate_cert\")
e.execute_plan(p)
e.rollback_plan(p)
assert p.actions[0].status == RemediationStatus.ROLLED_BACK
print(\"ok\")
' | grep -q ok"

run_test "finalize_plan moves to history" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine, HealingTrigger
e = AutomatedRemediationEngine()
p = e.create_plan(\"t\",\"svc\",HealingTrigger.MANUAL)
e.add_action(p, \"step1\", \"p49\", handler_key=\"rotate_cert\")
e.execute_plan(p)
e.finalize_plan(p)
assert p.plan_id not in e.plans and p in e.history
print(\"ok\")
' | grep -q ok"

run_test "generate_report contains all required keys" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine, HealingTrigger
e = AutomatedRemediationEngine()
p = e.create_plan(\"t\",\"svc\",HealingTrigger.MANUAL)
e.add_action(p, \"step1\", \"p49\", handler_key=\"rotate_cert\")
e.execute_plan(p)
r = e.generate_report(p)
for k in [\"plan_id\",\"success_rate\",\"phase50_score\",\"is_complete\",\"action_summary\",\"total_actions\"]:
    assert k in r, f\"missing {k}\"
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 5: Auto-triage — compliance findings
# -----------------------------------------------------------------------
echo ""
echo "GROUP 5: Auto-triage from compliance findings"

run_test "Critical finding → 2-action plan" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine, HealingTrigger
e = AutomatedRemediationEngine()
plans = e.triage_compliance_findings([
    {\"title\":\"Cert Expired\",\"control_id\":\"ctrl-31\",\"severity\":\"critical\",\"phase_source\":\"phase_49\"}
])
assert len(plans) == 1 and plans[0].trigger == HealingTrigger.COMPLIANCE_FINDING
assert len(plans[0].actions) == 2
print(\"ok\")
' | grep -q ok"

run_test "Low-severity finding → 1-action plan" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine
e = AutomatedRemediationEngine()
plans = e.triage_compliance_findings([
    {\"title\":\"Minor Gap\",\"control_id\":\"ctrl-30\",\"severity\":\"low\",\"phase_source\":\"phase_46\"}
])
assert len(plans[0].actions) == 1
print(\"ok\")
' | grep -q ok"

run_test "Multiple findings → multiple plans" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine
e = AutomatedRemediationEngine()
findings = [
    {\"title\":\"F1\",\"control_id\":\"c1\",\"severity\":\"high\",\"phase_source\":\"phase_49\"},
    {\"title\":\"F2\",\"control_id\":\"c2\",\"severity\":\"medium\",\"phase_source\":\"phase_46\"},
]
plans = e.triage_compliance_findings(findings)
assert len(plans) == 2
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 6: Auto-triage — risk factors
# -----------------------------------------------------------------------
echo ""
echo "GROUP 6: Auto-triage from risk factors"

run_test "Risk triage filters below threshold" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine, HealingTrigger
e = AutomatedRemediationEngine()
risk_factors = [
    {\"name\":\"high-risk\",\"risk_score\":75.0,\"phase_source\":\"phase_47\"},
    {\"name\":\"low-risk\", \"risk_score\":20.0,\"phase_source\":\"phase_47\"},
]
plans = e.triage_risk_factors(risk_factors, risk_threshold=50.0)
assert len(plans) == 1 and plans[0].trigger == HealingTrigger.RISK_THRESHOLD
print(\"ok\")
' | grep -q ok"

run_test "Risk plan has 2 actions (scale + flush)" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine
e = AutomatedRemediationEngine()
plans = e.triage_risk_factors([{\"name\":\"rf-high\",\"risk_score\":80.0,\"phase_source\":\"phase_47\"}])
assert len(plans[0].actions) == 2
print(\"ok\")
' | grep -q ok"

run_test "Zero plans when all below threshold" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine
e = AutomatedRemediationEngine()
plans = e.triage_risk_factors([{\"name\":\"rf-low\",\"risk_score\":10.0,\"phase_source\":\"phase_47\"}], risk_threshold=50.0)
assert len(plans) == 0
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 7: Auto-triage — dashboard alerts & policy violations
# -----------------------------------------------------------------------
echo ""
echo "GROUP 7: Auto-triage from dashboard alerts and policy violations"

run_test "Critical alert → 2-action plan" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine, HealingTrigger
e = AutomatedRemediationEngine()
plans = e.triage_dashboard_alerts([{\"title\":\"Crit\",\"severity\":\"critical\",\"phase_source\":\"phase_48\"}])
assert len(plans) == 1 and plans[0].trigger == HealingTrigger.DASHBOARD_ALERT
assert len(plans[0].actions) == 2
print(\"ok\")
' | grep -q ok"

run_test "Warning alert → 1-action plan" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine
e = AutomatedRemediationEngine()
plans = e.triage_dashboard_alerts([{\"title\":\"Warn\",\"severity\":\"warning\",\"phase_source\":\"phase_48\"}])
assert len(plans[0].actions) == 1
print(\"ok\")
' | grep -q ok"

run_test "Policy violation triage → POLICY_VIOLATION trigger" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine, HealingTrigger
e = AutomatedRemediationEngine()
plans = e.triage_policy_violations([{\"rule_id\":\"rule-mfa\",\"severity\":\"critical\",\"phase_source\":\"phase_49\"}])
assert len(plans) == 1 and plans[0].trigger == HealingTrigger.POLICY_VIOLATION
print(\"ok\")
' | grep -q ok"

run_test "Critical policy violation → 2 actions" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine
e = AutomatedRemediationEngine()
plans = e.triage_policy_violations([{\"rule_id\":\"rule-mfa\",\"severity\":\"critical\",\"phase_source\":\"phase_49\"}])
assert len(plans[0].actions) == 2
print(\"ok\")
' | grep -q ok"

run_test "Medium policy violation → 1 action" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine
e = AutomatedRemediationEngine()
plans = e.triage_policy_violations([{\"rule_id\":\"rule-log\",\"severity\":\"medium\",\"phase_source\":\"phase_49\"}])
assert len(plans[0].actions) == 1
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 8: healing_score() and summary()
# -----------------------------------------------------------------------
echo ""
echo "GROUP 8: healing_score() and summary()"

run_test "Empty engine → score=0.0" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine, healing_score
e = AutomatedRemediationEngine()
assert healing_score(e) == 0.0
print(\"ok\")
' | grep -q ok"

run_test "Full success → healing_score=25.0" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine, HealingTrigger, healing_score
e = AutomatedRemediationEngine()
p = e.create_plan(\"t\",\"svc\",HealingTrigger.MANUAL)
e.add_action(p, \"s1\", \"p49\", handler_key=\"rotate_cert\")
e.execute_plan(p)
e.finalize_plan(p)
assert healing_score(e) == 25.0, healing_score(e)
print(\"ok\")
' | grep -q ok"

run_test "summary() with no plans is safe" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine
e = AutomatedRemediationEngine()
s = e.summary()
assert s[\"total_plans\"] == 0 and s[\"avg_success_rate\"] == 0.0
print(\"ok\")
' | grep -q ok"

run_test "Two complete plans → avg_rate=1.0 score=25.0" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine, HealingTrigger
e = AutomatedRemediationEngine()
for i in range(2):
    p = e.create_plan(f\"p{i}\",\"svc\",HealingTrigger.SCHEDULED)
    e.add_action(p, f\"s{i}\", \"p49\", handler_key=\"flush_cache\")
    e.execute_plan(p)
    e.finalize_plan(p)
s = e.summary()
assert s[\"total_plans\"] == 2
assert s[\"avg_success_rate\"] == 1.0
assert s[\"phase50_healing_score\"] == 25.0
print(\"ok\")
' | grep -q ok"

run_test "In-flight plans counted in summary" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine, HealingTrigger
e = AutomatedRemediationEngine()
p = e.create_plan(\"active\",\"svc\",HealingTrigger.MANUAL)
s = e.summary()
assert s[\"total_plans\"] == 1
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 9: DRY_RUN mode end-to-end
# -----------------------------------------------------------------------
echo ""
echo "GROUP 9: DRY_RUN mode end-to-end"

run_test "DRY_RUN engine: all plans succeed" \
    "py '
from security_ai.automated_remediation_engine import (
    AutomatedRemediationEngine, HealingTrigger, RemediationMode, healing_score
)
e = AutomatedRemediationEngine(default_mode=RemediationMode.DRY_RUN)
alerts = [{\"title\":\"Crit\",\"severity\":\"critical\",\"phase_source\":\"phase_48\"}]
plans = e.triage_dashboard_alerts(alerts)
for p in plans:
    e.execute_plan(p)
    e.finalize_plan(p)
assert healing_score(e) == 25.0
print(\"ok\")
' | grep -q ok"

run_test "DRY_RUN actions have DRY-RUN in result_detail" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine, HealingTrigger, RemediationMode
e = AutomatedRemediationEngine(default_mode=RemediationMode.DRY_RUN)
p = e.create_plan(\"t\",\"svc\",HealingTrigger.MANUAL)
a = e.add_action(p, \"step1\", \"p49\", handler_key=\"apply_policy\")
e.execute_plan(p)
assert \"DRY-RUN\" in a.result_detail
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 10: Full triage → execute → finalize cycle
# -----------------------------------------------------------------------
echo ""
echo "GROUP 10: Full triage-execute-report cycle"

run_test "Compliance + risk + policy triage all succeed" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine
e = AutomatedRemediationEngine()
c = e.triage_compliance_findings([
    {\"title\":\"SOC2\",\"control_id\":\"ctrl-30\",\"severity\":\"high\",\"phase_source\":\"phase_49\"}
])
r = e.triage_risk_factors([
    {\"name\":\"rf-threat\",\"risk_score\":80.0,\"phase_source\":\"phase_47\"}
])
v = e.triage_policy_violations([
    {\"rule_id\":\"rule-mfa\",\"severity\":\"medium\",\"phase_source\":\"phase_49\"}
])
for p in c + r + v:
    ok = e.execute_plan(p)
    assert ok is True, f\"{p.name} failed\"
    e.finalize_plan(p)
s = e.summary()
assert s[\"completed_plans\"] == 3 and s[\"avg_success_rate\"] == 1.0
print(\"ok\")
' | grep -q ok"

run_test "Mixed severity compliance triage scales correctly" \
    "py '
from security_ai.automated_remediation_engine import AutomatedRemediationEngine
e = AutomatedRemediationEngine()
findings = [
    {\"title\":\"F-crit\",\"control_id\":\"c1\",\"severity\":\"critical\",\"phase_source\":\"phase_49\"},
    {\"title\":\"F-high\",\"control_id\":\"c2\",\"severity\":\"high\",   \"phase_source\":\"phase_49\"},
    {\"title\":\"F-med\", \"control_id\":\"c3\",\"severity\":\"medium\",  \"phase_source\":\"phase_46\"},
]
plans = e.triage_compliance_findings(findings)
assert len(plans) == 3
# critical and high both get 2 actions; medium gets 1
assert len(plans[0].actions) == 2
assert len(plans[1].actions) == 2
assert len(plans[2].actions) == 1
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 11: Ops script
# -----------------------------------------------------------------------
echo ""
echo "GROUP 11: Ops script integration"

OPS_SCRIPT="${PROJECT_ROOT}/scripts/ops/phase-50-automated-remediation.sh"

run_test "Ops script exists" \
    "[[ -f '$OPS_SCRIPT' ]]"

[[ -x "$OPS_SCRIPT" ]] || chmod +x "$OPS_SCRIPT"

run_test "demo mode exits 0" \
    "bash '$OPS_SCRIPT' demo > /tmp/p50demo.out 2>&1"

run_test "demo outputs PHASE 50" \
    "grep -q 'PHASE 50' /tmp/p50demo.out"

run_test "demo shows Healing Score" \
    "grep -q 'Healing Score' /tmp/p50demo.out"

run_test "summary mode outputs phase50_healing_score" \
    "bash '$OPS_SCRIPT' summary > /tmp/p50sum.out 2>&1 && grep -q 'phase50_healing_score' /tmp/p50sum.out"

run_test "heal mode exits 0 and shows Phase 50 Score" \
    "bash '$OPS_SCRIPT' heal platform > /tmp/p50heal.out 2>&1 && grep -q 'Phase 50 Score' /tmp/p50heal.out"

# -----------------------------------------------------------------------
# GROUP 12: Phase 49 regression guard
# -----------------------------------------------------------------------
echo ""
echo "GROUP 12: Phase 49 regression guard"

run_test "Phase 49 integration suite still passes" \
    "timeout 150 bash '${PROJECT_ROOT}/scripts/ci/phase-49-integration-tests.sh' > /tmp/p50_reg49.log 2>&1"

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "============================================================"
echo "PHASE 50 TEST RESULTS"
echo "============================================================"
echo "PASS:  $PASS"
echo "FAIL:  $FAIL"
echo "TOTAL: $TOTAL"
echo "============================================================"

if [[ $FAIL -eq 0 ]]; then
    echo ""
    echo "✅  ALL TESTS PASSED — Phase 50 Automated Remediation verified"
    exit 0
else
    echo ""
    echo "❌  SOME TESTS FAILED"
    exit 1
fi
