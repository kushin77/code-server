#!/bin/bash
# @file phase-55-zero-trust-policy-engine.sh
# @description Phase 55 — Zero-Trust Policy Engine
# @since 2026-05-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'rm -f /tmp/p55*.tmp 2>/dev/null || true' EXIT
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR

MODE="${1:-demo}"

cmd_demo() {
    log_info "PHASE 55: Zero-Trust Policy Engine" >&2
    "$PYTHON_CMD" <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.zero_trust_policy_engine import (
    ZeroTrustPolicyEngine, PolicyRule, TrustLevel, PolicyAction, make_request
)

engine = ZeroTrustPolicyEngine()

# Register rules
engine.add_rule(PolicyRule("r1","Require FULL for admin","admin/*",TrustLevel.FULL,PolicyAction.ALLOW))
engine.add_rule(PolicyRule("r2","Require ELEVATED for data","data/*",TrustLevel.ELEVATED,PolicyAction.ALLOW))
engine.add_rule(PolicyRule("r3","Allow minimal for public","public/*",TrustLevel.MINIMAL,PolicyAction.ALLOW))
engine.set_default_action(PolicyAction.DENY)

print("=== PHASE 55: Zero-Trust Policy Engine Dashboard ===")
print()

# Evaluate a mix of requests
scenarios = [
    ("Trusted admin",     make_request("admin/settings", mfa=True, managed=True, auth_strength=95)),
    ("Low-trust admin",   make_request("admin/settings", mfa=False, managed=False, auth_strength=40)),
    ("Good data access",  make_request("data/reports",   mfa=True, managed=True, auth_strength=80)),
    ("Public access",     make_request("public/docs",    mfa=False, managed=False, auth_strength=20)),
    ("Unknown resource",  make_request("secret/vault",   mfa=True, managed=True, auth_strength=85)),
]

for label, req in scenarios:
    res = engine.evaluate(req)
    print(f"  {label:25s}  trust={res.trust_score:3d}  [{res.decision.value.upper():10s}]  {res.reason[:40]}")

print()
s = engine.summary()
print(f"  Total Evaluations:  {s['total_evaluations']}")
print(f"  Decisions:          {s['decisions']}")
print(f"  Phase 55 Score:     {s['phase55_score']:.2f}/25")
PYEOF
}

cmd_summary() {
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.zero_trust_policy_engine import ZeroTrustPolicyEngine, make_request
engine = ZeroTrustPolicyEngine()
for mfa, managed in [(True,True),(True,False),(False,False)]:
    engine.evaluate(make_request("api/data", mfa=mfa, managed=managed))
print(json.dumps(engine.summary(), indent=2))
PYEOF
}

cmd_check() {
    local resource="${2:-api/data}"
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.zero_trust_policy_engine import (
    ZeroTrustPolicyEngine, PolicyRule, TrustLevel, PolicyAction, make_request
)
engine = ZeroTrustPolicyEngine()
engine.add_rule(PolicyRule("r1","Default allow","*",TrustLevel.ELEVATED,PolicyAction.ALLOW))
req = make_request("${resource}", mfa=True, managed=True, auth_strength=80)
res = engine.evaluate(req)
print(json.dumps(engine.generate_report(res), indent=2))
PYEOF
}

case "$MODE" in
    demo)    cmd_demo ;;
    summary) cmd_summary ;;
    check)   cmd_check "$@" ;;
    *)
        echo "Usage: $0 [demo|summary|check [resource]]"
        exit 1
        ;;
esac
