#!/usr/bin/env bash
###############################################################################
# @file        scripts/ops/phase-31-gitops-compliance-gate.sh
# @module      ops/phase31
# @description Phase 31 — GitOps Compliance Gate
#
# Enforces a minimum compliance score as a deployment gate. Designed to run
# in CI (GitLab pipeline / local) before any infrastructure change is applied.
#
# Features:
#   --mode check       Run audit, report score, exit non-zero if below threshold
#   --mode enforce     Run audit + auto-remediate safe violations
#   --mode baseline    Save a compliance baseline for future drift detection
#   --mode drift       Compare current score against saved baseline
#
# Usage:
#   bash scripts/ops/phase-31-gitops-compliance-gate.sh --mode check
#   bash scripts/ops/phase-31-gitops-compliance-gate.sh --mode check --min-score 85
#   bash scripts/ops/phase-31-gitops-compliance-gate.sh --mode baseline
#   bash scripts/ops/phase-31-gitops-compliance-gate.sh --mode drift
#   bash scripts/ops/phase-31-gitops-compliance-gate.sh --mode enforce --dry-run
#
# Exit codes:
#   0  — gate passed (score >= threshold, no critical violations)
#   1  — gate failed (score below threshold or critical violations)
#   2  — baseline missing (--mode drift without prior baseline)
#
# @governance GOV-002: IaC, deterministic, audited
# @since 2026-05-01
###############################################################################

set -euo pipefail
trap 'log_error "Phase 31 gate failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/phase31*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

################################################################################
# Configuration
################################################################################

readonly STATE_DIR="${REPO_ROOT}/artifacts/phase31"
readonly BASELINE_FILE="${STATE_DIR}/compliance-baseline.json"
readonly GATE_REPORT_FILE="${STATE_DIR}/gate-report.json"
readonly OPS_LOG="${STATE_DIR}/phase31-gate.log"

# Defaults
MODE="${MODE:-check}"
DRY_RUN="${DRY_RUN:-false}"
MIN_SCORE="${MIN_SCORE:-80}"           # Minimum acceptable compliance score
MAX_CRITICAL="${MAX_CRITICAL:-0}"      # Zero critical violations allowed
BASELINE_DRIFT_WARN="${BASELINE_DRIFT_WARN:-5}"   # Warn if score drops > 5 pts from baseline
BASELINE_DRIFT_FAIL="${BASELINE_DRIFT_FAIL:-15}"  # Fail if score drops > 15 pts from baseline

ENFORCEMENT_SCRIPT="${REPO_ROOT}/scripts/ops/phase-30-security-enforcement.sh"
CLI_MODULE="${REPO_ROOT}/apps/security_ai/cli.py"
COMPLIANCE_JSON="${REPO_ROOT}/artifacts/phase30/compliance.json"
VIOLATIONS_JSON="${REPO_ROOT}/artifacts/phase30/violations.json"

################################################################################
# Helpers
################################################################################

_gate_log() {
  local level="$1"; shift
  local msg="$*"
  local ts; ts="$(date +'%Y-%m-%d %H:%M:%S')"
  echo "[${ts}] [GATE-${level}] ${msg}" >> "${OPS_LOG}"
  case "${level}" in
    PASS)  log_success "${msg}" ;;
    FAIL)  log_error   "${msg}" ;;
    WARN)  log_warn    "${msg}" ;;
    INFO)  log_info    "${msg}" ;;
  esac
}

_run_phase30_audit() {
  _gate_log INFO "Running Phase 30 security audit..."
  if DRY_RUN="${DRY_RUN}" bash "${ENFORCEMENT_SCRIPT}" --mode audit \
      $( [[ "${DRY_RUN}" == "true" ]] && echo "--dry-run" ) > /tmp/phase31-audit.tmp 2>&1; then
    _gate_log INFO "Phase 30 audit completed"
  else
    _gate_log WARN "Phase 30 audit exited non-zero — results may be partial"
  fi
}

_get_compliance_score() {
  python3 -c "
import json, sys
try:
    d = json.load(open('${COMPLIANCE_JSON}'))
    print(d.get('score', 0))
except Exception as e:
    print(0)
" 2>/dev/null || echo "0"
}

_get_open_violations() {
  python3 -c "
import json, sys
try:
    d = json.load(open('${VIOLATIONS_JSON}'))
    print(len([v for v in d.get('violations', []) if v.get('status') == 'open']))
except Exception:
    print(0)
" 2>/dev/null || echo "0"
}

_get_critical_violations() {
  python3 -c "
import json, sys
try:
    d = json.load(open('${VIOLATIONS_JSON}'))
    print(len([v for v in d.get('violations', []) if v.get('severity') == 'CRITICAL' and v.get('status') == 'open']))
except Exception:
    print(0)
" 2>/dev/null || echo "0"
}

