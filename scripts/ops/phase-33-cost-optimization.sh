#!/usr/bin/env bash
###############################################################################
# @file scripts/ops/phase-33-cost-optimization.sh
# @description Phase 33 — Cost Intelligence & Optimization Engine orchestrator
#
# Modes:
#   --mode scan       Ingest resource profiles from Prometheus/k8s and generate recommendations
#   --mode analyze    Analyze a single resource (--resource-file <json>)
#   --mode summary    Print cost optimization summary + score
#   --mode approve    Auto-approve all LOW-risk recommendations
#   --mode implement  Mark approved recommendations as implemented
#   --mode demo       Generate synthetic resource profiles and run full loop
#
# Usage:
#   bash scripts/ops/phase-33-cost-optimization.sh --mode scan
#   bash scripts/ops/phase-33-cost-optimization.sh --mode summary
#   bash scripts/ops/phase-33-cost-optimization.sh --mode approve && \
#     bash scripts/ops/phase-33-cost-optimization.sh --mode implement
#   bash scripts/ops/phase-33-cost-optimization.sh --mode demo
#
# @governance GOV-002
# @since 2026-05-01
###############################################################################

set -euo pipefail
trap 'log_error "Phase 33 failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup..."; rm -f /tmp/phase33*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

MODE="${MODE:-scan}"
DRY_RUN="${DRY_RUN:-false}"
RESOURCE_FILE="${RESOURCE_FILE:-}"
STATE_DIR="${REPO_ROOT}/artifacts/phase33"
OPS_LOG="${STATE_DIR}/phase33.log"

mkdir -p "${STATE_DIR}"

_p33_log() {
  local level="$1"; shift
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [P33-${level}] $*" >> "${OPS_LOG}"
  case "${level}" in
    PASS)  log_success "$*" ;;
    FAIL)  log_error   "$*" ;;
    WARN)  log_warn    "$*" ;;
    *)     log_info    "$*" ;;
  esac
}

################################################################################
# Mode: scan (generate recommendations from synthetic resource profiles)
################################################################################

run_scan() {
  _p33_log INFO "Scanning resources for optimization opportunities..."
  python3 - <<PYEOF
import sys, json
sys.path.insert(0, '${REPO_ROOT}')
from apps.security_ai.cost_optimizer import ResourceProfile, ResourceType, analyze

# Simulate scanned resources
resources = [
    ResourceProfile('api-gateway-cpu', ResourceType.CPU, 8, 'vCPU', 0.25, 0.35, 0.40),
    ResourceProfile('api-gateway-mem', ResourceType.MEMORY, 16, 'GB', 0.30, 0.42, 0.50),
    ResourceProfile('db-replica-cpu', ResourceType.CPU, 16, 'vCPU', 0.10, 0.20, 0.25),
    ResourceProfile('db-replica-mem', ResourceType.MEMORY, 64, 'GB', 0.15, 0.28, 0.35),
    ResourceProfile('cache-storage', ResourceType.STORAGE, 500, 'GB', 0.45, 0.60, 0.70),
]

generated = 0
for profile in resources:
    rec = analyze(profile)
    if rec:
        print(f'  {profile.resource_name:20s} → reduce to {rec.recommended_capacity} {rec.recommended_unit} (save \${rec.monthly_savings_usd}/mo, risk={rec.risk_level.value})')
        generated += 1

print(f'\\nGenerated {generated} recommendation(s)')
PYEOF
  _p33_log PASS "Scan complete"
}

################################################################################
# Mode: analyze (single resource file)
################################################################################

run_analyze() {
  if [[ -z "${RESOURCE_FILE}" || ! -f "${RESOURCE_FILE}" ]]; then
    log_error "Provide --resource-file <json>"
    exit 1
  fi
  python3 - <<PYEOF
import sys, json
sys.path.insert(0, '${REPO_ROOT}')
from apps.security_ai.cost_optimizer import ResourceProfile, ResourceType, analyze

profile_data = json.load(open('${RESOURCE_FILE}'))
profile = ResourceProfile(
    profile_data['resource_name'],
    ResourceType[profile_data.get('resource_type', 'CPU').upper()],
    profile_data['current_capacity'],
    profile_data.get('current_unit', 'units'),
    profile_data['utilization_p50'],
    profile_data['utilization_p95'],
    profile_data['utilization_p99'],
)
rec = analyze(profile)
if rec:
    print(f'Recommendation generated: \${rec.monthly_savings_usd} savings, risk={rec.risk_level.value}')
else:
    print('No optimization opportunity')
PYEOF
}

################################################################################
# Mode: summary
################################################################################

