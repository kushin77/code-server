#!/usr/bin/env bash
# @file        scripts/performance/slo-report.sh
# @module      performance/slo
# @description Phase 8 — SLO compliance report: availability, latency, error rate, error budget
#
# Usage: bash scripts/performance/slo-report.sh [--window 30d] [--prometheus http://localhost:9090]
# On-prem: ssh akushnir@192.168.168.31 'cd code-server-enterprise && bash scripts/performance/slo-report.sh'
#
set -euo pipefail

# shellcheck source=scripts/_common/logging.sh
source "$(dirname "${BASH_SOURCE[0]}")/../_common/logging.sh"

# ─── Config ──────────────────────────────────────────────────────────────────
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
WINDOW="${WINDOW:-30d}"
SLO_AVAILABILITY_TARGET="${SLO_AVAILABILITY_TARGET:-0.9999}"  # 99.99%
SLO_LATENCY_P50_MS="${SLO_LATENCY_P50_MS:-50}"
SLO_LATENCY_P99_MS="${SLO_LATENCY_P99_MS:-100}"
SLO_ERROR_RATE_TARGET="${SLO_ERROR_RATE_TARGET:-0.0001}"      # 0.01%
OUTPUT_DIR="/tmp/perf-reports"
REPORT_FILE="${OUTPUT_DIR}/slo-report-$(date +%Y%m%d-%H%M%S).txt"

# ─── Parse args ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --window) WINDOW="$2"; shift 2 ;;
    --prometheus) PROMETHEUS_URL="$2"; shift 2 ;;
    *) log_warn "Unknown arg: $1"; shift ;;
  esac
done

mkdir -p "${OUTPUT_DIR}"

# ─── Helper: Prometheus instant query ────────────────────────────────────────
promquery() {
  local query="$1"
  curl -sG "${PROMETHEUS_URL}/api/v1/query" \
    --data-urlencode "query=${query}" \
    2>/dev/null | \
  python3 -c "
import sys, json
d = json.load(sys.stdin)
r = d.get('data', {}).get('result', [])
if r: print(r[0]['value'][1])
else: print('N/A')
" 2>/dev/null || echo "N/A"
}

# ─── Check Prometheus reachability ───────────────────────────────────────────
if ! curl -sf "${PROMETHEUS_URL}/-/healthy" > /dev/null 2>&1; then
  log_error "Prometheus unreachable at ${PROMETHEUS_URL}. Check: docker ps | grep prometheus"
  exit 1
fi
log_info "Prometheus reachable at ${PROMETHEUS_URL}"

# ─── Report header ───────────────────────────────────────────────────────────
{
  echo "═══════════════════════════════════════════════════════════════"
  echo " SLO Compliance Report — Phase 8 Post-HA"
  echo " Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo " Window: ${WINDOW} | Prometheus: ${PROMETHEUS_URL}"
  echo " Targets: Avail=${SLO_AVAILABILITY_TARGET} | P50<${SLO_LATENCY_P50_MS}ms | P99<${SLO_LATENCY_P99_MS}ms | ErrRate<${SLO_ERROR_RATE_TARGET}"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
} | tee "${REPORT_FILE}"

# ─── Section 1: Availability SLO ─────────────────────────────────────────────
log_info "Querying availability SLI (${WINDOW} window)..."
AVAIL=$(promquery "
  (
    sum(rate(http_requests_total{status!~\"5..\"}[${WINDOW}]))
  ) / (
    sum(rate(http_requests_total[${WINDOW}])) > 0
  )
")
ERROR_BUDGET_USED=$(promquery "
  (1 - (
    sum(rate(http_requests_total{status!~\"5..\"}[${WINDOW}]))
    / (sum(rate(http_requests_total[${WINDOW}])) > 0)
  )) / ${SLO_ERROR_RATE_TARGET} * 100
")
{
  echo "── AVAILABILITY SLO (target: ${SLO_AVAILABILITY_TARGET}) ──────────────────"
  echo "  Current:          ${AVAIL}"
  echo "  Error budget used: ${ERROR_BUDGET_USED}%"
  echo ""
} | tee -a "${REPORT_FILE}"

# ─── Section 2: Latency SLO ───────────────────────────────────────────────────
log_info "Querying latency SLIs..."
P50=$(promquery "histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket[${WINDOW}])) by (le)) * 1000")
P99=$(promquery "histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[${WINDOW}])) by (le)) * 1000")
{
  echo "── LATENCY SLO ─────────────────────────────────────────────────────────────"
  echo "  P50 latency:  ${P50}ms (target: <${SLO_LATENCY_P50_MS}ms)"
  echo "  P99 latency:  ${P99}ms (target: <${SLO_LATENCY_P99_MS}ms)"
  echo ""
} | tee -a "${REPORT_FILE}"

# ─── Section 3: Error rate ────────────────────────────────────────────────────
log_info "Querying error rate..."
ERR_RATE=$(promquery "
  1 - (
    sum(rate(http_requests_total{status!~\"5..\"}[${WINDOW}]))
    / (sum(rate(http_requests_total[${WINDOW}])) > 0)
  )
")
{
  echo "── ERROR RATE (target: <${SLO_ERROR_RATE_TARGET}) ─────────────────────────"
  echo "  Error rate: ${ERR_RATE} (target: <${SLO_ERROR_RATE_TARGET})"
  echo ""
} | tee -a "${REPORT_FILE}"

# ─── Section 4: PgBouncer stats ───────────────────────────────────────────────
log_info "Querying PgBouncer pool stats..."
PB_WAITING=$(promquery "max(pgbouncer_pools_cl_waiting)")
PB_ACTIVE=$(promquery "sum(pgbouncer_pools_sv_active)")
{
  echo "── PGBOUNCER POOL STATS ────────────────────────────────────────────────────"
  echo "  Clients waiting:  ${PB_WAITING}"
  echo "  Active srv conns: ${PB_ACTIVE}"
  echo ""
} | tee -a "${REPORT_FILE}"

# ─── Section 5: Service health ────────────────────────────────────────────────
log_info "Checking container health via Docker..."
if command -v docker &>/dev/null; then
  {
    echo "── CONTAINER HEALTH ────────────────────────────────────────────────────────"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}" 2>/dev/null || echo "  Docker not available"
    echo ""
  } | tee -a "${REPORT_FILE}"
fi

# ─── Section 6: Compliance verdict ───────────────────────────────────────────
{
  echo "── SLO COMPLIANCE VERDICT ──────────────────────────────────────────────────"
  echo "  (Manual verification required — compare above values to targets)"
  echo "  Availability ${SLO_AVAILABILITY_TARGET}:  [CHECK AVAIL VALUE ABOVE]"
  echo "  P50 <${SLO_LATENCY_P50_MS}ms:            [CHECK P50 VALUE ABOVE]"
  echo "  P99 <${SLO_LATENCY_P99_MS}ms:           [CHECK P99 VALUE ABOVE]"
  echo "  Error rate <${SLO_ERROR_RATE_TARGET}:   [CHECK ERR_RATE VALUE ABOVE]"
  echo ""
  echo "  Full report: ${REPORT_FILE}"
  echo "═══════════════════════════════════════════════════════════════"
} | tee -a "${REPORT_FILE}"

log_info "SLO report complete: ${REPORT_FILE}"
