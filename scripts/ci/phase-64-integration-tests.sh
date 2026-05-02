#!/bin/bash
# @file phase-64-integration-tests.sh
# @description Integration tests for Phase 64 — Threat Hunt Orchestration Engine

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p64*.* /tmp/p64_reg63.log 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

PASS=0; FAIL=0; TOTAL=0

run_test() {
    local name="$1" cmd="$2"
    ((TOTAL++)) || true
    if eval "$cmd" > /tmp/p64_last.out 2>&1; then
        echo "  ✓ $name"; ((PASS++)) || true
    else
        echo "  ✗ $name"; ((FAIL++)) || true
        [[ -s /tmp/p64_last.out ]] && head -3 /tmp/p64_last.out | sed 's/^/    /'
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
echo "  PHASE 64 — THREAT HUNT ORCHESTRATION ENGINE"
echo "============================================================"
echo ""

# -----------------------------------------------------------------------
# GROUP 1: Module imports
# -----------------------------------------------------------------------
echo "GROUP 1: Module imports"

run_test "Engine importable" \
    "py 'from security_ai.threat_hunt_orchestration_engine import ThreatHuntOrchestrationEngine; print(\"ok\")' | grep -q ok"

run_test "IOCType has 8 values" \
    "py 'from security_ai.threat_hunt_orchestration_engine import IOCType; assert len(list(IOCType)) == 8; print(\"ok\")' | grep -q ok"

run_test "FindingType has 5 values" \
    "py 'from security_ai.threat_hunt_orchestration_engine import FindingType; assert len(list(FindingType)) == 5; print(\"ok\")' | grep -q ok"

run_test "HuntStatus has 5 values" \
    "py 'from security_ai.threat_hunt_orchestration_engine import HuntStatus; assert len(list(HuntStatus)) == 5; print(\"ok\")' | grep -q ok"

run_test "Helpers importable" \
    "py 'from security_ai.threat_hunt_orchestration_engine import make_hunt, hunt_orchestration_score; print(\"ok\")' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 2: Hunt creation
# -----------------------------------------------------------------------
echo ""
echo "GROUP 2: Hunt creation"

run_test "create_hunt returns HuntCampaign" \
    "py '
from security_ai.threat_hunt_orchestration_engine import ThreatHuntOrchestrationEngine
e = ThreatHuntOrchestrationEngine()
h = e.create_hunt(\"Test\", \"ioc_search\")
assert h.hunt_id.startswith(\"HNT-\")
print(\"ok\")
' | grep -q ok"

run_test "Hunt starts as PLANNED" \
    "py '
from security_ai.threat_hunt_orchestration_engine import ThreatHuntOrchestrationEngine, HuntStatus
e = ThreatHuntOrchestrationEngine()
h = e.create_hunt(\"T\", \"behavioral\")
assert h.status == HuntStatus.PLANNED
print(\"ok\")
' | grep -q ok"

run_test "start_hunt sets ACTIVE" \
    "py '
from security_ai.threat_hunt_orchestration_engine import ThreatHuntOrchestrationEngine, HuntStatus
e = ThreatHuntOrchestrationEngine()
h = e.create_hunt(\"T\", \"threat_actor\")
e.start_hunt(h.hunt_id)
assert h.status == HuntStatus.ACTIVE
print(\"ok\")
' | grep -q ok"

run_test "conclude_hunt sets CONCLUDED" \
    "py '
from security_ai.threat_hunt_orchestration_engine import ThreatHuntOrchestrationEngine, HuntStatus
e = ThreatHuntOrchestrationEngine()
h = e.create_hunt(\"T\", \"vulnerability\")
e.start_hunt(h.hunt_id)
e.conclude_hunt(h.hunt_id)
assert h.status == HuntStatus.CONCLUDED
print(\"ok\")
' | grep -q ok"

run_test "get_hunt retrieves by ID" \
    "py '
from security_ai.threat_hunt_orchestration_engine import ThreatHuntOrchestrationEngine
e = ThreatHuntOrchestrationEngine()
h1 = e.create_hunt(\"T\", \"ioc_search\")
h2 = e.get_hunt(h1.hunt_id)
assert h1.hunt_id == h2.hunt_id
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 3: IOC registration
# -----------------------------------------------------------------------
echo ""
echo "GROUP 3: IOC registration"

run_test "register_ioc creates IOC" \
    "py '
from security_ai.threat_hunt_orchestration_engine import ThreatHuntOrchestrationEngine, IOCType
e = ThreatHuntOrchestrationEngine()
ioc = e.register_ioc(IOCType.IP_ADDRESS, \"192.168.1.1\", \"source\")
assert ioc.ioc_id.startswith(\"IOC-\")
print(\"ok\")
' | grep -q ok"

run_test "record_ioc_detection increments count" \
    "py '
from security_ai.threat_hunt_orchestration_engine import ThreatHuntOrchestrationEngine, IOCType
e = ThreatHuntOrchestrationEngine()
ioc = e.register_ioc(IOCType.DOMAIN_NAME, \"test.com\", \"src\")
e.record_ioc_detection(ioc.ioc_id)
e.record_ioc_detection(ioc.ioc_id)
assert ioc.detection_count == 2
print(\"ok\")
' | grep -q ok"

run_test "iocs_by_type filters correctly" \
    "py '
from security_ai.threat_hunt_orchestration_engine import ThreatHuntOrchestrationEngine, IOCType
e = ThreatHuntOrchestrationEngine()
e.register_ioc(IOCType.IP_ADDRESS, \"1.1.1.1\", \"s\")
e.register_ioc(IOCType.IP_ADDRESS, \"2.2.2.2\", \"s\")
e.register_ioc(IOCType.DOMAIN_NAME, \"d.com\", \"s\")
ips = e.iocs_by_type(IOCType.IP_ADDRESS)
assert len(ips) == 2
print(\"ok\")
' | grep -q ok"

run_test "high_confidence_iocs filters correctly" \
    "py '
from security_ai.threat_hunt_orchestration_engine import ThreatHuntOrchestrationEngine, IOCType
e = ThreatHuntOrchestrationEngine()
e.register_ioc(IOCType.IP_ADDRESS, \"1.1.1.1\", \"s\", 95.0)
e.register_ioc(IOCType.IP_ADDRESS, \"2.2.2.2\", \"s\", 70.0)
e.register_ioc(IOCType.IP_ADDRESS, \"3.3.3.3\", \"s\", 88.0)
high = e.high_confidence_iocs(85.0)
assert len(high) == 2
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 4: Findings
# -----------------------------------------------------------------------
echo ""
echo "GROUP 4: Findings"

run_test "add_finding creates HuntFinding" \
    "py '
from security_ai.threat_hunt_orchestration_engine import ThreatHuntOrchestrationEngine, FindingType
e = ThreatHuntOrchestrationEngine()
h = e.create_hunt(\"T\", \"ioc_search\")
f = e.add_finding(h.hunt_id, FindingType.CONFIRMED_THREAT, \"Found\", \"critical\")
assert f.finding_id.startswith(\"FND-\")
print(\"ok\")
' | grep -q ok"

run_test "link_ioc_to_finding associates IOC" \
    "py '
from security_ai.threat_hunt_orchestration_engine import ThreatHuntOrchestrationEngine, IOCType, FindingType
e = ThreatHuntOrchestrationEngine()
h = e.create_hunt(\"T\", \"ioc_search\")
f = e.add_finding(h.hunt_id, FindingType.SUSPICIOUS_ACTIVITY, \"x\", \"high\")
ioc = e.register_ioc(IOCType.IP_ADDRESS, \"1.1.1.1\", \"s\")
e.link_ioc_to_finding(f.finding_id, ioc.ioc_id)
assert len(f.iocs_matched) == 1
print(\"ok\")
' | grep -q ok"

run_test "findings_by_type filters correctly" \
    "py '
from security_ai.threat_hunt_orchestration_engine import ThreatHuntOrchestrationEngine, FindingType
e = ThreatHuntOrchestrationEngine()
h = e.create_hunt(\"T\", \"ioc_search\")
e.add_finding(h.hunt_id, FindingType.CONFIRMED_THREAT, \"x\", \"c\")
e.add_finding(h.hunt_id, FindingType.CONFIRMED_THREAT, \"y\", \"h\")
e.add_finding(h.hunt_id, FindingType.FALSE_POSITIVE, \"z\", \"m\")
confirmed = e.findings_by_type(FindingType.CONFIRMED_THREAT)
assert len(confirmed) == 2
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 5: Threat campaigns
# -----------------------------------------------------------------------
echo ""
echo "GROUP 5: Threat campaigns"

run_test "identify_campaign creates ThreatCampaign" \
    "py '
from security_ai.threat_hunt_orchestration_engine import ThreatHuntOrchestrationEngine
e = ThreatHuntOrchestrationEngine()
c = e.identify_campaign(\"APT-29\", \"APT-29\")
assert c.campaign_id.startswith(\"CAM-\")
print(\"ok\")
' | grep -q ok"

run_test "link_campaign_to_hunt associates campaign" \
    "py '
from security_ai.threat_hunt_orchestration_engine import ThreatHuntOrchestrationEngine
e = ThreatHuntOrchestrationEngine()
h = e.create_hunt(\"T\", \"threat_actor\")
c = e.identify_campaign(\"APT\", \"actor\")
e.link_campaign_to_hunt(h.hunt_id, c.campaign_id)
assert len(h.threat_campaigns) == 1
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 6: Reporting
# -----------------------------------------------------------------------
echo ""
echo "GROUP 6: Reporting"

run_test "generate_report returns HuntReport" \
    "py '
from security_ai.threat_hunt_orchestration_engine import ThreatHuntOrchestrationEngine
e = ThreatHuntOrchestrationEngine()
r = e.generate_report()
assert r.report_id.startswith(\"HTR-\")
print(\"ok\")
' | grep -q ok"

run_test "phase64_score in [0, 25]" \
    "py '
from security_ai.threat_hunt_orchestration_engine import ThreatHuntOrchestrationEngine
e = ThreatHuntOrchestrationEngine()
sc = e.phase64_score()
assert 0 <= sc <= 25, sc
print(\"ok\")
' | grep -q ok"

run_test "summary has required keys" \
    "py '
from security_ai.threat_hunt_orchestration_engine import ThreatHuntOrchestrationEngine
e = ThreatHuntOrchestrationEngine()
s = e.summary()
for k in [\"total_hunts\",\"active_hunts\",\"total_findings\",\"confirmed_threats\",
          \"suspicious_activities\",\"total_iocs\",\"threat_campaigns\",\"phase64_score\"]:
    assert k in s, f\"missing {k}\"
print(\"ok\")
' | grep -q ok"

run_test "make_hunt helper" \
    "py '
from security_ai.threat_hunt_orchestration_engine import make_hunt
h = make_hunt()
assert h.hunt_id.startswith(\"HNT-\")
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 7: Ops script integration
# -----------------------------------------------------------------------
echo ""
echo "GROUP 7: Ops script integration"

OPS="${PROJECT_ROOT}/scripts/ops/phase-64-threat-hunt-orchestration.sh"
[[ -x "$OPS" ]] || chmod +x "$OPS"

run_test "Ops script exists" "[[ -f '$OPS' ]]"

run_test "demo mode exits 0" \
    "bash '$OPS' demo 2>/dev/null > /tmp/p64demo.out"

run_test "demo outputs PHASE 64" \
    "grep -q 'PHASE 64' /tmp/p64demo.out"

run_test "summary mode outputs valid JSON" \
    "bash '$OPS' summary 2>/dev/null > /tmp/p64sum.out && python3 -c 'import json; json.load(open(\"/tmp/p64sum.out\"))'"

run_test "report mode outputs valid JSON" \
    "bash '$OPS' report 2>/dev/null > /tmp/p64rep.out && python3 -c 'import json; json.load(open(\"/tmp/p64rep.out\"))'"

# -----------------------------------------------------------------------
# GROUP 8: Phase 63 regression guard
# -----------------------------------------------------------------------
echo ""
echo "GROUP 8: Phase 63 regression guard"

run_test "Phase 63 still passes" \
    "timeout 120 bash '${PROJECT_ROOT}/scripts/ci/phase-63-integration-tests.sh' > /tmp/p64_reg63.log 2>&1"

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "============================================================"
echo "PHASE 64 TEST RESULTS"
echo "============================================================"
echo "PASS:  $PASS"
echo "FAIL:  $FAIL"
echo "TOTAL: $TOTAL"
echo "============================================================"

if [[ $FAIL -eq 0 ]]; then
    echo ""
    echo "✅  ALL TESTS PASSED — Phase 64 Threat Hunt verified"
    exit 0
else
    echo ""
    echo "❌  SOME TESTS FAILED"
    exit 1
fi