_get_framework_scores() {
  python3 -c "
import json, sys
try:
    d = json.load(open('${COMPLIANCE_JSON}'))
    for fw, data in d.get('frameworks', {}).items():
        score = data.get('score', 0) if isinstance(data, dict) else 0
        print(f'  {fw}: {score}/100')
except Exception as e:
    print('  (unavailable)')
" 2>/dev/null || echo "  (unavailable)"
}

_write_gate_report() {
  local score="$1"
  local critical="$2"
  local open_vio="$3"
  local decision="$4"
  local reason="$5"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local py_dry_run; py_dry_run="$([[ "${DRY_RUN}" == "true" ]] && echo "True" || echo "False")"
  local py_passed; py_passed="$([[ "${score}" -ge "${MIN_SCORE}" ]] && echo "True" || echo "False")"
  local py_crit_ok; py_crit_ok="$([[ "${critical}" -le "${MAX_CRITICAL}" ]] && echo "True" || echo "False")"

  python3 - <<PYEOF
import json
report = {
    'timestamp': '${ts}',
    'mode': '${MODE}',
    'dry_run': ${py_dry_run},
    'gate_decision': '${decision}',
    'reason': '${reason}',
    'scores': {
        'overall': ${score},
        'threshold': ${MIN_SCORE},
        'passed_threshold': ${py_passed},
    },
    'violations': {
        'open': ${open_vio},
        'critical': ${critical},
        'max_critical_allowed': ${MAX_CRITICAL},
        'critical_passed': ${py_crit_ok},
    },
    'git': {
        'branch': '$(git -C "${REPO_ROOT}" branch --show-current 2>/dev/null || echo unknown)',
        'commit': '$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)',
    },
}
with open('${GATE_REPORT_FILE}', 'w') as f:
    json.dump(report, f, indent=2)
print(f'Gate report saved: ${GATE_REPORT_FILE}')
PYEOF
}

################################################################################
# Mode: check
################################################################################

run_check() {
  _gate_log INFO "=== Phase 31 Compliance Gate CHECK ==="
  _gate_log INFO "Threshold: score >= ${MIN_SCORE}/100, critical violations = 0"

  _run_phase30_audit

  local score; score="$(_get_compliance_score)"
  local critical; critical="$(_get_critical_violations)"
  local open_vio; open_vio="$(_get_open_violations)"

  echo ""
  echo "┌──────────────────────────────────────────────────"
  echo "│  Phase 31 Compliance Gate Report"
  echo "├──────────────────────────────────────────────────"
  printf "│  Overall Score:    %s/100  (threshold: %s)\n" "${score}" "${MIN_SCORE}"
  printf "│  Open Violations:  %s\n" "${open_vio}"
  printf "│  Critical:         %s  (max allowed: %s)\n" "${critical}" "${MAX_CRITICAL}"
  echo "│  Framework Scores:"
  _get_framework_scores | while IFS= read -r line; do echo "│ $line"; done
  echo "└──────────────────────────────────────────────────"
  echo ""

  local passed=true
  local failure_reason=""

  if [[ "${score}" -lt "${MIN_SCORE}" ]]; then
    _gate_log FAIL "Score ${score}/100 is below minimum threshold ${MIN_SCORE}/100"
    passed=false
    failure_reason="score ${score} < threshold ${MIN_SCORE}"
  fi

  if [[ "${critical}" -gt "${MAX_CRITICAL}" ]]; then
    _gate_log FAIL "${critical} critical violation(s) found (max allowed: ${MAX_CRITICAL})"
    passed=false
    failure_reason="${failure_reason:+${failure_reason}; }${critical} critical violations"
  fi

  if [[ "${passed}" == "true" ]]; then
    _gate_log PASS "✅ Gate PASSED — score=${score}/100, critical=${critical}"
    _write_gate_report "${score}" "${critical}" "${open_vio}" "PASS" "score=${score} >= threshold=${MIN_SCORE}"
    return 0
  else
    _gate_log FAIL "❌ Gate FAILED — ${failure_reason}"
    _write_gate_report "${score}" "${critical}" "${open_vio}" "FAIL" "${failure_reason}"
    return 1
  fi
}

################################################################################
# Mode: baseline
################################################################################

run_baseline() {
  _gate_log INFO "=== Phase 31 Compliance BASELINE ==="

  _run_phase30_audit

  local score; score="$(_get_compliance_score)"
  local critical; critical="$(_get_critical_violations)"
  local open_vio; open_vio="$(_get_open_violations)"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  python3 - <<PYEOF
import json
baseline = {
    'created_at': '${ts}',
    'score': ${score},
    'open_violations': ${open_vio},
    'critical_violations': ${critical},
    'git': {
        'branch': '$(git -C "${REPO_ROOT}" branch --show-current 2>/dev/null || echo unknown)',
        'commit': '$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)',
    },
    'note': 'Compliance baseline — used for drift detection in subsequent runs'
}
with open('${BASELINE_FILE}', 'w') as f:
    json.dump(baseline, f, indent=2)
print(f'Baseline saved: score={baseline["score"]}/100, violations={baseline["open_violations"]}')
print(f'File: ${BASELINE_FILE}')
PYEOF

  _gate_log PASS "Compliance baseline saved (score=${score}/100)"
}

