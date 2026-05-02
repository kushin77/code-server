#!/bin/bash
# @file phase-62-integration-tests.sh
# @description Integration tests for Phase 62 — Security Policy Automation Engine
# @since 2026-05-01

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p62*.* /tmp/p62_reg61.log 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

PASS=0; FAIL=0; TOTAL=0

run_test() {
    local name="$1" cmd="$2"
    ((TOTAL++)) || true
    if eval "$cmd" > /tmp/p62_last.out 2>&1; then
        echo "  ✓ $name"; ((PASS++)) || true
    else
        echo "  ✗ $name"; ((FAIL++)) || true
        [[ -s /tmp/p62_last.out ]] && head -5 /tmp/p62_last.out | sed 's/^/    /'
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
echo "  PHASE 62 — SECURITY POLICY AUTOMATION ENGINE"
echo "============================================================"
echo ""

# -----------------------------------------------------------------------
# GROUP 1: Module imports
# -----------------------------------------------------------------------
echo "GROUP 1: Module imports"

run_test "SecurityPolicyAutomationEngine importable" \
    "py 'from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine; print(\"ok\")' | grep -q ok"

run_test "SecurityPolicy importable" \
    "py 'from security_ai.security_policy_automation_engine import SecurityPolicy; print(\"ok\")' | grep -q ok"

run_test "PolicyType has 8 values" \
    "py '
from security_ai.security_policy_automation_engine import PolicyType
assert len(list(PolicyType)) == 8
print(\"ok\")
' | grep -q ok"

run_test "PolicyStatus has 5 values" \
    "py '
from security_ai.security_policy_automation_engine import PolicyStatus
assert len(list(PolicyStatus)) == 5
print(\"ok\")
' | grep -q ok"

run_test "DeploymentStatus has 6 values" \
    "py '
from security_ai.security_policy_automation_engine import DeploymentStatus
assert len(list(DeploymentStatus)) == 6
print(\"ok\")
' | grep -q ok"

run_test "ViolationType has 7 values" \
    "py '
from security_ai.security_policy_automation_engine import ViolationType
assert len(list(ViolationType)) == 7
print(\"ok\")
' | grep -q ok"

run_test "Helpers importable" \
    "py 'from security_ai.security_policy_automation_engine import make_policy, policy_compliance_score; print(\"ok\")' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 2: Policy creation and retrieval
# -----------------------------------------------------------------------
echo ""
echo "GROUP 2: Policy creation and retrieval"

run_test "create_policy returns SecurityPolicy" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"Test\", PolicyType.ACCESS_CONTROL, \"Desc\")
assert p.policy_id.startswith(\"POL-\")
print(\"ok\")
' | grep -q ok"

run_test "Policy version starts at 1.0.0" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"T\", PolicyType.DATA_PROTECTION, \"D\")
assert p.version == \"1.0.0\"
print(\"ok\")
' | grep -q ok"

run_test "Policy status starts as DRAFT" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType, PolicyStatus
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"T\", PolicyType.NETWORK_SECURITY, \"D\")
assert p.status == PolicyStatus.DRAFT
print(\"ok\")
' | grep -q ok"

run_test "get_policy retrieves by ID" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType
e = SecurityPolicyAutomationEngine()
p1 = e.create_policy(\"T\", PolicyType.INCIDENT_RESPONSE, \"D\")
p2 = e.get_policy(p1.policy_id)
assert p1.policy_id == p2.policy_id
print(\"ok\")
' | grep -q ok"

run_test "get_policy raises KeyError for unknown" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine
e = SecurityPolicyAutomationEngine()
try:
    e.get_policy(\"NOTREAL\")
    assert False
except KeyError:
    pass
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 3: Policy rules
# -----------------------------------------------------------------------
echo ""
echo "GROUP 3: Policy rules"

run_test "add_rule_to_policy creates rule" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"T\", PolicyType.CRYPTOGRAPHY, \"D\")
r = e.add_rule_to_policy(p.policy_id, \"Rule\", \"allow\", {\"x\": \"y\"})
assert r.rule_id.startswith(\"RULE-\")
print(\"ok\")
' | grep -q ok"

run_test "Rules added to policy list" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"T\", PolicyType.AUTHENTICATION, \"D\")
e.add_rule_to_policy(p.policy_id, \"R1\", \"allow\", {})
e.add_rule_to_policy(p.policy_id, \"R2\", \"deny\", {})
assert len(p.rules) == 2
print(\"ok\")
' | grep -q ok"

run_test "add_rule for unknown policy raises KeyError" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine
e = SecurityPolicyAutomationEngine()
try:
    e.add_rule_to_policy(\"NOTREAL\", \"R\", \"allow\", {})
    assert False
except KeyError:
    pass
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 4: Policy deployment
# -----------------------------------------------------------------------
echo ""
echo "GROUP 4: Policy deployment"

run_test "deploy_policy creates PolicyDeployment" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType, DeploymentStatus
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"T\", PolicyType.AUDIT_LOGGING, \"D\")
d = e.deploy_policy(p.policy_id)
assert d.deployment_id.startswith(\"DEP-\")
print(\"ok\")
' | grep -q ok"

run_test "Deployment starts as IN_PROGRESS" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType, DeploymentStatus
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"T\", PolicyType.COMPLIANCE, \"D\")
d = e.deploy_policy(p.policy_id)
assert d.status == DeploymentStatus.IN_PROGRESS
print(\"ok\")
' | grep -q ok"

run_test "complete_deployment sets SUCCESS for full success" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType, DeploymentStatus
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"T\", PolicyType.ACCESS_CONTROL, \"D\")
d = e.deploy_policy(p.policy_id)
e.complete_deployment(d.deployment_id, affected_resources=10, successful_resources=10)
assert d.status == DeploymentStatus.SUCCESS
print(\"ok\")
' | grep -q ok"

run_test "complete_deployment sets PARTIAL for partial success" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType, DeploymentStatus
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"T\", PolicyType.DATA_PROTECTION, \"D\")
d = e.deploy_policy(p.policy_id)
e.complete_deployment(d.deployment_id, affected_resources=10, successful_resources=5)
assert d.status == DeploymentStatus.PARTIAL
print(\"ok\")
' | grep -q ok"

run_test "complete_deployment updates policy status" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType, PolicyStatus
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"T\", PolicyType.NETWORK_SECURITY, \"D\")
d = e.deploy_policy(p.policy_id)
e.complete_deployment(d.deployment_id, 5, 5)
p_updated = e.get_policy(p.policy_id)
assert p_updated.status == PolicyStatus.DEPLOYED
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 5: Policy violations
# -----------------------------------------------------------------------
echo ""
echo "GROUP 5: Policy violations"

run_test "record_violation creates PolicyViolation" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType, ViolationType
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"T\", PolicyType.INCIDENT_RESPONSE, \"D\")
v = e.record_violation(p.policy_id, ViolationType.UNAUTHORIZED_ACCESS, \"critical\", \"res1\", \"desc\")
assert v.violation_id.startswith(\"VIO-\")
print(\"ok\")
' | grep -q ok"

run_test "Violation starts unresolved" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType, ViolationType
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"T\", PolicyType.CRYPTOGRAPHY, \"D\")
v = e.record_violation(p.policy_id, ViolationType.DATA_EXPOSURE, \"high\", \"res\", \"d\")
assert not v.resolved
print(\"ok\")
' | grep -q ok"

run_test "resolve_violation marks resolved" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType, ViolationType
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"T\", PolicyType.AUTHENTICATION, \"D\")
v = e.record_violation(p.policy_id, ViolationType.MISSING_ENCRYPTION, \"medium\", \"res\", \"d\")
e.resolve_violation(v.violation_id, \"Fixed\")
assert v.resolved
print(\"ok\")
' | grep -q ok"

run_test "violations_by_severity filters correctly" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType, ViolationType
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"T\", PolicyType.AUDIT_LOGGING, \"D\")
e.record_violation(p.policy_id, ViolationType.COMPLIANCE_BREACH, \"critical\", \"r1\", \"d\")
e.record_violation(p.policy_id, ViolationType.AUDIT_FAILURE, \"high\", \"r2\", \"d\")
critical = e.violations_by_severity(\"critical\")
assert len(critical) == 1
print(\"ok\")
' | grep -q ok"

run_test "unresolved_violations returns only unresolved" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType, ViolationType
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"T\", PolicyType.COMPLIANCE, \"D\")
v1 = e.record_violation(p.policy_id, ViolationType.CONFIG_DRIFT, \"low\", \"r1\", \"d\")
v2 = e.record_violation(p.policy_id, ViolationType.AUTHENTICATION_FAILURE, \"high\", \"r2\", \"d\")
e.resolve_violation(v1.violation_id)
unres = e.unresolved_violations()
assert len(unres) == 1
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 6: Drift detection and remediation
# -----------------------------------------------------------------------
echo ""
echo "GROUP 6: Drift detection and remediation"

run_test "detect_drift creates PolicyDriftEvent" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"T\", PolicyType.ACCESS_CONTROL, \"D\")
d = e.detect_drift(p.policy_id, \"res1\", {\"x\": \"1\"}, {\"x\": \"2\"})
assert d.drift_id.startswith(\"DFT-\")
print(\"ok\")
' | grep -q ok"

run_test "Drift starts unresolved" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"T\", PolicyType.DATA_PROTECTION, \"D\")
d = e.detect_drift(p.policy_id, \"r\", {}, {})
assert not d.remediated
print(\"ok\")
' | grep -q ok"

run_test "remediate_drift marks remediated" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"T\", PolicyType.NETWORK_SECURITY, \"D\")
d = e.detect_drift(p.policy_id, \"r\", {}, {})
e.remediate_drift(d.drift_id)
assert d.remediated
print(\"ok\")
' | grep -q ok"

run_test "active_drift_events returns unresolved only" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"T\", PolicyType.INCIDENT_RESPONSE, \"D\")
d1 = e.detect_drift(p.policy_id, \"r1\", {}, {})
d2 = e.detect_drift(p.policy_id, \"r2\", {}, {})
e.remediate_drift(d1.drift_id)
active = e.active_drift_events()
assert len(active) == 1
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 7: Queries
# -----------------------------------------------------------------------
echo ""
echo "GROUP 7: Queries"

run_test "policies_by_type filters correctly" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType
e = SecurityPolicyAutomationEngine()
e.create_policy(\"P1\", PolicyType.ACCESS_CONTROL, \"d\")
e.create_policy(\"P2\", PolicyType.ACCESS_CONTROL, \"d\")
e.create_policy(\"P3\", PolicyType.DATA_PROTECTION, \"d\")
ac = e.policies_by_type(PolicyType.ACCESS_CONTROL)
assert len(ac) == 2
print(\"ok\")
' | grep -q ok"

run_test "policies_by_status filters correctly" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType, PolicyStatus
e = SecurityPolicyAutomationEngine()
p1 = e.create_policy(\"P1\", PolicyType.ACCESS_CONTROL, \"d\")
p2 = e.create_policy(\"P2\", PolicyType.DATA_PROTECTION, \"d\")
d = e.deploy_policy(p1.policy_id)
e.complete_deployment(d.deployment_id, 5, 5)
deployed = e.policies_by_status(PolicyStatus.DEPLOYED)
assert len(deployed) == 1
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 8: Reporting and scoring
# -----------------------------------------------------------------------
echo ""
echo "GROUP 8: Reporting and scoring"

run_test "generate_report returns PolicyReport" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType
e = SecurityPolicyAutomationEngine()
r = e.generate_report()
assert r.report_id.startswith(\"RPT-\")
print(\"ok\")
' | grep -q ok"

run_test "phase62_score in [0, 25]" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, PolicyType
e = SecurityPolicyAutomationEngine()
p = e.create_policy(\"T\", PolicyType.ACCESS_CONTROL, \"d\")
d = e.deploy_policy(p.policy_id)
e.complete_deployment(d.deployment_id, 5, 5)
sc = e.phase62_score()
assert 0 <= sc <= 25, sc
print(\"ok\")
' | grep -q ok"

run_test "Empty engine score is reasonable" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine
e = SecurityPolicyAutomationEngine()
sc = e.phase62_score()
assert 0 <= sc <= 25
print(\"ok\")
' | grep -q ok"

run_test "policy_compliance_score helper" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine, policy_compliance_score
e = SecurityPolicyAutomationEngine()
assert policy_compliance_score(e) == e.phase62_score()
print(\"ok\")
' | grep -q ok"

run_test "summary has required keys" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine
e = SecurityPolicyAutomationEngine()
s = e.summary()
for k in [\"total_policies\",\"policy_types\",\"policy_statuses\",\"total_deployments\",
          \"successful_deployments\",\"unresolved_violations\",\"critical_violations\",
          \"active_drift_events\",\"phase62_score\"]:
    assert k in s, f\"missing {k}\"
print(\"ok\")
' | grep -q ok"

run_test "Report to_dict includes phase62_score" \
    "py '
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine
e = SecurityPolicyAutomationEngine()
r = e.generate_report()
d = r.to_dict()
assert \"phase62_score\" in d
print(\"ok\")
' | grep -q ok"

run_test "make_policy helper" \
    "py '
from security_ai.security_policy_automation_engine import make_policy
p = make_policy()
assert p.policy_id.startswith(\"POL-\")
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 9: Ops script integration
# -----------------------------------------------------------------------
echo ""
echo "GROUP 9: Ops script integration"

OPS="${PROJECT_ROOT}/scripts/ops/phase-62-security-policy-automation.sh"
[[ -x "$OPS" ]] || chmod +x "$OPS"

run_test "Ops script exists" "[[ -f '$OPS' ]]"

run_test "demo mode exits 0" \
    "bash '$OPS' demo > /tmp/p62demo.out 2>&1"

run_test "demo outputs PHASE 62" \
    "grep -q 'PHASE 62' /tmp/p62demo.out"

run_test "demo shows Phase 62 Score" \
    "grep -q 'Phase 62 Score' /tmp/p62demo.out"

run_test "summary mode outputs valid JSON" \
    "bash '$OPS' summary 2>/dev/null > /tmp/p62sum.out && python3 -c 'import json; json.load(open(\"/tmp/p62sum.out\"))'"

run_test "summary JSON contains phase62_score" \
    "python3 -c 'import json; d=json.load(open(\"/tmp/p62sum.out\")); assert \"phase62_score\" in d or \"report\" in d'"

run_test "report mode outputs valid JSON" \
    "bash '$OPS' report 2>/dev/null > /tmp/p62rep.out && python3 -c 'import json; json.load(open(\"/tmp/p62rep.out\"))'"

# -----------------------------------------------------------------------
# GROUP 10: Phase 61 regression guard
# -----------------------------------------------------------------------
echo ""
echo "GROUP 10: Phase 61 regression guard"

run_test "Phase 61 integration suite still passes" \
    "timeout 120 bash '${PROJECT_ROOT}/scripts/ci/phase-61-integration-tests.sh' > /tmp/p62_reg61.log 2>&1"

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "============================================================"
echo "PHASE 62 TEST RESULTS"
echo "============================================================"
echo "PASS:  $PASS"
echo "FAIL:  $FAIL"
echo "TOTAL: $TOTAL"
echo "============================================================"

if [[ $FAIL -eq 0 ]]; then
    echo ""
    echo "✅  ALL TESTS PASSED — Phase 62 Security Policy Automation verified"
    exit 0
else
    echo ""
    echo "❌  SOME TESTS FAILED"
    exit 1
fi
