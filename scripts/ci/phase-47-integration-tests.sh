#!/bin/bash
# @file phase-47-integration-tests.sh
# @description Integration tests for Phase 47 — Risk Quantification & Threat Scoring
# @since 2026-05-01

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p47*.* /tmp/p47_reg46.log 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

PASS=0; FAIL=0; TOTAL=0

run_test() {
    local name="$1" cmd="$2"
    TOTAL=$((TOTAL + 1))
    if eval "$cmd" > /dev/null 2>&1; then
        echo "  ✓ $name"; PASS=$((PASS + 1))
    else
        echo "  ✗ $name"; FAIL=$((FAIL + 1))
    fi
}

PY() { "$PYTHON_CMD" -c "import sys; sys.path.insert(0,'${PROJECT_ROOT}/apps'); $1"; }

echo "============================================================"
echo "PHASE 47: RISK QUANTIFICATION ENGINE — INTEGRATION TESTS"
echo "============================================================"
echo ""

# GROUP 1: Module imports
echo "GROUP 1: Module Import & API Surface"
run_test "Import RiskQuantificationEngine" \
    "PY 'from security_ai.risk_quantification_engine import RiskQuantificationEngine'"
run_test "Import ThreatScoreRecord" \
    "PY 'from security_ai.risk_quantification_engine import ThreatScoreRecord'"
run_test "Import RiskFactor" \
    "PY 'from security_ai.risk_quantification_engine import RiskFactor'"
run_test "Import BusinessImpact" \
    "PY 'from security_ai.risk_quantification_engine import BusinessImpact'"
run_test "Import RiskLevel" \
    "PY 'from security_ai.risk_quantification_engine import RiskLevel'"
run_test "Import ImpactCategory" \
    "PY 'from security_ai.risk_quantification_engine import ImpactCategory'"
run_test "Import RiskTrend" \
    "PY 'from security_ai.risk_quantification_engine import RiskTrend'"
run_test "Import quantify_risk helper" \
    "PY 'from security_ai.risk_quantification_engine import quantify_risk'"

echo ""
echo "GROUP 2: RiskFactor Scoring"
run_test "risk_score is probability * impact" \
    "PY '
