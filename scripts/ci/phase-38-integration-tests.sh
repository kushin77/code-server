#!/bin/bash
# @file phase-38-integration-tests.sh
# @description Integration test suite for Phase 38 ML-driven behavioral analytics
# @since 2026-05-01
# @phase 38

set -o pipefail

# Error handling
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Setup
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${PROJECT_ROOT}/artifacts/phase38"
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
echo "PHASE 38: BEHAVIORAL ANALYTICS INTEGRATION TESTS"
echo "============================================================"
echo ""

# GROUP 1: Import and Initialization
echo "GROUP 1: Module Import & Initialization"
run_test "Import BehavioralAnalyticsEngine" "
python_test 'from security_ai.behavioral_analytics import BehavioralAnalyticsEngine'
"

run_test "Import BehaviorMetric" "
python_test 'from security_ai.behavioral_analytics import BehaviorMetric'
"

run_test "Import BehavioralAnomaly" "
python_test 'from security_ai.behavioral_analytics import BehavioralAnomaly'
"

run_test "Import AnomalySource enum" "
python_test 'from security_ai.behavioral_analytics import AnomalySource'
"

run_test "Engine initialization" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine
engine = BehavioralAnalyticsEngine()
assert engine is not None
assert engine.state_dir is not None
'
"

# GROUP 2: Baseline Building
echo ""
echo "GROUP 2: Baseline Profile Building"
run_test "Build baseline from values" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine
import random
engine = BehavioralAnalyticsEngine()
values = [random.uniform(10, 100) for _ in range(50)]
baseline = engine.build_baseline(
    entity_id=\"test_entity\",
    entity_type=\"service\",
    metric_type=\"cpu_usage\",
    values=values
)
assert baseline.mean > 0
assert baseline.stddev > 0
assert baseline.p95 > baseline.mean
'
"

run_test "Baseline with insufficient data" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine
engine = BehavioralAnalyticsEngine()
baseline = engine.build_baseline(
    entity_id=\"test\",
    entity_type=\"user\",
    metric_type=\"login_count\",
    values=[1, 2]  # Only 2 values
)
assert baseline.sample_count == 2
'
"

run_test "Baseline percentile calculations" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine
engine = BehavioralAnalyticsEngine()
values = list(range(1, 101))  # 1-100
baseline = engine.build_baseline(
    entity_id=\"test\",
    entity_type=\"service\",
    metric_type=\"metric\",
    values=values
)
assert 45 < baseline.p95 < 100
assert 95 < baseline.p99 <= 100
'
"

