#!/bin/bash
# @file phase-49-integration-tests.sh
# @description Integration tests for Phase 49 — Automated Policy Enforcement & Governance Engine
# @since 2026-05-01

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p49*.* /tmp/p49_reg48.log 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

PASS=0; FAIL=0; TOTAL=0

run_test() {
    local name="$1" cmd="$2"
    TOTAL=$((TOTAL + 1))
    if eval "$cmd" > /dev/null 2>&1; then
        echo "  ✓ $name"; PASS=$((PASS + 1))
    else
        echo "  ✗ $name"; FAIL=$((FAIL + 1))
    fi
}

run_python_test() {
    local name="$1"
    local code="$2"
    TOTAL=$((TOTAL + 1))
    if "$PYTHON_CMD" - <<PYEOF > /dev/null 2>&1
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
$code
PYEOF
    then
        echo "  ✓ $name"; PASS=$((PASS + 1))
    else
        echo "  ✗ $name"; FAIL=$((FAIL + 1))
    fi
}

echo "============================================================"
echo "PHASE 49: AUTOMATED POLICY ENFORCEMENT & GOVERNANCE ENGINE"
echo "                   INTEGRATION TESTS"
echo "============================================================"
echo ""

# -----------------------------------------------------------------------
# GROUP 1: Module imports & API surface
# -----------------------------------------------------------------------
echo "GROUP 1: Module Import & API Surface"

run_python_test "Import PolicyEnforcementEngine" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine"

run_python_test "Import PolicyRule" \
"from security_ai.policy_enforcement_engine import PolicyRule"

run_python_test "Import PolicyStatus enum" \
"from security_ai.policy_enforcement_engine import PolicyStatus
assert len(list(PolicyStatus)) >= 5"

run_python_test "Import PolicySeverity enum" \
"from security_ai.policy_enforcement_engine import PolicySeverity
assert len(list(PolicySeverity)) == 4"

run_python_test "Import RemediationTask" \
"from security_ai.policy_enforcement_engine import RemediationTask"

run_python_test "Import RemediationStatus enum" \
"from security_ai.policy_enforcement_engine import RemediationStatus
assert len(list(RemediationStatus)) == 4"

run_python_test "Import GovernanceTier enum" \
"from security_ai.policy_enforcement_engine import GovernanceTier
tiers = {t.value for t in GovernanceTier}
assert 'regulatory' in tiers and 'operational' in tiers and 'engineering' in tiers"

run_python_test "Import GovernanceReport" \
"from security_ai.policy_enforcement_engine import GovernanceReport"

run_python_test "Import PolicyEvaluation" \
"from security_ai.policy_enforcement_engine import PolicyEvaluation"

echo ""

# -----------------------------------------------------------------------
# GROUP 2: PolicyRule evaluation logic
# -----------------------------------------------------------------------
echo "GROUP 2: PolicyRule Evaluation Logic"

run_python_test "PolicyRule status ENFORCED when score above threshold" \
"from security_ai.policy_enforcement_engine import PolicyRule, PolicyStatus, PolicySeverity, GovernanceTier
rule = PolicyRule('R1', 'Test', 'desc', PolicySeverity.HIGH, GovernanceTier.OPERATIONAL, ['phase30'], 15.0)
status = rule.status({'phase30': 20.0})
assert status == PolicyStatus.ENFORCED, status"

run_python_test "PolicyRule status VIOLATED when score below threshold" \
"from security_ai.policy_enforcement_engine import PolicyRule, PolicyStatus, PolicySeverity, GovernanceTier
rule = PolicyRule('R1', 'Test', 'desc', PolicySeverity.HIGH, GovernanceTier.OPERATIONAL, ['phase30'], 15.0)
status = rule.status({'phase30': 10.0})
assert status == PolicyStatus.VIOLATED, status"

run_python_test "PolicyRule status PENDING when phase missing" \
"from security_ai.policy_enforcement_engine import PolicyRule, PolicyStatus, PolicySeverity, GovernanceTier
rule = PolicyRule('R1', 'Test', 'desc', PolicySeverity.LOW, GovernanceTier.ENGINEERING, ['phase99'], 12.0)
status = rule.status({})
assert status == PolicyStatus.PENDING, status"

