#!/usr/bin/env bash
# @file        scripts/ops/benchmark-nas-throughput.sh
# @module      ops/storage
# @description NAS performance benchmarking (iperf3, fio, mount latency)
# @governance  GOV-002: IaC, idempotent, version-controlled
# Issue #1536: Networking, DNS & Performance — NAS Tuning

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/logging.sh"
source "${REPO_ROOT}/scripts/_common/_base-config.env"
source "${REPO_ROOT}/scripts/lib/nas.sh"

# ── Configuration ─────────────────────────────────────────────────────────────
# All infrastructure hosts come from _base-config.env (SSOT)
NAS_MOUNT_POINT="${NAS_MOUNT_POINT:-/mnt/nas}"

DRY_RUN="${DRY_RUN:-0}"
REPORT_FILE="${REPORT_FILE:-${REPO_ROOT}/artifacts/reports/nas-benchmark-$(date +%Y%m%d-%H%M%S).json}"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
pass() { printf "${GREEN}  ✔  %s${NC}\n" "$*"; }
fail() { printf "${RED}  ✖  %s${NC}\n" "$*" >&2; }
warn() { printf "${YELLOW}  ⚠  %s${NC}\n" "$*" >&2; }
info() { printf "     %s\n" "$*"; }

# ── Prerequisites Check ───────────────────────────────────────────────────────

