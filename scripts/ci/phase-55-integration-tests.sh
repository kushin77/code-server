#!/bin/bash
# @file phase-55-integration-tests.sh
# @description Integration tests for Phase 55 — Zero-Trust Policy Engine
# @since 2026-05-01

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p55*.* /tmp/p55_reg54.log 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

PASS=0; FAIL=0; TOTAL=0

run_test() {
    local name="$1" cmd="$2"
    ((TOTAL++)) || true
    if eval "$cmd" > /tmp/p55_last.out 2>&1; then
        echo "  ✓ $name"; ((PASS++)) || true
    else
        echo "  ✗ $name"; ((FAIL++)) || true
        [[ -s /tmp/p55_last.out ]] && head -5 /tmp/p55_last.out | sed 's/^/    /'
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
echo "  PHASE 55 — ZERO-TRUST POLICY ENGINE"
echo "============================================================"
echo ""

# -----------------------------------------------------------------------
# GROUP 1: Module imports
# -----------------------------------------------------------------------
echo "GROUP 1: Module imports"

run_test "ZeroTrustPolicyEngine importable" \
    "py 'from security_ai.zero_trust_policy_engine import ZeroTrustPolicyEngine; print(\"ok\")' | grep -q ok"

run_test "AccessRequest importable" \
    "py 'from security_ai.zero_trust_policy_engine import AccessRequest; print(\"ok\")' | grep -q ok"

run_test "AccessResult importable" \
    "py 'from security_ai.zero_trust_policy_engine import AccessResult; print(\"ok\")' | grep -q ok"

run_test "PolicyRule importable" \
    "py 'from security_ai.zero_trust_policy_engine import PolicyRule; print(\"ok\")' | grep -q ok"

run_test "DevicePosture importable" \
    "py 'from security_ai.zero_trust_policy_engine import DevicePosture; print(\"ok\")' | grep -q ok"

run_test "IdentityContext importable" \
    "py 'from security_ai.zero_trust_policy_engine import IdentityContext; print(\"ok\")' | grep -q ok"

run_test "TrustLevel has 5 values" \
    "py '
from security_ai.zero_trust_policy_engine import TrustLevel
assert len(list(TrustLevel)) == 5
print(\"ok\")
' | grep -q ok"

run_test "AccessDecision has 4 values" \
    "py '
from security_ai.zero_trust_policy_engine import AccessDecision
assert len(list(AccessDecision)) == 4
print(\"ok\")
' | grep -q ok"

run_test "PolicyAction has 5 values" \
    "py '
from security_ai.zero_trust_policy_engine import PolicyAction
assert len(list(PolicyAction)) == 5
print(\"ok\")
' | grep -q ok"

run_test "RiskFactor has 7 values" \
    "py '
from security_ai.zero_trust_policy_engine import RiskFactor
assert len(list(RiskFactor)) == 7
print(\"ok\")
' | grep -q ok"

run_test "make_request helper importable" \
    "py 'from security_ai.zero_trust_policy_engine import make_request; print(\"ok\")' | grep -q ok"

run_test "trust_score helper importable" \
    "py 'from security_ai.zero_trust_policy_engine import trust_score; print(\"ok\")' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 2: DevicePosture scoring
# -----------------------------------------------------------------------
echo ""
echo "GROUP 2: DevicePosture scoring"

run_test "All checks pass → posture_score=100" \
    "py '
from security_ai.zero_trust_policy_engine import DevicePosture
d = DevicePosture(\"dev1\")
assert d.posture_score() == 100
print(\"ok\")
' | grep -q ok"

run_test "All checks fail → posture_score=0" \
    "py '
from security_ai.zero_trust_policy_engine import DevicePosture
d = DevicePosture(\"dev1\", os_patched=False, disk_encrypted=False,
                  edr_present=False, certificate_valid=False, managed=False)
assert d.posture_score() == 0
print(\"ok\")
' | grep -q ok"

run_test "3 of 5 checks → posture_score=60" \
    "py '
from security_ai.zero_trust_policy_engine import DevicePosture
d = DevicePosture(\"dev1\", edr_present=False, certificate_valid=False)
assert d.posture_score() == 60
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 3: IdentityContext scoring
# -----------------------------------------------------------------------
echo ""
echo "GROUP 3: IdentityContext scoring"

run_test "MFA=True, strength=80, shared=False → identity_score=80" \
    "py '
from security_ai.zero_trust_policy_engine import IdentityContext
i = IdentityContext(\"user1\", mfa_verified=True, auth_strength=80)
assert i.identity_score() == 80
print(\"ok\")
' | grep -q ok"

run_test "MFA=False reduces identity_score by 30" \
    "py '
from security_ai.zero_trust_policy_engine import IdentityContext
i = IdentityContext(\"user1\", mfa_verified=False, auth_strength=80)
assert i.identity_score() == 50
print(\"ok\")
' | grep -q ok"

run_test "Shared account reduces identity_score by 20" \
    "py '
from security_ai.zero_trust_policy_engine import IdentityContext
i = IdentityContext(\"user1\", mfa_verified=True, auth_strength=80, shared_account=True)
assert i.identity_score() == 60
print(\"ok\")
' | grep -q ok"

run_test "identity_score() never exceeds 100" \
    "py '
from security_ai.zero_trust_policy_engine import IdentityContext
i = IdentityContext(\"user1\", auth_strength=110)
assert i.identity_score() == 100
print(\"ok\")
' | grep -q ok"

run_test "identity_score() never below 0" \
    "py '
from security_ai.zero_trust_policy_engine import IdentityContext
i = IdentityContext(\"user1\", mfa_verified=False, auth_strength=10, shared_account=True)
assert i.identity_score() >= 0
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 4: composite trust score and level
# -----------------------------------------------------------------------
echo ""
echo "GROUP 4: Composite trust score and TrustLevel"

run_test "Full posture + full identity → score=100, level=FULL" \
    "py '
from security_ai.zero_trust_policy_engine import make_request, TrustLevel
req = make_request(\"api/data\", mfa=True, managed=True, auth_strength=100)
assert req.composite_trust_score() == 100
assert req.trust_level == TrustLevel.FULL
print(\"ok\")
' | grep -q ok"

run_test "All checks fail → level=NONE" \
    "py '
from security_ai.zero_trust_policy_engine import (
    AccessRequest, DevicePosture, IdentityContext, TrustLevel
)
req = AccessRequest(
    request_id=\"r1\", resource=\"x\", action=\"read\",
    device=DevicePosture(\"d\", os_patched=False, disk_encrypted=False,
                         edr_present=False, certificate_valid=False, managed=False),
    identity=IdentityContext(\"u\", mfa_verified=False, auth_strength=0),
)
assert req.trust_level == TrustLevel.NONE
print(\"ok\")
' | grep -q ok"

run_test "composite_trust_score is in [0,100]" \
    "py '
from security_ai.zero_trust_policy_engine import make_request
req = make_request(\"api\", mfa=True, managed=True)
sc = req.composite_trust_score()
assert 0 <= sc <= 100, sc
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 5: PolicyRule matching
# -----------------------------------------------------------------------
echo ""
echo "GROUP 5: PolicyRule matching"

run_test "Exact resource match returns True" \
    "py '
from security_ai.zero_trust_policy_engine import PolicyRule, TrustLevel, PolicyAction
r = PolicyRule(\"r1\",\"t\",\"api/data\",TrustLevel.ELEVATED,PolicyAction.ALLOW)
assert r.matches(\"api/data\")
print(\"ok\")
' | grep -q ok"

run_test "Wildcard rule matches any resource" \
    "py '
from security_ai.zero_trust_policy_engine import PolicyRule, TrustLevel, PolicyAction
r = PolicyRule(\"r1\",\"t\",\"*\",TrustLevel.MINIMAL,PolicyAction.ALLOW)
assert r.matches(\"anything\")
print(\"ok\")
' | grep -q ok"

run_test "Non-matching resource returns False" \
    "py '
from security_ai.zero_trust_policy_engine import PolicyRule, TrustLevel, PolicyAction
r = PolicyRule(\"r1\",\"t\",\"admin/panel\",TrustLevel.FULL,PolicyAction.ALLOW)
assert not r.matches(\"public/docs\")
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 6: Policy evaluation
# -----------------------------------------------------------------------
echo ""
echo "GROUP 6: Policy evaluation"

run_test "High-trust request to ALLOW rule → ALLOW" \
    "py '
from security_ai.zero_trust_policy_engine import (
    ZeroTrustPolicyEngine, PolicyRule, TrustLevel, PolicyAction, AccessDecision, make_request
)
engine = ZeroTrustPolicyEngine()
engine.add_rule(PolicyRule(\"r1\",\"allow all\",\"*\",TrustLevel.MINIMAL,PolicyAction.ALLOW))
req = make_request(\"api/data\", mfa=True, managed=True, auth_strength=90, source_ip=\"10.0.0.1\")
res = engine.evaluate(req)
assert res.decision == AccessDecision.ALLOW, res.decision
print(\"ok\")
' | grep -q ok"

run_test "No matching rule → default DENY" \
    "py '
from security_ai.zero_trust_policy_engine import (
    ZeroTrustPolicyEngine, PolicyRule, TrustLevel, PolicyAction, AccessDecision, make_request
)
engine = ZeroTrustPolicyEngine()
engine.add_rule(PolicyRule(\"r1\",\"admin\",\"admin/*\",TrustLevel.FULL,PolicyAction.ALLOW))
engine.set_default_action(PolicyAction.DENY)
req = make_request(\"other/resource\", mfa=True, managed=True, auth_strength=90)
res = engine.evaluate(req)
assert res.decision == AccessDecision.DENY, res.decision
print(\"ok\")
' | grep -q ok"

run_test "Insufficient trust for rule → default action" \
    "py '
from security_ai.zero_trust_policy_engine import (
    ZeroTrustPolicyEngine, PolicyRule, TrustLevel, PolicyAction, AccessDecision, make_request
)
engine = ZeroTrustPolicyEngine()
engine.add_rule(PolicyRule(\"r1\",\"need full\",\"*\",TrustLevel.FULL,PolicyAction.ALLOW))
engine.set_default_action(PolicyAction.DENY)
# low trust
req = make_request(\"api/data\", mfa=False, managed=False, auth_strength=10)
res = engine.evaluate(req)
assert res.decision == AccessDecision.DENY, res.decision
print(\"ok\")
' | grep -q ok"

run_test "QUARANTINE action → QUARANTINE decision" \
    "py '
from security_ai.zero_trust_policy_engine import (
    ZeroTrustPolicyEngine, PolicyRule, TrustLevel, PolicyAction, AccessDecision, make_request
)
engine = ZeroTrustPolicyEngine()
engine.add_rule(PolicyRule(\"r1\",\"quarantine\",\"*\",TrustLevel.MINIMAL,PolicyAction.QUARANTINE))
req = make_request(\"api/data\", mfa=True, managed=True, auth_strength=80, source_ip=\"10.0.0.1\")
res = engine.evaluate(req)
assert res.decision == AccessDecision.QUARANTINE, res.decision
print(\"ok\")
' | grep -q ok"

run_test "AccessResult.allowed True for ALLOW and QUARANTINE" \
    "py '
from security_ai.zero_trust_policy_engine import (
    ZeroTrustPolicyEngine, PolicyRule, TrustLevel, PolicyAction, make_request
)
engine = ZeroTrustPolicyEngine()
engine.add_rule(PolicyRule(\"r1\",\"q\",\"*\",TrustLevel.MINIMAL,PolicyAction.QUARANTINE))
res = engine.evaluate(make_request(\"x\", mfa=True, managed=True, auth_strength=80, source_ip=\"10.0.0.1\"))
assert res.allowed is True
print(\"ok\")
' | grep -q ok"

run_test "AccessResult.allowed False for DENY" \
    "py '
from security_ai.zero_trust_policy_engine import ZeroTrustPolicyEngine, PolicyAction, make_request
engine = ZeroTrustPolicyEngine()
engine.set_default_action(PolicyAction.DENY)
res = engine.evaluate(make_request(\"x\"))
assert res.allowed is False
print(\"ok\")
' | grep -q ok"

run_test "evaluate_batch returns list of results" \
    "py '
from security_ai.zero_trust_policy_engine import ZeroTrustPolicyEngine, make_request
engine = ZeroTrustPolicyEngine()
reqs = [make_request(f\"r{i}\") for i in range(4)]
results = engine.evaluate_batch(reqs)
assert len(results) == 4
print(\"ok\")
' | grep -q ok"

run_test "Results logged to audit_log" \
    "py '
from security_ai.zero_trust_policy_engine import ZeroTrustPolicyEngine, make_request
engine = ZeroTrustPolicyEngine()
for _ in range(3):
    engine.evaluate(make_request(\"api\"))
assert len(engine.audit_log) == 3
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 7: Risk factors
# -----------------------------------------------------------------------
echo ""
echo "GROUP 7: Risk factor detection"

run_test "Unmanaged device → UNKNOWN_DEVICE risk factor" \
    "py '
from security_ai.zero_trust_policy_engine import (
    ZeroTrustPolicyEngine, make_request, RiskFactor
)
engine = ZeroTrustPolicyEngine()
res = engine.evaluate(make_request(\"api\", managed=False))
assert RiskFactor.UNKNOWN_DEVICE in res.risk_factors
print(\"ok\")
' | grep -q ok"

run_test "No MFA → WEAK_AUTH risk factor" \
    "py '
from security_ai.zero_trust_policy_engine import (
    ZeroTrustPolicyEngine, make_request, RiskFactor
)
engine = ZeroTrustPolicyEngine()
res = engine.evaluate(make_request(\"api\", mfa=False))
assert RiskFactor.WEAK_AUTH in res.risk_factors
print(\"ok\")
' | grep -q ok"

run_test "Clean request → no risk factors" \
    "py '
from security_ai.zero_trust_policy_engine import (
    ZeroTrustPolicyEngine, make_request
)
engine = ZeroTrustPolicyEngine()
res = engine.evaluate(make_request(\"api\", mfa=True, managed=True, source_ip=\"10.0.0.1\"))
assert res.risk_factors == [], res.risk_factors
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 8: Scoring
# -----------------------------------------------------------------------
echo ""
echo "GROUP 8: phase55_score()"

run_test "Empty engine → score=25.0" \
    "py '
from security_ai.zero_trust_policy_engine import ZeroTrustPolicyEngine, trust_score
engine = ZeroTrustPolicyEngine()
assert trust_score(engine) == 25.0
print(\"ok\")
' | grep -q ok"

run_test "All ALLOW → score=25.0" \
    "py '
from security_ai.zero_trust_policy_engine import (
    ZeroTrustPolicyEngine, PolicyRule, TrustLevel, PolicyAction, make_request, trust_score
)
engine = ZeroTrustPolicyEngine()
engine.add_rule(PolicyRule(\"r1\",\"allow\",\"*\",TrustLevel.MINIMAL,PolicyAction.ALLOW))
for _ in range(5):
    engine.evaluate(make_request(\"api\", mfa=True, managed=True, auth_strength=90, source_ip=\"10.0.0.1\"))
assert trust_score(engine) == 25.0, trust_score(engine)
print(\"ok\")
' | grep -q ok"

run_test "All DENY → score=0.0" \
    "py '
from security_ai.zero_trust_policy_engine import ZeroTrustPolicyEngine, PolicyAction, make_request, trust_score
engine = ZeroTrustPolicyEngine()
engine.set_default_action(PolicyAction.DENY)
for _ in range(4):
    engine.evaluate(make_request(\"api\"))
assert trust_score(engine) == 0.0, trust_score(engine)
print(\"ok\")
' | grep -q ok"

run_test "Mixed ALLOW/DENY → score in (0, 25)" \
    "py '
from security_ai.zero_trust_policy_engine import (
    ZeroTrustPolicyEngine, PolicyRule, TrustLevel, PolicyAction, make_request, trust_score
)
engine = ZeroTrustPolicyEngine()
engine.add_rule(PolicyRule(\"r1\",\"allow matched\",\"good/*\",TrustLevel.MINIMAL,PolicyAction.ALLOW))
engine.set_default_action(PolicyAction.DENY)
engine.evaluate(make_request(\"good/data\", mfa=True, managed=True, auth_strength=90, source_ip=\"10.0.0.1\"))
engine.evaluate(make_request(\"bad/resource\"))
sc = trust_score(engine)
assert 0.0 < sc < 25.0, sc
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 9: summary() and generate_report()
# -----------------------------------------------------------------------
echo ""
echo "GROUP 9: summary() and generate_report()"

run_test "summary() contains all required keys" \
    "py '
from security_ai.zero_trust_policy_engine import ZeroTrustPolicyEngine
engine = ZeroTrustPolicyEngine()
s = engine.summary()
for k in [\"total_evaluations\",\"decisions\",\"trust_levels\",\"registered_rules\",\"phase55_score\"]:
    assert k in s, f\"missing {k}\"
print(\"ok\")
' | grep -q ok"

run_test "generate_report() has required fields" \
    "py '
from security_ai.zero_trust_policy_engine import ZeroTrustPolicyEngine, make_request
engine = ZeroTrustPolicyEngine()
res = engine.evaluate(make_request(\"api\"))
r = engine.generate_report(res)
for k in [\"result_id\",\"resource\",\"decision\",\"trust_score\",\"trust_level\",
          \"risk_factors\",\"allowed\",\"reason\"]:
    assert k in r, f\"missing {k}\"
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 10: Ops script integration
# -----------------------------------------------------------------------
echo ""
echo "GROUP 10: Ops script integration"

OPS="${PROJECT_ROOT}/scripts/ops/phase-55-zero-trust-policy-engine.sh"
[[ -x "$OPS" ]] || chmod +x "$OPS"

run_test "Ops script exists" "[[ -f '$OPS' ]]"

run_test "demo mode exits 0" \
    "bash '$OPS' demo > /tmp/p55demo.out 2>&1"

run_test "demo outputs PHASE 55" \
    "grep -q 'PHASE 55' /tmp/p55demo.out"

run_test "demo shows Phase 55 Score" \
    "grep -q 'Phase 55 Score' /tmp/p55demo.out"

run_test "summary mode outputs valid JSON" \
    "bash '$OPS' summary > /tmp/p55sum.out 2>&1 && python3 -c 'import json; json.load(open(\"/tmp/p55sum.out\"))'"

run_test "summary contains phase55_score" \
    "python3 -c 'import json; d=json.load(open(\"/tmp/p55sum.out\")); assert \"phase55_score\" in d'"

run_test "check mode exits 0" \
    "bash '$OPS' check api/data > /tmp/p55check.out 2>&1"

run_test "check mode outputs valid JSON" \
    "python3 -c 'import json; json.load(open(\"/tmp/p55check.out\"))'"

# -----------------------------------------------------------------------
# GROUP 11: Phase 54 regression guard
# -----------------------------------------------------------------------
echo ""
echo "GROUP 11: Phase 54 regression guard"

run_test "Phase 54 integration suite still passes" \
    "timeout 150 bash '${PROJECT_ROOT}/scripts/ci/phase-54-integration-tests.sh' > /tmp/p55_reg54.log 2>&1"

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "============================================================"
echo "PHASE 55 TEST RESULTS"
echo "============================================================"
echo "PASS:  $PASS"
echo "FAIL:  $FAIL"
echo "TOTAL: $TOTAL"
echo "============================================================"

if [[ $FAIL -eq 0 ]]; then
    echo ""
    echo "✅  ALL TESTS PASSED — Phase 55 Zero-Trust Policy Engine verified"
    exit 0
else
    echo ""
    echo "❌  SOME TESTS FAILED"
    exit 1
fi