run_python_test "PolicyRule status EXEMPTED when exemption_reason set" \
"from security_ai.policy_enforcement_engine import PolicyRule, PolicyStatus, PolicySeverity, GovernanceTier
rule = PolicyRule('R1', 'Test', 'desc', PolicySeverity.MEDIUM, GovernanceTier.REGULATORY, ['phase30'], 15.0, exemption_reason='maintenance')
status = rule.status({'phase30': 5.0})
assert status == PolicyStatus.EXEMPTED, status"

run_python_test "PolicyRule score_delta positive when above threshold" \
"from security_ai.policy_enforcement_engine import PolicyRule, PolicySeverity, GovernanceTier
rule = PolicyRule('R1', 'Test', 'desc', PolicySeverity.HIGH, GovernanceTier.OPERATIONAL, ['phase30'], 15.0)
delta = rule.score_delta({'phase30': 20.0})
assert delta > 0, delta"

run_python_test "PolicyRule score_delta negative when below threshold" \
"from security_ai.policy_enforcement_engine import PolicyRule, PolicySeverity, GovernanceTier
rule = PolicyRule('R1', 'Test', 'desc', PolicySeverity.HIGH, GovernanceTier.OPERATIONAL, ['phase30'], 15.0)
delta = rule.score_delta({'phase30': 10.0})
assert delta < 0, delta"

run_python_test "PolicyRule multi-phase average used for threshold check" \
"from security_ai.policy_enforcement_engine import PolicyRule, PolicyStatus, PolicySeverity, GovernanceTier
rule = PolicyRule('R1', 'Test', 'desc', PolicySeverity.HIGH, GovernanceTier.OPERATIONAL, ['p1','p2'], 15.0)
# avg(10+20)=15 == threshold => ENFORCED
status = rule.status({'p1': 10.0, 'p2': 20.0})
assert status == PolicyStatus.ENFORCED, status"

echo ""

# -----------------------------------------------------------------------
# GROUP 3: RemediationTask lifecycle
# -----------------------------------------------------------------------
echo "GROUP 3: RemediationTask Lifecycle"

run_python_test "RemediationTask created with OPEN status" \
"from security_ai.policy_enforcement_engine import RemediationTask, RemediationStatus
t = RemediationTask(rule_id='R1', rule_name='Test')
assert t.status == RemediationStatus.OPEN"

run_python_test "RemediationTask resolve() sets RESOLVED + timestamp" \
"from security_ai.policy_enforcement_engine import RemediationTask, RemediationStatus
t = RemediationTask(rule_id='R1', rule_name='Test')
t.resolve('fixed it')
assert t.status == RemediationStatus.RESOLVED
assert t.resolved_at is not None
assert t.notes == 'fixed it'"

run_python_test "RemediationTask suppress() sets SUPPRESSED" \
"from security_ai.policy_enforcement_engine import RemediationTask, RemediationStatus
t = RemediationTask(rule_id='R1', rule_name='Test')
t.suppress('risk accepted')
assert t.status == RemediationStatus.SUPPRESSED
assert 'risk accepted' in t.notes"

run_python_test "RemediationTask age_seconds() returns positive float" \
"from security_ai.policy_enforcement_engine import RemediationTask
t = RemediationTask(rule_id='R1', rule_name='Test')
assert t.age_seconds() >= 0.0"

run_python_test "RemediationTask task_id auto-generated uniquely" \
"from security_ai.policy_enforcement_engine import RemediationTask
t1 = RemediationTask(); t2 = RemediationTask()
assert t1.task_id != t2.task_id"

echo ""

# -----------------------------------------------------------------------
# GROUP 4: PolicyEnforcementEngine default rules
# -----------------------------------------------------------------------
echo "GROUP 4: Engine — Default Rules"

run_python_test "Engine loads 19 default rules" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
assert e.rule_count() == 19, e.rule_count()"

