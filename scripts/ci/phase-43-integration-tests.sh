#!/bin/bash
# @file phase-43-integration-tests.sh
# @description Integration test suite for Phase 43 advanced threat hunting
# @since 2026-05-01
# @phase 43

set -o pipefail

# Error handling
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${PROJECT_ROOT}/artifacts/phase43"
PYTHON_CMD="python3"
if [[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]]; then
    PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"
fi

# Test counters
PASS=0
FAIL=0
TOTAL=0

# Cleanup function to ensure fresh state
cleanup_state() {
    mkdir -p "$STATE_DIR"
    rm -f "$STATE_DIR"/*.json
}

# Run cleanup before starting
cleanup_state

# Helper functions
run_test() {
    local test_name="$1"
    local test_cmd="$2"
    TOTAL=$((TOTAL + 1))
    
    # Clean state before each test
    cleanup_state
    
    if eval "$test_cmd" > /tmp/test_output.log 2>&1; then
        echo "  ✓ $test_name"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $test_name"
        FAIL=$((FAIL + 1))
    fi
}

python_test() {
    local test_code="$1"
    "$PYTHON_CMD" - <<EOF
import sys
sys.path.insert(0, "${PROJECT_ROOT}/apps")
$test_code
EOF
}

# Start tests
echo "============================================================"
echo "PHASE 43: ADVANCED THREAT HUNTING INTEGRATION TESTS"
echo "============================================================"
echo ""

# GROUP 1: Module Import & Initialization
echo "GROUP 1: Module Import & Initialization"
run_test "Import AdvancedThreatHunting" "
python_test 'from security_ai.advanced_threat_hunting import AdvancedThreatHunting'
"

run_test "Import HuntingStatus enum" "
python_test 'from security_ai.advanced_threat_hunting import HuntingStatus'
"

run_test "Import ThreatLevel enum" "
python_test 'from security_ai.advanced_threat_hunting import ThreatLevel'
"

run_test "Engine initialization" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
engine = AdvancedThreatHunting()
assert engine is not None
assert len(engine.indicators) == 0
'
"

# GROUP 2: Threat Indicator Registration
echo ""
echo "GROUP 2: Threat Indicator Registration"
run_test "Register threat indicator" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
engine = AdvancedThreatHunting()
indicator = engine.register_indicator(\"ip\", \"192.168.1.100\", \"high\", 40, \"forecasted_c2\", 0.95)
assert indicator.indicator_id in engine.indicators
'
"

run_test "Multiple indicators registration" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
engine = AdvancedThreatHunting()
engine.register_indicator(\"ip\", \"192.168.1.100\", \"high\", 40, \"c2\", 0.95)
engine.register_indicator(\"domain\", \"malicious.com\", \"critical\", 40, \"c2_domain\", 0.98)
engine.register_indicator(\"hash\", \"abc123\", \"high\", 40, \"malware\", 0.92)
assert len(engine.indicators) == 3
'
"

# GROUP 3: Hunting Playbook Creation
echo ""
echo "GROUP 3: Hunting Playbook Creation"
run_test "Create hunting playbook" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
engine = AdvancedThreatHunting()
playbook = engine.create_hunting_playbook(
    \"C2 Hunt\", \"Hunt for C2 communications\", \"indicator_based\",
    [\"192.168.1.100\"], [\"dns_to_c2\"], \"Detect C2\", \"Any match\"
)
assert playbook.playbook_id in engine.playbooks
'
"

run_test "Multiple playbooks" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
engine = AdvancedThreatHunting()
engine.create_hunting_playbook(\"C2\", \"C2 hunt\", \"indicator_based\", [], [], \"C2\", \"match\")
engine.create_hunting_playbook(\"Malware\", \"Malware hunt\", \"behavior_based\", [], [], \"Malware\", \"match\")
assert len(engine.playbooks) == 2
'
"

# GROUP 4: Campaign Management
echo ""
echo "GROUP 4: Campaign Management"
run_test "Start hunting campaign" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
engine = AdvancedThreatHunting()
playbook = engine.create_hunting_playbook(\"Test\", \"Test\", \"indicator_based\", [], [], \"Test\", \"match\")
campaign = engine.start_hunting_campaign(playbook.playbook_id)
assert campaign.campaign_id in engine.campaigns
'
"

run_test "Complete campaign" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
engine = AdvancedThreatHunting()
playbook = engine.create_hunting_playbook(\"Test\", \"Test\", \"indicator_based\", [], [], \"Test\", \"match\")
campaign = engine.start_hunting_campaign(playbook.playbook_id)
engine.complete_campaign(campaign.campaign_id)
assert engine.campaigns[campaign.campaign_id].status == \"completed\"
'
"

# GROUP 5: Finding Management
echo ""
echo "GROUP 5: Finding Management"
run_test "Log hunting finding" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
engine = AdvancedThreatHunting()
playbook = engine.create_hunting_playbook(\"Test\", \"Test\", \"indicator_based\", [], [], \"Test\", \"match\")
campaign = engine.start_hunting_campaign(playbook.playbook_id)
finding = engine.log_finding(campaign.campaign_id, \"indicator_match\", \"Found IOC\", [\"192.168.1.100\"], {}, \"high\", 0.95)
assert finding.finding_id in engine.findings
'
"

run_test "Multiple findings with severity" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
engine = AdvancedThreatHunting()
playbook = engine.create_hunting_playbook(\"Test\", \"Test\", \"indicator_based\", [], [], \"Test\", \"match\")
campaign = engine.start_hunting_campaign(playbook.playbook_id)
engine.log_finding(campaign.campaign_id, \"type1\", \"Finding 1\", [], {}, \"critical\", 0.95)
engine.log_finding(campaign.campaign_id, \"type2\", \"Finding 2\", [], {}, \"high\", 0.88)
assert len(engine.findings) == 2
'
"

# GROUP 6: Response Execution
echo ""
echo "GROUP 6: Response Execution"
run_test "Execute response action" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
engine = AdvancedThreatHunting()
playbook = engine.create_hunting_playbook(\"Test\", \"Test\", \"indicator_based\", [], [], \"Test\", \"match\")
campaign = engine.start_hunting_campaign(playbook.playbook_id)
finding = engine.log_finding(campaign.campaign_id, \"test\", \"Test finding\", [], {}, \"high\", 0.9)
result = engine.execute_response(finding.finding_id, \"isolate_host\")
assert result == True
'
"

# GROUP 7: Hunting Success Scoring
echo ""
echo "GROUP 7: Hunting Success Scoring"
run_test "Calculate hunting success rate" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
engine = AdvancedThreatHunting()
engine.register_indicator(\"ip\", \"192.168.1.100\", \"high\", 40, \"c2\", 0.95)
playbook = engine.create_hunting_playbook(\"Test\", \"Test\", \"indicator_based\", [], [], \"Test\", \"match\")
campaign = engine.start_hunting_campaign(playbook.playbook_id)
engine.log_finding(campaign.campaign_id, \"match\", \"Found\", [], {}, \"high\", 0.9)
engine.complete_campaign(campaign.campaign_id)
rate = engine.calculate_hunting_success_rate()
assert 0 <= rate <= 1
'
"

run_test "Hunting score in valid range" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
engine = AdvancedThreatHunting()
score = engine.hunting_score()
assert 0 <= score <= 25.0
'
"

# GROUP 8: Phase Data Integration
echo ""
echo "GROUP 8: Phase Data Integration"
run_test "Ingest phase data" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
engine = AdvancedThreatHunting()
engine.ingest_phase_data(40, \"Predictive Threat Intelligence\", {\"threats_forecasted\": 5})
assert 40 in engine.phase_data
'
"

run_test "Multiple phase data ingestion" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
engine = AdvancedThreatHunting()
engine.ingest_phase_data(40, \"Threat Intel\", {\"threats\": 5})
engine.ingest_phase_data(41, \"Incident Response\", {\"incidents\": 2})
engine.ingest_phase_data(42, \"Compliance\", {\"violations\": 1})
assert len(engine.phase_data) == 3
'
"

# GROUP 9: Risk Area Identification
echo ""
echo "GROUP 9: Risk Area Identification"
run_test "Identify risk areas" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
engine = AdvancedThreatHunting()
playbook = engine.create_hunting_playbook(\"Test\", \"Test\", \"indicator_based\", [], [], \"Test\", \"match\")
campaign = engine.start_hunting_campaign(playbook.playbook_id)
engine.log_finding(campaign.campaign_id, \"test\", \"Critical\", [], {}, \"critical\", 0.95)
risk_areas = engine.identify_risk_areas()
assert len(risk_areas) > 0
'
"

# GROUP 10: Report Generation
echo ""
echo "GROUP 10: Report Generation"
run_test "Generate hunting report" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
engine = AdvancedThreatHunting()
report = engine.generate_hunting_report()
assert \"total_campaigns\" in report
assert \"total_findings\" in report
'
"

run_test "Report includes recommendations" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
engine = AdvancedThreatHunting()
playbook = engine.create_hunting_playbook(\"Test\", \"Test\", \"indicator_based\", [], [], \"Test\", \"match\")
campaign = engine.start_hunting_campaign(playbook.playbook_id)
engine.log_finding(campaign.campaign_id, \"test\", \"Finding\", [], {}, \"critical\", 0.95)
report = engine.generate_hunting_report()
assert len(report[\"recommendations\"]) > 0
'
"

# GROUP 11: State Persistence
echo ""
echo "GROUP 11: State Persistence"
run_test "Persist state to disk" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
import os
engine = AdvancedThreatHunting()
engine.register_indicator(\"ip\", \"192.168.1.100\", \"high\", 40, \"c2\", 0.95)
engine.persist_state()
assert os.path.exists(engine.state_dir + \"/indicators.json\")
'
"

run_test "Persist campaigns to disk" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
import os
engine = AdvancedThreatHunting()
playbook = engine.create_hunting_playbook(\"Test\", \"Test\", \"indicator_based\", [], [], \"Test\", \"match\")
campaign = engine.start_hunting_campaign(playbook.playbook_id)
engine.persist_state()
assert os.path.exists(engine.state_dir + \"/campaigns.json\")
'
"

# GROUP 12: Summary Generation
echo ""
echo "GROUP 12: Summary Generation"
run_test "Generate summary" "
python_test '
from security_ai.advanced_threat_hunting import AdvancedThreatHunting
engine = AdvancedThreatHunting()
summary = engine.summary()
assert \"total_indicators\" in summary
assert \"hunting_success_rate\" in summary
'
"

# GROUP 13: Ops Orchestrator
echo ""
echo "GROUP 13: Ops Orchestrator"
run_test "Ops script syntax validation" "
bash -n ${PROJECT_ROOT}/scripts/ops/phase-43-threat-hunting.sh
"

run_test "Ops demo mode" "
output=\$(bash ${PROJECT_ROOT}/scripts/ops/phase-43-threat-hunting.sh demo 2>&1); echo \"\$output\" | grep -q 'PHASE 43'
"

# Summary
echo ""
echo "============================================================"
echo "TEST SUMMARY"
echo "============================================================"
echo "PASS: $PASS"
echo "FAIL: $FAIL"
echo "TOTAL: $TOTAL"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo "✓ ALL TESTS PASSED"
    exit 0
else
    echo "✗ SOME TESTS FAILED"
    exit 1
fi
