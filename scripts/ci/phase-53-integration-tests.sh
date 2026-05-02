#!/bin/bash
# @file phase-53-integration-tests.sh
# @description Integration tests for Phase 53 — Behavioral Anomaly Detection Engine
# @since 2026-05-01

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p53*.* /tmp/p53_reg52.log 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

PASS=0; FAIL=0; TOTAL=0

run_test() {
    local name="$1" cmd="$2"
    ((TOTAL++)) || true
    if eval "$cmd" > /tmp/p53_last.out 2>&1; then
        echo "  ✓ $name"; ((PASS++)) || true
    else
        echo "  ✗ $name"; ((FAIL++)) || true
        [[ -s /tmp/p53_last.out ]] && head -5 /tmp/p53_last.out | sed 's/^/    /'
    fi
}

py() {
    "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
$1
PYEOF
}

echo ""
echo "============================================================"
echo "  PHASE 53 — BEHAVIORAL ANOMALY DETECTION ENGINE"
echo "============================================================"
echo ""

# -----------------------------------------------------------------------
# GROUP 1: Module imports
# -----------------------------------------------------------------------
echo "GROUP 1: Module imports"

run_test "BehavioralAnomalyDetector importable" \
    "py 'from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector; print(\"ok\")' | grep -q ok"

run_test "AnomalySeverity importable" \
    "py 'from security_ai.behavioral_anomaly_detection import AnomalySeverity; print(\"ok\")' | grep -q ok"

run_test "DriftDirection importable" \
    "py 'from security_ai.behavioral_anomaly_detection import DriftDirection; print(\"ok\")' | grep -q ok"

run_test "DetectionMode importable" \
    "py 'from security_ai.behavioral_anomaly_detection import DetectionMode; print(\"ok\")' | grep -q ok"

run_test "ScoreObservation importable" \
    "py 'from security_ai.behavioral_anomaly_detection import ScoreObservation; print(\"ok\")' | grep -q ok"

run_test "AnomalyEvent importable" \
    "py 'from security_ai.behavioral_anomaly_detection import AnomalyEvent; print(\"ok\")' | grep -q ok"

run_test "PhaseBaseline importable" \
    "py 'from security_ai.behavioral_anomaly_detection import PhaseBaseline; print(\"ok\")' | grep -q ok"

run_test "anomaly_score helper importable" \
    "py 'from security_ai.behavioral_anomaly_detection import anomaly_score; print(\"ok\")' | grep -q ok"

run_test "AnomalySeverity has 4 values" \
    "py '
