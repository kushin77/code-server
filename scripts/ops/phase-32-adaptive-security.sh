#!/usr/bin/env bash
###############################################################################
# @file scripts/ops/phase-32-adaptive-security.sh
# @description Phase 32 — Adaptive Security Intelligence orchestrator
#
# Modes:
#   --mode respond   Ingest a JSON signal file and trigger adaptive response
#   --mode scan      Scan artifacts/phase30/violations.json and auto-respond
#   --mode status    Print open incidents + compliance penalty
#   --mode resolve   Resolve incident by ID (--incident-id <id>)
#   --mode demo      Generate a synthetic signal set and run full loop (dry-run)
#
# Usage:
#   bash scripts/ops/phase-32-adaptive-security.sh --mode scan
#   bash scripts/ops/phase-32-adaptive-security.sh --mode respond --signal /path/to/signal.json
#   bash scripts/ops/phase-32-adaptive-security.sh --mode status
#   bash scripts/ops/phase-32-adaptive-security.sh --mode resolve --incident-id abc12345
#   bash scripts/ops/phase-32-adaptive-security.sh --mode demo --dry-run
#
# @governance GOV-002
# @since 2026-05-01
###############################################################################

set -euo pipefail
trap 'log_error "Phase 32 failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup..."; rm -f /tmp/phase32*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

MODE="${MODE:-scan}"
DRY_RUN="${DRY_RUN:-true}"
SIGNAL_FILE="${SIGNAL_FILE:-}"
INCIDENT_ID="${INCIDENT_ID:-}"
STATE_DIR="${REPO_ROOT}/artifacts/phase32"
OPS_LOG="${STATE_DIR}/phase32.log"

mkdir -p "${STATE_DIR}"

_p32_log() {
  local level="$1"; shift
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [P32-${level}] $*" >> "${OPS_LOG}"
  case "${level}" in
    PASS)  log_success "$*" ;;
    FAIL)  log_error   "$*" ;;
    WARN)  log_warn    "$*" ;;
    *)     log_info    "$*" ;;
  esac
}

################################################################################
# Mode: respond (process a single signal file)
################################################################################

run_respond() {
  if [[ -z "${SIGNAL_FILE}" || ! -f "${SIGNAL_FILE}" ]]; then
    log_error "Signal file not found. Use: --signal /path/to/signal.json"
    exit 1
  fi
  _p32_log INFO "Ingesting signal: ${SIGNAL_FILE} (dry_run=${DRY_RUN})"
  python3 - <<PYEOF
import json, sys
sys.path.insert(0, '${REPO_ROOT}')
from apps.security_ai.adaptive_response import AnomalySignal, respond
sig_data = json.load(open('${SIGNAL_FILE}'))
signal = AnomalySignal(**sig_data)
incident = respond(signal, dry_run=${DRY_RUN} == 'true')
d = incident.to_dict()
print(f'Incident {d["id"]} tier={d["tier"]} penalty={d["compliance_penalty"]} actions={len(d["actions"])}')
for a in d['actions']:
    status = '(dry-run)' if a['dry_run'] else ('✅' if a['executed'] else '⚠️')
    print(f'  {a["action_type"]} → {a["target"]} {status}')
PYEOF
}

################################################################################
# Mode: scan (ingest current Phase 30 violations as signals)
################################################################################

run_scan() {
  local violations_file="${REPO_ROOT}/artifacts/phase30/violations.json"
  if [[ ! -f "${violations_file}" ]]; then
    _p32_log WARN "No violations.json found — run Phase 30 audit first"
    exit 0
  fi

  _p32_log INFO "Scanning Phase 30 violations (dry_run=${DRY_RUN})..."
  python3 - <<PYEOF
import json, sys
sys.path.insert(0, '${REPO_ROOT}')
from apps.security_ai.adaptive_response import AnomalySignal, respond, summary

data = json.load(open('${REPO_ROOT}/artifacts/phase30/violations.json'))
violations = [v for v in data.get('violations', []) if v.get('status') == 'open']
print(f'Processing {len(violations)} open violation(s)...')

created = 0
for v in violations:
    sev = v.get('severity', 'MEDIUM')
    score = {'CRITICAL': 95, 'HIGH': 80, 'MEDIUM': 50, 'LOW': 20}.get(sev.upper(), 50)
    signal = AnomalySignal(
        source='phase30',
        signal_type=v.get('type', 'policy_violation'),
        severity=sev,
        score=score,
        details={'target': v.get('resource', 'unknown'), 'control': v.get('control', ''), 'id': v.get('id', '')},
    )
    incident = respond(signal, dry_run=True)
    print(f'  [{sev:8s}] → incident {incident.id} tier={incident.tier.value} penalty={incident.compliance_penalty}')
    created += 1

s = summary()
print(f'\\nAdaptive Response Summary:')
print(f'  Open incidents:      {s["open_incidents"]}')
print(f'  Compliance penalty:  -{s["compliance_penalty"]} pts')
print(f'  By tier: {s["open_by_tier"]}')
PYEOF
  _p32_log PASS "Scan complete"
}