from security_ai.risk_quantification_engine import RiskFactor, ImpactCategory
f = RiskFactor(\"f1\", \"T\", \"phase_30\", ImpactCategory.OPERATIONAL, 0.5, 60.0)
assert abs(f.risk_score() - 30.0) < 0.01
'"
run_test "probability clamped 0-1" \
    "PY '
from security_ai.risk_quantification_engine import RiskFactor, ImpactCategory
f = RiskFactor(\"f1\", \"T\", \"phase_30\", ImpactCategory.OPERATIONAL, 2.5, 50.0)
assert f.probability == 1.0
f2 = RiskFactor(\"f2\", \"T\", \"phase_30\", ImpactCategory.OPERATIONAL, -0.5, 50.0)
assert f2.probability == 0.0
'"
run_test "impact clamped 0-100" \
    "PY '
from security_ai.risk_quantification_engine import RiskFactor, ImpactCategory
f = RiskFactor(\"f1\", \"T\", \"phase_30\", ImpactCategory.OPERATIONAL, 0.5, 150.0)
assert f.impact == 100.0
'"
run_test "CRITICAL risk_level at high score" \
    "PY '
from security_ai.risk_quantification_engine import RiskFactor, ImpactCategory, RiskLevel
f = RiskFactor(\"f1\", \"T\", \"phase_30\", ImpactCategory.OPERATIONAL, 0.9, 90.0)
assert f.risk_level() == RiskLevel.CRITICAL
'"
run_test "NEGLIGIBLE risk_level at low score" \
    "PY '
from security_ai.risk_quantification_engine import RiskFactor, ImpactCategory, RiskLevel
f = RiskFactor(\"f1\", \"T\", \"phase_30\", ImpactCategory.OPERATIONAL, 0.05, 10.0)
assert f.risk_level() == RiskLevel.NEGLIGIBLE
'"
run_test "HIGH risk_level at moderate-high score" \
    "PY '
from security_ai.risk_quantification_engine import RiskFactor, ImpactCategory, RiskLevel
f = RiskFactor(\"f1\", \"T\", \"phase_30\", ImpactCategory.FINANCIAL, 0.7, 80.0)
# 0.7 * 80 = 56 — falls in HIGH (50-70)
assert f.risk_level() == RiskLevel.HIGH
'"

echo ""
echo "GROUP 3: BusinessImpact"
run_test "total_exposure_usd includes downtime cost" \
    "PY '
from security_ai.risk_quantification_engine import BusinessImpact
b = BusinessImpact(financial_loss_usd=50000, downtime_hours=4.0)
# 4 * 15000 = 60000 + 50000 = 110000
assert b.total_exposure_usd() == 110000.0
'"
run_test "severity_label catastrophic above 1M" \
    "PY '
from security_ai.risk_quantification_engine import BusinessImpact
b = BusinessImpact(financial_loss_usd=2_000_000)
assert b.severity_label() == \"catastrophic\"
'"
run_test "severity_label negligible at zero" \
    "PY '
from security_ai.risk_quantification_engine import BusinessImpact
b = BusinessImpact()
assert b.severity_label() == \"negligible\"
'"
run_test "regulatory_fine included in total" \
    "PY '
from security_ai.risk_quantification_engine import BusinessImpact
b = BusinessImpact(regulatory_fine_usd=500_000)
assert b.total_exposure_usd() == 500_000.0
'"

echo ""
echo "GROUP 4: ThreatScoreRecord"
run_test "create_assessment returns record with 8 default factors" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine
engine = RiskQuantificationEngine()
rec = engine.create_assessment(\"svc\")
assert len(rec.factors) == 8
'"
run_test "composite_score in range 0-100" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine
engine = RiskQuantificationEngine()
rec = engine.create_assessment(\"svc\")
s = rec.composite_score()
assert 0.0 <= s <= 100.0
'"
run_test "high phase scores reduce composite risk" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine
engine = RiskQuantificationEngine()
safe = engine.create_assessment(\"safe\", {
    \"phase30_score\": 99.0, \"phase31_score\": 99.0,
    \"phase34_score\": 99.0, \"phase38_score\": 99.0,
    \"phase40_score\": 99.0, \"phase45_score\": 99.0,
    \"phase46_score\": 99.0, \"phase33_score\": 99.0,
})
risky = engine.create_assessment(\"risky\", {
    \"phase30_score\": 10.0, \"phase31_score\": 10.0,
})
assert safe.composite_score() < risky.composite_score()
'"
run_test "overall_risk_level returns RiskLevel enum" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine, RiskLevel
engine = RiskQuantificationEngine()
rec = engine.create_assessment(\"svc\")
lvl = rec.overall_risk_level()
assert isinstance(lvl, RiskLevel)
'"
run_test "top_factors returns at most n" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine
engine = RiskQuantificationEngine()
rec = engine.create_assessment(\"svc\")
top = rec.top_factors(3)
assert len(top) <= 3
'"
run_test "top_factors sorted descending by score" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine
engine = RiskQuantificationEngine()
rec = engine.create_assessment(\"svc\")
top = rec.top_factors(3)
scores = [f.risk_score() for f in top]
assert scores == sorted(scores, reverse=True)
'"
run_test "factors_by_level totals equal number of factors" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine
engine = RiskQuantificationEngine()
rec = engine.create_assessment(\"svc\")
counts = rec.factors_by_level()
assert sum(counts.values()) == len(rec.factors)
'"

echo ""
echo "GROUP 5: Phase 47 Posture Score"
run_test "phase47_score in range 0-25" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine
engine = RiskQuantificationEngine()
rec = engine.create_assessment(\"svc\")
s = rec.phase47_score()
assert 0.0 <= s <= 25.0
'"
run_test "low risk yields high phase47_score" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine
engine = RiskQuantificationEngine()
safe = engine.create_assessment(\"safe\", {k: 99.0 for k in [
    \"phase30_score\",\"phase31_score\",\"phase33_score\",\"phase34_score\",
    \"phase38_score\",\"phase40_score\",\"phase45_score\",\"phase46_score\"]})
assert safe.phase47_score() > 20.0
'"
run_test "high risk yields lower phase47_score than low risk" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine
engine = RiskQuantificationEngine()
safe = engine.create_assessment(\"safe\", {k: 99.0 for k in [
    \"phase30_score\",\"phase31_score\",\"phase33_score\",\"phase34_score\",
    \"phase38_score\",\"phase40_score\",\"phase45_score\",\"phase46_score\"]})
risky = engine.create_assessment(\"risky\", {k: 1.0 for k in [
    \"phase30_score\",\"phase31_score\",\"phase33_score\",\"phase34_score\",
    \"phase38_score\",\"phase40_score\",\"phase45_score\",\"phase46_score\"]})
assert risky.phase47_score() < safe.phase47_score()
'"
run_test "quantify_risk helper returns float 0-25" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine, quantify_risk
engine = RiskQuantificationEngine()
rec = engine.create_assessment(\"svc\")
engine.finalize(rec)
s = quantify_risk(engine)
assert isinstance(s, float) and 0 <= s <= 25
'"

echo ""
echo "GROUP 6: Trend Analysis"
run_test "compute_trend STABLE when score unchanged" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine, RiskTrend
engine = RiskQuantificationEngine()
rec = engine.create_assessment(\"svc\")
current = rec.composite_score()
trend = engine.compute_trend(rec, previous_score=current)
assert trend == RiskTrend.STABLE
'"
run_test "compute_trend INCREASING when score rises >5" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine, RiskTrend
engine = RiskQuantificationEngine()
rec = engine.create_assessment(\"svc\")
current = rec.composite_score()
trend = engine.compute_trend(rec, previous_score=current - 10.0)
assert trend == RiskTrend.INCREASING
'"
run_test "compute_trend DECREASING when score drops >5" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine, RiskTrend
engine = RiskQuantificationEngine()
rec = engine.create_assessment(\"svc\")
current = rec.composite_score()
trend = engine.compute_trend(rec, previous_score=current + 10.0)
assert trend == RiskTrend.DECREASING
'"
run_test "compute_trend STABLE when no previous score" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine, RiskTrend
engine = RiskQuantificationEngine()
rec = engine.create_assessment(\"svc\")
trend = engine.compute_trend(rec)
assert trend == RiskTrend.STABLE
'"

echo ""
echo "GROUP 7: Report & Summary"
run_test "generate_report returns required keys" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine
engine = RiskQuantificationEngine()
rec = engine.create_assessment(\"svc\")
report = engine.generate_report(rec)
for key in [\"record_id\",\"target\",\"composite_score\",\"overall_risk_level\",\"phase47_score\",\"trend\",\"factors_by_level\",\"top_factors\"]:
    assert key in report, f\"Missing: {key}\"
'"
run_test "business_impact included in report when set" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine
engine = RiskQuantificationEngine()
rec = engine.create_assessment(\"svc\")
engine.set_business_impact(rec, financial_loss_usd=100000)
report = engine.generate_report(rec)
assert \"business_impact\" in report
assert report[\"business_impact\"][\"total_exposure_usd\"] == 100000.0
'"
run_test "finalize moves record to history" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine
engine = RiskQuantificationEngine()
rec = engine.create_assessment(\"svc\")
engine.finalize(rec)
assert len(engine.history) == 1
assert len(engine.assessments) == 0
'"
run_test "summary returns required keys" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine
engine = RiskQuantificationEngine()
s = engine.summary()
for key in [\"total_assessments\",\"avg_composite_score\",\"critical_targets\",\"phase47_risk_score\"]:
    assert key in s, f\"Missing: {key}\"
'"
run_test "Multiple assessments tracked in summary" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine
engine = RiskQuantificationEngine()
for i in range(3):
    rec = engine.create_assessment(f\"svc-{i}\")
    engine.finalize(rec)
s = engine.summary()
assert s[\"total_assessments\"] == 3
'"

echo ""
echo "GROUP 8: Custom Factor"
run_test "add_factor appends to record factors" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine, ImpactCategory
engine = RiskQuantificationEngine()
rec = engine.create_assessment(\"svc\")
initial = len(rec.factors)
engine.add_factor(rec, \"custom-1\", \"Custom Risk\", \"phase_47\",
    ImpactCategory.FINANCIAL, 0.3, 50.0, \"custom risk factor\")
assert len(rec.factors) == initial + 1
'"
run_test "custom factor included in composite score" \
    "PY '
from security_ai.risk_quantification_engine import RiskQuantificationEngine, ImpactCategory
engine = RiskQuantificationEngine()
rec = engine.create_assessment(\"svc\", {k: 99.0 for k in [
    \"phase30_score\",\"phase31_score\",\"phase33_score\",\"phase34_score\",
    \"phase38_score\",\"phase40_score\",\"phase45_score\",\"phase46_score\"]})
before = rec.composite_score()
engine.add_factor(rec, \"c1\", \"High Risk\", \"phase_47\",
    ImpactCategory.FINANCIAL, 1.0, 100.0)
after = rec.composite_score()
assert after > before
'"

echo ""
echo "GROUP 9: Ops Script"
OPS_SCRIPT="${PROJECT_ROOT}/scripts/ops/phase-47-risk-quantification.sh"
run_test "Ops script exists" "test -f '$OPS_SCRIPT'"
run_test "Ops script syntax valid" "bash -n '$OPS_SCRIPT'"
run_test "Ops demo mode" "
timeout 30 bash '$OPS_SCRIPT' demo > /tmp/p47demo.out 2>&1 && grep -q 'PHASE 47' /tmp/p47demo.out
"
run_test "Ops summary mode" "
timeout 30 bash '$OPS_SCRIPT' summary > /tmp/p47sum.out 2>&1 && grep -q 'phase47_risk_score' /tmp/p47sum.out
"
run_test "Ops assess mode" "
timeout 30 bash '$OPS_SCRIPT' assess api-gateway > /tmp/p47assess.out 2>&1 && grep -q 'composite_score\|Composite Risk' /tmp/p47assess.out
"

echo ""
echo "GROUP 10: Cross-Phase Regression"
run_test "Phase 46 compliance audit still passing" "
timeout 150 bash ${PROJECT_ROOT}/scripts/ci/phase-46-integration-tests.sh > /tmp/p47_reg46.log 2>&1 && grep -q 'ALL TESTS PASSED' /tmp/p47_reg46.log
"

echo ""
echo "============================================================"
echo "TEST SUMMARY"
echo "============================================================"
printf "PASS: %d\nFAIL: %d\nTOTAL: %d\n" "$PASS" "$FAIL" "$TOTAL"
echo ""
if [[ "$FAIL" -eq 0 ]]; then
    echo "✓ ALL TESTS PASSED"
    exit 0
else
    echo "✗ SOME TESTS FAILED"
    exit 1
fi
