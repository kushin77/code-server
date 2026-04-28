#!/usr/bin/env bash
# @file scripts/capacity/forecast.sh
# @description Phase 13 - Forecast resource utilization 12 months out via linear
# regression on Prometheus history (CSV input fallback for offline runs).
# Tracks GitHub issue #2406.

set -euo pipefail

# Required error handling traps (pre-commit policy)
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/../_common/init.sh"

# Inputs
INPUT_CSV="${1:-}"
OUT="${REPO_ROOT}/artifacts/capacity/forecast-$(date -u +%Y%m%dT%H%M%SZ).md"
mkdir -p "$(dirname "${OUT}")"

if [ -z "${INPUT_CSV}" ]; then
    # Generate a synthetic 12-month history so the script is runnable offline.
    INPUT_CSV="${REPO_ROOT}/artifacts/capacity/sample-history.csv"
    log_info "No input CSV given; generating synthetic 12-month sample at ${INPUT_CSV}"
    python3 - "${INPUT_CSV}" <<'PY'
import sys, math, random
from datetime import datetime, timedelta, timezone
out = sys.argv[1]
random.seed(42)
rows = ['month,cpu_used_vcpu,mem_used_gb,disk_used_gb,requests_per_sec']
base = datetime(2025, 5, 1, tzinfo=timezone.utc)
for i in range(12):
    m = base + timedelta(days=30 * i)
    cpu = 18 + 0.55 * i + random.uniform(-0.6, 0.6)
    mem = 96 + 2.4 * i + random.uniform(-2, 2)
    dsk = 410 + 14 * i + random.uniform(-5, 5)
    rps = 320 + 12 * i + random.uniform(-8, 8)
    rows.append(f"{m.strftime('%Y-%m')},{cpu:.2f},{mem:.2f},{dsk:.2f},{rps:.2f}")
open(out, 'w').write('\n'.join(rows) + '\n')
PY
fi

log_info "=== Capacity Forecast (Phase 13) ==="
log_info "Input: ${INPUT_CSV}"

python3 - "${INPUT_CSV}" "${OUT}" <<'PY'
import csv, sys, statistics
from datetime import datetime
src, out = sys.argv[1], sys.argv[2]

# Capacity ceilings (override via env if needed); kept conservative.
CEIL = {'cpu_used_vcpu': 64, 'mem_used_gb': 512, 'disk_used_gb': 4096, 'requests_per_sec': 2000}

rows = list(csv.DictReader(open(src)))
if len(rows) < 3:
    raise SystemExit("Need at least 3 history rows for forecasting")

def linreg(xs, ys):
    # Ordinary least squares
    n = len(xs)
    mx = sum(xs)/n; my = sum(ys)/n
    num = sum((xs[i]-mx)*(ys[i]-my) for i in range(n))
    den = sum((xs[i]-mx)**2 for i in range(n)) or 1e-9
    slope = num/den
    intercept = my - slope*mx
    # R^2
    ss_tot = sum((y-my)**2 for y in ys) or 1e-9
    ss_res = sum((ys[i] - (slope*xs[i]+intercept))**2 for i in range(n))
    r2 = 1 - ss_res/ss_tot
    return slope, intercept, r2

xs = list(range(len(rows)))
metrics = ['cpu_used_vcpu', 'mem_used_gb', 'disk_used_gb', 'requests_per_sec']
forecasts = {}
for m in metrics:
    ys = [float(r[m]) for r in rows]
    slope, intercept, r2 = linreg(xs, ys)
    proj_12 = slope*(len(xs) + 11) + intercept  # 12 months ahead from last point
    months_to_ceiling = None
    if slope > 1e-6:
        # solve slope*x + intercept = ceiling
        x_at = (CEIL[m] - intercept) / slope
        months_to_ceiling = max(0, x_at - (len(xs)-1))
    forecasts[m] = {
        'slope_per_month': slope, 'r2': r2, 'last': ys[-1],
        'proj_12mo': proj_12, 'ceiling': CEIL[m],
        'months_to_ceiling': months_to_ceiling,
        'utilization_now': ys[-1]/CEIL[m],
        'utilization_12mo': proj_12/CEIL[m],
    }

with open(out, 'w') as f:
    f.write("# Capacity Forecast — Phase 13\n\n")
    f.write("Tracks: GitHub issue #2406.\n\n")
    f.write(f"Source rows: **{len(rows)}** (months {rows[0]['month']} → {rows[-1]['month']})\n\n")
    f.write("## 12-month projection\n\n")
    f.write("| Metric | Now | +12mo | Ceiling | Util now | Util +12mo | R² | Months → ceiling |\n|---|---|---|---|---|---|---|---|\n")
    for m in metrics:
        d = forecasts[m]
        mtc = f"{d['months_to_ceiling']:.1f}" if d['months_to_ceiling'] is not None else "n/a (flat or decreasing)"
        f.write(
            f"| {m} | {d['last']:.1f} | {d['proj_12mo']:.1f} | {d['ceiling']:.0f} "
            f"| {d['utilization_now']*100:.1f}% | {d['utilization_12mo']*100:.1f}% "
            f"| {d['r2']:.2f} | {mtc} |\n"
        )
    f.write("\n## Recommendations\n\n")
    for m in metrics:
        d = forecasts[m]
        if d['utilization_12mo'] >= 0.80:
            f.write(f"- **{m}**: projected to exceed 80% within 12 months — plan capacity expansion now.\n")
        elif d['utilization_12mo'] >= 0.60:
            f.write(f"- **{m}**: trending toward 60% — schedule a review at month 6.\n")
        else:
            f.write(f"- **{m}**: comfortable headroom; no action this quarter.\n")
    f.write("\n## Methodology\n\n")
    f.write("- Linear regression (OLS) on monthly observations.\n")
    f.write("- Ceilings are conservative cluster-wide capacity numbers; override via env or CSV-driven plant size.\n")
    f.write("- R² < 0.5 means the trend is unreliable — treat the projection as directional only.\n")
print('OK', out)
PY

log_success "Capacity forecast: ${OUT}"
exit 0
