#!/bin/bash
# @file phase-44-integration-tests.sh
# @description Integration test suite for Phase 44 platform orchestration
# @since 2026-05-01
# @phase 44

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${PROJECT_ROOT}/artifacts/phase44"
PYTHON_CMD="python3"
if [[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]]; then
    PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"
fi

PASS=0
FAIL=0
TOTAL=0

cleanup_state() {
    mkdir -p "$STATE_DIR"
    rm -f "$STATE_DIR"/*.json
}

run_python_test() {
    local test_name="$1"
    local test_code="$2"
    TOTAL=$((TOTAL + 1))
    cleanup_state

    if "$PYTHON_CMD" - <<PYEOF > /tmp/test_output.log 2>&1
import sys
sys.path.insert(0, "${PROJECT_ROOT}/apps")
${test_code}
PYEOF
    then
        echo "  ✓ $test_name"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $test_name"
        echo "    [Debug] Output saved to /tmp/test_output.log"
        FAIL=$((FAIL + 1))
    fi
}

run_shell_test() {
    local test_name="$1"
    local test_cmd="$2"
    TOTAL=$((TOTAL + 1))
    cleanup_state

    if eval "$test_cmd" > /tmp/test_output.log 2>&1; then
        echo "  ✓ $test_name"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $test_name"
        echo "    [Debug] Output saved to /tmp/test_output.log"
        FAIL=$((FAIL + 1))
    fi
}

echo "============================================================"
echo "PHASE 44: PLATFORM ORCHESTRATION INTEGRATION TESTS"
echo "============================================================"
echo ""

echo "GROUP 1: Module Import & Initialization"
run_python_test "Import PlatformOrchestration" "from security_ai.platform_orchestration import PlatformOrchestration"
run_python_test "Import OrchestrationStrategy enum" "from security_ai.platform_orchestration import OrchestrationStrategy"
run_python_test "Import ExecutionStatus enum" "from security_ai.platform_orchestration import ExecutionStatus"
run_python_test "Engine initialization" "
from security_ai.platform_orchestration import PlatformOrchestration
engine = PlatformOrchestration()
assert engine is not None
assert len(engine.services) == 0
"

echo ""
echo "GROUP 2: Service Registration"
run_python_test "Register service node" "
from security_ai.platform_orchestration import PlatformOrchestration
engine = PlatformOrchestration()
svc = engine.register_service('api-gateway', 'core', ['auth'], 0.8, 0.6, 0.7, 41)
assert svc.service_id in engine.services
"
run_python_test "Register multiple services" "
from security_ai.platform_orchestration import PlatformOrchestration
engine = PlatformOrchestration()
engine.register_service('api-gateway', 'core', ['auth'], 0.8, 0.6, 0.7, 41)
engine.register_service('auth', 'critical', [], 0.9, 0.5, 0.6, 42)
assert len(engine.services) == 2
"

echo ""
echo "GROUP 3: Phase Signal Ingestion"
run_python_test "Ingest phase signal" "
from security_ai.platform_orchestration import PlatformOrchestration
engine = PlatformOrchestration()
engine.ingest_phase_signal(40, 'predictive', {'forecasted_threats': 3})
assert 40 in engine.phase_signals
"
run_python_test "Ingest multiple phase signals" "
from security_ai.platform_orchestration import PlatformOrchestration
engine = PlatformOrchestration()
engine.ingest_phase_signal(40, 'predictive', {'x': 1})
engine.ingest_phase_signal(41, 'response', {'x': 2})
engine.ingest_phase_signal(42, 'compliance', {'x': 3})
engine.ingest_phase_signal(43, 'hunting', {'x': 4})
assert len(engine.phase_signals) == 4
"

echo ""
echo "GROUP 4: Plan Generation"
run_python_test "Create orchestration plan" "
from security_ai.platform_orchestration import PlatformOrchestration
engine = PlatformOrchestration()
engine.ingest_phase_signal(40, 'predictive', {'x': 1})
engine.register_service('api-gateway', 'core', ['auth'], 0.7, 0.8, 0.9, 41)
plan = engine.create_orchestration_plan('stabilize')
assert plan.plan_id in engine.plans
assert len(plan.actions) > 0
"
run_python_test "Create plan with strategy" "
from security_ai.platform_orchestration import PlatformOrchestration, OrchestrationStrategy
engine = PlatformOrchestration()
engine.ingest_phase_signal(40, 'predictive', {'x': 1})
engine.register_service('auth', 'critical', [], 0.6, 0.7, 0.8, 42)
plan = engine.create_orchestration_plan('secure', OrchestrationStrategy.SECURITY_FIRST.value)
assert plan.strategy == OrchestrationStrategy.SECURITY_FIRST.value
"

echo ""
echo "GROUP 5: Plan Validation"
run_python_test "Validate plan" "
from security_ai.platform_orchestration import PlatformOrchestration
engine = PlatformOrchestration()
engine.ingest_phase_signal(40, 'predictive', {'x': 1})
engine.register_service('auth', 'core', [], 0.8, 0.6, 0.7, 42)
plan = engine.create_orchestration_plan('validate')
validation = engine.validate_plan(plan.plan_id)
assert validation is not None
assert 'has_actions' in validation
"
run_python_test "Validation detects signal context" "
from security_ai.platform_orchestration import PlatformOrchestration
engine = PlatformOrchestration()
engine.register_service('auth', 'core', [], 0.8, 0.6, 0.7, 42)
plan = engine.create_orchestration_plan('validate')
validation = engine.validate_plan(plan.plan_id)
assert validation['signal_context_present'] == False
"

echo ""
echo "GROUP 6: Execution"
run_python_test "Execute plan dry-run" "
from security_ai.platform_orchestration import PlatformOrchestration
engine = PlatformOrchestration()
engine.ingest_phase_signal(40, 'predictive', {'x': 1})
engine.register_service('api-gateway', 'core', ['auth'], 0.7, 0.8, 0.9, 41)
plan = engine.create_orchestration_plan('execute')
engine.validate_plan(plan.plan_id)
run = engine.execute_plan(plan.plan_id, dry_run=True)
assert run.status == 'dry_run'
assert run.actions_executed > 0
"
run_python_test "Execute plan real mode" "
from security_ai.platform_orchestration import PlatformOrchestration
engine = PlatformOrchestration()
engine.ingest_phase_signal(41, 'response', {'x': 1})
engine.register_service('auth', 'critical', [], 0.6, 0.8, 0.9, 41)
plan = engine.create_orchestration_plan('execute')
engine.validate_plan(plan.plan_id)
run = engine.execute_plan(plan.plan_id, dry_run=False)
assert run.status in ['completed', 'failed']
"

echo ""
echo "GROUP 7: Scoring"
run_python_test "Orchestration score in range" "
from security_ai.platform_orchestration import PlatformOrchestration
engine = PlatformOrchestration()
score = engine.orchestration_score()
assert 0 <= score <= 25.0
"
run_python_test "Score increases with validated run" "
from security_ai.platform_orchestration import PlatformOrchestration
engine = PlatformOrchestration()
engine.ingest_phase_signal(40, 'predictive', {'x': 1})
engine.ingest_phase_signal(41, 'response', {'x': 1})
engine.register_service('api-gateway', 'core', ['auth'], 0.7, 0.8, 0.9, 41)
plan = engine.create_orchestration_plan('score')
engine.validate_plan(plan.plan_id)
engine.execute_plan(plan.plan_id, dry_run=True)
assert engine.orchestration_score() > 0
"

echo ""
echo "GROUP 8: Report & Summary"
run_python_test "Generate orchestration report" "
from security_ai.platform_orchestration import PlatformOrchestration
engine = PlatformOrchestration()
report = engine.generate_orchestration_report()
assert 'plans_created' in report
assert 'orchestration_score' in report
"
run_python_test "Generate summary" "
from security_ai.platform_orchestration import PlatformOrchestration
engine = PlatformOrchestration()
summary = engine.summary()
assert 'services' in summary
assert 'orchestration_score' in summary
"

echo ""
echo "GROUP 9: State Persistence"
run_python_test "Persist services to disk" "
from security_ai.platform_orchestration import PlatformOrchestration
import os
engine = PlatformOrchestration()
engine.register_service('api-gateway', 'core', ['auth'], 0.7, 0.8, 0.9, 41)
engine.persist_state()
assert os.path.exists(engine.state_dir + '/services.json')
"
run_python_test "Persist plans and runs to disk" "
from security_ai.platform_orchestration import PlatformOrchestration
import os
engine = PlatformOrchestration()
engine.ingest_phase_signal(40, 'predictive', {'x': 1})
engine.register_service('api-gateway', 'core', ['auth'], 0.7, 0.8, 0.9, 41)
plan = engine.create_orchestration_plan('persist')
engine.validate_plan(plan.plan_id)
engine.execute_plan(plan.plan_id, dry_run=True)
engine.persist_state()
assert os.path.exists(engine.state_dir + '/plans.json')
assert os.path.exists(engine.state_dir + '/runs.json')
"

echo ""
echo "GROUP 10: Cross-Phase Integration"
run_python_test "Integrate Phase 40 signal" "
from security_ai.platform_orchestration import PlatformOrchestration
engine = PlatformOrchestration()
engine.ingest_phase_signal(40, 'predictive_threat_intelligence', {'forecasted_threats': 4})
assert engine.phase_signals[40]['phase_name'] == 'predictive_threat_intelligence'
"
run_python_test "Integrate Phase 43 signal" "
from security_ai.platform_orchestration import PlatformOrchestration
engine = PlatformOrchestration()
engine.ingest_phase_signal(43, 'advanced_threat_hunting', {'critical_findings': 1})
assert engine.phase_signals[43]['metrics']['critical_findings'] == 1
"

echo ""
echo "GROUP 11: Ops Orchestrator"
run_shell_test "Ops script syntax validation" "bash -n ${PROJECT_ROOT}/scripts/ops/phase-44-platform-orchestration.sh"
run_shell_test "Ops demo mode" "output=\"\$(timeout 30 bash ${PROJECT_ROOT}/scripts/ops/phase-44-platform-orchestration.sh demo 2>&1 || true)\"; echo \"\$output\" | grep -q 'PHASE 44'"
run_shell_test "Ops summary mode" "output=\"\$(timeout 30 bash ${PROJECT_ROOT}/scripts/ops/phase-44-platform-orchestration.sh summary 2>&1 || true)\"; echo \"\$output\" | grep -q 'Orchestration Score'"

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