################################################################################
# Mode: drift
################################################################################

run_drift() {
  _gate_log INFO "=== Phase 31 Compliance DRIFT Detection ==="

  if [[ ! -f "${BASELINE_FILE}" ]]; then
    _gate_log WARN "No baseline found at ${BASELINE_FILE}"
    _gate_log INFO "Run: bash $0 --mode baseline"
    exit 2
  fi

  local baseline_score
  baseline_score="$(python3 -c "import json; print(json.load(open('${BASELINE_FILE}'))['score'])" 2>/dev/null || echo "0")"
  local baseline_commit
  baseline_commit="$(python3 -c "import json; print(json.load(open('${BASELINE_FILE}'))['git']['commit'])" 2>/dev/null || echo "unknown")"

  _run_phase30_audit

  local current_score; current_score="$(_get_compliance_score)"
  local delta=$(( current_score - baseline_score ))
  local abs_delta=${delta#-}  # absolute value

  echo ""
  echo "┌──────────────────────────────────────────────────"
  echo "│  Phase 31 Compliance Drift Report"
  echo "├──────────────────────────────────────────────────"
  printf "│  Baseline Score:  %s/100  (commit: %s)\n" "${baseline_score}" "${baseline_commit}"
  printf "│  Current Score:   %s/100\n" "${current_score}"
  printf "│  Delta:           %s%s pts\n" "$([ ${delta} -ge 0 ] && echo '+' || echo '')" "${delta}"
  echo "└──────────────────────────────────────────────────"
  echo ""

  if [[ ${abs_delta} -ge ${BASELINE_DRIFT_FAIL} && ${delta} -lt 0 ]]; then
    _gate_log FAIL "Compliance dropped ${abs_delta} pts from baseline (threshold: ${BASELINE_DRIFT_FAIL})"
    _write_gate_report "${current_score}" "$(_get_critical_violations)" "$(_get_open_violations)" \
      "FAIL" "drift: -${abs_delta} pts from baseline ${baseline_score}"
    return 1
  elif [[ ${abs_delta} -ge ${BASELINE_DRIFT_WARN} && ${delta} -lt 0 ]]; then
    _gate_log WARN "Compliance dropped ${abs_delta} pts from baseline (warn threshold: ${BASELINE_DRIFT_WARN})"
    _gate_log PASS "Gate PASSED with warning — investigate compliance drift"
    _write_gate_report "${current_score}" "$(_get_critical_violations)" "$(_get_open_violations)" \
      "WARN" "drift: -${abs_delta} pts from baseline ${baseline_score}"
    return 0
  else
    _gate_log PASS "No significant drift (delta=${delta:+${delta}} pts from baseline ${baseline_score})"
    _write_gate_report "${current_score}" "$(_get_critical_violations)" "$(_get_open_violations)" \
      "PASS" "no significant drift"
    return 0
  fi
}

################################################################################
# Mode: enforce (run audit + safe auto-remediation)
################################################################################

run_enforce() {
  _gate_log INFO "=== Phase 31 Compliance ENFORCE ==="

  if [[ "${DRY_RUN}" == "true" ]]; then
    _gate_log INFO "[DRY-RUN] Would: run Phase 30 enforce mode (auto-remediate safe violations)"
    _run_phase30_audit
  else
    _gate_log INFO "Running Phase 30 enforce mode..."
    bash "${ENFORCEMENT_SCRIPT}" --mode enforce 2>&1 | \
      while IFS= read -r line; do _gate_log INFO "${line}"; done || true
  fi

  run_check
}

################################################################################
# Argument parsing
################################################################################

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)       MODE="$2"; shift 2 ;;
      --dry-run)    DRY_RUN=true; shift ;;
      --min-score)  MIN_SCORE="$2"; shift 2 ;;
      --help|-h)
        echo "Usage: $0 [--mode check|enforce|baseline|drift] [--dry-run] [--min-score N]"
        echo "  --mode check     Audit + exit non-zero if score < threshold (default)"
        echo "  --mode enforce   Audit + auto-remediate + check gate"
        echo "  --mode baseline  Save current score as baseline for drift detection"
        echo "  --mode drift     Compare current score to saved baseline"
        echo "  --min-score N    Minimum score to pass gate (default: ${MIN_SCORE})"
        echo "  --dry-run        Do not make any changes"
        exit 0 ;;
      *) log_warn "Unknown argument: $1"; shift ;;
    esac
  done
}

main() {
  parse_args "$@"
  mkdir -p "${STATE_DIR}"

  log_info "Phase 31 GitOps Compliance Gate (mode=${MODE}, dry_run=${DRY_RUN}, min_score=${MIN_SCORE})"

  case "${MODE}" in
    check)    run_check ;;
    enforce)  run_enforce ;;
    baseline) run_baseline ;;
    drift)    run_drift ;;
    *)
      log_error "Unknown mode: ${MODE}. Use check|enforce|baseline|drift"
      exit 1 ;;
  esac
}

main "$@"