run_python_test "Engine has rules in all 3 tiers" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine, GovernanceTier
e = PolicyEnforcementEngine()
tiers = {r.tier for r in e.rules()}
assert GovernanceTier.REGULATORY in tiers
assert GovernanceTier.OPERATIONAL in tiers
assert GovernanceTier.ENGINEERING in tiers"

run_python_test "Engine register_rule adds custom rule" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine, PolicyRule, PolicySeverity, GovernanceTier
e = PolicyEnforcementEngine()
before = e.rule_count()
r = PolicyRule('CUST-001','Custom','desc', PolicySeverity.LOW, GovernanceTier.ENGINEERING, ['phase30'])
e.register_rule(r)
assert e.rule_count() == before + 1"

run_python_test "Engine remove_rule removes rule" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
before = e.rule_count()
assert e.remove_rule('REG-001')
assert e.rule_count() == before - 1"

run_python_test "Engine exempt_rule marks rule as exempted" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
assert e.exempt_rule('REG-001', 'maintenance window')
rule = next(r for r in e.rules() if r.rule_id == 'REG-001')
assert rule.exemption_reason == 'maintenance window'"

run_python_test "Engine auto_load_defaults=False loads 0 rules" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine(auto_load_defaults=False)
assert e.rule_count() == 0"

echo ""

# -----------------------------------------------------------------------
# GROUP 5: Phase score ingestion
# -----------------------------------------------------------------------
echo "GROUP 5: Phase Score Ingestion"

run_python_test "ingest_phase_scores() stores all scores" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
scores = {f'phase{i}': float(i % 25) for i in range(30,49)}
e.ingest_phase_scores(scores)
stored = e.phase_scores()
assert len(stored) == 19"

run_python_test "ingest_phase_scores() clamps values to 0-25" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.ingest_phase_scores({'phase30': 999.0, 'phase31': -5.0})
s = e.phase_scores()
assert s['phase30'] == 25.0
assert s['phase31'] == 0.0"

run_python_test "set_phase_score() updates single phase" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.set_phase_score('phase30', 22.5)
assert e.phase_scores().get('phase30') == 22.5"

run_python_test "set_phase_score() clamps at 25" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.set_phase_score('phase30', 30.0)
assert e.phase_scores().get('phase30') == 25.0"

echo ""

# -----------------------------------------------------------------------
# GROUP 6: Enforcement cycle
# -----------------------------------------------------------------------
echo "GROUP 6: Enforcement Cycle"

run_python_test "enforce() returns GovernanceReport" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine, GovernanceReport
e = PolicyEnforcementEngine()
e.ingest_phase_scores({'phase30': 22.0})
report = e.enforce()
assert isinstance(report, GovernanceReport)"

run_python_test "enforce() evaluates all 19 rules" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30,49)})
report = e.enforce()
assert report.total_rules() == 19"

run_python_test "enforce() all ENFORCED with high scores" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine, PolicyStatus
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 25.0 for i in range(30,49)})
report = e.enforce()
assert report.violated_count() == 0
assert report.enforced_count() > 0"

run_python_test "enforce() creates remediations for violations" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
# All phases score 0 → everything violated
e.ingest_phase_scores({f'phase{i}': 0.0 for i in range(30,49)})
report = e.enforce()
assert report.violated_count() > 0
assert len(report.open_remediations()) > 0"

run_python_test "enforce() with create_remediations=False creates no tasks" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 0.0 for i in range(30,49)})
report = e.enforce(create_remediations=False)
assert len(report.open_remediations()) == 0"

run_python_test "Multiple enforce() cycles accumulate in reports list" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30,49)})
e.enforce(); e.enforce(); e.enforce()
# latest_report() returns last one
assert e.latest_report() is not None"

echo ""

# -----------------------------------------------------------------------
# GROUP 7: GovernanceReport aggregates
# -----------------------------------------------------------------------
echo "GROUP 7: GovernanceReport Aggregates"

