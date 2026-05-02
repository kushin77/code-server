#!/bin/bash
# @file phase-63-incident-response-remediation.sh
# @description Operational handler for Phase 63 — Automated Incident Response & Remediation
# @usage ./scripts/ops/phase-63-incident-response-remediation.sh [demo | summary | report]

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

trap 'rm -f /tmp/p63*.tmp 2>/dev/null || true' EXIT

MODE="${1:-summary}"

case "$MODE" in
demo)
    "$PYTHON_CMD" <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.incident_response_remediation_engine import (
    IncidentResponseOrchestrationEngine, IncidentType, IncidentSeverity, PlaybookAction
)

engine = IncidentResponseOrchestrationEngine()

print("")
print("============================================================")
print("  PHASE 63 — AUTOMATED INCIDENT RESPONSE & REMEDIATION")
print("============================================================")
print("")

# Create sample incidents
inc1 = engine.create_incident("Malware Detection", IncidentType.MALWARE, IncidentSeverity.CRITICAL, "Trojan detected on host", ["host-001"])
inc2 = engine.create_incident("Policy Violation", IncidentType.POLICY_VIOLATION, IncidentSeverity.HIGH, "Data access violation", ["app-server-02"])

# Add containment actions
con1 = engine.add_containment_action(inc1.incident_id, PlaybookAction.ISOLATE_RESOURCE, "host-001")
engine.execute_containment_action(inc1.incident_id, con1.action_id)

# Add remediation
rem1 = engine.add_remediation_action(inc1.incident_id, PlaybookAction.RESTORE_BACKUP, "host-001")
engine.execute_remediation_action(inc1.incident_id, rem1.action_id)

# Collect forensics
engine.collect_forensics(inc1.incident_id, "memory_dump", "host-001", 4096)

# Close incident
engine.close_incident(inc1.incident_id, "Compromised account recovered")

summary = engine.summary()
report = engine.generate_report()

print("  Incident Response Status:")
print(f"    • Total Incidents: {summary['total_incidents']}")
print(f"    • Open Incidents: {summary['open_incidents']}")
print(f"    • Closed Incidents: {summary['closed_incidents']}")
print(f"    • Critical Incidents: {summary['critical_incidents']}")
print(f"    • Total Playbooks: {summary['total_playbooks']}")
print(f"    • Avg MTTR: {report.avg_mttr_hours:.1f} hours")
print(f"    • Containment Success Rate: {report.containment_success_rate:.1f}%")
print(f"    • Remediation Success Rate: {report.remediation_success_rate:.1f}%")
print(f"    • Forensic Coverage: {report.forensic_coverage:.1f}%")
print(f"    • Phase 63 Score: {summary['phase63_score']:.2f}/25")
print("")

PYEOF
    ;;

summary)
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.incident_response_remediation_engine import IncidentResponseOrchestrationEngine

engine = IncidentResponseOrchestrationEngine()
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
from security_ai.incident_response_remediation_engine import (
    IncidentResponseOrchestrationEngine, IncidentType, IncidentSeverity, PlaybookAction
)

engine = IncidentResponseOrchestrationEngine()

# Create comprehensive incident set
for i, it in enumerate([IncidentType.MALWARE, IncidentType.INTRUSION, IncidentType.DATA_BREACH]):
    inc = engine.create_incident(f"Incident {i+1}", it, [IncidentSeverity.CRITICAL, IncidentSeverity.HIGH, IncidentSeverity.MEDIUM][i], f"Description {i+1}", [f"resource-{i+1}"])
    con = engine.add_containment_action(inc.incident_id, PlaybookAction.ISOLATE_RESOURCE, f"resource-{i+1}")
    engine.execute_containment_action(inc.incident_id, con.action_id)
    engine.close_incident(inc.incident_id, f"Root cause: Issue {i+1}")

report = engine.generate_report()
print(json.dumps(report.to_dict(), indent=2, default=str))
PYEOF
    ;;

*)
    echo "Usage: $0 [demo | summary | report]" >&2
    exit 1
    ;;
esac
