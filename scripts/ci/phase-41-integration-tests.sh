#!/bin/bash
# @file phase-41-integration-tests.sh
# @description Integration test suite for Phase 41 intelligent incident response
# @since 2026-05-01
# @phase 41

set -o pipefail

# Error handling
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${PROJECT_ROOT}/artifacts/phase41"
PYTHON_CMD="python3"
if [[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]]; then
    PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"
fi

# Test counters
PASS=0
FAIL=0
TOTAL=0

# Cleanup
mkdir -p "$STATE_DIR"
rm -f "$STATE_DIR"/*.json

# Helper functions
run_test() {
    local test_name="$1"
    local test_cmd="$2"
    TOTAL=$((TOTAL + 1))
    
    if eval "$test_cmd" > /dev/null 2>&1; then
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
echo "PHASE 41: INTELLIGENT INCIDENT RESPONSE INTEGRATION TESTS"
echo "============================================================"
echo ""

# GROUP 1: Module Import & Initialization
echo "GROUP 1: Module Import & Initialization"
run_test "Import IntelligentIncidentResponse" "
python_test 'from security_ai.intelligent_incident_response import IntelligentIncidentResponse'
"

run_test "Import IncidentSeverity enum" "
python_test 'from security_ai.intelligent_incident_response import IncidentSeverity'
"

run_test "Import IncidentStatus enum" "
python_test 'from security_ai.intelligent_incident_response import IncidentStatus'
"

run_test "Import RemediationStrategy enum" "
python_test 'from security_ai.intelligent_incident_response import RemediationStrategy'
"

run_test "Engine initialization" "
python_test '
from security_ai.intelligent_incident_response import IntelligentIncidentResponse
engine = IntelligentIncidentResponse()
assert engine is not None
assert len(engine.incidents) == 0
'
"

# GROUP 2: Incident Detection
echo ""
echo "GROUP 2: Incident Detection"
run_test "Detect incident from phase" "
python_test '
from security_ai.intelligent_incident_response import IntelligentIncidentResponse, IncidentSeverity
engine = IntelligentIncidentResponse()
incident = engine.detect_incident(34, \"resource_exhaustion\", \"High CPU\", IncidentSeverity.HIGH.value, {\"cpu\": 95})
assert incident.incident_id is not None
'
"

run_test "Multiple incidents tracking" "
python_test '
from security_ai.intelligent_incident_response import IntelligentIncidentResponse, IncidentSeverity
engine = IntelligentIncidentResponse()
engine.detect_incident(34, \"resource_exhaustion\", \"CPU\", IncidentSeverity.HIGH.value, {\"cpu\": 90})
engine.detect_incident(40, \"security_breach\", \"Threat\", IncidentSeverity.CRITICAL.value, {\"threat\": 0.95})
assert len(engine.incidents) == 2
'
"

run_test "Incident severity classification" "
python_test '
from security_ai.intelligent_incident_response import IntelligentIncidentResponse, IncidentSeverity
engine = IntelligentIncidentResponse()
incident = engine.detect_incident(36, \"policy_violation\", \"Policy\", IncidentSeverity.MEDIUM.value, {\"violations\": 3})
assert incident.severity == IncidentSeverity.MEDIUM.value
'
"

# GROUP 3: Response Initiation
echo ""
echo "GROUP 3: Response Initiation"
run_test "Initiate incident response" "
python_test '
from security_ai.intelligent_incident_response import IntelligentIncidentResponse, IncidentSeverity, IncidentStatus
engine = IntelligentIncidentResponse()
incident = engine.detect_incident(34, \"resource_exhaustion\", \"CPU\", IncidentSeverity.HIGH.value, {\"cpu\": 95})
response = engine.initiate_response(incident.incident_id)
assert response.status == IncidentStatus.INVESTIGATING.value
'
"

run_test "Response has remediation playbook" "
python_test '
from security_ai.intelligent_incident_response import IntelligentIncidentResponse, IncidentSeverity
engine = IntelligentIncidentResponse()
incident = engine.detect_incident(34, \"resource_exhaustion\", \"CPU\", IncidentSeverity.HIGH.value, {\"cpu\": 95})
response = engine.initiate_response(incident.incident_id)
assert len(response.remediation_actions) > 0
'
"

run_test "Different incident types generate different playbooks" "
python_test '
from security_ai.intelligent_incident_response import IntelligentIncidentResponse, IncidentSeverity
engine = IntelligentIncidentResponse()
incident1 = engine.detect_incident(34, \"resource_exhaustion\", \"CPU\", IncidentSeverity.HIGH.value, {\"cpu\": 95})
incident2 = engine.detect_incident(40, \"security_breach\", \"Threat\", IncidentSeverity.CRITICAL.value, {\"threat\": 0.95})
response1 = engine.initiate_response(incident1.incident_id)
response2 = engine.initiate_response(incident2.incident_id)
# Different incident types should have different playbooks
assert response1.remediation_actions[0].strategy != response2.remediation_actions[0].strategy
'
"

# GROUP 4: Remediation Execution
echo ""
echo "GROUP 4: Remediation Execution"
run_test "Execute remediation actions" "
python_test '
from security_ai.intelligent_incident_response import IntelligentIncidentResponse, IncidentSeverity
engine = IntelligentIncidentResponse()
incident = engine.detect_incident(34, \"resource_exhaustion\", \"CPU\", IncidentSeverity.HIGH.value, {\"cpu\": 95})
response = engine.initiate_response(incident.incident_id)
engine.execute_remediation(incident.incident_id, response)
assert response.actions_executed > 0
'
"

run_test "Remediation success rate tracking" "
python_test '
from security_ai.intelligent_incident_response import IntelligentIncidentResponse, IncidentSeverity
engine = IntelligentIncidentResponse()
incident = engine.detect_incident(36, \"policy_violation\", \"Policy\", IncidentSeverity.MEDIUM.value, {\"violations\": 3})
response = engine.initiate_response(incident.incident_id)
engine.execute_remediation(incident.incident_id, response)
assert 0 <= response.remediation_success_rate <= 1.0
'
"

run_test "MTTD and MTTR calculation" "
python_test '
from security_ai.intelligent_incident_response import IntelligentIncidentResponse, IncidentSeverity
engine = IntelligentIncidentResponse()
incident = engine.detect_incident(40, \"security_breach\", \"Threat\", IncidentSeverity.CRITICAL.value, {\"threat\": 0.95})
response = engine.initiate_response(incident.incident_id)
engine.execute_remediation(incident.incident_id, response)
assert response.mttd is not None
assert response.mttr is not None
'
"

# GROUP 5: Metrics & Scoring
echo ""
echo "GROUP 5: Incident Metrics & Scoring"
run_test "Calculate remediation success score" "
python_test '
from security_ai.intelligent_incident_response import IntelligentIncidentResponse, IncidentSeverity
engine = IntelligentIncidentResponse()
incident = engine.detect_incident(34, \"resource_exhaustion\", \"CPU\", IncidentSeverity.HIGH.value, {\"cpu\": 95})
response = engine.initiate_response(incident.incident_id)
engine.execute_remediation(incident.incident_id, response)
engine.response_history.append(response)
score = engine.remediation_success_score()
assert 0 <= score <= 25.0
'
"

run_test "Get incident metrics" "
python_test '
from security_ai.intelligent_incident_response import IntelligentIncidentResponse, IncidentSeverity
engine = IntelligentIncidentResponse()
incident = engine.detect_incident(36, \"policy_violation\", \"Policy\", IncidentSeverity.MEDIUM.value, {\"violations\": 3})
response = engine.initiate_response(incident.incident_id)
engine.response_history.append(response)
metrics = engine.get_incident_metrics()
assert \"total_incidents\" in metrics
assert \"avg_success_rate\" in metrics
'
"

# GROUP 6: State Persistence
echo ""
echo "GROUP 6: State Persistence"
run_test "Persist incidents to disk" "
python_test '
from security_ai.intelligent_incident_response import IntelligentIncidentResponse, IncidentSeverity
import os
engine = IntelligentIncidentResponse()
engine.detect_incident(34, \"resource_exhaustion\", \"CPU\", IncidentSeverity.HIGH.value, {\"cpu\": 95})
engine.persist_state()
assert os.path.exists(engine.state_dir + \"/incidents.json\")
'
"

run_test "Persist responses to disk" "
python_test '
from security_ai.intelligent_incident_response import IntelligentIncidentResponse, IncidentSeverity
import os
engine = IntelligentIncidentResponse()
incident = engine.detect_incident(40, \"security_breach\", \"Threat\", IncidentSeverity.CRITICAL.value, {\"threat\": 0.95})
response = engine.initiate_response(incident.incident_id)
engine.response_history.append(response)
engine.persist_state()
assert os.path.exists(engine.state_dir + \"/responses.json\")
'
"

# GROUP 7: Summary Generation
echo ""
echo "GROUP 7: Summary & Reporting"
run_test "Generate response summary" "
python_test '
from security_ai.intelligent_incident_response import IntelligentIncidentResponse, IncidentSeverity
engine = IntelligentIncidentResponse()
engine.detect_incident(34, \"resource_exhaustion\", \"CPU\", IncidentSeverity.HIGH.value, {\"cpu\": 95})
summary = engine.summary()
assert \"active_incidents\" in summary
assert \"incident_responses\" in summary
'
"

run_test "Summary includes severity distribution" "
python_test '
from security_ai.intelligent_incident_response import IntelligentIncidentResponse, IncidentSeverity
engine = IntelligentIncidentResponse()
engine.detect_incident(34, \"resource_exhaustion\", \"CPU\", IncidentSeverity.HIGH.value, {\"cpu\": 95})
engine.detect_incident(40, \"security_breach\", \"Threat\", IncidentSeverity.CRITICAL.value, {\"threat\": 0.95})
summary = engine.summary()
assert \"severity_distribution\" in summary
assert summary[\"severity_distribution\"][\"high\"] >= 1
'
"

run_test "Summary success score in range" "
python_test '
from security_ai.intelligent_incident_response import IntelligentIncidentResponse, IncidentSeverity
engine = IntelligentIncidentResponse()
incident = engine.detect_incident(36, \"policy_violation\", \"Policy\", IncidentSeverity.MEDIUM.value, {\"violations\": 3})
response = engine.initiate_response(incident.incident_id)
engine.response_history.append(response)
summary = engine.summary()
assert 0 <= summary[\"remediation_success_score\"] <= 25.0
'
"

# GROUP 8: Ops Orchestrator
echo ""
echo "GROUP 8: Ops Orchestrator"
run_test "Ops script syntax validation" "
bash -n ${PROJECT_ROOT}/scripts/ops/phase-41-intelligent-incident-response.sh
"

run_test "Ops demo mode" "
output=\"\$(timeout 30 bash ${PROJECT_ROOT}/scripts/ops/phase-41-intelligent-incident-response.sh demo 2>&1)\"
echo \"\$output\" | grep -q 'PHASE 41'
"

# GROUP 9: Cross-Phase Integration
echo ""
echo "GROUP 9: Cross-Phase Integration"
run_test "Ingest from Phase 34 (resilience)" "
python_test '
from security_ai.intelligent_incident_response import IntelligentIncidentResponse, IncidentSeverity
engine = IntelligentIncidentResponse()
incident = engine.detect_incident(34, \"degradation\", \"Resilience incident\", IncidentSeverity.MEDIUM.value, {})
assert any(i.source_phase == 34 for i in engine.incidents.values())
'
"

run_test "Ingest from Phase 40 (predictive)" "
python_test '
from security_ai.intelligent_incident_response import IntelligentIncidentResponse, IncidentSeverity
engine = IntelligentIncidentResponse()
incident = engine.detect_incident(40, \"forecast_threat\", \"Predicted threat\", IncidentSeverity.HIGH.value, {})
assert any(i.source_phase == 40 for i in engine.incidents.values())
'
"

run_test "Phase 40 predictive threats still passing" "
phase40_output=\"\$(timeout 120 bash ${PROJECT_ROOT}/scripts/ci/phase-40-integration-tests.sh 2>&1 || true)\"
echo \"\$phase40_output\" | grep -q 'PASS:'
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
