#!/bin/bash
# @file phase-52-adaptive-threat-response.sh
# @description Phase 52 — Adaptive Threat Response Orchestration
# @since 2026-05-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'rm -f /tmp/p52*.tmp 2>/dev/null || true' EXIT
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR

MODE="${1:-demo}"

cmd_demo() {
    log_info "PHASE 52: Adaptive Threat Response Orchestration"
    echo ""
    "$PYTHON_CMD" <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.adaptive_threat_response import (
    AdaptiveThreatResponseOrchestrator, make_signal, response_score
)

orch = AdaptiveThreatResponseOrchestrator()

print("=== PHASE 52: Adaptive Threat Response Dashboard ===")
print()

# Simulate threat signals from various upstream phases
signals = [
    make_signal("phase_48", 8.0,  "Security Dashboard Critical Alert",   "security"),
    make_signal("phase_47", 13.0, "High Risk Factor: Threat Exposure",    "intelligence"),
    make_signal("phase_46", 18.0, "Compliance Gap Detected",              "compliance"),
    make_signal("phase_50", 22.0, "Low-Priority Self-Heal Trigger",       "resilience"),
]

playbooks = orch.ingest_signals_bulk(signals)
results   = orch.execute_all()

for pb in playbooks:
    orch.resolve_playbook(pb)
    print(f"  [{pb.threat_signal.severity.value.upper():8s}] "
          f"{pb.name[:55]:55s} "
          f"score={pb.phase52_score():.1f}/25")

print()
s = orch.summary()
print(f"  Total Playbooks:    {s['total_playbooks']}")
print(f"  Resolved:           {s['resolved_playbooks']}")
print(f"  Avg Success Rate:   {s['avg_success_rate']:.0%}")
print(f"  Phase 52 Score:     {s['phase52_score']:.2f}/25")
print()
print("  Severity breakdown:", s['severity_breakdown'])
PYEOF
}

cmd_summary() {
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.adaptive_threat_response import (
    AdaptiveThreatResponseOrchestrator, make_signal
)
orch = AdaptiveThreatResponseOrchestrator()
for score, source in [(9.0,"phase_48"),(14.0,"phase_47"),(19.0,"phase_46")]:
    pb = orch.ingest_signal(make_signal(source, score))
    orch.execute_playbook(pb)
    orch.resolve_playbook(pb)
print(json.dumps(orch.summary(), indent=2))
PYEOF
}

cmd_respond() {
    local source="${2:-phase_51}"
    local score="${3:-15.0}"
    log_info "PHASE 52: On-demand response for ${source} score=${score}" >&2
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.adaptive_threat_response import (
    AdaptiveThreatResponseOrchestrator, make_signal
)
orch = AdaptiveThreatResponseOrchestrator()
sig  = make_signal("${source}", float("${score}"))
pb   = orch.ingest_signal(sig)
orch.execute_playbook(pb)
report = orch.generate_report(pb)
orch.resolve_playbook(pb)
print(json.dumps(report, indent=2))
PYEOF
}

case "$MODE" in
    demo)    cmd_demo ;;
    summary) cmd_summary ;;
    respond) cmd_respond "$@" ;;
    *)
        echo "Usage: $0 [demo|summary|respond [phase_source] [score]]"
        exit 1
        ;;
esac
