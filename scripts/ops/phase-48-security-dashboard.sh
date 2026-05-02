#!/bin/bash
# @file phase-48-security-dashboard.sh
# @description Phase 48 — Security Intelligence Dashboard & Metrics Aggregation
# @since 2026-05-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'rm -f /tmp/p48*.tmp 2>/dev/null || true' EXIT
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR

MODE="${1:-demo}"

cmd_demo() {
    log_info "PHASE 48: Security Intelligence Dashboard"
    echo ""
    "$PYTHON_CMD" <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier, AlertSeverity, dashboard_score
)

dash = SecurityIntelligenceDashboard()

# Ingest live scores from upstream phases
dash.ingest_phase_scores({
    "phase_30": 22.5, "phase_31": 21.0, "phase_36": 22.0,
    "phase_40": 21.5, "phase_45": 23.0, "phase_46": 22.5,
    "phase_47": 21.0,
})

print("=== PHASE 48: Security Intelligence Dashboard ===")
print()

for tier in [DashboardTier.EXECUTIVE, DashboardTier.OPERATIONS, DashboardTier.ENGINEERING]:
    snap = dash.create_snapshot(tier)
    ms   = snap.metric_summary()
    idx  = snap.composite_index()
    p48  = snap.phase48_score()
    top  = snap.top_risks(1)[0]
    print(f"  [{tier.value.upper()}] Composite Index: {idx:.1f}/100")
    print(f"    Metrics: healthy={ms['healthy']} warning={ms['warning']} critical={ms['critical']}")
    print(f"    Phase 48 Score: {p48:.2f}/25")
    print(f"    Top Risk: {top.phase_name} ({top.score:.1f}/25)")
    print(f"    Open Alerts: {snap.critical_alert_count()} critical")
    print()

s = dash.summary()
print(f"  Platform Dashboard Score: {s['phase48_dashboard_score']:.2f}/25")
print(f"  Avg Composite Index:      {s['avg_composite_index']:.1f}/100")
print(f"  Healthy Snapshots:        {s['healthy_snapshots']}/{s['total_snapshots']}")
PYEOF
}

cmd_summary() {
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier, dashboard_score
)
dash = SecurityIntelligenceDashboard()
snap = dash.create_snapshot(DashboardTier.OPERATIONS)
s = dash.summary()
print(json.dumps(s, indent=2))
PYEOF
}

cmd_report() {
    local tier="${2:-operations}"
    log_info "PHASE 48: Generating ${tier} dashboard report"
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.security_intelligence_dashboard import (
    SecurityIntelligenceDashboard, DashboardTier, dashboard_score
)
tier_map = {
    "executive": DashboardTier.EXECUTIVE,
    "operations": DashboardTier.OPERATIONS,
    "engineering": DashboardTier.ENGINEERING,
}
dash = SecurityIntelligenceDashboard()
snap = dash.create_snapshot(tier_map.get("${tier}", DashboardTier.OPERATIONS))
report = dash.generate_report(snap)
print(json.dumps(report, indent=2))
print(f"Composite Index: {snap.composite_index():.2f}/100")
print(f"Phase 48 Score:  {snap.phase48_score():.2f}/25")
PYEOF
}

case "$MODE" in
    demo)    cmd_demo ;;
    summary) cmd_summary ;;
    report)  cmd_report "$@" ;;
    *)
        echo "Usage: $0 [demo|summary|report [executive|operations|engineering]]"
        exit 1
        ;;
esac