from security_ai.behavioral_anomaly_detection import AnomalySeverity
assert len(list(AnomalySeverity)) == 4
print(\"ok\")
' | grep -q ok"

run_test "DriftDirection has 3 values" \
    "py '
from security_ai.behavioral_anomaly_detection import DriftDirection
assert len(list(DriftDirection)) == 3
print(\"ok\")
' | grep -q ok"

run_test "DetectionMode has 4 values" \
    "py '
from security_ai.behavioral_anomaly_detection import DetectionMode
assert len(list(DetectionMode)) == 4
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 2: PhaseBaseline statistics
# -----------------------------------------------------------------------
echo ""
echo "GROUP 2: PhaseBaseline statistics"

run_test "Empty baseline mean=0" \
    "py '
from security_ai.behavioral_anomaly_detection import PhaseBaseline
b = PhaseBaseline(phase_source=\"p\")
assert b.mean == 0.0
print(\"ok\")
' | grep -q ok"

run_test "Empty baseline std=0" \
    "py '
from security_ai.behavioral_anomaly_detection import PhaseBaseline
b = PhaseBaseline(phase_source=\"p\")
assert b.std == 0.0
print(\"ok\")
' | grep -q ok"

run_test "Single observation std=0" \
    "py '
from security_ai.behavioral_anomaly_detection import PhaseBaseline
b = PhaseBaseline(phase_source=\"p\")
b.add(18.0)
assert b.std == 0.0
print(\"ok\")
' | grep -q ok"

run_test "is_ready() True with 3+ observations" \
    "py '
from security_ai.behavioral_anomaly_detection import PhaseBaseline
b = PhaseBaseline(phase_source=\"p\")
for v in [18.0, 19.0, 20.0]:
    b.add(v)
assert b.is_ready()
print(\"ok\")
' | grep -q ok"

run_test "is_ready() False with < 3 observations" \
    "py '
from security_ai.behavioral_anomaly_detection import PhaseBaseline
b = PhaseBaseline(phase_source=\"p\")
b.add(18.0); b.add(19.0)
assert not b.is_ready()
print(\"ok\")
' | grep -q ok"

run_test "rolling window capped at window_size" \
    "py '
from security_ai.behavioral_anomaly_detection import PhaseBaseline
b = PhaseBaseline(phase_source=\"p\", window_size=5)
for v in range(10):
    b.add(float(v))
assert len(b.observations) == 5
print(\"ok\")
' | grep -q ok"

run_test "z_score 0 when std=0" \
    "py '
from security_ai.behavioral_anomaly_detection import PhaseBaseline
b = PhaseBaseline(phase_source=\"p\")
b.add(18.0); b.add(18.0); b.add(18.0)
assert b.z_score(18.0) == 0.0
print(\"ok\")
' | grep -q ok"

run_test "trend DEGRADING with declining scores" \
    "py '
from security_ai.behavioral_anomaly_detection import PhaseBaseline, DriftDirection
b = PhaseBaseline(phase_source=\"p\")
for v in [20.0, 19.0, 18.0, 17.0, 16.0]:
    b.add(v)
assert b.trend == DriftDirection.DEGRADING, b.trend
print(\"ok\")
' | grep -q ok"

run_test "trend IMPROVING with rising scores" \
    "py '
from security_ai.behavioral_anomaly_detection import PhaseBaseline, DriftDirection
b = PhaseBaseline(phase_source=\"p\")
for v in [15.0, 16.0, 17.0, 18.0, 19.0]:
    b.add(v)
assert b.trend == DriftDirection.IMPROVING, b.trend
print(\"ok\")
' | grep -q ok"

run_test "trend STABLE with flat scores" \
    "py '
from security_ai.behavioral_anomaly_detection import PhaseBaseline, DriftDirection
b = PhaseBaseline(phase_source=\"p\")
for v in [18.0, 18.1, 17.9, 18.0, 18.1]:
    b.add(v)
assert b.trend == DriftDirection.STABLE, b.trend
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 3: Severity classification
# -----------------------------------------------------------------------
echo ""
echo "GROUP 3: AnomalySeverity classification"

run_test "z-score 3.0 → CRITICAL" \
    "py '
from security_ai.behavioral_anomaly_detection import _classify_severity, AnomalySeverity
assert _classify_severity(3.0) == AnomalySeverity.CRITICAL
print(\"ok\")
' | grep -q ok"

run_test "z-score -3.5 → CRITICAL" \
    "py '
from security_ai.behavioral_anomaly_detection import _classify_severity, AnomalySeverity
assert _classify_severity(-3.5) == AnomalySeverity.CRITICAL
print(\"ok\")
' | grep -q ok"

run_test "z-score 2.0 → HIGH" \
    "py '
from security_ai.behavioral_anomaly_detection import _classify_severity, AnomalySeverity
assert _classify_severity(2.0) == AnomalySeverity.HIGH
print(\"ok\")
' | grep -q ok"

run_test "z-score 1.5 → MEDIUM" \
    "py '
from security_ai.behavioral_anomaly_detection import _classify_severity, AnomalySeverity
assert _classify_severity(1.5) == AnomalySeverity.MEDIUM
print(\"ok\")
' | grep -q ok"

run_test "z-score 1.0 → LOW" \
    "py '
from security_ai.behavioral_anomaly_detection import _classify_severity, AnomalySeverity
assert _classify_severity(1.0) == AnomalySeverity.LOW
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 4: observe() and detection
# -----------------------------------------------------------------------
echo ""
echo "GROUP 4: observe() detection"

run_test "No event before baseline is ready" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector
d = BehavioralAnomalyDetector()
evt = d.observe(\"p47\", 18.0)
assert evt is None
print(\"ok\")
' | grep -q ok"

run_test "No event on stable score" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector
d = BehavioralAnomalyDetector()
for v in [18.0, 19.0, 18.5, 19.0, 18.5]:
    d.observe(\"p47\", v)
# 6th stable obs → no anomaly
evt = d.observe(\"p47\", 18.8)
assert evt is None
print(\"ok\")
' | grep -q ok"

run_test "Extreme low score triggers anomaly" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector
d = BehavioralAnomalyDetector()
for v in [18.0, 19.0, 18.5, 19.0, 18.5, 18.0]:
    d.observe(\"p47\", v)
evt = d.observe(\"p47\", 6.0)
assert evt is not None, \"expected anomaly\"
print(\"ok\")
' | grep -q ok"

run_test "Extreme score gets CRITICAL severity" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector, AnomalySeverity
d = BehavioralAnomalyDetector()
for v in [18.0, 19.0, 18.5, 19.0, 18.5, 18.0]:
    d.observe(\"p47\", v)
evt = d.observe(\"p47\", 4.0)
assert evt is not None
assert evt.severity == AnomalySeverity.CRITICAL, evt.severity
print(\"ok\")
' | grep -q ok"

run_test "Hard threshold low (≤5.0) triggers anomaly" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector
d = BehavioralAnomalyDetector(hard_threshold_low=5.0)
for v in [18.0, 18.0, 18.0]:
    d.observe(\"p47\", v)
evt = d.observe(\"p47\", 5.0)
assert evt is not None
print(\"ok\")
' | grep -q ok"

run_test "Hard threshold high (≥23.0) triggers anomaly" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector
d = BehavioralAnomalyDetector(hard_threshold_high=23.0)
for v in [18.0, 18.0, 18.0]:
    d.observe(\"p47\", v)
evt = d.observe(\"p47\", 23.0)
assert evt is not None
print(\"ok\")
' | grep -q ok"

run_test "Anomaly is logged to anomaly_log" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector
d = BehavioralAnomalyDetector()
for v in [18.0, 19.0, 18.5, 19.0, 18.5, 18.0]:
    d.observe(\"p47\", v)
d.observe(\"p47\", 4.0)
assert len(d.anomaly_log) == 1
print(\"ok\")
' | grep -q ok"

run_test "AnomalyEvent has all required fields" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector
d = BehavioralAnomalyDetector()
for v in [18.0, 19.0, 18.5, 19.0, 18.5, 18.0]:
    d.observe(\"p47\", v)
evt = d.observe(\"p47\", 4.0)
assert evt is not None
for attr in [\"event_id\",\"phase_source\",\"score\",\"z_score\",\"severity\",\"direction\",\"mode\"]:
    assert hasattr(evt, attr), f\"missing {attr}\"
print(\"ok\")
' | grep -q ok"

run_test "phase53_contribution ≤ 25.0" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector
d = BehavioralAnomalyDetector()
for v in [18.0, 19.0, 18.5, 19.0, 18.5, 18.0]:
    d.observe(\"p47\", v)
evt = d.observe(\"p47\", 4.0)
assert evt is not None
assert 0.0 <= evt.phase53_contribution <= 25.0
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 5: observe_batch
# -----------------------------------------------------------------------
echo ""
echo "GROUP 5: observe_batch()"

run_test "observe_batch returns list of anomalies" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector
d = BehavioralAnomalyDetector()
# Seed baseline for two phases
for v in [18.0, 19.0, 18.5, 19.0, 18.5, 18.0]:
    d.observe(\"p47\", v)
    d.observe(\"p48\", v + 1)
evts = d.observe_batch([(\"p47\", 4.0), (\"p48\", 4.0)])
assert isinstance(evts, list)
assert len(evts) == 2
print(\"ok\")
' | grep -q ok"

run_test "observe_batch stable observations return empty list" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector
d = BehavioralAnomalyDetector()
evts = d.observe_batch([(\"p47\", 18.0), (\"p48\", 19.0)])
assert evts == []
print(\"ok\")
' | grep -q ok"

run_test "observation_count increments per observe" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector
d = BehavioralAnomalyDetector()
d.observe_batch([(\"p47\", v) for v in [18.0, 19.0, 18.5]])
assert d.observation_count == 3
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 6: Scoring
# -----------------------------------------------------------------------
echo ""
echo "GROUP 6: phase53_score()"

run_test "No observations → score=0.0" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector, anomaly_score
d = BehavioralAnomalyDetector()
assert anomaly_score(d) == 0.0
print(\"ok\")
' | grep -q ok"

run_test "All observations stable → score=25.0" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector, anomaly_score
d = BehavioralAnomalyDetector()
for v in [18.0, 18.5, 18.0, 18.5, 18.0, 18.5, 18.0, 18.5, 18.0, 18.5]:
    d.observe(\"p47\", v)
assert anomaly_score(d) == 25.0
print(\"ok\")
' | grep -q ok"

run_test "score after critical anomaly is < 25.0" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector, anomaly_score
d = BehavioralAnomalyDetector()
for v in [18.0, 19.0, 18.5, 19.0, 18.5, 18.0]:
    d.observe(\"p47\", v)
d.observe(\"p47\", 4.0)
assert anomaly_score(d) < 25.0, anomaly_score(d)
print(\"ok\")
' | grep -q ok"

run_test "score is in [0.0, 25.0]" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector, anomaly_score
d = BehavioralAnomalyDetector()
for _ in range(5):
    d.observe(\"p47\", 18.0)
for _ in range(10):
    d.observe(\"p47\", 4.0)
sc = anomaly_score(d)
assert 0.0 <= sc <= 25.0, sc
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 7: summary()
# -----------------------------------------------------------------------
echo ""
echo "GROUP 7: summary()"

run_test "summary() contains required keys" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector
d = BehavioralAnomalyDetector()
s = d.summary()
for k in [\"total_observations\",\"active_baselines\",\"total_anomalies\",
          \"severity_breakdown\",\"phase53_score\"]:
    assert k in s, f\"missing {k}\"
print(\"ok\")
' | grep -q ok"

run_test "summary severity_breakdown tracks critical count" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector
d = BehavioralAnomalyDetector()
for v in [18.0, 19.0, 18.5, 19.0, 18.5, 18.0]:
    d.observe(\"p47\", v)
d.observe(\"p47\", 4.0)
s = d.summary()
assert s[\"severity_breakdown\"][\"critical\"] >= 1
print(\"ok\")
' | grep -q ok"

run_test "summary active_baselines counted correctly" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector
d = BehavioralAnomalyDetector()
d.observe(\"p47\", 18.0)
d.observe(\"p48\", 19.0)
s = d.summary()
assert s[\"active_baselines\"] == 2
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 8: generate_report()
# -----------------------------------------------------------------------
echo ""
echo "GROUP 8: generate_report()"

run_test "report for specific phase has correct keys" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector
d = BehavioralAnomalyDetector()
for v in [18.0, 18.5, 19.0]:
    d.observe(\"p47\", v)
r = d.generate_report(\"p47\")
for k in [\"phase_source\",\"anomaly_count\",\"baseline_mean\",\"baseline_std\",\"events\"]:
    assert k in r, f\"missing {k}\"
print(\"ok\")
' | grep -q ok"

run_test "report baseline_mean within expected range" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector
d = BehavioralAnomalyDetector()
for v in [18.0, 18.5, 19.0]:
    d.observe(\"p47\", v)
r = d.generate_report(\"p47\")
assert 18.0 <= r[\"baseline_mean\"] <= 19.0, r[\"baseline_mean\"]
print(\"ok\")
' | grep -q ok"

run_test "report for all phases phase_source='all'" \
    "py '
from security_ai.behavioral_anomaly_detection import BehavioralAnomalyDetector
d = BehavioralAnomalyDetector()
r = d.generate_report()
assert r[\"phase_source\"] == \"all\"
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 9: Ops script
# -----------------------------------------------------------------------
echo ""
echo "GROUP 9: Ops script integration"

OPS="${PROJECT_ROOT}/scripts/ops/phase-53-behavioral-anomaly-detection.sh"
[[ -x "$OPS" ]] || chmod +x "$OPS"

run_test "Ops script exists" "[[ -f '$OPS' ]]"

run_test "demo mode exits 0" \
    "bash '$OPS' demo > /tmp/p53demo.out 2>&1"

run_test "demo outputs PHASE 53" \
    "grep -q 'PHASE 53' /tmp/p53demo.out"

run_test "demo shows Phase 53 Score" \
    "grep -q 'Phase 53 Score' /tmp/p53demo.out"

run_test "summary mode outputs valid JSON" \
    "bash '$OPS' summary > /tmp/p53sum.out 2>&1 && python3 -c 'import json; json.load(open(\"/tmp/p53sum.out\"))'"

run_test "summary contains phase53_score" \
    "python3 -c 'import json; d=json.load(open(\"/tmp/p53sum.out\")); assert \"phase53_score\" in d'"

run_test "scan mode exits 0" \
    "bash '$OPS' scan phase_51 > /tmp/p53scan.out 2>&1"

run_test "scan outputs valid JSON" \
    "python3 -c 'import json; json.load(open(\"/tmp/p53scan.out\"))'"

# -----------------------------------------------------------------------
# GROUP 10: Phase 52 regression guard
# -----------------------------------------------------------------------
echo ""
echo "GROUP 10: Phase 52 regression guard"

run_test "Phase 52 integration suite still passes" \
    "timeout 150 bash '${PROJECT_ROOT}/scripts/ci/phase-52-integration-tests.sh' > /tmp/p53_reg52.log 2>&1"

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "============================================================"
echo "PHASE 53 TEST RESULTS"
echo "============================================================"
echo "PASS:  $PASS"
echo "FAIL:  $FAIL"
echo "TOTAL: $TOTAL"
echo "============================================================"

if [[ $FAIL -eq 0 ]]; then
    echo ""
    echo "✅  ALL TESTS PASSED — Phase 53 Behavioral Anomaly Detection verified"
    exit 0
else
    echo ""
    echo "❌  SOME TESTS FAILED"
    exit 1
fi
