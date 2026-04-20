#!/usr/bin/env bash
# @file        scripts/ops/benchmark-nfs-performance.sh
# @module      infrastructure/performance
# @description Baseline NFS read/write throughput and latency performance

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Configuration
NAS_HOST="${NAS_HOST:-nas.internal}"
NAS_MOUNT_PATH="${NAS_MOUNT_PATH:-/mnt/nfs}"
TEST_FILE_SIZE="100M"  # 100MB test file
NUM_SMALL_FILES=1000
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
log_info "Running NFS performance baseline benchmark..."

mkdir -p "$OUTPUT_DIR"
: > "$OUTPUT_DIR/nfs-baseline.json"

# Check if NAS mount point exists
if [[ ! -d "$NAS_MOUNT_PATH" ]]; then
  log_warn "NAS mount point $NAS_MOUNT_PATH does not exist"
  log_info "To mount NAS:"
  log_info "  mkdir -p $NAS_MOUNT_PATH"
  log_info "  mount -t nfs -o vers=4.1,rsize=131072,wsize=131072 $NAS_HOST:/export $NAS_MOUNT_PATH"
  exit 1
fi

# Verify it's actually mounted
if ! mountpoint -q "$NAS_MOUNT_PATH"; then
  log_error "$NAS_MOUNT_PATH is not mounted"
  exit 1
fi

log_info "NFS mount verified: $NAS_MOUNT_PATH"

# Create temp directory for test files
TEST_DIR="$NAS_MOUNT_PATH/.benchmark-$$"
mkdir -p "$TEST_DIR"
trap "rm -rf '$TEST_DIR'" EXIT

# ─────────────────────────────────────────────────────────────────────────────
# Single-file read throughput
# ─────────────────────────────────────────────────────────────────────────────
log_info "Testing single-file read throughput (${TEST_FILE_SIZE})..."

# Create test file
test_file="$TEST_DIR/read-test.bin"
dd if=/dev/zero of="$test_file" bs=1M count=100 status=none 2>&1 || true

# Warm up filesystem cache (drop caches)
if [[ -f /proc/sys/vm/drop_caches ]]; then
  sync
  echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null 2>&1 || true
fi

# Measure read throughput
start_time=$(date +%s.%N)
dd if="$test_file" of=/dev/null bs=1M status=none 2>&1 || true
end_time=$(date +%s.%N)

elapsed=$(echo "$end_time - $start_time" | bc)
throughput_mbs=$(echo "scale=2; 100 / $elapsed" | bc)

json_result "nfs_read_throughput" "$throughput_mbs" "MBps" >> "$OUTPUT_DIR/nfs-baseline.json"
log_info "Read throughput: ${throughput_mbs} MBps (target: ≥800 Mbps)"

# ─────────────────────────────────────────────────────────────────────────────
# Single-file write throughput
# ─────────────────────────────────────────────────────────────────────────────
log_info "Testing single-file write throughput..."

write_file="$TEST_DIR/write-test.bin"

start_time=$(date +%s.%N)
dd if=/dev/zero of="$write_file" bs=1M count=100 status=none 2>&1 || true
sync
end_time=$(date +%s.%N)

elapsed=$(echo "$end_time - $start_time" | bc)
write_throughput_mbs=$(echo "scale=2; 100 / $elapsed" | bc)

json_result "nfs_write_throughput" "$write_throughput_mbs" "MBps" >> "$OUTPUT_DIR/nfs-baseline.json"
log_info "Write throughput: ${write_throughput_mbs} MBps (target: ≥700 Mbps)"

# ─────────────────────────────────────────────────────────────────────────────
# Small-file latency (touch + stat)
# ─────────────────────────────────────────────────────────────────────────────
log_info "Testing small-file create latency (${NUM_SMALL_FILES} files)..."

small_file_dir="$TEST_DIR/small-files"
mkdir -p "$small_file_dir"

start_time=$(date +%s.%N)
for i in $(seq 1 "$NUM_SMALL_FILES"); do
  touch "$small_file_dir/file-$i.txt"