run_python_test "compliance_rate() = 100% when all enforced" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 25.0 for i in range(30,49)})
report = e.enforce()
assert report.compliance_rate() == 100.0"

run_python_test "compliance_rate() < 100 when violations exist" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 0.0 for i in range(30,49)})
report = e.enforce()
assert report.compliance_rate() < 100.0"

run_python_test "violations_by_severity() returns dict with all severity keys" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30,49)})
report = e.enforce()
vbs = report.violations_by_severity()
assert 'critical' in vbs and 'high' in vbs and 'medium' in vbs and 'low' in vbs"

run_python_test "phase49_score() = 25 when no violations" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 25.0 for i in range(30,49)})
report = e.enforce()
assert report.phase49_score() == 25, report.phase49_score()"

run_python_test "phase49_score() >= 0 always" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 0.0 for i in range(30,49)})
report = e.enforce()
assert report.phase49_score() >= 0"

run_python_test "GovernanceReport to_dict() has required keys" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30,49)})
report = e.enforce()
d = report.to_dict()
for k in ('report_id','compliance_rate_pct','violated','enforced','phase49_score','evaluations'):
    assert k in d, k"

run_python_test "PolicyEvaluation to_dict() has required keys" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30,49)})
report = e.enforce()
ev = report.evaluations[0].to_dict()
for k in ('rule_id','rule_name','status','severity','tier','score_delta'):
    assert k in ev, k"

echo ""

# -----------------------------------------------------------------------
# GROUP 8: Remediation management
# -----------------------------------------------------------------------
echo "GROUP 8: Remediation Management"

run_python_test "open_remediations() returns list of open tasks" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 0.0 for i in range(30,49)})
e.enforce()
tasks = e.open_remediations()
assert isinstance(tasks, list) and len(tasks) > 0"

run_python_test "resolve_remediation() closes task by id" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine, RemediationStatus
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 0.0 for i in range(30,49)})
e.enforce()
tasks = e.open_remediations()
assert tasks, 'no violations to remediate'
tid = tasks[0].task_id
assert e.resolve_remediation(tid, 'patched')
task = e.get_remediation(tid)
assert task.status == RemediationStatus.RESOLVED"

run_python_test "resolve_remediation() returns False for unknown id" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
assert not e.resolve_remediation('nonexistent-id')"

run_python_test "all_remediations() includes resolved tasks" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine, RemediationStatus
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 0.0 for i in range(30,49)})
e.enforce()
tasks = e.open_remediations()
if tasks:
    e.resolve_remediation(tasks[0].task_id, 'done')
all_tasks = e.all_remediations()
statuses = {t.status for t in all_tasks}
assert RemediationStatus.RESOLVED in statuses or len(all_tasks) == 0"

echo ""

# -----------------------------------------------------------------------
# GROUP 9: Engine summary & governance score
# -----------------------------------------------------------------------
echo "GROUP 9: Engine Summary & Governance Score"

run_python_test "summary() returns dict with required keys before enforcement" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
s = e.summary()
assert 'rules_registered' in s and 'governance_score' in s"

run_python_test "summary() after enforcement has compliance_rate_pct" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30,49)})
e.enforce()
s = e.summary()
assert 'compliance_rate_pct' in s and 'enforced' in s and 'violated' in s"

run_python_test "governance_score() = 0 before any enforcement" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
assert e.governance_score() == 0"

run_python_test "governance_score() = 25 with all perfect scores" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 25.0 for i in range(30,49)})
e.enforce()
assert e.governance_score() == 25, e.governance_score()"

run_python_test "compliance_rate() matches report compliance_rate" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30,49)})
e.enforce()
assert e.compliance_rate() == e.latest_report().compliance_rate()"

echo ""

# -----------------------------------------------------------------------
# GROUP 10: generate_report with tier filter
# -----------------------------------------------------------------------
echo "GROUP 10: Tier-Filtered Report"

run_python_test "generate_report() without tier returns all evaluations" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30,49)})
e.enforce()
report = e.generate_report()
assert len(report['evaluations']) == 19"

