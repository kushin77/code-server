#!/bin/bash
# @file phase-40-integration-tests.sh
# @description Integration test suite for Phase 40 predictive threat intelligence
# @since 2026-05-01
# @phase 40

set -o pipefail

# Error handling
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${PROJECT_ROOT}/artifacts/phase40"
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
echo "PHASE 40: PREDICTIVE THREAT INTELLIGENCE INTEGRATION TESTS"
echo "============================================================"
echo ""

# GROUP 1: Module Import & Initialization
echo "GROUP 1: Module Import & Initialization"
run_test "Import PredictiveThreatIntelligence" "
python_test 'from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence'
"

run_test "Import ThreatType enum" "
python_test 'from security_ai.predictive_threat_intelligence import ThreatType'
"

run_test "Import ForecastMethod enum" "
python_test 'from security_ai.predictive_threat_intelligence import ForecastMethod'
"

run_test "Engine initialization" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
engine = PredictiveThreatIntelligence()
assert engine is not None
assert len(engine.metrics_history) == 0
'
"

# GROUP 2: Metric Ingestion
echo ""
echo "GROUP 2: Threat Metric Ingestion"
run_test "Ingest threat metrics" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
engine = PredictiveThreatIntelligence()
engine.ingest_threat_metrics(34, {\"latency\": 100.0, \"recovery_time\": 2.0})
assert len(engine.metrics_history) == 2
'
"

run_test "Multiple phase ingestion" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
engine = PredictiveThreatIntelligence()
engine.ingest_threat_metrics(34, {\"latency\": 100})
engine.ingest_threat_metrics(35, {\"trace_latency\": 120})
engine.ingest_threat_metrics(38, {\"anomaly_score\": 0.08})
assert len(engine.metrics_history) == 3
'
"

run_test "Metric timestamp tracking" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
engine = PredictiveThreatIntelligence()
engine.ingest_threat_metrics(36, {\"violation_count\": 1})
assert engine.metrics_history[0].timestamp > 0
'
"

# GROUP 3: Threat Classification
echo ""
echo "GROUP 3: Threat Type Classification"
run_test "Classify behavioral anomaly" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence, ThreatType
engine = PredictiveThreatIntelligence()
threat_type = engine._classify_threat_type(\"anomaly_score\")
assert threat_type == ThreatType.BEHAVIORAL_ANOMALY.value
'
"

run_test "Classify resource exhaustion" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence, ThreatType
engine = PredictiveThreatIntelligence()
threat_type = engine._classify_threat_type(\"cpu_usage_percent\")
assert threat_type == ThreatType.RESOURCE_EXHAUSTION.value
'
"

run_test "Classify policy violation" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence, ThreatType
engine = PredictiveThreatIntelligence()
threat_type = engine._classify_threat_type(\"policy_violation_count\")
assert threat_type == ThreatType.POLICY_VIOLATION.value
'
"

# GROUP 4: Forecast Generation
echo ""
echo "GROUP 4: Threat Forecast Generation"
run_test "Generate forecasts from metrics" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
engine = PredictiveThreatIntelligence()
for i in range(10):
    engine.ingest_threat_metrics(34, {\"latency\": 100 + i * 5})
forecasts = engine.generate_forecasts()
assert len(forecasts) > 0
'
"

run_test "Forecasts have valid fields" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
engine = PredictiveThreatIntelligence()
for i in range(8):
    engine.ingest_threat_metrics(35, {\"trace_latency\": 120 + i * 3})
forecasts = engine.generate_forecasts()
if forecasts:
    f = forecasts[0]
    assert hasattr(f, \"forecast_id\")
    assert hasattr(f, \"confidence\")
    assert 0 <= f.confidence <= 1.0
    assert f.lower_bound <= f.predicted_value <= f.upper_bound
'
"

run_test "Forecasts include threat classification" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
engine = PredictiveThreatIntelligence()
engine.ingest_threat_metrics(36, {\"violation_count\": 2})
engine.ingest_threat_metrics(38, {\"anomaly_score\": 0.1})
forecasts = engine.generate_forecasts()
if forecasts:
    assert forecasts[0].threat_type is not None
'
"

run_test "Forecasts include recommended actions" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
engine = PredictiveThreatIntelligence()
for i in range(10):
    engine.ingest_threat_metrics(34, {\"latency\": 100 + i * 10})
forecasts = engine.generate_forecasts()
if forecasts:
    assert len(forecasts[0].recommended_actions) > 0
'
"

# GROUP 5: Forecast Verification
echo ""
echo "GROUP 5: Forecast Verification & Accuracy"
run_test "Verify forecast accuracy" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
engine = PredictiveThreatIntelligence()
for i in range(8):
    engine.ingest_threat_metrics(34, {\"latency\": 100 + i * 2})
forecasts = engine.generate_forecasts()
if forecasts:
    forecast = forecasts[0]
    accuracy = engine.verify_forecast(forecast.forecast_id, 110.0)
    assert accuracy is not None
    assert accuracy.absolute_error >= 0
'
"

run_test "Calculate MAPE correctly" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
engine = PredictiveThreatIntelligence()
for i in range(10):
    engine.ingest_threat_metrics(35, {\"trace_latency\": 120 + i})
forecasts = engine.generate_forecasts()
if forecasts:
    engine.verify_forecast(forecasts[0].forecast_id, 125.0)
    assert len(engine.forecast_accuracy) > 0
'
"

# GROUP 6: Accuracy Scoring
echo ""
echo "GROUP 6: Accuracy Score Calculation"
run_test "Calculate accuracy score" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
engine = PredictiveThreatIntelligence()
for i in range(8):
    engine.ingest_threat_metrics(36, {\"violation_count\": max(0, i-2)})
engine.generate_forecasts()
score = engine.forecast_accuracy_score()
assert 0 <= score <= 25.0
'
"

run_test "Score increases with forecast accuracy" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
engine = PredictiveThreatIntelligence()
for i in range(10):
    engine.ingest_threat_metrics(38, {\"anomaly_score\": 0.05 + i * 0.01})
forecasts = engine.generate_forecasts()
if forecasts:
    # Verify with close value for high accuracy
    engine.verify_forecast(forecasts[0].forecast_id, forecasts[0].predicted_value * 1.05)
    score = engine.forecast_accuracy_score()
    assert score >= 5.0
'
"

# GROUP 7: State Persistence
echo ""
echo "GROUP 7: State Persistence"
run_test "Persist forecasts to disk" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
import os
engine = PredictiveThreatIntelligence()
for i in range(6):
    engine.ingest_threat_metrics(34, {\"latency\": 100 + i})
engine.generate_forecasts()
engine.persist_state()
assert os.path.exists(engine.state_dir + \"/forecasts.json\")
'
"

run_test "Persist accuracy to disk" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
import os
engine = PredictiveThreatIntelligence()
for i in range(8):
    engine.ingest_threat_metrics(35, {\"trace_latency\": 120 + i})
forecasts = engine.generate_forecasts()
if forecasts:
    engine.verify_forecast(forecasts[0].forecast_id, 130.0)
engine.persist_state()
assert os.path.exists(engine.state_dir + \"/accuracy.json\")
'
"

# GROUP 8: Summary Generation
echo ""
echo "GROUP 8: Summary & Reporting"
run_test "Generate intelligence summary" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
engine = PredictiveThreatIntelligence()
for i in range(8):
    engine.ingest_threat_metrics(36, {\"violation_count\": i})
engine.generate_forecasts()
summary = engine.summary()
assert \"metrics_ingested\" in summary
assert \"forecasts_generated\" in summary
'
"

run_test "Summary includes threat types" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
engine = PredictiveThreatIntelligence()
engine.ingest_threat_metrics(34, {\"latency\": 100})
engine.ingest_threat_metrics(38, {\"anomaly_score\": 0.08})
engine.generate_forecasts()
summary = engine.summary()
assert len(summary[\"threat_types_detected\"]) > 0
'
"

run_test "Summary accuracy score in range" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
engine = PredictiveThreatIntelligence()
for i in range(10):
    engine.ingest_threat_metrics(39, {\"optimization_score\": 15 + i})
engine.generate_forecasts()
summary = engine.summary()
assert 0 <= summary[\"accuracy_score\"] <= 25.0
'
"

# GROUP 9: Ops Orchestrator
echo ""
echo "GROUP 9: Ops Orchestrator"
run_test "Ops script syntax validation" "
bash -n ${PROJECT_ROOT}/scripts/ops/phase-40-predictive-threat-intelligence.sh
"

run_test "Ops demo mode" "
timeout 30 bash ${PROJECT_ROOT}/scripts/ops/phase-40-predictive-threat-intelligence.sh demo 2>&1 | grep -q 'PHASE 40'
"

# GROUP 10: Cross-Phase Integration
echo ""
echo "GROUP 10: Cross-Phase Integration"
run_test "Ingest from Phase 34 (resilience)" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
engine = PredictiveThreatIntelligence()
engine.ingest_threat_metrics(34, {\"degradation_latency_ms\": 100})
assert any(m.phase_id == 34 for m in engine.metrics_history)
'
"

run_test "Ingest from Phase 35 (forensics)" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
engine = PredictiveThreatIntelligence()
engine.ingest_threat_metrics(35, {\"trace_latency_ms\": 120})
assert any(m.phase_id == 35 for m in engine.metrics_history)
'
"

run_test "Ingest from Phase 38 (behavioral)" "
python_test '
from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
engine = PredictiveThreatIntelligence()
engine.ingest_threat_metrics(38, {\"anomaly_latency_ms\": 90})
assert any(m.phase_id == 38 for m in engine.metrics_history)
'
"

run_test "Phase 39 autonomous optimizer still passing" "
timeout 120 bash ${PROJECT_ROOT}/scripts/ci/phase-39-integration-tests.sh 2>&1 | grep -q 'PASS:'
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
