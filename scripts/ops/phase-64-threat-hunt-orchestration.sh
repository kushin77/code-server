#!/bin/bash
# @file phase-64-threat-hunt-orchestration.sh
# @description Operational handler for Phase 64 — Threat Hunt Orchestration
# @usage ./scripts/ops/phase-64-threat-hunt-orchestration.sh [demo | summary | report]

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

trap 'rm -f /tmp/p64*.tmp 2>/dev/null || true' EXIT

MODE="${1:-summary}"

case "$MODE" in
demo)
    "$PYTHON_CMD" <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.threat_hunt_orchestration_engine import (
    ThreatHuntOrchestrationEngine, IOCType, FindingType, HuntStatus
)

engine = ThreatHuntOrchestrationEngine()

print("")
print("============================================================")
print("  PHASE 64 — THREAT HUNT ORCHESTRATION ENGINE")
print("============================================================")
print("")

# Create hunt
hunt = engine.create_hunt("APT Campaign Hunt", "threat_actor", ["prod-server-01", "prod-server-02"])
engine.start_hunt(hunt.hunt_id)

# Register IOCs
ioc1 = engine.register_ioc(IOCType.IP_ADDRESS, "192.168.1.100", "threat_intel", 95.0, "APT-29")
ioc2 = engine.register_ioc(IOCType.DOMAIN_NAME, "malicious.com", "threat_intel", 90.0, "APT-29")

# Record detections
engine.record_ioc_detection(ioc1.ioc_id, "prod-server-01")
engine.record_ioc_detection(ioc2.ioc_id, "prod-server-02")

# Add findings
finding = engine.add_finding(hunt.hunt_id, FindingType.CONFIRMED_THREAT, "APT-29 indicators found", "critical", ["prod-server-01"])
engine.link_ioc_to_finding(finding.finding_id, ioc1.ioc_id)

# Identify campaign
campaign = engine.identify_campaign("APT-29 Campaign", "APT-29", "critical")
engine.link_campaign_to_hunt(hunt.hunt_id, campaign.campaign_id)

engine.conclude_hunt(hunt.hunt_id)

summary = engine.summary()
report = engine.generate_report()

print("  Threat Hunt Status:")
print(f"    • Total Hunts: {summary['total_hunts']}")
print(f"    • Active Hunts: {summary['active_hunts']}")
print(f"    • Concluded Hunts: {summary['concluded_hunts']}")
print(f"    • Total Findings: {summary['total_findings']}")
print(f"    • Confirmed Threats: {summary['confirmed_threats']}")
print(f"    • Suspicious Activities: {summary['suspicious_activities']}")
print(f"    • Total IOCs: {summary['total_iocs']}")
print(f"    • High Confidence IOCs: {summary['high_confidence_iocs']}")
print(f"    • Threat Campaigns: {summary['threat_campaigns']}")
print(f"    • Threat Detection Rate: {report.threat_detection_rate:.1f}%")
print(f"    • Phase 64 Score: {summary['phase64_score']:.2f}/25")
print("")

PYEOF
    ;;

summary)
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.threat_hunt_orchestration_engine import ThreatHuntOrchestrationEngine

engine = ThreatHuntOrchestrationEngine()
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
from security_ai.threat_hunt_orchestration_engine import (
    ThreatHuntOrchestrationEngine, IOCType, FindingType
)

engine = ThreatHuntOrchestrationEngine()

# Create comprehensive hunt
hunt = engine.create_hunt("Full Hunt", "ioc_search", ["srv1", "srv2"])
engine.start_hunt(hunt.hunt_id)

for i in range(3):
    ioc = engine.register_ioc(IOCType.IP_ADDRESS, f"10.0.0.{i+1}", "source", 80+i)
    engine.record_ioc_detection(ioc.ioc_id)
    finding = engine.add_finding(hunt.hunt_id, FindingType.SUSPICIOUS_ACTIVITY, f"Activity {i}", "high")
    engine.link_ioc_to_finding(finding.finding_id, ioc.ioc_id)

engine.conclude_hunt(hunt.hunt_id)
report = engine.generate_report()
print(json.dumps(report.to_dict(), indent=2, default=str))
PYEOF
    ;;

*)
    echo "Usage: $0 [demo | summary | report]" >&2
    exit 1
    ;;
esac
