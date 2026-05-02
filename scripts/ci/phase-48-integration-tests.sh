#!/bin/bash
# @file phase-48-integration-tests.sh
# @description Integration tests for Phase 48 — Security Intelligence Dashboard
# @since 2026-05-01

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p48*.* /tmp/p48_reg47.log 2>/dev/null || true' EXIT

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
echo "PHASE 48: SECURITY INTELLIGENCE DASHBOARD — INTEGRATION TESTS"
echo "============================================================"
echo ""

# GROUP 1: Module imports
echo "GROUP 1: Module Import & API Surface"
run_test "Import SecurityIntelligenceDashboard" \
    "PY 'from security_ai.security_intelligence_dashboard import SecurityIntelligenceDashboard'"
run_test "Import DashboardSnapshot" \
    "PY 'from security_ai.security_intelligence_dashboard import DashboardSnapshot'"
run_test "Import PhaseMetric" \
    "PY 'from security_ai.security_intelligence_dashboard import PhaseMetric'"
run_test "Import DashboardAlert" \
    "PY 'from security_ai.security_intelligence_dashboard import DashboardAlert'"
run_test "Import MetricStatus" \
    "PY 'from security_ai.security_intelligence_dashboard import MetricStatus'"
run_test "Import AlertSeverity" \
    "PY 'from security_ai.security_intelligence_dashboard import AlertSeverity'"
run_test "Import DashboardTier" \
    "PY 'from security_ai.security_intelligence_dashboard import DashboardTier'"
run_test "Import dashboard_score helper" \
    "PY 'from security_ai.security_intelligence_dashboard import dashboard_score'"
run_test "PHASE_REGISTRY has 18 phases" \
    "PY 'from security_ai.security_intelligence_dashboard import SecurityIntelligenceDashboard; assert len(SecurityIntelligenceDashboard.PHASE_REGISTRY) == 18'"

echo ""
echo "GROUP 2: PhaseMetric"
run_test "score clamped 0-25" \
    "PY '