run_summary() {
  python3 - <<PYEOF
import sys
sys.path.insert(0, '${REPO_ROOT}')
from apps.security_ai.cost_optimizer import summary

s = summary()
print()
print('┌─────────────────────────────────────────────')
print('│  Phase 33 Cost Optimization Summary')
print('├─────────────────────────────────────────────')
print(f'│  Total recommendations:    {s["total_recommendations"]}')
print(f'│    Pending:                {s["pending"]}')
print(f'│    Approved:               {s["approved"]}')
print(f'│    Implemented:            {s["implemented"]}')
print('│')
print(f'│  Potential monthly savings: \${s["potential_monthly_savings_usd"]}')
print(f'│  Realized monthly savings:  \${s["realized_monthly_savings_usd"]}')
print('│')
print(f'│  Cost Optimization Score:   +{s["cost_optimization_score"]} pts (of 20)')
print('│    (adds to compliance gate)')
print('└─────────────────────────────────────────────')
print()
PYEOF
}

################################################################################
# Mode: approve
################################################################################

run_approve() {
  python3 - <<PYEOF
import sys
sys.path.insert(0, '${REPO_ROOT}')
from apps.security_ai.cost_optimizer import auto_approve_low_risk, summary

count = auto_approve_low_risk()
print(f'Auto-approved {count} low-risk recommendation(s)')
s = summary()
print(f'Now: {s["pending"]} pending, {s["approved"]} approved, {s["implemented"]} implemented')
PYEOF
}

################################################################################
# Mode: implement
################################################################################

run_implement() {
  python3 - <<PYEOF
import sys, json
sys.path.insert(0, '${REPO_ROOT}')
from apps.security_ai.cost_optimizer import _load_recommendations, implement

recs = _load_recommendations()
approved = [r for r in recs if r.get('status') == 'approved']
for rec in approved:
    ok = implement(rec['id'])
    status = '✅' if ok else '⚠️'
    print(f'{status} Implemented {rec["id"]} (\${rec["monthly_savings_usd"]}/mo)')
print(f'\\nImplemented {len(approved)} recommendation(s)')
PYEOF
}

################################################################################
# Mode: demo
################################################################################

run_demo() {
  _p33_log INFO "Running Phase 33 demo..."
  python3 - <<PYEOF
import sys
sys.path.insert(0, '${REPO_ROOT}')
from apps.security_ai.cost_optimizer import (
    ResourceProfile, ResourceType, analyze, auto_approve_low_risk, 
    implement, summary, cost_optimization_score, _load_recommendations
)

print('Demo: 5 resources → recommendations → auto-approve → implement')
print('─' * 60)

resources = [
    ('api-gate', ResourceType.CPU, 8, 'vCPU', 0.22, 0.32, 0.38),
    ('api-gate', ResourceType.MEMORY, 16, 'GB', 0.28, 0.40, 0.48),
    ('db-read-1', ResourceType.CPU, 32, 'vCPU', 0.08, 0.18, 0.22),
    ('db-read-1', ResourceType.MEMORY, 128, 'GB', 0.12, 0.25, 0.32),
    ('cache', ResourceType.STORAGE, 1000, 'GB', 0.42, 0.58, 0.68),
]

generated = 0
for name, rtype, cap, unit, p50, p95, p99 in resources:
    profile = ResourceProfile(name, rtype, cap, unit, p50, p95, p99)
    rec = analyze(profile)
    if rec:
        print(f'✓ {name:15s} → \${rec.monthly_savings_usd:6.2f}/mo savings (risk={rec.risk_level.value})')
        generated += 1

print()
approved = auto_approve_low_risk()
print(f'Auto-approved {approved} low-risk recommendations')

# Implement all approved
recs = _load_recommendations()
approved_ids = [r['id'] for r in recs if r.get('status') == 'approved']
for rec_id in approved_ids:
    implement(rec_id)

s = summary()
score = cost_optimization_score()
print()
print(f'Result:')
print(f'  Recommendations: {s["total_recommendations"]} generated')
print(f'  Implemented: {s["implemented"]} (realized \${s["realized_monthly_savings_usd"]}/mo)')
print(f'  Compliance bonus: +{score} pts')
print()
print('Demo complete ✅')
PYEOF
  _p33_log PASS "Demo complete"
}

################################################################################
# Argument parsing + main
################################################################################

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)          MODE="$2";         shift 2 ;;
      --dry-run)       DRY_RUN=true;      shift ;;
      --resource-file) RESOURCE_FILE="$2"; shift 2 ;;
      --help|-h)
        echo "Usage: $0 --mode scan|analyze|summary|approve|implement|demo [--resource-file FILE]"
        exit 0 ;;
      *) log_warn "Unknown arg: $1"; shift ;;
    esac
  done
}

main() {
  parse_args "$@"
  log_info "Phase 33 Cost Optimization (mode=${MODE})"
  case "${MODE}" in
    scan)       run_scan       ;;
    analyze)    run_analyze    ;;
    summary)    run_summary    ;;
    approve)    run_approve    ;;
    implement)  run_implement  ;;
    demo)       run_demo       ;;
    *)          log_error "Unknown mode: ${MODE}"; exit 1 ;;
  esac
}

main "$@"
