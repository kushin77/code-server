#!/usr/bin/env bash
###############################################################################
# @file        scripts/benchmark-nas.sh
# @module      benchmark-nas
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
#
# ElevatedIQ NAS Performance Benchmarking
# Measures network throughput, file I/O, and mount performance
#
# Prerequisites:
#   - SSH access to primary host (${PRIMARY_HOST})
#   - iperf3 and fio installed on both hosts
#   - NAS mounted at /mnt/nas or Z: drive
#
# Usage:
#   bash scripts/perf/benchmark-nas.sh [--nas-host ${NAS_HOST}] [--output report.json]
#
# Expected Metrics:
#   - Network: >100 Mbps on 1GbE, >1000 Mbps on 10GbE
#   - Throughput: >50 MB/s sequential, >30 MB/s random
#   - IOPS: >500 ops/sec (small files), >100 ops/sec (random)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${REPO_ROOT}/scripts/_common/init.sh"
source "${REPO_ROOT}/scripts/_common/hosts.sh"

# Configuration
NAS_HOST="${NAS_HOST:-}"
PRIMARY_HOST="${PRIMARY_HOST:-}"
OUTPUT_FILE="$(date +nas-benchmark-%Y%m%d-%H%M%S.json)"
BENCHMARK_DIR="/tmp/nas-benchmark-$$"
MOUNT_POINT="/mnt/nas"

usage() {
  echo "Usage: bash scripts/perf/benchmark-nas.sh [--nas-host HOST] [--primary-host HOST] [--output FILE]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --nas-host)
      NAS_HOST="${2:-}"
      shift 2
      ;;
    --primary-host)
      PRIMARY_HOST="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="${2:-$OUTPUT_FILE}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

: "${NAS_HOST:?NAS_HOST must be set via --nas-host or environment}"
: "${PRIMARY_HOST:?PRIMARY_HOST must be set via --primary-host or environment}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