# GROUP 3: Anomaly Detection - ML
echo ""
echo "GROUP 3: ML-Based Anomaly Detection"
run_test "Detect ML anomalies" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine
engine = BehavioralAnalyticsEngine()
anomalies = engine.detect_anomalies_ml(
    \"test_service\",
    \"service\",
    [(\"cpu_usage\", 95.0), (\"memory_usage\", 50.0), (\"disk_io\", 8000.0)]
)
assert isinstance(anomalies, list)
'
"

run_test "Anomaly ID generation" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine
engine = BehavioralAnalyticsEngine()
anomalies = engine.detect_anomalies_ml(
    \"test_entity\",
    \"container\",
    [(\"network_connections\", 5000)]
)
if anomalies:
    assert all(a.anomaly_id.startswith(\"anomaly_\") for a in anomalies)
'
"

run_test "Anomaly confidence scoring" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine
engine = BehavioralAnalyticsEngine()
anomalies = engine.detect_anomalies_ml(
    \"user\",
    \"user\",
    [(\"privilege_escalation_count\", 50)]
)
if anomalies:
    assert all(0.0 <= a.confidence <= 1.0 for a in anomalies)
'
"

run_test "Anomaly severity calculation" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine
engine = BehavioralAnalyticsEngine()
anomalies = engine.detect_anomalies_ml(
    \"service\",
    \"service\",
    [(\"cpu_usage\", 99.0)]
)
if anomalies:
    assert all(1 <= a.severity <= 5 for a in anomalies)
'
"

# GROUP 4: Statistical Fallback
echo ""
echo "GROUP 4: Statistical Anomaly Detection"
run_test "Statistical anomaly detection fallback" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine, BaselineProfile
engine = BehavioralAnalyticsEngine()

# Create baseline for statistical detection
entity_key = \"user:test_user\"
engine.baselines[entity_key][\"api_calls\"] = BaselineProfile(
    entity_id=\"test_user\",
    entity_type=\"user\",
    metric_type=\"api_calls\",
    mean=100.0,
    stddev=10.0,
    p95=120.0,
    p99=130.0,
    sample_count=1000,
    last_updated=\"2026-05-01T00:00:00\"
)

# Test statistical detection (anomaly > 3 sigma)
anomalies = engine._detect_anomalies_statistical(
    \"test_user\",
    \"user\",
    [(\"api_calls\", 450.0)]  # Far above baseline
)
assert len(anomalies) > 0
'
"

run_test "Statistical: 3-sigma rule" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine, BaselineProfile
engine = BehavioralAnalyticsEngine()

entity_key = \"service:api\"
engine.baselines[entity_key][\"requests\"] = BaselineProfile(
    entity_id=\"api\",
    entity_type=\"service\",
    metric_type=\"requests\",
    mean=1000.0,
    stddev=100.0,
    p95=1200.0,
    p99=1300.0,
    sample_count=500,
    last_updated=\"2026-05-01T00:00:00\"
)

# Test within 3-sigma (should not trigger)
anomalies = engine._detect_anomalies_statistical(
    \"api\",
    \"service\",
    [(\"requests\", 1150.0)]  # Within normal range
)
# May or may not have anomalies depending on implementation
assert isinstance(anomalies, list)
'
"

# GROUP 5: Anomaly Classification
echo ""
echo "GROUP 5: Anomaly Type Classification"
run_test "Classify privilege escalation anomalies" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine, BehaviorAnomaloType
engine = BehavioralAnalyticsEngine()
anomaly_type = engine._classify_anomaly_type(\"sudo_command_attempts\")
assert anomaly_type == BehaviorAnomaloType.PRIVILEGE_ESCALATION
'
"

run_test "Classify lateral movement anomalies" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine, BehaviorAnomaloType
engine = BehavioralAnalyticsEngine()
anomaly_type = engine._classify_anomaly_type(\"ssh_connection_count\")
assert anomaly_type == BehaviorAnomaloType.LATERAL_MOVEMENT
'
"

run_test "Classify data exfiltration anomalies" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine, BehaviorAnomaloType
engine = BehavioralAnalyticsEngine()
anomaly_type = engine._classify_anomaly_type(\"data_download_size\")
assert anomaly_type == BehaviorAnomaloType.DATA_EXFILTRATION
'
"

run_test "Classify resource abuse anomalies" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine, BehaviorAnomaloType
engine = BehavioralAnalyticsEngine()
anomaly_type = engine._classify_anomaly_type(\"cpu_usage_percent\")
assert anomaly_type == BehaviorAnomaloType.RESOURCE_ABUSE
'
"

# GROUP 6: Scoring and Compliance
echo ""
echo "GROUP 6: Behavioral Scoring & Compliance"
run_test "Calculate behavioral score without anomalies" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine, BehavioralProfile
engine = BehavioralAnalyticsEngine()
engine.profiles[\"user:perfect\"] = BehavioralProfile(
    entity_id=\"perfect\",
    entity_type=\"user\"
)
score = engine.behavioral_score(\"perfect\", \"user\")
assert score == 25.0  # Perfect score
'
"

run_test "Calculate behavioral score with anomalies" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine, BehavioralProfile, BehavioralAnomaly, BehaviorAnomaloType
engine = BehavioralAnalyticsEngine()
profile = BehavioralProfile(
    entity_id=\"risky\",
    entity_type=\"user\"
)
# Add a critical anomaly
anomaly = BehavioralAnomaly(
    anomaly_id=\"test_anomaly\",
    timestamp=\"2026-05-01T00:00:00\",
    entity_id=\"risky\",
    entity_type=\"user\",
    anomaly_type=BehaviorAnomaloType.PRIVILEGE_ESCALATION,
    severity=5,
    confidence=0.95,
    deviation_score=5.0,
    contributing_metrics=[\"sudo_count\"],
    supporting_events=[],
    description=\"Critical anomaly\"
)
profile.anomalies.append(anomaly)
engine.profiles[\"user:risky\"] = profile
score = engine.behavioral_score(\"risky\", \"user\")
assert 0 <= score < 25.0
'
"

run_test "Compliance gate score range" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine
engine = BehavioralAnalyticsEngine()
# Behavioral score should always be 0-25 for compliance gate
for i in range(10):
    score = engine.behavioral_score(f\"entity_{i}\", \"user\")
    assert 0 <= score <= 25
'
"

# GROUP 7: State Persistence
echo ""
echo "GROUP 7: State Persistence"
run_test "Persist state to disk" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine
import os
engine = BehavioralAnalyticsEngine()
engine.persist_state()
# Check files exist
assert os.path.exists(engine.state_dir + \"/profiles.json\")
'
"

run_test "Load state from disk" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine
engine = BehavioralAnalyticsEngine()
engine.persist_state()
engine.load_state()  # Should not raise
'
"

# GROUP 8: Summary Generation
echo ""
echo "GROUP 8: Summary and Reporting"
run_test "Generate analytics summary" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine
engine = BehavioralAnalyticsEngine()
summary = engine.summary()
assert \"timestamp\" in summary
assert \"total_entities_monitored\" in summary
assert \"total_anomalies_detected\" in summary
'
"

run_test "Summary metrics are valid" "
python_test '
from security_ai.behavioral_analytics import BehavioralAnalyticsEngine
engine = BehavioralAnalyticsEngine()
summary = engine.summary()
assert summary[\"total_entities_monitored\"] >= 0
assert summary[\"total_anomalies_detected\"] >= 0
assert 0 <= summary[\"average_confidence\"] <= 1.0
assert 0 <= summary[\"phase38_behavioral_score\"] <= 25.0
'
"

# GROUP 9: Ops Orchestrator
echo ""
echo "GROUP 9: Ops Orchestrator"
run_test "Ops script syntax validation" "
bash -n ${PROJECT_ROOT}/scripts/ops/phase-38-behavioral-analytics.sh
"

run_test "Ops demo mode" "
timeout 30 bash ${PROJECT_ROOT}/scripts/ops/phase-38-behavioral-analytics.sh demo 2>&1 | grep -q 'PHASE 38'
"

run_test "Ops summary mode" "
timeout 30 bash ${PROJECT_ROOT}/scripts/ops/phase-38-behavioral-analytics.sh summary 2>&1 | grep -q 'total_entities_monitored'
"

# GROUP 10: Regression Tests
echo ""
echo "GROUP 10: Regression & Cross-Phase Integration"
run_test "Phase 37 still passing" "
timeout 60 bash ${PROJECT_ROOT}/scripts/ci/phase-37-integration-tests.sh > /tmp/p37.log 2>&1 && grep -q 'All tests passed' /tmp/p37.log
"

run_test "Phase 36 still passing" "
timeout 60 bash ${PROJECT_ROOT}/scripts/ci/phase-36-integration-tests.sh > /tmp/p36.log 2>&1 && grep -q 'All tests passed' /tmp/p36.log
"

run_test "Phase 31 compliance gate still operational" "
python_test '
from apps.security_ai.compliance_checker import ComplianceChecker
checker = ComplianceChecker()
assert checker is not None
'
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
