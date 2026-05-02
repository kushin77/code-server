#!/bin/bash
# @file phase-46-integration-tests.sh
# @description Integration tests for Phase 46 — Compliance Audit & Security Posture Verification
# @since 2026-05-01

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p46*.* /tmp/p46_reg45.log 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
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

PY() { "$PYTHON_CMD" -c "import sys; sys.path.insert(0,'${PROJECT_ROOT}/apps'); $1"; }

echo "============================================================"
echo "PHASE 46: COMPLIANCE AUDIT ENGINE — INTEGRATION TESTS"
echo "============================================================"
echo ""

# GROUP 1: Module imports
echo "GROUP 1: Module Import & API Surface"
run_test "Import ComplianceAuditEngine" \
    "PY 'from security_ai.compliance_audit_engine import ComplianceAuditEngine'"
run_test "Import AuditRecord" \
    "PY 'from security_ai.compliance_audit_engine import AuditRecord'"
run_test "Import AuditFinding" \
    "PY 'from security_ai.compliance_audit_engine import AuditFinding'"
run_test "Import ControlCheck" \
    "PY 'from security_ai.compliance_audit_engine import ControlCheck'"
run_test "Import AuditSeverity" \
    "PY 'from security_ai.compliance_audit_engine import AuditSeverity'"
run_test "Import FindingStatus" \
    "PY 'from security_ai.compliance_audit_engine import FindingStatus'"
run_test "Import ControlStatus" \
    "PY 'from security_ai.compliance_audit_engine import ControlStatus'"
run_test "Import audit_score helper" \
    "PY 'from security_ai.compliance_audit_engine import audit_score'"
run_test "Import STANDARD_CONTROLS" \
    "PY 'from security_ai.compliance_audit_engine import STANDARD_CONTROLS; assert len(STANDARD_CONTROLS) == 8'"

echo ""
echo "GROUP 2: Control Check Evaluation"
run_test "Control COMPLIANT at high score" \
    "PY '
