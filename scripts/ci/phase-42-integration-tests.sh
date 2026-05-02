#!/bin/bash
# @file phase-42-integration-tests.sh
# @description Integration test suite for Phase 42 advanced compliance automation
# @since 2026-05-01
# @phase 42

set -o pipefail

# Error handling
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${PROJECT_ROOT}/artifacts/phase42"
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
        local exit_code=$?
        echo "  ✗ $test_name (exit=$exit_code)"
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
echo "PHASE 42: ADVANCED COMPLIANCE AUTOMATION INTEGRATION TESTS"
echo "============================================================"
echo ""

# GROUP 1: Module Import & Initialization
echo "GROUP 1: Module Import & Initialization"
run_test "Import AdvancedComplianceAutomation" "
python_test 'from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation'
"

run_test "Import ComplianceFramework enum" "
python_test 'from security_ai.advanced_compliance_automation import ComplianceFramework'
"

run_test "Import ComplianceDomain enum" "
python_test 'from security_ai.advanced_compliance_automation import ComplianceDomain'
"

run_test "Engine initialization" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
engine = AdvancedComplianceAutomation()
assert engine is not None
assert len(engine.controls) == 0
'
"

# GROUP 2: Control Registration
echo ""
echo "GROUP 2: Compliance Control Registration"
run_test "Register control" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
engine = AdvancedComplianceAutomation()
control = engine.register_control(\"AC-1\", \"soc2\", \"access_control\", \"Access management\")
assert control.control_id == \"AC-1\"
'
"

run_test "Multiple controls registration" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
engine = AdvancedComplianceAutomation()
engine.register_control(\"AC-1\", \"soc2\", \"access_control\", \"Access\")
engine.register_control(\"DP-1\", \"soc2\", \"data_protection\", \"Encryption\")
engine.register_control(\"IR-1\", \"hipaa\", \"incident_response\", \"Detection\")
assert len(engine.controls) == 3
'
"

run_test "Control tracking by framework" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
engine = AdvancedComplianceAutomation()
engine.register_control(\"AC-1\", \"soc2\", \"access_control\", \"Access\")
engine.register_control(\"AC-2\", \"soc2\", \"access_control\", \"MFA\")
engine.register_control(\"IR-1\", \"hipaa\", \"incident_response\", \"Detection\")
soc2_controls = [c for c in engine.controls.values() if c.framework == \"soc2\"]
assert len(soc2_controls) == 2
'
"

# GROUP 3: Control Assessment
echo ""
echo "GROUP 3: Control Assessment"
run_test "Assess control implementation" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
engine = AdvancedComplianceAutomation()
control = engine.register_control(\"AC-1\", \"soc2\", \"access_control\", \"Access\")
engine.assess_control_implementation(\"AC-1\", True)
assert engine.controls[\"AC-1\"].is_implemented == True
'
"

run_test "Assess control effectiveness" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
engine = AdvancedComplianceAutomation()
engine.register_control(\"AC-1\", \"soc2\", \"access_control\", \"Access\")
engine.assess_control_effectiveness(\"AC-1\", 85.0)
assert engine.controls[\"AC-1\"].effectiveness_score == 85.0
assert engine.controls[\"AC-1\"].is_effective == True
'
"

run_test "Ineffective control below threshold" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
engine = AdvancedComplianceAutomation()
engine.register_control(\"AC-1\", \"soc2\", \"access_control\", \"Access\")
engine.assess_control_effectiveness(\"AC-1\", 60.0)
assert engine.controls[\"AC-1\"].is_effective == False
'
"

# GROUP 4: Violation Management
echo ""
echo "GROUP 4: Violation Management"
run_test "Log compliance violation" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
engine = AdvancedComplianceAutomation()
engine.register_control(\"AC-1\", \"soc2\", \"access_control\", \"Access\")
violation = engine.log_violation(\"AC-1\", \"high\", \"MFA not enforced\")
assert violation.violation_id in engine.violations
'
"

run_test "Multiple violations tracking" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
engine = AdvancedComplianceAutomation()
engine.register_control(\"AC-1\", \"soc2\", \"access_control\", \"Access\")
engine.register_control(\"DP-1\", \"soc2\", \"data_protection\", \"Encryption\")
engine.log_violation(\"AC-1\", \"high\", \"MFA not enforced\")
engine.log_violation(\"DP-1\", \"critical\", \"Unencrypted data\")
assert len(engine.violations) == 2
'
"

run_test "Remediate violation" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
engine = AdvancedComplianceAutomation()
engine.register_control(\"AC-1\", \"soc2\", \"access_control\", \"Access\")
violation = engine.log_violation(\"AC-1\", \"high\", \"MFA not enforced\")
engine.remediate_violation(violation.violation_id, \"Enabled MFA on all accounts\")
assert engine.violations[violation.violation_id].remediated_at is not None
'
"

# GROUP 5: Framework Compliance Scoring
echo ""
echo "GROUP 5: Framework Compliance Scoring"
run_test "Calculate framework compliance" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
engine = AdvancedComplianceAutomation()
engine.register_control(\"AC-1\", \"soc2\", \"access_control\", \"Access\")
engine.register_control(\"DP-1\", \"soc2\", \"data_protection\", \"Encryption\")
engine.assess_control_implementation(\"AC-1\", True)
engine.assess_control_effectiveness(\"AC-1\", 85)
score = engine.calculate_framework_compliance(\"soc2\")
assert 0 <= score <= 100
'
"

run_test "Compliance score in valid range" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
engine = AdvancedComplianceAutomation()
engine.register_control(\"AC-1\", \"soc2\", \"access_control\", \"Access\")
engine.assess_control_implementation(\"AC-1\", True)
score = engine.compliance_score()
assert 0 <= score <= 25.0
'
"

# GROUP 6: Phase Data Integration
echo ""
echo "GROUP 6: Phase Data Integration"
run_test "Ingest phase data" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
engine = AdvancedComplianceAutomation()
engine.ingest_phase_data(31, \"Compliance Gate\", {\"score\": 22.5})
assert 31 in engine.phase_data
'
"

run_test "Multiple phase data ingestion" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
engine = AdvancedComplianceAutomation()
engine.ingest_phase_data(31, \"Compliance\", {\"score\": 22})
engine.ingest_phase_data(34, \"Resilience\", {\"availability\": 99.95})
engine.ingest_phase_data(41, \"Response\", {\"mttd\": 30})
assert len(engine.phase_data) == 3
'
"

# GROUP 7: Compliance Report Generation
echo ""
echo "GROUP 7: Compliance Report Generation"
run_test "Generate compliance report" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
engine = AdvancedComplianceAutomation()
engine.register_control(\"AC-1\", \"soc2\", \"access_control\", \"Access\")
report = engine.generate_compliance_report(\"soc2\")
assert report.framework == \"soc2\"
assert report.total_controls == 1
'
"

run_test "Report includes recommendations" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
engine = AdvancedComplianceAutomation()
engine.register_control(\"AC-1\", \"soc2\", \"access_control\", \"Access\")
engine.log_violation(\"AC-1\", \"high\", \"MFA not enforced\")
report = engine.generate_compliance_report(\"soc2\")
assert len(report.recommendations) > 0
'
"

# GROUP 8: State Persistence
echo ""
echo "GROUP 8: State Persistence"
run_test "Persist controls to disk" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
import os
engine = AdvancedComplianceAutomation()
engine.register_control(\"AC-1\", \"soc2\", \"access_control\", \"Access\")
engine.persist_state()
assert os.path.exists(engine.state_dir + \"/controls.json\")
'
"

run_test "Persist violations to disk" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
import os
engine = AdvancedComplianceAutomation()
engine.register_control(\"AC-1\", \"soc2\", \"access_control\", \"Access\")
engine.log_violation(\"AC-1\", \"high\", \"Violation\")
engine.persist_state()
assert os.path.exists(engine.state_dir + \"/violations.json\")
'
"

# GROUP 9: Summary Generation
echo ""
echo "GROUP 9: Summary & Reporting"
run_test "Generate summary" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
engine = AdvancedComplianceAutomation()
engine.register_control(\"AC-1\", \"soc2\", \"access_control\", \"Access\")
summary = engine.summary()
assert \"total_controls\" in summary
assert \"compliance_score\" in summary
'
"

run_test "Summary includes risk areas" "
python_test '
from security_ai.advanced_compliance_automation import AdvancedComplianceAutomation
engine = AdvancedComplianceAutomation()
engine.register_control(\"AC-1\", \"soc2\", \"access_control\", \"Access\")
engine.log_violation(\"AC-1\", \"critical\", \"Critical violation\")
summary = engine.summary()
assert len(summary[\"risk_areas\"]) > 0
'
"

# GROUP 10: Ops Orchestrator
echo ""
echo "GROUP 10: Ops Orchestrator"
run_test "Ops script syntax validation" "
bash -n ${PROJECT_ROOT}/scripts/ops/phase-42-compliance-automation.sh
"

run_test "Ops demo mode" "
output=\$(bash ${PROJECT_ROOT}/scripts/ops/phase-42-compliance-automation.sh demo 2>&1); echo \"\$output\" | grep -q 'PHASE 42'
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
