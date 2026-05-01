#!/usr/bin/env bash
# @file scripts/ci/performance-gate.sh
# @description CI performance gate — compares current run metrics against the stored
#              baseline. Fails the build if regressions exceed configured thresholds.
# @usage performance-gate.sh [--baseline <path>] [--current <path>] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false
BASELINE_FILE=""
CURRENT_FILE=""

# Gate thresholds (% regression allowed before failing)
P95_REGRESSION_PCT=20
ERROR_RATE_MAX_PCT=1
RPS_DROP_PCT=15

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=true; shift ;;
    --baseline)  BASELINE_FILE="$2"; shift 2 ;;
    --current)   CURRENT_FILE="$2"; shift 2 ;;
    *)           shift ;;
  esac
done

# Auto-discover latest baseline if not provided
if [[ -z "${BASELINE_FILE}" ]]; then
  BASELINE_FILE=$(ls -t "${REPO_ROOT}/artifacts/perf-baseline-"*.json 2>/dev/null | head -1 || echo "")
fi

# Auto-discover latest current run
if [[ -z "${CURRENT_FILE}" ]]; then
  CURRENT_FILE=$(ls -t "${REPO_ROOT}/artifacts/perf-current-"*.json 2>/dev/null | head -1 || echo "")
fi

if [[ "${DRY_RUN}" != "true" ]]; then
  [[ -z "${BASELINE_FILE}" || ! -f "${BASELINE_FILE}" ]] && {
    log_error "No baseline file found. Run performance-baseline.sh first."
    exit 1
  }
  [[ -z "${CURRENT_FILE}" || ! -f "${CURRENT_FILE}" ]] && {
    log_error "No current perf file found. Run performance-baseline.sh --output artifacts/perf-current-<sha>.json"
    exit 1
  }
fi

compare_metrics() {
  local base="$1" curr="$2"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] would compare ${base} vs ${curr}"
    return 0
  fi

  python3 - "${base}" "${curr}" << 'PYEOF'
import json, sys

def load(path):
    with open(path) as f:
        return json.load(f)

base = load(sys.argv[1])
curr = load(sys.argv[2])

P95_THRESH = float("20")   # filled by shell below
RPS_THRESH  = float("15")
ERR_THRESH  = float("1")

failures = []
warnings = []

for ep, bm in base["endpoints"].items():
    cm = curr["endpoints"].get(ep)
    if not cm:
        warnings.append(f"  WARN: endpoint {ep} not in current results")
        continue

    # p95 regression
    if bm["p95_ms"] > 0:
        p95_delta = (cm["p95_ms"] - bm["p95_ms"]) / bm["p95_ms"] * 100
        if p95_delta > P95_THRESH:
            failures.append(f"  FAIL {ep}: p95 regression +{p95_delta:.1f}% "
                            f"(base={bm['p95_ms']}ms current={cm['p95_ms']}ms)")
        else:
            print(f"  OK   {ep}: p95 {cm['p95_ms']}ms (Δ{p95_delta:+.1f}%)")

    # RPS drop
    if bm["rps"] > 0:
        rps_delta = (cm["rps"] - bm["rps"]) / bm["rps"] * 100
        if rps_delta < -RPS_THRESH:
            failures.append(f"  FAIL {ep}: RPS drop {rps_delta:.1f}% "
                            f"(base={bm['rps']} current={cm['rps']})")

    # Error rate
    if cm.get("errors", 0) > 0 and cm.get("rps", 0) > 0:
        err_pct = cm["errors"] / (cm["rps"] * base.get("duration_sec", 60)) * 100
        if err_pct > ERR_THRESH:
            failures.append(f"  FAIL {ep}: error rate {err_pct:.2f}% > {ERR_THRESH}%")

for w in warnings:
    print(w)

if failures:
    for f in failures:
        print(f, file=sys.stderr)
    sys.exit(1)
else:
    print("  All performance gates passed")
    sys.exit(0)
PYEOF
}

# Main
log_info "Performance Gate — dry-run=${DRY_RUN}"
log_info "Baseline: ${BASELINE_FILE:-<dry-run>}"
log_info "Current:  ${CURRENT_FILE:-<dry-run>}"
log_info "Thresholds: p95_regression=${P95_REGRESSION_PCT}% rps_drop=${RPS_DROP_PCT}% err_max=${ERROR_RATE_MAX_PCT}%"
log_info "============================================================"

compare_metrics "${BASELINE_FILE}" "${CURRENT_FILE}"
EXIT_CODE=$?

log_info "============================================================"
if [[ ${EXIT_CODE} -eq 0 ]]; then
  log_info "✅ Performance gate: PASSED"
else
  log_error "❌ Performance gate: FAILED — regressions detected"
fi
exit ${EXIT_CODE}
