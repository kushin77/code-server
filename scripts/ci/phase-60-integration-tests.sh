#!/bin/bash
# @file phase-60-integration-tests.sh
# @description Integration tests for Phase 60 — Continuous Compliance & Evidence Collection Engine
# @since 2026-05-01

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p60*.* /tmp/p60_reg59.log 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

PASS=0; FAIL=0; TOTAL=0

run_test() {
    local name="$1" cmd="$2"
    ((TOTAL++)) || true
    if eval "$cmd" > /tmp/p60_last.out 2>&1; then
        echo "  ✓ $name"; ((PASS++)) || true
    else
        echo "  ✗ $name"; ((FAIL++)) || true
        [[ -s /tmp/p60_last.out ]] && head -5 /tmp/p60_last.out | sed 's/^/    /'
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
echo "  PHASE 60 — CONTINUOUS COMPLIANCE & EVIDENCE COLLECTION"
echo "============================================================"
echo ""

# -----------------------------------------------------------------------
# GROUP 1: Module imports
# -----------------------------------------------------------------------
echo "GROUP 1: Module imports"

run_test "ContinuousComplianceEngine importable" \
    "py 'from security_ai.continuous_compliance_engine import ContinuousComplianceEngine; print(\"ok\")' | grep -q ok"

run_test "ComplianceControl importable" \
    "py 'from security_ai.continuous_compliance_engine import ComplianceControl; print(\"ok\")' | grep -q ok"

run_test "ComplianceEvidence importable" \
    "py 'from security_ai.continuous_compliance_engine import ComplianceEvidence; print(\"ok\")' | grep -q ok"

run_test "AuditEntry importable" \
    "py 'from security_ai.continuous_compliance_engine import AuditEntry; print(\"ok\")' | grep -q ok"

run_test "ComplianceFramework has 6 values" \
    "py '
from security_ai.continuous_compliance_engine import ComplianceFramework
assert len(list(ComplianceFramework)) == 6
print(\"ok\")
' | grep -q ok"

run_test "ControlStatus has 5 values" \
    "py '
from security_ai.continuous_compliance_engine import ControlStatus
assert len(list(ControlStatus)) == 5
print(\"ok\")
' | grep -q ok"

run_test "EvidenceType has 8 values" \
    "py '
from security_ai.continuous_compliance_engine import EvidenceType
assert len(list(EvidenceType)) == 8
print(\"ok\")
' | grep -q ok"

run_test "AuditAction has 8 values" \
    "py '
from security_ai.continuous_compliance_engine import AuditAction
assert len(list(AuditAction)) == 8
print(\"ok\")
' | grep -q ok"

run_test "Helpers importable" \
    "py 'from security_ai.continuous_compliance_engine import make_control, compliance_score; print(\"ok\")' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 2: Control registration
# -----------------------------------------------------------------------
echo ""
echo "GROUP 2: Control registration"

run_test "register_control returns ComplianceControl" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, ComplianceControl, ComplianceFramework
e = ContinuousComplianceEngine()
c = e.register_control(ComplianceFramework.SOC2, \"CTL-001\", \"Title\", \"Desc\")
assert isinstance(c, ComplianceControl)
print(\"ok\")
' | grep -q ok"

run_test "Duplicate control_id raises ValueError" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, ComplianceFramework
e = ContinuousComplianceEngine()
e.register_control(ComplianceFramework.SOC2, \"CTL-001\", \"T\", \"D\")
try:
    e.register_control(ComplianceFramework.SOC2, \"CTL-001\", \"T2\", \"D2\")
    assert False
except ValueError:
    pass
print(\"ok\")
' | grep -q ok"

run_test "Control status starts as EVIDENCE_PENDING" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, ComplianceFramework, ControlStatus
e = ContinuousComplianceEngine()
c = e.register_control(ComplianceFramework.HIPAA, \"H-001\", \"T\", \"D\")
assert c.status == ControlStatus.EVIDENCE_PENDING
print(\"ok\")
' | grep -q ok"

run_test "get_control retrieves by ID" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, ComplianceFramework
e = ContinuousComplianceEngine()
c1 = e.register_control(ComplianceFramework.PCI_DSS, \"P-001\", \"T\", \"D\")
c2 = e.get_control(\"P-001\")
assert c1.control_id == c2.control_id
print(\"ok\")
' | grep -q ok"

run_test "get_control raises KeyError for unknown ID" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine
e = ContinuousComplianceEngine()
try:
    e.get_control(\"NOTREAL\")
    assert False
except KeyError:
    pass
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 3: Evidence collection
# -----------------------------------------------------------------------
echo ""
echo "GROUP 3: Evidence collection"

run_test "collect_evidence returns ComplianceEvidence" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, ComplianceFramework, EvidenceType, ComplianceEvidence
e = ContinuousComplianceEngine()
c = e.register_control(ComplianceFramework.SOC2, \"S-001\", \"T\", \"D\")
ev = e.collect_evidence(\"S-001\", EvidenceType.POLICY, \"desc\", \"/path\", \"analyst\")
assert isinstance(ev, ComplianceEvidence)
print(\"ok\")
' | grep -q ok"

run_test "evidence_id starts with EV-" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, ComplianceFramework, EvidenceType
e = ContinuousComplianceEngine()
c = e.register_control(ComplianceFramework.GDPR, \"G-001\", \"T\", \"D\")
ev = e.collect_evidence(\"G-001\", EvidenceType.LOG_ENTRY, \"x\", \"/x\", \"y\")
assert ev.evidence_id.startswith(\"EV-\"), ev.evidence_id
print(\"ok\")
' | grep -q ok"

run_test "collect_evidence for unknown control raises KeyError" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, EvidenceType
e = ContinuousComplianceEngine()
try:
    e.collect_evidence(\"NOTREAL\", EvidenceType.POLICY, \"x\", \"/x\", \"y\")
    assert False
except KeyError:
    pass
print(\"ok\")
' | grep -q ok"

run_test "evidence_for_control returns correct evidence" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, ComplianceFramework, EvidenceType
e = ContinuousComplianceEngine()
c = e.register_control(ComplianceFramework.ISO27001, \"I-001\", \"T\", \"D\")
e.collect_evidence(\"I-001\", EvidenceType.POLICY, \"a\", \"/a\", \"u1\")
e.collect_evidence(\"I-001\", EvidenceType.AUDIT_REPORT, \"b\", \"/b\", \"u2\")
assert len(e.evidence_for_control(\"I-001\")) == 2
print(\"ok\")
' | grep -q ok"

run_test "Evidence not expired when expires_at is None" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, ComplianceFramework, EvidenceType
e = ContinuousComplianceEngine()
c = e.register_control(ComplianceFramework.SOC2, \"S-001\", \"T\", \"D\")
ev = e.collect_evidence(\"S-001\", EvidenceType.POLICY, \"x\", \"/x\", \"y\")
assert not ev.is_expired
print(\"ok\")
' | grep -q ok"

run_test "Evidence expiration tracking works" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, ComplianceFramework, EvidenceType
e = ContinuousComplianceEngine()
c = e.register_control(ComplianceFramework.HIPAA, \"H-001\", \"T\", \"D\")
ev = e.collect_evidence(\"H-001\", EvidenceType.ATTESTATION, \"x\", \"/x\", \"y\", expires_in_days=365)
assert ev.days_until_expiry is not None
assert ev.days_until_expiry > 300  # Conservative check
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 4: Control status updates
# -----------------------------------------------------------------------
echo ""
echo "GROUP 4: Control status updates"

run_test "update_control_status changes status" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, ComplianceFramework, ControlStatus
e = ContinuousComplianceEngine()
c = e.register_control(ComplianceFramework.NIST, \"N-001\", \"T\", \"D\")
e.update_control_status(\"N-001\", ControlStatus.COMPLIANT, \"OK\")
assert e.get_control(\"N-001\").status == ControlStatus.COMPLIANT
print(\"ok\")
' | grep -q ok"

run_test "update_control_status sets last_verified" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, ComplianceFramework, ControlStatus
e = ContinuousComplianceEngine()
c = e.register_control(ComplianceFramework.PCI_DSS, \"P-001\", \"T\", \"D\")
e.update_control_status(\"P-001\", ControlStatus.PARTIAL)
assert e.get_control(\"P-001\").last_verified is not None
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 5: Audit logging
# -----------------------------------------------------------------------
echo ""
echo "GROUP 5: Audit logging"

run_test "log_audit_event creates AuditEntry" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, AuditAction, AuditEntry
e = ContinuousComplianceEngine()
entry = e.log_audit_event(AuditAction.ACCESS_GRANTED, \"user\", \"resource\", \"success\")
assert isinstance(entry, AuditEntry)
print(\"ok\")
' | grep -q ok"

run_test "audit_id starts with AUD-" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, AuditAction
e = ContinuousComplianceEngine()
entry = e.log_audit_event(AuditAction.OBJECT_CREATED, \"admin\", \"config\", \"success\")
assert entry.audit_id.startswith(\"AUD-\"), entry.audit_id
print(\"ok\")
' | grep -q ok"

run_test "recent_audit_entries returns recent entries" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, AuditAction
e = ContinuousComplianceEngine()
e.log_audit_event(AuditAction.ACCESS_GRANTED, \"u1\", \"r1\", \"success\")
e.log_audit_event(AuditAction.ACCESS_DENIED, \"u2\", \"r2\", \"failure\")
recent = e.recent_audit_entries(hours=1)
assert len(recent) >= 2
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 6: Assessment
# -----------------------------------------------------------------------
echo ""
echo "GROUP 6: Assessment"

run_test "assess_framework returns ComplianceAssessment" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, ComplianceFramework, ControlStatus, ComplianceAssessment
e = ContinuousComplianceEngine()
c = e.register_control(ComplianceFramework.SOC2, \"S-001\", \"T\", \"D\")
e.update_control_status(\"S-001\", ControlStatus.COMPLIANT)
a = e.assess_framework(ComplianceFramework.SOC2)
assert isinstance(a, ComplianceAssessment)
print(\"ok\")
' | grep -q ok"

run_test "Assessment compliance_pct calculates correctly" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, ComplianceFramework, ControlStatus
e = ContinuousComplianceEngine()
for i in range(1, 4):
    cid = f\"S-{i:03d}\"
    e.register_control(ComplianceFramework.SOC2, cid, \"T\", \"D\")
e.update_control_status(\"S-001\", ControlStatus.COMPLIANT)
e.update_control_status(\"S-002\", ControlStatus.COMPLIANT)
e.update_control_status(\"S-003\", ControlStatus.NON_COMPLIANT)
a = e.assess_framework(ComplianceFramework.SOC2)
assert a.compliance_pct == 66.66 or a.compliance_pct == 66.67
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 7: Queries
# -----------------------------------------------------------------------
echo ""
echo "GROUP 7: Queries"

run_test "controls_by_framework filters correctly" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, ComplianceFramework
e = ContinuousComplianceEngine()
e.register_control(ComplianceFramework.SOC2, \"S-001\", \"T\", \"D\")
e.register_control(ComplianceFramework.SOC2, \"S-002\", \"T\", \"D\")
e.register_control(ComplianceFramework.HIPAA, \"H-001\", \"T\", \"D\")
soc2 = e.controls_by_framework(ComplianceFramework.SOC2)
assert len(soc2) == 2
print(\"ok\")
' | grep -q ok"

run_test "controls_by_status filters correctly" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, ComplianceFramework, ControlStatus
e = ContinuousComplianceEngine()
for i in range(1, 4):
    c = e.register_control(ComplianceFramework.SOC2, f\"S-{i}\", \"T\", \"D\")
e.update_control_status(\"S-1\", ControlStatus.COMPLIANT)
e.update_control_status(\"S-2\", ControlStatus.COMPLIANT)
compliant = e.controls_by_status(ControlStatus.COMPLIANT)
assert len(compliant) == 2
print(\"ok\")
' | grep -q ok"

run_test "expired_evidence finds expired items" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, ComplianceFramework, EvidenceType
from datetime import timedelta
import datetime as dt
e = ContinuousComplianceEngine()
c = e.register_control(ComplianceFramework.SOC2, \"S-001\", \"T\", \"D\")
ev = e.collect_evidence(\"S-001\", EvidenceType.POLICY, \"x\", \"/x\", \"y\", expires_in_days=-1)
# Manually set expired_at to past
ev.expires_at = dt.datetime.utcnow() - timedelta(days=1)
expired = e.expired_evidence()
assert len(expired) >= 1
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 8: phase60_score()
# -----------------------------------------------------------------------
echo ""
echo "GROUP 8: phase60_score()"

run_test "Empty engine score is reasonable" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine
e = ContinuousComplianceEngine()
sc = e.phase60_score()
assert 0.0 <= sc <= 25.0, sc
print(\"ok\")
' | grep -q ok"

run_test "score in [0, 25]" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, ComplianceFramework, ControlStatus
e = ContinuousComplianceEngine()
c = e.register_control(ComplianceFramework.SOC2, \"S-001\", \"T\", \"D\")
e.update_control_status(\"S-001\", ControlStatus.COMPLIANT)
sc = e.phase60_score()
assert 0.0 <= sc <= 25.0, sc
print(\"ok\")
' | grep -q ok"

run_test "compliance_score helper returns phase60_score" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, compliance_score
e = ContinuousComplianceEngine()
assert compliance_score(e) == e.phase60_score()
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 9: Summary and reporting
# -----------------------------------------------------------------------
echo ""
echo "GROUP 9: Summary and reporting"

run_test "summary() has all required keys" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine
e = ContinuousComplianceEngine()
s = e.summary()
for k in [\"total_controls\",\"required_controls\",\"compliant\",\"partial\",\"non_compliant\",
          \"total_evidence\",\"expired_evidence\",\"expiring_soon_30d\",\"total_audit_entries\",
          \"frameworks\",\"phase60_score\"]:
    assert k in s, f\"missing {k}\"
print(\"ok\")
' | grep -q ok"

run_test "Control.to_dict() has required fields" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, ComplianceFramework
e = ContinuousComplianceEngine()
c = e.register_control(ComplianceFramework.GDPR, \"G-001\", \"Title\", \"Desc\")
d = c.to_dict()
for k in [\"control_id\",\"framework\",\"title\",\"status\",\"required\",\"evidence_count\"]:
    assert k in d, f\"missing {k}\"
print(\"ok\")
' | grep -q ok"

run_test "Evidence.to_dict() has required fields" \
    "py '
from security_ai.continuous_compliance_engine import ContinuousComplianceEngine, ComplianceFramework, EvidenceType
e = ContinuousComplianceEngine()
c = e.register_control(ComplianceFramework.NIST, \"N-001\", \"T\", \"D\")
ev = e.collect_evidence(\"N-001\", EvidenceType.CONFIGURATION, \"x\", \"/x\", \"y\")
d = ev.to_dict()
for k in [\"evidence_id\",\"control_id\",\"evidence_type\",\"location\",\"is_expired\"]:
    assert k in d, f\"missing {k}\"
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 10: Ops script integration
# -----------------------------------------------------------------------
echo ""
echo "GROUP 10: Ops script integration"

OPS="${PROJECT_ROOT}/scripts/ops/phase-60-continuous-compliance.sh"
[[ -x "$OPS" ]] || chmod +x "$OPS"

run_test "Ops script exists" "[[ -f '$OPS' ]]"

run_test "demo mode exits 0" \
    "bash '$OPS' demo > /tmp/p60demo.out 2>&1"

run_test "demo outputs PHASE 60" \
    "grep -q 'PHASE 60' /tmp/p60demo.out"

run_test "demo shows Phase 60 Score" \
    "grep -q 'Phase 60 Score' /tmp/p60demo.out"

run_test "summary mode outputs valid JSON" \
    "bash '$OPS' summary > /tmp/p60sum.out 2>&1 && python3 -c 'import json; json.load(open(\"/tmp/p60sum.out\"))'"

run_test "summary JSON contains phase60_score" \
    "python3 -c 'import json; d=json.load(open(\"/tmp/p60sum.out\")); assert \"phase60_score\" in d'"

run_test "assess mode outputs valid JSON" \
    "bash '$OPS' assess > /tmp/p60ass.out 2>&1 && python3 -c 'import json; json.load(open(\"/tmp/p60ass.out\"))'"

# -----------------------------------------------------------------------
# GROUP 11: Phase 59 regression guard
# -----------------------------------------------------------------------
echo ""
echo "GROUP 11: Phase 59 regression guard"

run_test "Phase 59 integration suite still passes" \
    "timeout 150 bash '${PROJECT_ROOT}/scripts/ci/phase-59-integration-tests.sh' > /tmp/p60_reg59.log 2>&1"

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "============================================================"
echo "PHASE 60 TEST RESULTS"
echo "============================================================"
echo "PASS:  $PASS"
echo "FAIL:  $FAIL"
echo "TOTAL: $TOTAL"
echo "============================================================"

if [[ $FAIL -eq 0 ]]; then
    echo ""
    echo "✅  ALL TESTS PASSED — Phase 60 Continuous Compliance verified"
    exit 0
else
    echo ""
    echo "❌  SOME TESTS FAILED"
    exit 1
fi
