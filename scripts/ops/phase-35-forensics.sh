#!/usr/bin/env bash
###############################################################################
# @file scripts/ops/phase-35-forensics.sh
# @description Phase 35 — Event Correlation & Forensics orchestrator
#
# Modes:
#   --mode analyze    Analyze incident and reconstruct forensic timeline
#   --mode summary    Print forensics status + score
#   --mode demo       Synthetic incident round-trip (memory leak → OOM → crash)
#
# Usage:
#   bash scripts/ops/phase-35-forensics.sh --mode analyze --incident <id>
#   bash scripts/ops/phase-35-forensics.sh --mode summary
#   bash scripts/ops/phase-35-forensics.sh --mode demo
#
# @governance GOV-002
# @since 2026-05-01
###############################################################################

set -euo pipefail
trap 'log_error "Phase 35 failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup..."; rm -f /tmp/phase35*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

MODE="${MODE:-analyze}"
INCIDENT_ID="${INCIDENT_ID:-demo}"
STATE_DIR="${REPO_ROOT}/artifacts/phase35"
OPS_LOG="${STATE_DIR}/phase35.log"

mkdir -p "${STATE_DIR}"

_p35_log() {
  local level="$1"; shift
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [P35-${level}] $*" >> "${OPS_LOG}"
  case "${level}" in
    PASS)  log_success "$*" ;;
    FAIL)  log_error   "$*" ;;
    WARN)  log_warn    "$*" ;;
    *)     log_info    "$*" ;;
  esac
}

################################################################################
# Mode: analyze (analyze incident for root cause)
################################################################################

run_analyze() {
  _p35_log INFO "Analyzing incident ${INCIDENT_ID} for root cause..."
  python3 - <<PYEOF
import sys
sys.path.insert(0, '${REPO_ROOT}')
from apps.security_ai.forensics_engine import analyze_incident, summary

trace = analyze_incident('${INCIDENT_ID}')
if trace:
    print(f'  Forensic trace: {trace.id}')
    print(f'  Root cause: {trace.root_cause_event_id}')
    print(f'  Event chain: {len(trace.event_chain)} events over {trace.timeline_seconds}s')
    print(f'  Impact: {trace.impact_count} resource(s)')
    print(f'  Confidence: {trace.confidence:.2%}')
    print()
    print(f'  Summary: {trace.summary}')
else:
    print('  No trace generated')

s = summary()
print()
print(f'Forensics: {s["total_forensic_traces"]} traces, {s["total_correlations"]} correlations')
PYEOF
  _p35_log PASS "Analysis complete"
}

################################################################################
# Mode: summary
################################################################################

run_summary() {
  python3 - <<PYEOF
import sys
sys.path.insert(0, '${REPO_ROOT}')
from apps.security_ai.forensics_engine import summary

s = summary()
print()
print('┌─────────────────────────────────────────────')
print('│  Phase 35 Forensics Summary')
print('├─────────────────────────────────────────────')
print(f'│  Forensic traces:        {s["total_forensic_traces"]}')
print(f'│  Event correlations:     {s["total_correlations"]}')
print(f'│  High-confidence:        {s["high_confidence_corrs"]}')
print('│')
print(f'│  Forensic Score:         +{s["forensic_score"]} pts (of 15)')
print('│    (adds to compliance gate)')
print('└─────────────────────────────────────────────')
print()
PYEOF
}

################################################################################
# Mode: demo
################################################################################

run_demo() {
  _p35_log INFO "Running Phase 35 demo..."
  python3 - <<PYEOF
import sys
sys.path.insert(0, '${REPO_ROOT}')
from apps.security_ai.forensics_engine import (
    Event, EventSource, analyze_incident, summary
)

print('Demo: memory leak → OOM → crash loop (root cause analysis)')
print('─' * 60)

trace = analyze_incident('demo-incident-1')
if trace:
    print(f'  ✅ Forensic trace generated: {trace.id}')
    print(f'  Root cause: {trace.root_cause_event_id}')
    print(f'  Impact: {trace.impact_count} resources')
    print(f'  Timeline: {trace.timeline_seconds} seconds')

s = summary()
print()
print(f'Forensic Score: +{s["forensic_score"]} pts')
print()
print('Demo complete ✅')
PYEOF
  _p35_log PASS "Demo complete"
}

################################################################################
# Argument parsing + main
################################################################################

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)      MODE="$2";       shift 2 ;;
      --incident)  INCIDENT_ID="$2"; shift 2 ;;
      --help|-h)
        echo "Usage: $0 --mode analyze|summary|demo [--incident <id>]"
        exit 0 ;;
      *) log_warn "Unknown arg: $1"; shift ;;
    esac
  done
}

main() {
  parse_args "$@"
  log_info "Phase 35 Event Correlation & Forensics (mode=${MODE})"
  case "${MODE}" in
    analyze) run_analyze ;;
    summary) run_summary ;;
    demo)    run_demo    ;;
    *)       log_error "Unknown mode: ${MODE}"; exit 1 ;;
  esac
}

main "$@"
