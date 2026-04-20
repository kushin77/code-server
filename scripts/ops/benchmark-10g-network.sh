#!/usr/bin/env bash
# @file        scripts/ops/benchmark-10g-network.sh
# @module      infrastructure/performance
# @description Baseline 10G network performance between primary and replica hosts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Configuration
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
IPERF3_VERSION="3.14"
TEST_DURATION=30  # seconds
NUM_STREAMS=4
OUTPUT_DIR="artifacts/triage"

# ─────────────────────────────────────────────────────────────────────────────
# Helper: JSON output
# ─────────────────────────────────────────────────────────────────────────────
json_result() {
  local metric="$1" value="$2" unit="$3"
  echo "{\"metric\": \"$metric\", \"value\": $value, \"unit\": \"$unit\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Preflight checks
# ─────────────────────────────────────────────────────────────────────────────
log_info "Running 10G network baseline benchmark..."

mkdir -p "$OUTPUT_DIR"
: > "$OUTPUT_DIR/network-baseline.json"

# Check if iperf3 is installed
if ! command -v iperf3 &> /dev/null; then
  log_error "iperf3 not found. Install via: apt-get install iperf3"
  exit 1
fi

log_info "iperf3 version: $(iperf3 --version)"

# Test connectivity
if ! ping -c 1 "$REPLICA_HOST" &>/dev/null; then
  log_error "Cannot reach $REPLICA_HOST (replica host)"
  exit 1
fi

log_info "Network connectivity to $REPLICA_HOST: OK"

# ─────────────────────────────────────────────────────────────────────────────
# Single-stream throughput (from primary to replica)
# ─────────────────────────────────────────────────────────────────────────────
log_info "Starting single-stream throughput test (${TEST_DURATION}s)..."

# Start iperf3 server on replica (requires SSH or manual start)
# For now, assume server is already running or will be started separately
if timeout 5 bash -c "echo > /dev/tcp/$REPLICA_HOST/5201" 2>/dev/null; then
  log_info "iperf3 server is ready on $REPLICA_HOST"
  
  # Run client on primary
  iperf_output=$(mktemp)
  iperf3 -c "$REPLICA_HOST" -t "$TEST_DURATION" -J > "$iperf_output" 2>&1 || true
  
  # Extract throughput (bits per second)
  throughput_bps=$(jq '.end.sum_received.bits_per_second' "$iperf_output" 2>/dev/null || echo "0")
  throughput_mbps=$((throughput_bps / 1000000))
  
  json_result "network_single_stream_throughput" "$throughput_mbps" "Mbps" >> "$OUTPUT_DIR/network-baseline.json"
  log_info "Single-stream throughput: $throughput_mbps Mbps (target: ≥900 Mbps)"
  
  rm -f "$iperf_output"
else
  log_warn "iperf3 server not running on $REPLICA_HOST (start with: iperf3 -s)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Latency (round-trip)
# ─────────────────────────────────────────────────────────────────────────────
log_info "Measuring round-trip latency (1000 samples)..."

ping_output=$(ping -c 1000 -i 0.1 "$REPLICA_HOST" 2>&1 | grep "min/avg/max/stddev")
if [[ $ping_output =~ ([0-9.]+)/([0-9.]+)/([0-9.]+) ]]; then
  min_ms="${BASH_REMATCH[1]}"
  avg_ms="${BASH_REMATCH[2]}"
  max_ms="${BASH_REMATCH[3]}"
  
  json_result "network_latency_min" "$min_ms" "ms" >> "$OUTPUT_DIR/network-baseline.json"
  json_result "network_latency_avg" "$avg_ms" "ms" >> "$OUTPUT_DIR/network-baseline.json"
  json_result "network_latency_max" "$max_ms" "ms" >> "$OUTPUT_DIR/network-baseline.json"
  
  log_info "Latency — min: ${min_ms}ms, avg: ${avg_ms}ms, max: ${max_ms}ms (target: P95 ≤1ms)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Interface statistics
# ─────────────────────────────────────────────────────────────────────────────
log_info "Capturing interface statistics..."

# Primary host interface
if command -v ethtool &> /dev/null; then
  if ethtool -S eth0 &>/dev/null; then
    rx_errors=$(ethtool -S eth0 | grep -i "rx.*errors" | awk '{sum += $NF} END {print sum+0}')
    tx_errors=$(ethtool -S eth0 | grep -i "tx.*errors" | awk '{sum += $NF} END {print sum+0}')
    
    json_result "network_interface_rx_errors" "$rx_errors" "count" >> "$OUTPUT_DIR/network-baseline.json"
    json_result "network_interface_tx_errors" "$tx_errors" "count" >> "$OUTPUT_DIR/network-baseline.json"
    
    log_info "Interface errors — RX: $rx_errors, TX: $tx_errors (target: 0)"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# TCP window scaling and congestion control
# ─────────────────────────────────────────────────────────────────────────────
log_info "Checking TCP tuning parameters..."

tcp_window_scaling=$(cat /proc/sys/net/ipv4/tcp_window_scaling 2>/dev/null || echo "unknown")
tcp_cc=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo "unknown")

log_info "TCP window scaling: $tcp_window_scaling (1=enabled)"
log_info "TCP congestion control: $tcp_cc (recommended: bbr)"

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
log_info "✅ 10G network baseline benchmark complete"
log_info "Results saved to: $OUTPUT_DIR/network-baseline.json"

# Format output as readable JSON
if command -v jq &> /dev/null; then
  jq -s . "$OUTPUT_DIR/network-baseline.json" > "${OUTPUT_DIR}/network-baseline.formatted.json" 2>/dev/null || true
  log_info "Formatted results: ${OUTPUT_DIR}/network-baseline.formatted.json"
fi

log_info "Comparison against targets:"
log_info "  - Single-stream throughput: target ≥900 Mbps"
log_info "  - Latency (P95): target ≤1ms"
log_info "  - Interface errors: target = 0"