from security_ai.compliance_audit_engine import ControlCheck, ControlStatus
c = ControlCheck(\"ctrl-x\", \"Test\", \"SOC2\", \"phase_30\", threshold=80.0)
result = c.evaluate(95.0)
assert result == ControlStatus.COMPLIANT
'"
run_test "Control PARTIAL at moderate score" \
    "PY '
from security_ai.compliance_audit_engine import ControlCheck, ControlStatus
c = ControlCheck(\"ctrl-x\", \"Test\", \"SOC2\", \"phase_30\", threshold=80.0)
result = c.evaluate(65.0)  # 65 >= 0.75*80=60 but < 80
assert result == ControlStatus.PARTIAL
'"
run_test "Control NON_COMPLIANT at low score" \
    "PY '
from security_ai.compliance_audit_engine import ControlCheck, ControlStatus
c = ControlCheck(\"ctrl-x\", \"Test\", \"SOC2\", \"phase_30\", threshold=80.0)
result = c.evaluate(30.0)
assert result == ControlStatus.NON_COMPLIANT
'"
run_test "Control score clamped 0-100" \
    "PY '
from security_ai.compliance_audit_engine import ControlCheck
c = ControlCheck(\"ctrl-x\", \"Test\", \"SOC2\", \"phase_30\", threshold=80.0)
c.evaluate(150.0)
assert c.score == 100.0
c.evaluate(-10.0)
assert c.score == 0.0
'"
run_test "Control last_checked populated after evaluate" \
    "PY '
from security_ai.compliance_audit_engine import ControlCheck
c = ControlCheck(\"ctrl-x\", \"Test\", \"SOC2\", \"phase_30\", threshold=80.0)
c.evaluate(88.0)
assert c.last_checked is not None
'"

echo ""
echo "GROUP 3: AuditFinding Lifecycle"
run_test "Finding has unique finding_id" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine, AuditSeverity
engine = ComplianceAuditEngine()
rec = engine.create_audit(\"A\", \"svc\")
f1 = engine.add_finding(rec, \"T1\", \"D1\", AuditSeverity.HIGH, \"phase_30\", \"ctrl-30\")
f2 = engine.add_finding(rec, \"T2\", \"D2\", AuditSeverity.LOW, \"phase_31\", \"ctrl-31\")
assert f1.finding_id != f2.finding_id
'"
run_test "Finding severity_weight is positive" \
    "PY '
from security_ai.compliance_audit_engine import AuditFinding, AuditSeverity
from datetime import datetime
f = AuditFinding(\"F-001\", \"T\", \"D\", AuditSeverity.CRITICAL, \"phase_30\", \"ctrl-30\")
assert f.severity_weight() > 0
'"
run_test "CRITICAL higher weight than LOW" \
    "PY '
from security_ai.compliance_audit_engine import AuditFinding, AuditSeverity
from datetime import datetime
fc = AuditFinding(\"F-1\", \"T\", \"D\", AuditSeverity.CRITICAL, \"phase_30\", \"ctrl-30\")
fl = AuditFinding(\"F-2\", \"T\", \"D\", AuditSeverity.LOW, \"phase_30\", \"ctrl-30\")
assert fc.severity_weight() > fl.severity_weight()
'"
run_test "Remediate finding changes status" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine, AuditSeverity, FindingStatus
engine = ComplianceAuditEngine()
rec = engine.create_audit(\"A\", \"svc\")
f = engine.add_finding(rec, \"T\", \"D\", AuditSeverity.HIGH, \"phase_30\", \"ctrl-30\")
engine.remediate_finding(rec, f.finding_id, \"Patched\")
assert f.status == FindingStatus.REMEDIATED
'"
run_test "Remediate non-existent finding returns False" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine
engine = ComplianceAuditEngine()
rec = engine.create_audit(\"A\", \"svc\")
result = engine.remediate_finding(rec, \"F-FAKE\")
assert result is False
'"

echo ""
echo "GROUP 4: Audit Lifecycle"
run_test "create_audit returns AuditRecord with 8 controls" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine
engine = ComplianceAuditEngine()
rec = engine.create_audit(\"Test Audit\", \"platform\")
assert len(rec.controls) == 8
'"
run_test "run_audit returns bool" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine
engine = ComplianceAuditEngine()
rec = engine.create_audit(\"Test\", \"svc\")
result = engine.run_audit(rec)
assert isinstance(result, bool)
'"
run_test "High scores yield fully compliant" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine
engine = ComplianceAuditEngine()
rec = engine.create_audit(\"Test\", \"svc\")
engine.run_audit(rec, {c.control_id: 99.0 for c in rec.controls})
assert rec.is_fully_compliant()
'"
run_test "Low scores yield non-compliant" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine
engine = ComplianceAuditEngine()
rec = engine.create_audit(\"Test\", \"svc\")
engine.run_audit(rec, {c.control_id: 10.0 for c in rec.controls})
assert not rec.is_fully_compliant()
'"
run_test "control_summary totals equal number of controls" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine
engine = ComplianceAuditEngine()
rec = engine.create_audit(\"Test\", \"svc\")
engine.run_audit(rec)
cs = rec.control_summary()
assert sum(cs.values()) == len(rec.controls)
'"
run_test "Auto-generated findings for non-compliant controls" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine
engine = ComplianceAuditEngine()
rec = engine.create_audit(\"Test\", \"svc\")
engine.run_audit(rec, {c.control_id: 10.0 for c in rec.controls})
assert len(rec.findings) > 0
'"
run_test "finalize_audit moves record to history" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine
engine = ComplianceAuditEngine()
rec = engine.create_audit(\"Test\", \"svc\")
engine.run_audit(rec)
engine.finalize_audit(rec)
assert len(engine.history) == 1
assert len(engine.audits) == 0
'"

echo ""
echo "GROUP 5: Posture Scoring"
run_test "posture_score in range 0-25" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine
engine = ComplianceAuditEngine()
rec = engine.create_audit(\"Test\", \"svc\")
engine.run_audit(rec)
s = rec.posture_score()
assert 0.0 <= s <= 25.0, f\"Score out of range: {s}\"
'"
run_test "Fully compliant scores higher than non-compliant" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine
engine = ComplianceAuditEngine()
good = engine.create_audit(\"Good\", \"svc\")
engine.run_audit(good, {c.control_id: 99.0 for c in good.controls})
bad = engine.create_audit(\"Bad\", \"svc\")
engine.run_audit(bad, {c.control_id: 10.0 for c in bad.controls})
assert good.posture_score() > bad.posture_score()
'"
run_test "audit_score helper returns float in 0-25" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine, audit_score
engine = ComplianceAuditEngine()
rec = engine.create_audit(\"Test\", \"svc\")
engine.run_audit(rec)
engine.finalize_audit(rec)
s = audit_score(engine)
assert isinstance(s, float) and 0 <= s <= 25
'"
run_test "Critical open findings reduce posture score" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine, AuditSeverity
engine = ComplianceAuditEngine()
rec = engine.create_audit(\"Test\", \"svc\")
engine.run_audit(rec, {c.control_id: 95.0 for c in rec.controls})
clean = rec.posture_score()
engine.add_finding(rec, \"T\", \"D\", AuditSeverity.CRITICAL, \"phase_30\", \"ctrl-30\")
assert rec.posture_score() < clean
'"

echo ""
echo "GROUP 6: Report Generation"
run_test "generate_report returns required keys" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine
engine = ComplianceAuditEngine()
rec = engine.create_audit(\"Test\", \"svc\")
engine.run_audit(rec)
report = engine.generate_report(rec)
for key in [\"audit_id\",\"audit_name\",\"scope\",\"posture_score\",\"fully_compliant\",\"control_summary\",\"open_findings\"]:
    assert key in report, f\"Missing: {key}\"
'"
run_test "open_findings_by_severity counts by enum value" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine, AuditSeverity
engine = ComplianceAuditEngine()
rec = engine.create_audit(\"Test\", \"svc\")
engine.run_audit(rec, {c.control_id: 99.0 for c in rec.controls})
engine.add_finding(rec, \"T\", \"D\", AuditSeverity.CRITICAL, \"phase_30\", \"ctrl-30\")
counts = rec.open_findings_by_severity()
assert counts[\"critical\"] == 1
'"
run_test "critical_open returns correct count" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine, AuditSeverity
engine = ComplianceAuditEngine()
rec = engine.create_audit(\"Test\", \"svc\")
engine.run_audit(rec, {c.control_id: 99.0 for c in rec.controls})
for _ in range(3):
    engine.add_finding(rec, \"T\", \"D\", AuditSeverity.CRITICAL, \"phase_30\", \"ctrl-30\")
assert rec.critical_open() == 3
'"

echo ""
echo "GROUP 7: Phase Signal Integration"
run_test "Phase signals propagate to control scores" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine
engine = ComplianceAuditEngine()
rec = engine.create_audit(\"Test\", \"svc\", {\"phase36_score\": 99.0, \"phase30_score\": 99.0})
cleared = engine.run_audit(rec)
assert cleared, \"High phase signals should make all controls compliant\"
'"
run_test "Low phase signals trigger non-compliance" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine
engine = ComplianceAuditEngine()
rec = engine.create_audit(\"Test\", \"svc\", {
    \"phase36_score\": 20.0, \"phase30_score\": 20.0,
    \"phase31_score\": 20.0, \"phase34_score\": 20.0,
    \"phase35_score\": 20.0, \"phase38_score\": 20.0,
    \"phase40_score\": 20.0, \"phase45_score\": 20.0,
})
engine.run_audit(rec)
assert not rec.is_fully_compliant()
'"

echo ""
echo "GROUP 8: Summary"
run_test "summary returns required keys" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine
engine = ComplianceAuditEngine()
s = engine.summary()
for key in [\"total_audits\",\"fully_compliant\",\"avg_posture_score\",\"open_criticals\",\"phase46_audit_score\"]:
    assert key in s, f\"Missing key: {key}\"
'"
run_test "Multiple audits tracked in summary" \
    "PY '
from security_ai.compliance_audit_engine import ComplianceAuditEngine
engine = ComplianceAuditEngine()
for i in range(4):
    rec = engine.create_audit(f\"Audit {i}\", f\"svc-{i}\")
    engine.run_audit(rec)
    engine.finalize_audit(rec)
s = engine.summary()
assert s[\"total_audits\"] == 4
'"

echo ""
echo "GROUP 9: Ops Script"
OPS_SCRIPT="${PROJECT_ROOT}/scripts/ops/phase-46-compliance-audit.sh"
run_test "Ops script exists" "test -f '$OPS_SCRIPT'"
run_test "Ops script syntax valid" "bash -n '$OPS_SCRIPT'"
run_test "Ops demo mode" "
timeout 30 bash '$OPS_SCRIPT' demo > /tmp/p46demo.out 2>&1 && grep -q 'PHASE 46' /tmp/p46demo.out
"
run_test "Ops summary mode" "
timeout 30 bash '$OPS_SCRIPT' summary > /tmp/p46sum.out 2>&1 && grep -q 'phase46_audit_score' /tmp/p46sum.out
"
run_test "Ops audit mode" "
timeout 30 bash '$OPS_SCRIPT' audit api-gateway > /tmp/p46audit.out 2>&1 && grep -q 'posture_score\|Posture Score' /tmp/p46audit.out
"

echo ""
echo "GROUP 10: Cross-Phase Regression"
run_test "Phase 45 deployment orchestrator still passing" "
timeout 150 bash ${PROJECT_ROOT}/scripts/ci/phase-45-integration-tests.sh > /tmp/p46_reg45.log 2>&1 && grep -q 'ALL TESTS PASSED' /tmp/p46_reg45.log
"

echo ""
echo "============================================================"
echo "TEST SUMMARY"
echo "============================================================"
printf "PASS: %d\nFAIL: %d\nTOTAL: %d\n" "$PASS" "$FAIL" "$TOTAL"
echo ""
if [[ "$FAIL" -eq 0 ]]; then
    echo "✓ ALL TESTS PASSED"
    exit 0
else
    echo "✗ SOME TESTS FAILED"
    exit 1
fi
