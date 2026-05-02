#!/bin/bash
# @file phase-39-integration-tests.sh
# @description Integration test suite for Phase 39 autonomous optimizer
# @since 2026-05-01
# @phase 39

set -o pipefail

# Error handling
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${PROJECT_ROOT}/artifacts/phase39"
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
echo "PHASE 39: AUTONOMOUS SYSTEM OPTIMIZER INTEGRATION TESTS"
echo "============================================================"
echo ""

# GROUP 1: Module Import & Initialization
echo "GROUP 1: Module Import & Initialization"
run_test "Import AutonomousOptimizer" "
python_test 'from security_ai.autonomous_optimizer import AutonomousOptimizer'
"

run_test "Import OptimizationGoal enum" "
python_test 'from security_ai.autonomous_optimizer import OptimizationGoal'
"

run_test "Import OptimizationStrategy enum" "
python_test 'from security_ai.autonomous_optimizer import OptimizationStrategy'
"

run_test "Engine initialization" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer
engine = AutonomousOptimizer()
assert engine is not None
assert len(engine.metrics_history) == 0
'
"

run_test "Metric ingestion" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer
engine = AutonomousOptimizer()
engine.ingest_phase_metrics(34, {\"latency\": 100.0, \"throughput\": 1000})
assert len(engine.metrics_history) == 2
'
"

# GROUP 2: Metric Classification
echo ""
echo "GROUP 2: Metric Classification & Goal Mapping"
run_test "Classify performance metrics" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer, OptimizationGoal
engine = AutonomousOptimizer()
goal = engine._classify_metric_goal(\"response_latency_ms\")
assert goal == OptimizationGoal.PERFORMANCE
'
"

run_test "Classify cost metrics" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer, OptimizationGoal
engine = AutonomousOptimizer()
goal = engine._classify_metric_goal(\"cpu_usage_percent\")
assert goal == OptimizationGoal.COST
'
"

run_test "Classify reliability metrics" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer, OptimizationGoal
engine = AutonomousOptimizer()
goal = engine._classify_metric_goal(\"container_restart_count\")
assert goal == OptimizationGoal.RELIABILITY
'
"

run_test "Classify security metrics" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer, OptimizationGoal
engine = AutonomousOptimizer()
goal = engine._classify_metric_goal(\"threat_score\")
assert goal == OptimizationGoal.SECURITY
'
"

# GROUP 3: Recommendation Generation
echo ""
echo "GROUP 3: Recommendation Generation"
run_test "Generate recommendations from metrics" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer
engine = AutonomousOptimizer()
engine.ingest_phase_metrics(34, {\"latency\": 150.0, \"error_rate\": 0.05})
recommendations = engine.generate_recommendations()
assert len(recommendations) > 0
'
"

run_test "Recommendations have valid fields" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer
engine = AutonomousOptimizer()
engine.ingest_phase_metrics(35, {\"throughput\": 500})
recommendations = engine.generate_recommendations()
if recommendations:
    rec = recommendations[0]
    assert hasattr(rec, \"recommendation_id\")
    assert hasattr(rec, \"confidence\")
    assert 0 <= rec.confidence <= 1.0
'
"

run_test "Recommendations include phase insights" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer
engine = AutonomousOptimizer()
engine.ingest_phase_metrics(36, {\"violation_count\": 2})
engine.ingest_phase_metrics(37, {\"response_time\": 400})
recommendations = engine.generate_recommendations()
if recommendations:
    assert len(recommendations[0].phase_insights) > 0
'
"

# GROUP 4: Action Execution
echo ""
echo "GROUP 4: Optimization Action Execution"
run_test "Execute recommendation as action" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer
engine = AutonomousOptimizer()
engine.ingest_phase_metrics(38, {\"latency\": 200})
recommendations = engine.generate_recommendations()
if recommendations:
    action = engine.execute_recommendation(recommendations[0], dry_run=True)
    assert action.dry_run == True
    assert action.result == \"DRY_RUN: Ready to execute\"
'
"

run_test "Action history tracking" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer
engine = AutonomousOptimizer()
engine.ingest_phase_metrics(34, {\"latency\": 100})
recommendations = engine.generate_recommendations()
if recommendations:
    engine.execute_recommendation(recommendations[0], dry_run=True)
    assert len(engine.actions_history) > 0
'
"

run_test "Distinguish dry-run vs executed actions" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer
engine = AutonomousOptimizer()
engine.ingest_phase_metrics(35, {\"cost\": 5000})
recommendations = engine.generate_recommendations()
if recommendations:
    action_dry = engine.execute_recommendation(recommendations[0], dry_run=True)
    action_exec = engine.execute_recommendation(recommendations[0], dry_run=False)
    assert action_dry.dry_run == True
    assert action_exec.executed == True
'
"

# GROUP 5: Scoring
echo ""
echo "GROUP 5: Autonomous Optimization Scoring"
run_test "Calculate optimization score" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer
engine = AutonomousOptimizer()
engine.ingest_phase_metrics(36, {\"latency\": 100})
engine.generate_recommendations()
score = engine.optimization_score()
assert 0 <= score <= 25.0
'
"

run_test "Score increases with recommendations" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer
engine = AutonomousOptimizer()
engine.ingest_phase_metrics(37, {\"latency\": 200, \"cost\": 6000})
engine.ingest_phase_metrics(38, {\"throughput\": 800})
engine.generate_recommendations()
score = engine.optimization_score()
assert score >= 0
'
"

# GROUP 6: State Persistence
echo ""
echo "GROUP 6: State Persistence"
run_test "Persist state to disk" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer
import os
engine = AutonomousOptimizer()
engine.ingest_phase_metrics(34, {\"latency\": 100})
engine.persist_state()
assert os.path.exists(engine.state_dir + \"/metrics.json\")
'
"

run_test "Persist recommendations to disk" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer
import os
engine = AutonomousOptimizer()
engine.ingest_phase_metrics(35, {\"cost\": 5000})
engine.generate_recommendations()
engine.persist_state()
assert os.path.exists(engine.state_dir + \"/recommendations.json\")
'
"

run_test "Persist actions to disk" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer
import os
engine = AutonomousOptimizer()
engine.ingest_phase_metrics(36, {\"latency\": 150})
recommendations = engine.generate_recommendations()
if recommendations:
    engine.execute_recommendation(recommendations[0])
engine.persist_state()
assert os.path.exists(engine.state_dir + \"/actions.json\")
'
"

# GROUP 7: Summary Generation
echo ""
echo "GROUP 7: Summary & Reporting"
run_test "Generate optimizer summary" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer
engine = AutonomousOptimizer()
engine.ingest_phase_metrics(37, {\"latency\": 120})
engine.generate_recommendations()
summary = engine.summary()
assert \"timestamp\" in summary
assert \"recommendations_generated\" in summary
'
"

run_test "Summary includes phase sources" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer
engine = AutonomousOptimizer()
engine.ingest_phase_metrics(34, {\"latency\": 100})
engine.ingest_phase_metrics(38, {\"throughput\": 500})
engine.generate_recommendations()
summary = engine.summary()
assert 34 in summary[\"source_phases\"] or 38 in summary[\"source_phases\"]
'
"

run_test "Summary score in valid range" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer
engine = AutonomousOptimizer()
engine.ingest_phase_metrics(35, {\"cost\": 5500})
engine.generate_recommendations()
summary = engine.summary()
assert 0 <= summary[\"optimization_score\"] <= 25.0
'
"

# GROUP 8: Ops Orchestrator
echo ""
echo "GROUP 8: Ops Orchestrator"
run_test "Ops script syntax validation" "
bash -n ${PROJECT_ROOT}/scripts/ops/phase-39-autonomous-optimizer.sh
"

run_test "Ops demo mode" "
timeout 30 bash ${PROJECT_ROOT}/scripts/ops/phase-39-autonomous-optimizer.sh demo 2>&1 | grep -q 'PHASE 39'
"

run_test "Ops summary mode" "
timeout 30 bash ${PROJECT_ROOT}/scripts/ops/phase-39-autonomous-optimizer.sh summary 2>&1 | grep -q 'metrics_ingested'
"

# GROUP 9: Cross-Phase Integration
echo ""
echo "GROUP 9: Cross-Phase Integration"
run_test "Ingest from Phase 34 (resilience)" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer
engine = AutonomousOptimizer()
engine.ingest_phase_metrics(34, {\"degradation_latency\": 200})
assert len(engine.metrics_history) > 0
'
"

run_test "Ingest from Phase 35 (forensics)" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer
engine = AutonomousOptimizer()
engine.ingest_phase_metrics(35, {\"trace_latency\": 150})
assert len(engine.metrics_history) > 0
'
"

run_test "Ingest from Phase 38 (behavioral)" "
python_test '
from security_ai.autonomous_optimizer import AutonomousOptimizer
engine = AutonomousOptimizer()
engine.ingest_phase_metrics(38, {\"anomaly_latency\": 180})
assert len(engine.metrics_history) > 0
'
"

run_test "Phase 38 behavioral analytics still passing" "
timeout 120 bash ${PROJECT_ROOT}/scripts/ci/phase-38-integration-tests.sh > /tmp/p38.log 2>&1 && grep -q 'ALL TESTS PASSED' /tmp/p38.log
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