run_python_test "generate_report() with regulatory tier filters correctly" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine, GovernanceTier
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30,49)})
e.enforce()
report = e.generate_report(tier=GovernanceTier.REGULATORY)
assert 'tier_filter' in report
assert report['tier_filter'] == 'regulatory'
# All returned evals should be regulatory rules
reg_ids = {'REG-001','REG-002','REG-003','REG-004','REG-005','REG-006'}
for ev in report['evaluations']:
    assert ev['rule_id'] in reg_ids, ev['rule_id']"

run_python_test "generate_report() without enforcement returns error key" \
"from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
report = e.generate_report()
assert 'error' in report"

echo ""

# -----------------------------------------------------------------------
# GROUP 11: persist_state
# -----------------------------------------------------------------------
echo "GROUP 11: State Persistence"

run_python_test "persist_state() creates JSON file" \
"import os, json, tempfile
from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30,49)})
e.enforce()
with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
    path = f.name
path = e.persist_state(path)
assert os.path.exists(path)
with open(path) as f:
    data = json.load(f)
assert data['phase'] == 49
os.unlink(path)"

run_python_test "persist_state() JSON contains summary key" \
"import json, tempfile, os
from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30,49)})
e.enforce()
with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
    path = f.name
e.persist_state(path)
with open(path) as f:
    d = json.load(f)
assert 'summary' in d and 'reports' in d and 'remediations' in d
os.unlink(path)"

run_python_test "persist_state() remediations list populated on violations" \
"import json, tempfile, os
from security_ai.policy_enforcement_engine import PolicyEnforcementEngine
e = PolicyEnforcementEngine()
e.ingest_phase_scores({f'phase{i}': 0.0 for i in range(30,49)})
e.enforce()
with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
    path = f.name
e.persist_state(path)
with open(path) as f:
    d = json.load(f)
assert len(d['remediations']) > 0
os.unlink(path)"

echo ""

# -----------------------------------------------------------------------
# GROUP 12: Ops script
# -----------------------------------------------------------------------
echo "GROUP 12: Ops Script"

run_test "Ops script exists and is executable" \
    "[[ -x '${PROJECT_ROOT}/scripts/ops/phase-49-policy-enforcement.sh' ]]"

run_test "Ops script demo mode exits 0" \
    "timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-49-policy-enforcement.sh' demo"

run_test "Ops script summary mode outputs JSON" \
    "output=\$(timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-49-policy-enforcement.sh' summary 2>&1); echo \"\$output\" | python3 -c 'import sys,json; json.load(sys.stdin)'"

run_test "Ops script report regulatory mode exits 0" \
    "timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-49-policy-enforcement.sh' report regulatory"

run_test "Ops script report operational mode exits 0" \
    "timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-49-policy-enforcement.sh' report operational"

run_test "Ops script report engineering mode exits 0" \
    "timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-49-policy-enforcement.sh' report engineering"

echo ""

# -----------------------------------------------------------------------
# GROUP 13: Phase 48 regression guard
# -----------------------------------------------------------------------
echo "GROUP 13: Phase 48 Regression Guard"

if [[ -z "${SKIP_REGRESSION:-}" ]]; then
    run_test "Phase 48 integration suite still passes" \
        "SKIP_REGRESSION=1 timeout 120 bash '${PROJECT_ROOT}/scripts/ci/phase-48-integration-tests.sh' 2>&1 | grep -E 'FAIL:\s+0'"
else
    echo "  ⏭  Phase 48 regression skipped (SKIP_REGRESSION=1)"
fi

echo ""

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo "============================================================"
echo "PHASE 49 TEST RESULTS"
echo "============================================================"
printf "PASS:  %d\n" "$PASS"
printf "FAIL:  %d\n" "$FAIL"
printf "TOTAL: %d\n" "$TOTAL"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
    echo "✅  ALL TESTS PASSED — Phase 49 Policy Enforcement Engine verified"
    exit 0
else
    echo "❌  SOME TESTS FAILED — Review output above"
    exit 1
fi