check_prerequisites() {
  log_info "Checking prerequisites for NAS benchmarking..."

  # Check for required tools
  local required_tools=("iperf3" "fio" "jq" "ssh")
  local missing_tools=()

  for tool in "${required_tools[@]}"; do
    if ! command -v "${tool}" &>/dev/null; then
      missing_tools+=("${tool}")
    fi
  done

  if [ ${#missing_tools[@]} -gt 0 ]; then
    log_error "Missing required tools: ${missing_tools[*]}"
    log_info "Install with: apt-get install -y iperf3 fio jq openssh-client"
    return 1
  fi

  pass "All prerequisites satisfied"
  return 0
}

# ── NAS Baseline Checks ───────────────────────────────────────────────────────

check_nas_connectivity() {
  local host="${1}"

  if ping -c 1 -W 2 "${host}" >/dev/null 2>&1; then
    pass "NAS host (${host}) is reachable"
    return 0
  else
    fail "NAS host (${host}) is NOT reachable"
    return 1
  fi
}

check_nas_mount() {
  local mount_point="${1}"

  if mountpoint -q "${mount_point}" 2>/dev/null; then
    pass "NAS mounted at ${mount_point}"
    return 0
  else
    fail "NAS NOT mounted at ${mount_point}"
    return 1
  fi
}

# ── iperf3 Benchmarking (10G Network Throughput) ───────────────────────────────

benchmark_iperf3() {
  local source_host="${1}"
  local dest_host="${2}"
  local duration="${3:-10}"

  log_info "Starting iperf3 benchmark: ${source_host} → ${dest_host}"

  if [ "${DRY_RUN}" = "1" ]; then
    log_info "[DRY-RUN] Would run: iperf3 -c ${dest_host} -t ${duration} -J"
    return 0
  fi

  # Run iperf3 from source to dest
  local result
  result=$(ssh "${source_host}" "iperf3 -c ${dest_host} -t ${duration} -J" 2>/dev/null || echo "{}")

  if [ -z "${result}" ] || [ "${result}" = "{}" ]; then
    fail "iperf3 benchmark failed"
    echo "{}"
    return 1
  fi

  # Extract throughput (bits/sec)
  local throughput_bps
  throughput_bps=$(echo "${result}" | jq -r '.end.sum_received.bits_per_second // 0' 2>/dev/null || echo "0")

  if [ "${throughput_bps}" = "0" ] || [ -z "${throughput_bps}" ]; then
    fail "Could not extract throughput from iperf3 result"
    return 1
  fi

  local throughput_mbps=$(( throughput_bps / 1000000 ))
  pass "iperf3 throughput: ${throughput_mbps} Mbps"

  echo "${result}"
  return 0
}

# ── fio Benchmarking (NAS Mount I/O Performance) ────────────────────────────────

benchmark_fio() {
  local mount_point="${1}"
  local test_size="${2:-1G}"
  local io_depth="${3:-32}"
  local num_jobs="${4:-4}"

  log_info "Starting fio benchmark on ${mount_point}"

  if [ "${DRY_RUN}" = "1" ]; then
    log_info "[DRY-RUN] Would run fio sequential and random I/O tests"
    return 0
  fi

  # Create test file
  local test_file="${mount_point}/.fio-test-file"
  mkdir -p "${mount_point}"

  # Sequential write test
  log_info "Sequential write test..."
  local seq_write_result
  seq_write_result=$(fio \
    --name=seqwrite \
    --filename="${test_file}" \
    --filesize="${test_size}" \
    --bs=128k \
    --ioengine=libaio \
    --iodepth="${io_depth}" \
    --numjobs="${num_jobs}" \
    --rw=write \
    --output-format=json \
    --direct=1 2>/dev/null || echo "{}")

  local seq_write_bw=$(echo "${seq_write_result}" | jq -r '.jobs[0].write.bw_mean // 0' 2>/dev/null || echo "0")

  pass "Sequential write: ${seq_write_bw} KB/s"

  # Sequential read test
  log_info "Sequential read test..."
  local seq_read_result
  seq_read_result=$(fio \
    --name=seqread \
    --filename="${test_file}" \
    --filesize="${test_size}" \
    --bs=128k \
    --ioengine=libaio \
    --iodepth="${io_depth}" \
    --numjobs="${num_jobs}" \
    --rw=read \
    --output-format=json \
    --direct=1 2>/dev/null || echo "{}")

  local seq_read_bw=$(echo "${seq_read_result}" | jq -r '.jobs[0].read.bw_mean // 0' 2>/dev/null || echo "0")

  pass "Sequential read: ${seq_read_bw} KB/s"

  # Random read test
  log_info "Random read test..."
  local rand_read_result
  rand_read_result=$(fio \
    --name=randread \
    --filename="${test_file}" \
    --filesize="${test_size}" \
    --bs=4k \
    --ioengine=libaio \
    --iodepth="${io_depth}" \
    --numjobs="${num_jobs}" \
    --rw=randread \
    --output-format=json \
    --direct=1 2>/dev/null || echo "{}")

  local rand_read_bw=$(echo "${rand_read_result}" | jq -r '.jobs[0].read.bw_mean // 0' 2>/dev/null || echo "0")

  pass "Random read: ${rand_read_bw} KB/s"

  # Clean up test file
  rm -f "${test_file}"

  # Output combined result
  jq -n \
    --arg sw_bw "${seq_write_bw}" \
    --arg sr_bw "${seq_read_bw}" \
    --arg rr_bw "${rand_read_bw}" \
    '{sequential_write_kbps: $sw_bw, sequential_read_kbps: $sr_bw, random_read_kbps: $rr_bw}'
}

# ── Mount Latency Benchmarking ─────────────────────────────────────────────────

benchmark_mount_latency() {
  local mount_point="${1}"
  local iterations="${2:-100}"

  log_info "Measuring NAS mount latency (${iterations} iterations)..."

  local total_latency_ms=0
  local max_latency_ms=0
  local min_latency_ms=9999
  local i

  for i in $(seq 1 "${iterations}"); do
    local start_time end_time latency_ms
    start_time=$(date +%s%N)
    stat "${mount_point}" >/dev/null 2>&1 || true
    end_time=$(date +%s%N)

    latency_ms=$(( (end_time - start_time) / 1000000 ))
    total_latency_ms=$(( total_latency_ms + latency_ms ))

    if (( latency_ms > max_latency_ms )); then
      max_latency_ms=${latency_ms}
    fi

    if (( latency_ms < min_latency_ms )); then
      min_latency_ms=${latency_ms}
    fi
  done

  local avg_latency_ms=$(( total_latency_ms / iterations ))

  pass "Mount latency - Avg: ${avg_latency_ms}ms, Min: ${min_latency_ms}ms, Max: ${max_latency_ms}ms"

  jq -n \
    --arg avg "${avg_latency_ms}" \
    --arg min "${min_latency_ms}" \
    --arg max "${max_latency_ms}" \
    --arg iterations "${iterations}" \
    '{average_ms: $avg, min_ms: $min, max_ms: $max, iterations: $iterations}'
}

# ── Generate Benchmark Report ─────────────────────────────────────────────────

generate_report() {
  local iperf3_result="${1}"
  local fio_result="${2}"
  local latency_result="${3}"

  log_info "Generating benchmark report..."

  mkdir -p "$(dirname "${REPORT_FILE}")"

  local timestamp report_json

  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  report_json=$(jq -n \
    --arg timestamp "${timestamp}" \
    --arg primary_host "${PRIMARY_HOST}" \
    --arg replica_host "${REPLICA_HOST}" \
    --arg nas_host "${NAS_HOST}" \
    --argjson iperf3 "${iperf3_result}" \
    --argjson fio "${fio_result}" \
    --argjson latency "${latency_result}" \
    '{
      timestamp: $timestamp,
      infrastructure: {
        primary_host: $primary_host,
        replica_host: $replica_host,
        nas_host: $nas_host
      },
      benchmarks: {
        iperf3_throughput: $iperf3,
        fio_io_performance: $fio,
        mount_latency: $latency
      }
    }')

  echo "${report_json}" | jq . > "${REPORT_FILE}"
  pass "Report saved: ${REPORT_FILE}"

  return 0
}

# ── Main Benchmark Execution ──────────────────────────────────────────────────

main() {
  echo ""
  echo "======================================="
  echo "   NAS Performance Benchmarking (Phase 4)"
  echo "======================================="
  echo ""

  # Check prerequisites
  if ! check_prerequisites; then
    log_error "Prerequisites not satisfied"
    return 1
  fi

  # Check NAS connectivity
  if ! check_nas_connectivity "${NAS_HOST}"; then
    log_error "NAS connectivity check failed"
    return 1
  fi

  # Check NAS mount
  if ! check_nas_mount "${NAS_MOUNT_POINT}"; then
    log_error "NAS mount check failed"
    return 1
  fi

  # Run benchmarks
  echo ""
  echo "=== iperf3 Throughput Test (Primary → Replica) ==="
  local iperf3_result
  iperf3_result=$(benchmark_iperf3 "${PRIMARY_HOST}" "${REPLICA_HOST}" 10) || iperf3_result="{}"

  echo ""
  echo "=== fio I/O Performance Test ==="
  local fio_result
  fio_result=$(benchmark_fio "${NAS_MOUNT_POINT}" "1G" 32 4) || fio_result="{}"

  echo ""
  echo "=== Mount Latency Test ==="
  local latency_result
  latency_result=$(benchmark_mount_latency "${NAS_MOUNT_POINT}" 100) || latency_result="{}"

  # Generate report
  echo ""
  generate_report "${iperf3_result}" "${fio_result}" "${latency_result}"

  echo ""
  pass "NAS benchmarking complete"
  return 0
}

main "$@"
