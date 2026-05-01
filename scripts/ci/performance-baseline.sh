#!/usr/bin/env bash
# @file scripts/ci/performance-baseline.sh
# @description Capture a performance baseline from the running stack.
#              Records p50/p95/p99 latency, error rate, and throughput per endpoint.
#              Output saved to artifacts/perf-baseline-<sha>.json for gate comparison.
# @usage performance-baseline.sh [--url <base-url>] [--duration <seconds>] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false
BASE_URL="${BASE_URL:-http://localhost:8080}"
DURATION="${DURATION:-60}"
CONCURRENCY="${CONCURRENCY:-10}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=true; shift ;;
    --url)        BASE_URL="$2"; shift 2 ;;
    --duration)   DURATION="$2"; shift 2 ;;
    --concurrency) CONCURRENCY="$2"; shift 2 ;;
    *)            shift ;;
  esac
done

GIT_SHA=$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo "unknown")
BASELINE_FILE="${REPO_ROOT}/artifacts/perf-baseline-${GIT_SHA}.json"
mkdir -p "${REPO_ROOT}/artifacts"

# Check for hey (load testing tool), fallback to ab, fallback to curl loop
pick_load_tool() {
  if command -v hey >/dev/null 2>&1; then echo "hey"
  elif command -v ab >/dev/null 2>&1; then echo "ab"
  else echo "curl"
  fi
}

run_hey() {
  local url="$1" output
  output=$(hey -z "${DURATION}s" -c "${CONCURRENCY}" -q 10 -o json "${url}" 2>/dev/null)
  local p50 p95 p99 rps errors
  p50=$(echo "${output}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(round(d['latencyDistribution'][49]['latency']*1000,2))" 2>/dev/null || echo 0)
  p95=$(echo "${output}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(round(d['latencyDistribution'][94]['latency']*1000,2))" 2>/dev/null || echo 0)
  p99=$(echo "${output}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(round(d['latencyDistribution'][98]['latency']*1000,2))" 2>/dev/null || echo 0)
  rps=$(echo "${output}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(round(d['rps'],2))" 2>/dev/null || echo 0)
  errors=$(echo "${output}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(sum(d['statusCodeDist'].get(str(c),0) for c in range(500,600)))" 2>/dev/null || echo 0)
  echo "${p50} ${p95} ${p99} ${rps} ${errors}"
}

run_curl_loop() {
  local url="$1"
  local deadline=$(( $(date +%s) + DURATION ))
  local count=0 total_ms=0 errors=0
  while (( $(date +%s) < deadline )); do
    local start end ms http_code
    start=$(date +%s%3N)
    http_code=$(curl -sf -o /dev/null -w '%{http_code}' --max-time 10 "${url}" 2>/dev/null || echo 000)
    end=$(date +%s%3N)
    ms=$(( end - start ))
    total_ms=$(( total_ms + ms ))
    count=$(( count + 1 ))
    [[ "${http_code}" =~ ^5 ]] && errors=$(( errors + 1 ))
  done
  local avg=$(( count > 0 ? total_ms / count : 0 ))
  echo "${avg} ${avg} ${avg} 0 ${errors}"
}

measure_endpoint() {
  local name="$1" path="$2"
  local url="${BASE_URL}${path}"
  log_info "  Measuring ${name} (${url})..."

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo '{"p50_ms":5.2,"p95_ms":12.1,"p99_ms":25.0,"rps":95.3,"errors":0}'
    return
  fi

  local tool p50 p95 p99 rps errors
  tool=$(pick_load_tool)

  if [[ "${tool}" == "hey" ]]; then
    read -r p50 p95 p99 rps errors < <(run_hey "${url}")
  else
    read -r p50 p95 p99 rps errors < <(run_curl_loop "${url}")
  fi

  echo "{\"p50_ms\":${p50},\"p95_ms\":${p95},\"p99_ms\":${p99},\"rps\":${rps},\"errors\":${errors}}"
}

# Main
log_info "Performance Baseline — url=${BASE_URL} duration=${DURATION}s dry-run=${DRY_RUN}"
log_info "=================================================================="

declare -A ENDPOINTS
ENDPOINTS[health]="/health"
ENDPOINTS[api_status]="/api/v1/status"
ENDPOINTS[workspace_list]="/api/v1/workspaces"

# Build JSON
results=()
for name in "${!ENDPOINTS[@]}"; do
  path="${ENDPOINTS[$name]}"
  metric=$(measure_endpoint "${name}" "${path}")
  results+=("\"${name}\": ${metric}")
  log_info "    ${name}: $(echo "${metric}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'p50={d[\"p50_ms\"]}ms p95={d[\"p95_ms\"]}ms rps={d[\"rps\"]}')" 2>/dev/null || echo "${metric}")"
done

# Write baseline JSON
{
  echo "{"
  echo "  \"git_sha\": \"${GIT_SHA}\","
  echo "  \"captured_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"duration_sec\": ${DURATION},"
  echo "  \"concurrency\": ${CONCURRENCY},"
  echo "  \"base_url\": \"${BASE_URL}\","
  echo "  \"endpoints\": {"
  local_sep=""
  for entry in "${results[@]}"; do
    echo "    ${local_sep}${entry}"
    local_sep=","
  done
  echo "  }"
  echo "}"
} > "${BASELINE_FILE}"

log_info "=================================================================="
log_info "Baseline saved: ${BASELINE_FILE}"