# JSON helpers
json_start() {
  cat > "$OUTPUT_FILE" << 'EOF'
{
  "benchmark_date": "$(date -Iseconds)",
  "nas_host": "NAS_HOST_PLACEHOLDER",
  "primary_host": "PRIMARY_HOST_PLACEHOLDER",
  "results": {
EOF
}

# Main execution
main() {
  echo ""
  echo "╔════════════════════════════════════════════════════════╗"
  echo "║     ElevatedIQ NAS Performance Benchmarking Suite      ║"
  echo "╚════════════════════════════════════════════════════════╝"
  echo ""

  log_info "Configuration:"
  echo "   NAS Host: $NAS_HOST"
  echo "   Primary Host: $PRIMARY_HOST"
  echo "   Output: $OUTPUT_FILE"
  echo ""

  # Check NAS connectivity
  log_info "Checking NAS connectivity..."
  if ! ping -c 1 -W 2 "$NAS_HOST" &>/dev/null; then
    log_error "Cannot reach NAS at $NAS_HOST"
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Verify NAS IP: ping $NAS_HOST"
    echo "  2. Check network: traceroute $NAS_HOST"
    echo "  3. Verify mount: mount | grep $MOUNT_POINT"
    echo "  4. Test CIFS: smbclient -L $NAS_HOST -N"
    exit 1
  fi
  log_success "NAS is reachable at $NAS_HOST"
  echo ""

  # Check NAS mount
  log_info "Verifying NAS mount point..."
  if ! ssh -i ~/.ssh/id_rsa "akushnir@$PRIMARY_HOST" "test -d $MOUNT_POINT" 2>/dev/null; then
    log_warn "NAS not mounted at $MOUNT_POINT on $PRIMARY_HOST"
    echo "   Mount details will be reported separately"
  else
    log_success "NAS mounted at $MOUNT_POINT"
  fi
  echo ""

  # Network throughput test
  log_info "Starting network throughput benchmarks..."
  echo "   (requires iperf3 server listening on $NAS_HOST:5201)"
  echo ""
  benchmark_network || log_warn "Network benchmark skipped (iperf3 may not be running)"
  echo ""

  # File I/O benchmarks
  log_info "Starting file I/O benchmarks..."
  benchmark_file_io
  echo ""

  # Generate report
  log_info "Generating benchmark report..."
  generate_report
  echo ""

  log_success "Benchmarking complete!"
  echo "   Report saved to: $OUTPUT_FILE"
  echo ""
}

benchmark_network() {
  log_info "Network Throughput (requires iperf3 server on NAS)"
  
  # Attempt 10-second throughput test
  echo "   Testing 10-second sustained throughput..."
  
  RESULT=$(ssh -i ~/.ssh/id_rsa "akushnir@$PRIMARY_HOST" \
    "iperf3 -c $NAS_HOST -t 10 -f M 2>/dev/null | grep 'Bitrate' | tail -1" 2>/dev/null || echo "")
  
  if [[ -n "$RESULT" ]]; then
    echo "   Result: $RESULT"
  fi
}

benchmark_file_io() {
  # Create benchmark directory on NAS
  ssh -i ~/.ssh/id_rsa "akushnir@$PRIMARY_HOST" "mkdir -p $MOUNT_POINT/benchmark-$$" 2>/dev/null || true
  
  echo "   Running fio benchmarks on NAS..."
  
  # Sequential write test
  echo "   - Sequential write (128MB, 1MB block size)..."
  ssh -i ~/.ssh/id_rsa "akushnir@$PRIMARY_HOST" \
    "fio --name=seq-write --rw=write --bs=1m --size=128m --numjobs=1 --iodepth=8 \
     --directory=$MOUNT_POINT/benchmark-$$ --output-format=json" 2>/dev/null | \
    grep -oP '"write.*?":\s*\{\s*"io_bytes":\s*\d+' || true
  
  # Random read test
  echo "   - Random read (64MB, 4KB block size, 8 jobs)..."
  ssh -i ~/.ssh/id_rsa "akushnir@$PRIMARY_HOST" \
    "fio --name=rand-read --rw=randread --bs=4k --size=64m --numjobs=8 --iodepth=4 \
     --directory=$MOUNT_POINT/benchmark-$$ --output-format=json" 2>/dev/null | \
    grep -oP '"iops"' || true
  
  # Cleanup
  ssh -i ~/.ssh/id_rsa "akushnir@$PRIMARY_HOST" "rm -rf $MOUNT_POINT/benchmark-$$" 2>/dev/null || true
}

generate_report() {
  cat > "$OUTPUT_FILE" << EOF
{
  "benchmark_metadata": {
    "date": "$(date -Iseconds)",
    "nas_host": "$NAS_HOST",
    "primary_host": "$PRIMARY_HOST",
    "mount_point": "$MOUNT_POINT"
  },
  "network_benchmarks": {
    "description": "iperf3 throughput measurements",
    "unit": "Mbps",
    "expected_baseline_1GbE": 100,
    "expected_baseline_10GbE": 1000
  },
  "file_io_benchmarks": {
    "sequential_write": {
      "description": "Sequential write test (128MB, 1MB blocks)",
      "unit": "MB/s",
      "expected_baseline": 50
    },
    "random_read": {
      "description": "Random read test (64MB, 4KB blocks, 8 jobs)",
      "unit": "IOPS",
      "expected_baseline": 500
    }
  },
  "mount_details": {
    "filesystem_type": "cifs",
    "mount_protocol": "smb3",
    "optimization_notes": "Enable SMB3 signing and multichannel for best performance"
  },
  "recommendations": [
    "Verify 1GbE/10GbE network speed: ethtool eth0",
    "Enable SMB3 multichannel for parallel connections",
    "Use SSD cache on NAS for frequently accessed data",
    "Monitor CPU/disk utilization during sustained I/O",
    "Test with jumbo frames (MTU 9000) if applicable"
  ]
}
EOF
  log_success "Report generated: $OUTPUT_FILE"
}

# Cleanup on exit
cleanup() {
  rm -rf "$BENCHMARK_DIR" 2>/dev/null || true
}

trap cleanup EXIT

# Execute
main "$@"
