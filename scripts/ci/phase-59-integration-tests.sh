#!/bin/bash
# @file phase-59-integration-tests.sh
# @description Integration tests for Phase 59 — Forensic Investigation & Chain of Custody Engine
# @since 2026-05-01

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p59*.* /tmp/p59_reg58.log 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

PASS=0; FAIL=0; TOTAL=0

run_test() {
    local name="$1" cmd="$2"
    ((TOTAL++)) || true
    if eval "$cmd" > /tmp/p59_last.out 2>&1; then
        echo "  ✓ $name"; ((PASS++)) || true
    else
        echo "  ✗ $name"; ((FAIL++)) || true
        [[ -s /tmp/p59_last.out ]] && head -5 /tmp/p59_last.out | sed 's/^/    /'
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
echo "  PHASE 59 — FORENSIC INVESTIGATION & CHAIN OF CUSTODY"
echo "============================================================"
echo ""

# -----------------------------------------------------------------------
# GROUP 1: Module imports
# -----------------------------------------------------------------------
echo "GROUP 1: Module imports"

run_test "ForensicInvestigationEngine importable" \
    "py 'from security_ai.forensic_investigation_engine import ForensicInvestigationEngine; print(\"ok\")' | grep -q ok"

run_test "EvidenceItem importable" \
    "py 'from security_ai.forensic_investigation_engine import EvidenceItem; print(\"ok\")' | grep -q ok"

run_test "ForensicCase importable" \
    "py 'from security_ai.forensic_investigation_engine import ForensicCase; print(\"ok\")' | grep -q ok"

run_test "ForensicFinding importable" \
    "py 'from security_ai.forensic_investigation_engine import ForensicFinding; print(\"ok\")' | grep -q ok"

run_test "EvidenceType has 10 values" \
    "py '
from security_ai.forensic_investigation_engine import EvidenceType
assert len(list(EvidenceType)) == 10
print(\"ok\")
' | grep -q ok"

run_test "EvidenceStatus has 5 values" \
    "py '
from security_ai.forensic_investigation_engine import EvidenceStatus
assert len(list(EvidenceStatus)) == 5
print(\"ok\")
' | grep -q ok"

run_test "InvestigationStatus has 5 values" \
    "py '
from security_ai.forensic_investigation_engine import InvestigationStatus
assert len(list(InvestigationStatus)) == 5
print(\"ok\")
' | grep -q ok"

run_test "FindingSeverity has 5 values" \
    "py '
from security_ai.forensic_investigation_engine import FindingSeverity
assert len(list(FindingSeverity)) == 5
print(\"ok\")
' | grep -q ok"

run_test "ChainOfCustodyAction has 6 values" \
    "py '
from security_ai.forensic_investigation_engine import ChainOfCustodyAction
assert len(list(ChainOfCustodyAction)) == 6
print(\"ok\")
' | grep -q ok"

run_test "Helpers importable" \
    "py 'from security_ai.forensic_investigation_engine import make_case, forensic_score; print(\"ok\")' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 2: Case management
# -----------------------------------------------------------------------
echo ""
echo "GROUP 2: Case management"

run_test "open_case returns ForensicCase" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, ForensicCase
e = ForensicInvestigationEngine()
c = e.open_case(\"Test case\")
assert isinstance(c, ForensicCase)
print(\"ok\")
' | grep -q ok"

run_test "case_id starts with CASE-" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
assert c.case_id.startswith(\"CASE-\"), c.case_id
print(\"ok\")
' | grep -q ok"

run_test "Case status starts as OPEN" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, InvestigationStatus
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
assert c.status == InvestigationStatus.OPEN
print(\"ok\")
' | grep -q ok"

run_test "close_case sets status to CLOSED" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, InvestigationStatus
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
e.close_case(c.case_id)
assert c.status == InvestigationStatus.CLOSED
print(\"ok\")
' | grep -q ok"

run_test "close_case sets closed_at timestamp" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
e.close_case(c.case_id)
assert c.closed_at is not None
print(\"ok\")
' | grep -q ok"

run_test "get_case retrieves case by ID" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine
e = ForensicInvestigationEngine()
c1 = e.open_case(\"Test\")
c2 = e.get_case(c1.case_id)
assert c1.case_id == c2.case_id
print(\"ok\")
' | grep -q ok"

run_test "get_case raises KeyError for unknown ID" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine
e = ForensicInvestigationEngine()
try:
    e.get_case(\"CASE-NOTREAL\")
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

run_test "collect_evidence returns EvidenceItem" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, EvidenceType, EvidenceItem
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
ev = e.collect_evidence(c.case_id, EvidenceType.DISK_IMAGE, \"disk\", \"/path\", \"analyst\")
assert isinstance(ev, EvidenceItem)
print(\"ok\")
' | grep -q ok"

run_test "evidence_id starts with EV-" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, EvidenceType
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
ev = e.collect_evidence(c.case_id, EvidenceType.LOG_FILE, \"log\", \"/path\", \"analyst\")
assert ev.evidence_id.startswith(\"EV-\"), ev.evidence_id
print(\"ok\")
' | grep -q ok"

run_test "collected evidence added to case" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, EvidenceType
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
e.collect_evidence(c.case_id, EvidenceType.DISK_IMAGE, \"a\", \"/a\", \"a\")
e.collect_evidence(c.case_id, EvidenceType.LOG_FILE, \"b\", \"/b\", \"b\")
assert c.total_evidence == 2
print(\"ok\")
' | grep -q ok"

run_test "Evidence status starts as COLLECTED" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, EvidenceType, EvidenceStatus
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
ev = e.collect_evidence(c.case_id, EvidenceType.MEMORY_DUMP, \"x\", \"/x\", \"y\")
assert ev.status == EvidenceStatus.COLLECTED
print(\"ok\")
' | grep -q ok"

run_test "Collected evidence has COC action" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, EvidenceType
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
ev = e.collect_evidence(c.case_id, EvidenceType.DISK_IMAGE, \"d\", \"/d\", \"analyst\")
assert len(ev.coc_chain) >= 1
assert ev.coc_chain[0][\"action\"] == \"collected\"
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 4: Hash verification
# -----------------------------------------------------------------------
echo ""
echo "GROUP 4: Hash verification"

run_test "hash_verified=False when hash empty" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, EvidenceType
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
ev = e.collect_evidence(c.case_id, EvidenceType.LOG_FILE, \"x\", \"/x\", \"a\")
assert not ev.hash_verified
print(\"ok\")
' | grep -q ok"

run_test "hash_verified=True when hash set" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, EvidenceType
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
ev = e.collect_evidence(c.case_id, EvidenceType.LOG_FILE, \"x\", \"/x\", \"a\", 
                          sha256_hash=\"abc123\")
assert ev.hash_verified
print(\"ok\")
' | grep -q ok"

run_test "verify_evidence_hash returns True on match" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, EvidenceType
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
ev = e.collect_evidence(c.case_id, EvidenceType.DISK_IMAGE, \"x\", \"/x\", \"a\", 
                          sha256_hash=\"abc123\")
result = e.verify_evidence_hash(c.case_id, ev.evidence_id, \"abc123\", \"analyst\")
assert result == True
print(\"ok\")
' | grep -q ok"

run_test "verify_evidence_hash returns False on mismatch" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, EvidenceType
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
ev = e.collect_evidence(c.case_id, EvidenceType.DISK_IMAGE, \"x\", \"/x\", \"a\", 
                          sha256_hash=\"abc123\")
result = e.verify_evidence_hash(c.case_id, ev.evidence_id, \"xyz999\", \"analyst\")
assert result == False
print(\"ok\")
' | grep -q ok"

run_test "Verified evidence gets VERIFIED status" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, EvidenceType, EvidenceStatus
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
ev = e.collect_evidence(c.case_id, EvidenceType.EXECUTABLE, \"x\", \"/x\", \"a\", 
                          sha256_hash=\"abc123\")
e.verify_evidence_hash(c.case_id, ev.evidence_id, \"abc123\", \"analyst\")
assert ev.status == EvidenceStatus.VERIFIED
print(\"ok\")
' | grep -q ok"

run_test "verify_evidence_hash raises KeyError for unknown evidence" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
try:
    e.verify_evidence_hash(c.case_id, \"EV-NOTREAL\", \"hash\", \"analyst\")
    assert False
except KeyError:
    pass
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 5: Evidence transfer
# -----------------------------------------------------------------------
echo ""
echo "GROUP 5: Evidence transfer"

run_test "transfer_evidence updates location" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, EvidenceType
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
ev = e.collect_evidence(c.case_id, EvidenceType.LOG_FILE, \"x\", \"/x\", \"a\")
e.transfer_evidence(c.case_id, ev.evidence_id, \"/archive/storage\", \"analyst\")
assert ev.location == \"/archive/storage\"
print(\"ok\")
' | grep -q ok"

run_test "transfer_evidence adds TRANSFERRED to COC chain" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, EvidenceType
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
ev = e.collect_evidence(c.case_id, EvidenceType.LOG_FILE, \"x\", \"/x\", \"a\")
e.transfer_evidence(c.case_id, ev.evidence_id, \"/archive\", \"analyst\")
assert any(a[\"action\"] == \"transferred\" for a in ev.coc_chain)
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 6: Mark analyzed
# -----------------------------------------------------------------------
echo ""
echo "GROUP 6: Mark analyzed"

run_test "mark_evidence_analyzed sets ANALYZED status" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, EvidenceType, EvidenceStatus
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
ev = e.collect_evidence(c.case_id, EvidenceType.NETWORK_PCAP, \"x\", \"/x\", \"a\")
e.mark_evidence_analyzed(c.case_id, ev.evidence_id, \"analyst\")
assert ev.status == EvidenceStatus.ANALYZED
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 7: Findings
# -----------------------------------------------------------------------
echo ""
echo "GROUP 7: Findings"

run_test "add_finding returns ForensicFinding" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, FindingSeverity, ForensicFinding
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
f = e.add_finding(c.case_id, FindingSeverity.HIGH, \"Title\", \"Description\")
assert isinstance(f, ForensicFinding)
print(\"ok\")
' | grep -q ok"

run_test "finding_id starts with FIND-" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, FindingSeverity
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
f = e.add_finding(c.case_id, FindingSeverity.CRITICAL, \"x\", \"y\")
assert f.finding_id.startswith(\"FIND-\"), f.finding_id
print(\"ok\")
' | grep -q ok"

run_test "Finding counts by severity" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, FindingSeverity
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
e.add_finding(c.case_id, FindingSeverity.CRITICAL, \"a\", \"a\")
e.add_finding(c.case_id, FindingSeverity.CRITICAL, \"b\", \"b\")
e.add_finding(c.case_id, FindingSeverity.HIGH, \"c\", \"c\")
assert c.critical_findings == 2
assert c.high_findings == 1
print(\"ok\")
' | grep -q ok"

run_test "Finding can reference evidence" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, EvidenceType, FindingSeverity
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
ev = e.collect_evidence(c.case_id, EvidenceType.DISK_IMAGE, \"x\", \"/x\", \"a\")
f = e.add_finding(c.case_id, FindingSeverity.HIGH, \"Title\", \"Desc\", evidence_ids=[ev.evidence_id])
assert ev.evidence_id in f.evidence_ids
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 8: Case metrics
# -----------------------------------------------------------------------
echo ""
echo "GROUP 8: Case metrics"

run_test "verified_pct = 100 when all verified" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, EvidenceType
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
ev = e.collect_evidence(c.case_id, EvidenceType.LOG_FILE, \"x\", \"/x\", \"a\", sha256_hash=\"h1\")
e.verify_evidence_hash(c.case_id, ev.evidence_id, \"h1\", \"b\")
assert c.verified_pct == 100.0
print(\"ok\")
' | grep -q ok"

run_test "verified_pct = 0 when none verified" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, EvidenceType
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
e.collect_evidence(c.case_id, EvidenceType.LOG_FILE, \"x\", \"/x\", \"a\")
e.collect_evidence(c.case_id, EvidenceType.LOG_FILE, \"y\", \"/y\", \"b\")
assert c.verified_pct == 0.0
print(\"ok\")
' | grep -q ok"

run_test "duration_minutes is non-negative" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
assert c.duration_minutes() >= 0.0
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 9: Queries
# -----------------------------------------------------------------------
echo ""
echo "GROUP 9: Queries"

run_test "all_cases returns all cases" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine
e = ForensicInvestigationEngine()
e.open_case(\"A\")
e.open_case(\"B\")
assert len(e.all_cases()) == 2
print(\"ok\")
' | grep -q ok"

run_test "open_cases excludes closed" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine
e = ForensicInvestigationEngine()
c1 = e.open_case(\"A\")
c2 = e.open_case(\"B\")
e.close_case(c1.case_id)
assert len(e.open_cases()) == 1
print(\"ok\")
' | grep -q ok"

run_test "cases_with_unverified_evidence finds those with <100% verified" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, EvidenceType
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
e.collect_evidence(c.case_id, EvidenceType.LOG_FILE, \"x\", \"/x\", \"a\")
assert c in e.cases_with_unverified_evidence()
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 10: phase59_score()
# -----------------------------------------------------------------------
echo ""
echo "GROUP 10: phase59_score()"

run_test "Empty engine → score=25.0" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine
e = ForensicInvestigationEngine()
assert e.phase59_score() == 25.0
print(\"ok\")
' | grep -q ok"

run_test "score in [0, 25]" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, EvidenceType
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
e.collect_evidence(c.case_id, EvidenceType.LOG_FILE, \"x\", \"/x\", \"a\", sha256_hash=\"h\")
sc = e.phase59_score()
assert 0.0 <= sc <= 25.0, sc
print(\"ok\")
' | grep -q ok"

run_test "forensic_score helper returns phase59_score" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, forensic_score
e = ForensicInvestigationEngine()
assert forensic_score(e) == e.phase59_score()
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 11: Summary and reporting
# -----------------------------------------------------------------------
echo ""
echo "GROUP 11: Summary and reporting"

run_test "summary() has all required keys" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine
e = ForensicInvestigationEngine()
s = e.summary()
for k in [\"total_cases\",\"open_cases\",\"closed_cases\",\"total_evidence\",
          \"verified_evidence\",\"unverified_evidence\",\"verification_pct\",
          \"critical_findings\",\"high_findings\",\"phase59_score\"]:
    assert k in s, f\"missing {k}\"
print(\"ok\")
' | grep -q ok"

run_test "case_report() has all required fields" \
    "py '
from security_ai.forensic_investigation_engine import ForensicInvestigationEngine, EvidenceType
e = ForensicInvestigationEngine()
c = e.open_case(\"Test\")
e.collect_evidence(c.case_id, EvidenceType.LOG_FILE, \"x\", \"/x\", \"a\")
r = e.case_report(c.case_id)
for k in [\"case_id\",\"title\",\"opened_at\",\"status\",\"total_evidence\",
          \"verified_evidence\",\"findings\",\"evidence\"]:
    assert k in r, f\"missing {k}\"
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 12: Ops script integration
# -----------------------------------------------------------------------
echo ""
echo "GROUP 12: Ops script integration"

OPS="${PROJECT_ROOT}/scripts/ops/phase-59-forensic-investigation.sh"
[[ -x "$OPS" ]] || chmod +x "$OPS"

run_test "Ops script exists" "[[ -f '$OPS' ]]"

run_test "demo mode exits 0" \
    "bash '$OPS' demo > /tmp/p59demo.out 2>&1"

run_test "demo outputs PHASE 59" \
    "grep -q 'PHASE 59' /tmp/p59demo.out"

run_test "demo shows Phase 59 Score" \
    "grep -q 'Phase 59 Score' /tmp/p59demo.out"

run_test "summary mode outputs valid JSON" \
    "bash '$OPS' summary > /tmp/p59sum.out 2>&1 && python3 -c 'import json; json.load(open(\"/tmp/p59sum.out\"))'"

run_test "summary JSON contains phase59_score" \
    "python3 -c 'import json; d=json.load(open(\"/tmp/p59sum.out\")); assert \"phase59_score\" in d'"

run_test "report mode exits 0" \
    "bash '$OPS' report > /tmp/p59rep.out 2>&1"

run_test "report outputs valid JSON" \
    "python3 -c 'import json; json.load(open(\"/tmp/p59rep.out\"))'"

# -----------------------------------------------------------------------
# GROUP 13: Phase 58 regression guard
# -----------------------------------------------------------------------
echo ""
echo "GROUP 13: Phase 58 regression guard"

run_test "Phase 58 integration suite still passes" \
    "timeout 150 bash '${PROJECT_ROOT}/scripts/ci/phase-58-integration-tests.sh' > /tmp/p59_reg58.log 2>&1"

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "============================================================"
echo "PHASE 59 TEST RESULTS"
echo "============================================================"
echo "PASS:  $PASS"
echo "FAIL:  $FAIL"
echo "TOTAL: $TOTAL"
echo "============================================================"

if [[ $FAIL -eq 0 ]]; then
    echo ""
    echo "✅  ALL TESTS PASSED — Phase 59 Forensic Investigation verified"
    exit 0
else
    echo ""
    echo "❌  SOME TESTS FAILED"
    exit 1
fi
