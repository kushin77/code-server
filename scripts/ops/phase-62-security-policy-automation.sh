#!/bin/bash
# @file phase-62-security-policy-automation.sh
# @description Operational handler for Phase 62 — Security Policy Automation Engine
# @usage ./scripts/ops/phase-62-security-policy-automation.sh [demo | summary | report]

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*"; }

trap 'rm -f /tmp/p62*.tmp 2>/dev/null || true' EXIT

MODE="${1:-summary}"

case "$MODE" in
demo)
    log_info "Running Phase 62 Policy Automation — Demo Mode"
    echo ""
    echo "============================================================"
    echo "  PHASE 62 — SECURITY POLICY AUTOMATION ENGINE"
    echo "============================================================"
    echo ""
    
    "$PYTHON_CMD" <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.security_policy_automation_engine import (
    SecurityPolicyAutomationEngine, PolicyType, PolicyStatus, ViolationType, DeploymentStatus
)

engine = SecurityPolicyAutomationEngine()

# Create policies
for pt in [PolicyType.ACCESS_CONTROL, PolicyType.DATA_PROTECTION]:
    p = engine.create_policy(f"Policy: {pt.value}", pt, f"Automated {pt.value} policy")
    engine.add_rule_to_policy(p.policy_id, "Default Rule", "allow", {"default": "true"})

# Deploy policies
for p in engine.policies.values():
    dep = engine.deploy_policy(p.policy_id, "production")
    engine.complete_deployment(dep.deployment_id, affected_resources=10, successful_resources=9)

# Record some violations
for v in engine.violations_by_severity("critical"):
    pass
for p in list(engine.policies.values())[:1]:
    engine.record_violation(p.policy_id, ViolationType.UNAUTHORIZED_ACCESS, "critical", "resource-1", "Unauthorized access detected")
    engine.record_violation(p.policy_id, ViolationType.CONFIG_DRIFT, "high", "resource-2", "Configuration drift detected")

# Detect drift
for p in list(engine.policies.values())[:1]:
    engine.detect_drift(p.policy_id, "resource-3", {"encryption": "aes256"}, {"encryption": "none"})

summary = engine.summary()
report = engine.generate_report()

print("")
print("  Policy Automation Status:")
print(f"    • Total Policies: {summary['total_policies']}")
print(f"    • Deployed Policies: {engine.generate_report().deployed_policies}")
print(f"    • Total Deployments: {summary['total_deployments']}")
print(f"    • Unresolved Violations: {summary['unresolved_violations']}")
print(f"    • Critical Violations: {summary['critical_violations']}")
print(f"    • Active Drift Events: {summary['active_drift_events']}")
print(f"    • Deployment Success Rate: {round(report.deployment_success_rate, 1)}%")
print(f"    • Avg Deployment Time: {round(report.avg_deployment_time_minutes, 1)} min")
print(f"    • Policy Compliance Score: {round(report.compliance_score, 1)}%")
print(f"    • Phase 62 Score: {round(summary['phase62_score'], 2)}/25")
print("")

PYEOF
    ;;

summary)
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.security_policy_automation_engine import SecurityPolicyAutomationEngine

engine = SecurityPolicyAutomationEngine()
summary = engine.summary()
report = engine.generate_report()
output = {
    **summary,
    "report": report.to_dict()
}
print(json.dumps(output, indent=2, default=str))
PYEOF
    ;;

report)
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.security_policy_automation_engine import (
    SecurityPolicyAutomationEngine, PolicyType, PolicyStatus, ViolationType
)

engine = SecurityPolicyAutomationEngine()

# Create comprehensive policy set
for pt in PolicyType:
    p = engine.create_policy(f"Policy: {pt.value}", pt, f"Comprehensive {pt.value} policy")
    for i in range(2):
        engine.add_rule_to_policy(p.policy_id, f"Rule {i+1}", "allow" if i % 2 == 0 else "deny", {"priority": str(i+1)})

# Deploy and generate violations
for p in engine.policies.values():
    dep = engine.deploy_policy(p.policy_id)
    engine.complete_deployment(dep.deployment_id, affected_resources=100, successful_resources=95)

report = engine.generate_report()
print(json.dumps(report.to_dict(), indent=2, default=str))
PYEOF
    ;;

*)
    echo "Usage: $0 [demo | summary | report]" >&2
    exit 1
    ;;
esac
