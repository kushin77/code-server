#!/bin/bash
# @file phase-60-continuous-compliance.sh
# @description Phase 60 — Continuous Compliance & Evidence Collection Engine
# @since 2026-05-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'rm -f /tmp/p60*.tmp 2>/dev/null || true' EXIT
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR

MODE="${1:-demo}"

cmd_demo() {
    log_info "PHASE 60: Continuous Compliance & Evidence Collection" >&2
    "$PYTHON_CMD" <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.continuous_compliance_engine import (
    ContinuousComplianceEngine, ComplianceFramework, ControlStatus, EvidenceType, AuditAction
)

engine = ContinuousComplianceEngine()

print("=== PHASE 60: Continuous Compliance Dashboard ===")
print()

# Register controls
c1 = engine.register_control(ComplianceFramework.SOC2, "SEC-001", 
    "Access Control Policy", "Enforce MFA for all users")
c2 = engine.register_control(ComplianceFramework.SOC2, "SEC-002",
    "Encryption in Transit", "Use TLS 1.2+ for all communications")
c3 = engine.register_control(ComplianceFramework.GDPR, "DP-001",
    "Data Classification", "Classify all data by sensitivity")

print(f"  Controls registered: 3 (SOC2: 2, GDPR: 1)")
print()

# Collect evidence
ev1 = engine.collect_evidence(
    "SEC-001", EvidenceType.CONFIGURATION, "MFA enabled",
    "/evidence/mfa-config.json", "compliance@corp.io"
)
ev2 = engine.collect_evidence(
    "SEC-002", EvidenceType.POLICY, "TLS policy document",
    "/policies/tls-policy.md", "compliance@corp.io"
)

# Update status
engine.update_control_status("SEC-001", ControlStatus.COMPLIANT, "MFA verified")
engine.update_control_status("SEC-002", ControlStatus.PARTIAL, "Legacy systems still on TLS 1.1")
engine.update_control_status("DP-001", ControlStatus.NON_COMPLIANT, "No classification found")

print(f"  Control status:")
print(f"    SEC-001 (Access Control):     COMPLIANT")
print(f"    SEC-002 (Encryption):         PARTIAL")
print(f"    DP-001  (Data Classification): NON_COMPLIANT")
print()

# Log audit event
engine.log_audit_event(
    AuditAction.ACCESS_GRANTED, "user@corp.io", "database-prod",
    "success", "SSH access granted"
)

# Assess
assessment = engine.assess_framework(ComplianceFramework.SOC2)
print(f"  SOC2 Assessment: {assessment.compliance_pct:.0f}% compliant")
print(f"  Phase 60 Score:  {engine.phase60_score():.2f}/25")
PYEOF
}

cmd_summary() {
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.continuous_compliance_engine import (
    ContinuousComplianceEngine, ComplianceFramework, ControlStatus, EvidenceType
)
engine = ContinuousComplianceEngine()
for i, fw in enumerate([ComplianceFramework.SOC2, ComplianceFramework.HIPAA]):
    for j in range(3):
        cid = f"{fw.value.upper()}-{j+1:03d}"
        engine.register_control(fw, cid, f"Control {cid}", "desc")
engine.update_control_status("SOC2-001", ControlStatus.COMPLIANT)
engine.update_control_status("HIPAA-001", ControlStatus.PARTIAL)
print(json.dumps(engine.summary(), indent=2))
PYEOF
}

cmd_assess() {
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.continuous_compliance_engine import (
    ContinuousComplianceEngine, ComplianceFramework, ControlStatus, EvidenceType
)
engine = ContinuousComplianceEngine()
# Register SOC2 controls
for i in range(1, 6):
    cid = f"SOC2-{i:03d}"
    engine.register_control(ComplianceFramework.SOC2, cid, f"Control {cid}", "description")
# Mix of statuses
engine.update_control_status("SOC2-001", ControlStatus.COMPLIANT)
engine.update_control_status("SOC2-002", ControlStatus.COMPLIANT)
engine.update_control_status("SOC2-003", ControlStatus.PARTIAL)
engine.update_control_status("SOC2-004", ControlStatus.NON_COMPLIANT)
assessment = engine.assess_framework(ComplianceFramework.SOC2)
print(json.dumps(assessment.to_dict(), indent=2))
PYEOF
}

case "$MODE" in
    demo)      cmd_demo ;;
    summary)   cmd_summary ;;
    assess)    cmd_assess ;;
    *)
        echo "Usage: $0 [demo|summary|assess]"
        exit 1
        ;;
esac
