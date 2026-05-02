#!/bin/bash
# @file phase-46-compliance-audit.sh
# @description Phase 46 — Compliance Audit & Security Posture Verification
# @since 2026-05-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'rm -f /tmp/p46*.tmp 2>/dev/null || true' EXIT
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR

MODE="${1:-demo}"
SCOPE="${2:-platform}"

run_python() {
    "$PYTHON_CMD" - <<'PYEOF'
import sys, json
sys.path.insert(0, '__PROJECT_ROOT__/apps')
from security_ai.compliance_audit_engine import (
    ComplianceAuditEngine, AuditSeverity, FindingStatus, audit_score
)

engine = ComplianceAuditEngine()

services = [
    ("api-gateway",   {"phase36_score": 91.0, "phase30_score": 88.0}),
    ("auth-service",  {"phase31_score": 94.0, "phase40_score": 87.0}),
    ("data-pipeline", {"phase34_score": 82.0, "phase38_score": 80.0}),
]

records = []
for svc, signals in services:
    rec = engine.create_audit(f"Q2 Audit — {svc}", svc, signals)
    engine.run_audit(rec)
    engine.finalize_audit(rec)
    records.append(rec)

# Inject a synthetic MEDIUM finding on the last record to show remediation
synth = engine.create_audit("Synthetic Finding Demo", "infra", {})
engine.run_audit(synth)
f = engine.add_finding(
    synth,
    title="Stale Certificate Detected",
    description="TLS certificate on load balancer expires in 7 days.",
    severity=AuditSeverity.MEDIUM,
    phase_source="phase_31",
    control_id="ctrl-31",
    evidence="cert_expiry=7d",
)
engine.remediate_finding(synth, f.finding_id, "Auto-rotation scheduled")
engine.finalize_audit(synth)

s = engine.summary()
sys.stdout.write(json.dumps(s, indent=2))
sys.stdout.flush()
PYEOF
}

# Substitute PROJECT_ROOT into the heredoc
run_python_real() {
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.compliance_audit_engine import (
    ComplianceAuditEngine, AuditSeverity, FindingStatus, audit_score
)

engine = ComplianceAuditEngine()

services = [
    ("api-gateway",   {"phase36_score": 91.0, "phase30_score": 88.0}),
    ("auth-service",  {"phase31_score": 94.0, "phase40_score": 87.0}),
    ("data-pipeline", {"phase34_score": 82.0, "phase38_score": 80.0}),
]

records = []
for svc, signals in services:
    rec = engine.create_audit(f"Q2 Audit — {svc}", svc, signals)
    engine.run_audit(rec)
    engine.finalize_audit(rec)
    records.append(rec)

synth = engine.create_audit("Synthetic Finding Demo", "infra", {})
engine.run_audit(synth)
f = engine.add_finding(
    synth,
    title="Stale Certificate Detected",
    description="TLS certificate on load balancer expires in 7 days.",
    severity=AuditSeverity.MEDIUM,
    phase_source="phase_31",
    control_id="ctrl-31",
    evidence="cert_expiry=7d",
)
engine.remediate_finding(synth, f.finding_id, "Auto-rotation scheduled")
engine.finalize_audit(synth)

s = engine.summary()
sys.stdout.write(json.dumps(s, indent=2))
sys.stdout.flush()
PYEOF
}

cmd_demo() {
    log_info "PHASE 46: Compliance Audit & Security Posture Verification"
    log_info "Running audit across platform services..."
    echo ""

    "$PYTHON_CMD" <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.compliance_audit_engine import (
    ComplianceAuditEngine, AuditSeverity, FindingStatus, ControlStatus, audit_score
)

engine = ComplianceAuditEngine()

services = [
    ("api-gateway",   {"phase36_score": 91.0, "phase30_score": 88.0, "phase45_score": 92.0}),
    ("auth-service",  {"phase31_score": 94.0, "phase40_score": 87.0}),
    ("data-pipeline", {"phase34_score": 82.0, "phase38_score": 80.0}),
]

print("=== PHASE 46: Compliance Audit Dashboard ===")
print()
for svc, signals in services:
    rec = engine.create_audit(f"Q2-2026 Audit", svc, signals)
    engine.run_audit(rec)
    cs = rec.control_summary()
    print(f"  Service: {svc}")
    print(f"    Controls: compliant={cs['compliant']} partial={cs['partial']} non_compliant={cs['non_compliant']}")
    print(f"    Posture Score: {rec.posture_score():.2f}/25")
    print(f"    Findings: {len([f for f in rec.findings if f.status.value == 'open'])} open")
    engine.finalize_audit(rec)
    print()

s = engine.summary()
print(f"  Platform Audit Score:  {s['phase46_audit_score']:.2f}/25")
print(f"  Fully Compliant Runs:  {s['fully_compliant']}/{s['total_audits']}")
print(f"  Open Critical Findings:{s['open_criticals']}")
PYEOF
}

cmd_summary() {
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.compliance_audit_engine import ComplianceAuditEngine, audit_score

engine = ComplianceAuditEngine()
rec = engine.create_audit("Summary Audit", "platform", {})
engine.run_audit(rec)
engine.finalize_audit(rec)
s = engine.summary()
print(json.dumps(s, indent=2))
PYEOF
}

cmd_audit() {
    local scope="${2:-platform}"
    log_info "PHASE 46: Running compliance audit for scope: ${scope}"
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.compliance_audit_engine import ComplianceAuditEngine, audit_score

engine = ComplianceAuditEngine()
rec = engine.create_audit("On-demand Audit", "${scope}", {})
engine.run_audit(rec)
report = engine.generate_report(rec)
engine.finalize_audit(rec)
print(json.dumps(report, indent=2))
posture = rec.posture_score()
print(f"Posture Score: {posture:.2f}/25")
PYEOF
}

case "$MODE" in
    demo)    cmd_demo ;;
    summary) cmd_summary ;;
    audit)   cmd_audit "$@" ;;
    *)
        echo "Usage: $0 [demo|summary|audit [scope]]"
        exit 1
        ;;
esac