################################################################################
# Mode: status
################################################################################

run_status() {
  python3 - <<PYEOF
import json, sys
sys.path.insert(0, '${REPO_ROOT}')
from apps.security_ai.adaptive_response import list_open, summary, compliance_score_delta

open_incs = list_open()
s = summary()
delta = compliance_score_delta()

print(f'\\n┌─────────────────────────────────────────────')
print(f'│  Phase 32 Adaptive Security Status')
print(f'├─────────────────────────────────────────────')
print(f'│  Total incidents (all time): {s["total_incidents"]}')
print(f'│  Open incidents:             {s["open_incidents"]}')
print(f'│  Compliance penalty:         -{delta} pts')
print(f'│  By tier:')
for tier, count in s["open_by_tier"].items():
    if count:
        print(f'│    {tier}: {count}')
print(f'└─────────────────────────────────────────────')
if open_incs:
    print()
    for inc in open_incs[:10]:
        print(f'  [{inc["tier"]:8s}] #{inc["id"]} {inc["signal"]["signal_type"]} sev={inc["signal"]["severity"]} penalty={inc["compliance_penalty"]}')
PYEOF
}

################################################################################
# Mode: resolve
################################################################################

run_resolve() {
  if [[ -z "${INCIDENT_ID}" ]]; then
    log_error "Provide --incident-id <id>"
    exit 1
  fi
  python3 - <<PYEOF
import sys
sys.path.insert(0, '${REPO_ROOT}')
from apps.security_ai.adaptive_response import resolve
ok = resolve('${INCIDENT_ID}')
if ok:
    print(f'Incident ${INCIDENT_ID} resolved ✅')
else:
    print(f'Incident ${INCIDENT_ID} not found or already resolved')
    sys.exit(1)
PYEOF
}

################################################################################
# Mode: demo (synthetic signal round-trip)
################################################################################

run_demo() {
  _p32_log INFO "Running Phase 32 demo (synthetic signals, dry-run)..."
  python3 - <<PYEOF
import sys
sys.path.insert(0, '${REPO_ROOT}')
from apps.security_ai.adaptive_response import (
    AnomalySignal, respond, resolve, summary, compliance_score_delta, ARTIFACTS_DIR, INCIDENTS_FILE
)
import json

DEMO_SIGNALS = [
    AnomalySignal('phase25b', 'spike',       'CRITICAL', 95.0, {'target': 'api-gateway', 'metric': 'error_rate'}),
    AnomalySignal('phase30',  'brute_force', 'HIGH',     85.0, {'target': '10.0.0.99',   'user': 'admin'}),
    AnomalySignal('phase30',  'data_exfil',  'HIGH',     65.0, {'target': 'db-primary',  'bytes': 524288}),
    AnomalySignal('prometheus','trend',      'MEDIUM',   72.0, {'target': 'memory-engine','metric': 'mem_rss'}),
    AnomalySignal('phase25b', 'dip',         'LOW',      30.0, {'target': 'event-bus',   'metric': 'throughput'}),
]

print('Signal → Response mapping:')
print('─' * 60)
incidents = []
for sig in DEMO_SIGNALS:
    inc = respond(sig, dry_run=True)
    print(f'  {sig.severity:8s} score={sig.score:5.1f}  →  {inc.tier.value:9s}  penalty={inc.compliance_penalty}')
    incidents.append(inc)

s = summary()
delta = compliance_score_delta()
print()
print(f'Compliance delta from open incidents: -{delta} pts')
print(f'Open incidents: {s["open_incidents"]}')
print()

# Resolve the LOW-severity incident
for inc in incidents:
    if inc.tier.value == 'MONITOR':
        resolved = resolve(inc.id)
        print(f'Resolved MONITOR incident {inc.id}: {resolved}')

s2 = summary()
delta2 = compliance_score_delta()
print(f'Compliance delta after resolve: -{delta2} pts (was -{delta})')
print()
print('Demo complete ✅')
PYEOF
  _p32_log PASS "Demo complete"
}

################################################################################
# Argument parsing + main
################################################################################

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)        MODE="$2";        shift 2 ;;
      --dry-run)     DRY_RUN=true;     shift ;;
      --signal)      SIGNAL_FILE="$2"; shift 2 ;;
      --incident-id) INCIDENT_ID="$2"; shift 2 ;;
      --help|-h)
        echo "Usage: $0 --mode scan|respond|status|resolve|demo [--dry-run] [--signal FILE] [--incident-id ID]"
        exit 0 ;;
      *) log_warn "Unknown arg: $1"; shift ;;
    esac
  done
}

main() {
  parse_args "$@"
  log_info "Phase 32 Adaptive Security Intelligence (mode=${MODE})"
  case "${MODE}" in
    respond) run_respond ;;
    scan)    run_scan    ;;
    status)  run_status  ;;
    resolve) run_resolve ;;
    demo)    run_demo    ;;
    *)       log_error "Unknown mode: ${MODE}"; exit 1 ;;
  esac
}

main "$@"