done
end_time=$(date +%s.%N)

elapsed=$(echo "$end_time - $start_time" | bc)
create_latency_ms=$(echo "scale=2; ($elapsed * 1000) / $NUM_SMALL_FILES" | bc)

json_result "nfs_small_file_create_latency" "$create_latency_ms" "ms" >> "$OUTPUT_DIR/nfs-baseline.json"
log_info "Small-file create latency: ${create_latency_ms} ms/file (target: ≤10ms)"

# ─────────────────────────────────────────────────────────────────────────────
# Small-file read latency (stat)
# ─────────────────────────────────────────────────────────────────────────────
log_info "Testing small-file read latency (stat)..."

start_time=$(date +%s.%N)
for f in "$small_file_dir"/file-*.txt; do
  stat "$f" > /dev/null
done
end_time=$(date +%s.%N)

elapsed=$(echo "$end_time - $start_time" | bc)
read_latency_ms=$(echo "scale=2; ($elapsed * 1000) / $NUM_SMALL_FILES" | bc)

json_result "nfs_small_file_read_latency" "$read_latency_ms" "ms" >> "$OUTPUT_DIR/nfs-baseline.json"
log_info "Small-file read latency: ${read_latency_ms} ms/file (target: ≤5ms)"

# ─────────────────────────────────────────────────────────────────────────────
# Directory listing latency
# ─────────────────────────────────────────────────────────────────────────────
log_info "Testing directory listing latency (ls -l)..."

start_time=$(date +%s.%N)
ls -l "$small_file_dir" > /dev/null
end_time=$(date +%s.%N)

elapsed=$(echo "$end_time - $start_time" | bc)
dir_list_ms=$(echo "scale=2; $elapsed * 1000" | bc)

json_result "nfs_directory_listing_latency" "$dir_list_ms" "ms" >> "$OUTPUT_DIR/nfs-baseline.json"
log_info "Directory listing (${NUM_SMALL_FILES} files): ${dir_list_ms} ms (target: ≤500ms)"

# ─────────────────────────────────────────────────────────────────────────────
# NFS mount info and tuning parameters
# ─────────────────────────────────────────────────────────────────────────────
log_info "Capturing NFS mount configuration..."

mount_info=$(mount | grep "$NAS_MOUNT_PATH" || echo "unknown")
log_info "Mount info: $mount_info"

# Check for stale NFS handles in system logs
stale_count=$(dmesg | grep -i "stale" | wc -l || echo "0")
json_result "nfs_stale_handles_recent" "$stale_count" "count" >> "$OUTPUT_DIR/nfs-baseline.json"
log_info "Recent stale NFS handles: $stale_count (target: 0)"

# ─────────────────────────────────────────────────────────────────────────────
# Summary and recommendations
# ─────────────────────────────────────────────────────────────────────────────
log_info "✅ NFS performance baseline benchmark complete"
log_info "Results saved to: $OUTPUT_DIR/nfs-baseline.json"

if command -v jq &> /dev/null; then
  jq -s . "$OUTPUT_DIR/nfs-baseline.json" > "${OUTPUT_DIR}/nfs-baseline.formatted.json" 2>/dev/null || true
  log_info "Formatted results: ${OUTPUT_DIR}/nfs-baseline.formatted.json"
fi

log_info ""
log_info "Comparison against targets:"
log_info "  - Read throughput: target ≥800 MBps (${throughput_mbs} MBps measured)"
log_info "  - Write throughput: target ≥700 MBps (${write_throughput_mbs} MBps measured)"
log_info "  - Small-file read latency: target ≤5ms (${read_latency_ms} ms measured)"
log_info "  - Small-file create latency: target ≤10ms (${create_latency_ms} ms measured)"
log_info "  - Directory listing: target ≤500ms (${dir_list_ms} ms measured)"
log_info ""
log_info "📝 Recommended NFS tuning (apply in /etc/fstab or docker-compose.yml):"
log_info "   -o vers=4.1,rsize=131072,wsize=131072,hard,timeo=600,retrans=2"