from security_ai.security_intelligence_dashboard import PhaseMetric
m = PhaseMetric(\"phase_30\", \"Test\", 999.0)
assert m.score == 25.0
m2 = PhaseMetric(\"phase_30\", \"Test\", -5.0)
assert m2.score == 0.0
'"
run_test "HEALTHY status at score >= 20" \
    "PY '
from security_ai.security_intelligence_dashboard import PhaseMetric, MetricStatus
m = PhaseMetric(\"phase_30\", \"Test\", 22.0)
assert m.status == MetricStatus.HEALTHY
'"
run_test "WARNING status at score 12-19" \
    "PY '
from security_ai.security_intelligence_dashboard import PhaseMetric, MetricStatus
m = PhaseMetric(\"phase_30\", \"Test\", 15.0)
assert m.status == MetricStatus.WARNING
'"
run_test "CRITICAL status at score < 12" \
    "PY '
from security_ai.security_intelligence_dashboard import PhaseMetric, MetricStatus
m = PhaseMetric(\"phase_30\", \"Test\", 8.0)
assert m.status == MetricStatus.CRITICAL
'"
run_test "weighted_score is score * weight" \
    "PY '
from security_ai.security_intelligence_dashboard import PhaseMetric
m = PhaseMetric(\"phase_30\", \"Test\", 20.0, weight=1.5)
assert abs(m.weighted_score() - 30.0) < 0.01
'"

echo ""
echo "GROUP 3: DashboardAlert"
run_test "Alert acknowledge flips flag" \
    "PY '
from security_ai.security_intelligence_dashboard import DashboardAlert, AlertSeverity
from datetime import datetime
a = DashboardAlert(\"A-001\", \"T\", \"D\", AlertSeverity.HIGH, \"phase_30\")
assert not a.acknowledged
a.acknowledge()
assert a.acknowledged
'"
run_test "Unacknowledged alert counted in open_alerts" \
    "PY '
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier, AlertSeverity
)
dash = SecurityIntelligenceDashboard()
snap = dash.create_snapshot(DashboardTier.OPERATIONS)
dash.add_alert(snap, \"T\", \"D\", AlertSeverity.CRITICAL, \"phase_30\")
counts = snap.open_alerts_by_severity()
assert counts[\"critical\"] >= 1
'"
run_test "Acknowledged alert excluded from open count" \
    "PY '
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier, AlertSeverity
)
dash = SecurityIntelligenceDashboard()
snap = dash.create_snapshot(DashboardTier.OPERATIONS)
a = dash.add_alert(snap, \"T\", \"D\", AlertSeverity.HIGH, \"phase_30\")
dash.acknowledge_alert(snap, a.alert_id)
counts = snap.open_alerts_by_severity()
assert counts[\"high\"] == 0
'"
run_test "acknowledge_alert returns False for unknown id" \
    "PY '
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier
)
dash = SecurityIntelligenceDashboard()
snap = dash.create_snapshot(DashboardTier.OPERATIONS)
result = dash.acknowledge_alert(snap, \"ALT-FAKE\")
assert result is False
'"

echo ""
echo "GROUP 4: DashboardSnapshot Aggregation"
run_test "create_snapshot returns snapshot with 18 metrics" \
    "PY '
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier
)
dash = SecurityIntelligenceDashboard()
snap = dash.create_snapshot(DashboardTier.OPERATIONS)
assert len(snap.metrics) == 18
'"
run_test "composite_index in range 0-100" \
    "PY '
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier
)
dash = SecurityIntelligenceDashboard()
snap = dash.create_snapshot(DashboardTier.OPERATIONS)
idx = snap.composite_index()
assert 0.0 <= idx <= 100.0
'"
run_test "phase48_score in range 0-25" \
    "PY '
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier
)
dash = SecurityIntelligenceDashboard()
snap = dash.create_snapshot(DashboardTier.OPERATIONS)
s = snap.phase48_score()
assert 0.0 <= s <= 25.0
'"
run_test "high phase scores raise composite_index" \
    "PY '
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier
)
dash_low = SecurityIntelligenceDashboard()
dash_low.ingest_phase_scores({k: 5.0 for k in SecurityIntelligenceDashboard.PHASE_REGISTRY})
snap_low = dash_low.create_snapshot(DashboardTier.OPERATIONS)

dash_hi = SecurityIntelligenceDashboard()
dash_hi.ingest_phase_scores({k: 25.0 for k in SecurityIntelligenceDashboard.PHASE_REGISTRY})
snap_hi = dash_hi.create_snapshot(DashboardTier.OPERATIONS)

assert snap_hi.composite_index() > snap_low.composite_index()
'"
run_test "metric_summary totals equal number of metrics" \
    "PY '
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier
)
dash = SecurityIntelligenceDashboard()
snap = dash.create_snapshot(DashboardTier.OPERATIONS)
ms = snap.metric_summary()
assert sum(ms.values()) == len(snap.metrics)
'"
run_test "top_risks returns at most n lowest-scored" \
    "PY '
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier
)
dash = SecurityIntelligenceDashboard()
snap = dash.create_snapshot(DashboardTier.OPERATIONS)
top = snap.top_risks(3)
assert len(top) <= 3
scores = [m.score for m in top]
assert scores == sorted(scores)
'"
run_test "overall_status CRITICAL when any metric CRITICAL" \
    "PY '
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier, MetricStatus
)
dash = SecurityIntelligenceDashboard()
dash.ingest_phase_scores({\"phase_30\": 5.0})
snap = dash.create_snapshot(DashboardTier.OPERATIONS, phase_subset=[\"phase_30\"])
assert snap.overall_status() == MetricStatus.CRITICAL
'"
run_test "overall_status HEALTHY when all metrics healthy" \
    "PY '
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier, MetricStatus
)
dash = SecurityIntelligenceDashboard()
dash.ingest_phase_scores({k: 25.0 for k in SecurityIntelligenceDashboard.PHASE_REGISTRY})
snap = dash.create_snapshot(DashboardTier.OPERATIONS)
assert snap.overall_status() == MetricStatus.HEALTHY
'"

echo ""
echo "GROUP 5: Phase Subset & Tier"
run_test "create_snapshot with phase_subset limits metrics" \
    "PY '
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier
)
dash = SecurityIntelligenceDashboard()
snap = dash.create_snapshot(DashboardTier.EXECUTIVE, [\"phase_30\",\"phase_45\",\"phase_46\"])
assert len(snap.metrics) == 3
'"
run_test "EXECUTIVE tier snapshot has tier set correctly" \
    "PY '
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier
)
dash = SecurityIntelligenceDashboard()
snap = dash.create_snapshot(DashboardTier.EXECUTIVE)
assert snap.tier == DashboardTier.EXECUTIVE
'"
run_test "ingest_phase_scores overrides defaults" \
    "PY '
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier
)
dash = SecurityIntelligenceDashboard()
dash.ingest_phase_scores({\"phase_30\": 5.0})
snap = dash.create_snapshot(DashboardTier.OPERATIONS, [\"phase_30\"])
m = next(m for m in snap.metrics if m.phase_id == \"phase_30\")
assert m.score == 5.0
'"

echo ""
echo "GROUP 6: Auto-Alert Generation"
run_test "CRITICAL metric auto-generates CRITICAL alert" \
    "PY '
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier, AlertSeverity
)
dash = SecurityIntelligenceDashboard()
dash.ingest_phase_scores({\"phase_30\": 5.0})
snap = dash.create_snapshot(DashboardTier.OPERATIONS, [\"phase_30\"])
assert snap.critical_alert_count() >= 1
'"
run_test "HEALTHY metrics generate no CRITICAL alerts" \
    "PY '
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier
)
dash = SecurityIntelligenceDashboard()
dash.ingest_phase_scores({k: 25.0 for k in SecurityIntelligenceDashboard.PHASE_REGISTRY})
snap = dash.create_snapshot(DashboardTier.OPERATIONS)
assert snap.critical_alert_count() == 0
'"

echo ""
echo "GROUP 7: Report & Summary"
run_test "generate_report returns required keys" \
    "PY '
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier
)
dash = SecurityIntelligenceDashboard()
snap = dash.create_snapshot(DashboardTier.OPERATIONS)
report = dash.generate_report(snap)
for key in [\"snapshot_id\",\"tier\",\"composite_index\",\"phase48_score\",\"overall_status\",
            \"metric_summary\",\"open_alerts\",\"critical_alerts\",\"top_risks\",\"total_phases\"]:
    assert key in report, f\"Missing: {key}\"
'"
run_test "summary returns required keys" \
    "PY '
from security_ai.security_intelligence_dashboard import SecurityIntelligenceDashboard
dash = SecurityIntelligenceDashboard()
s = dash.summary()
for key in [\"total_snapshots\",\"avg_composite_index\",\"healthy_snapshots\",
            \"total_critical_alerts\",\"phase48_dashboard_score\"]:
    assert key in s, f\"Missing: {key}\"
'"
run_test "Multiple snapshots tracked in summary" \
    "PY '
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier
)
dash = SecurityIntelligenceDashboard()
for tier in [DashboardTier.EXECUTIVE, DashboardTier.OPERATIONS, DashboardTier.ENGINEERING]:
    dash.create_snapshot(tier)
s = dash.summary()
assert s[\"total_snapshots\"] == 3
'"
run_test "dashboard_score helper returns float 0-25" \
    "PY '
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier, dashboard_score
)
dash = SecurityIntelligenceDashboard()
dash.create_snapshot(DashboardTier.OPERATIONS)
s = dashboard_score(dash)
assert isinstance(s, float) and 0 <= s <= 25
'"

echo ""
echo "GROUP 8: Ops Script"
OPS_SCRIPT="${PROJECT_ROOT}/scripts/ops/phase-48-security-dashboard.sh"
run_test "Ops script exists" "test -f '$OPS_SCRIPT'"
run_test "Ops script syntax valid" "bash -n '$OPS_SCRIPT'"
run_test "Ops demo mode" "
timeout 30 bash '$OPS_SCRIPT' demo > /tmp/p48demo.out 2>&1 && grep -q 'PHASE 48' /tmp/p48demo.out
"
run_test "Ops summary mode" "
timeout 30 bash '$OPS_SCRIPT' summary > /tmp/p48sum.out 2>&1 && grep -q 'phase48_dashboard_score' /tmp/p48sum.out
"
run_test "Ops report mode" "
timeout 30 bash '$OPS_SCRIPT' report operations > /tmp/p48rep.out 2>&1 && grep -q 'composite_index\|Composite Index' /tmp/p48rep.out
"

echo ""
echo "GROUP 9: Cross-Phase Regression"
run_test "Phase 47 risk quantification still passing" "
timeout 150 bash ${PROJECT_ROOT}/scripts/ci/phase-47-integration-tests.sh > /tmp/p48_reg47.log 2>&1 && grep -q 'ALL TESTS PASSED' /tmp/p48_reg47.log
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
