#!/usr/bin/env bash
# @file        scripts/monitor-disk-space.sh
# @module      monitoring/infrastructure
# @description Emit disk space metrics to Prometheus textfile collector format
# @owner       platform
# @status      active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

METRICS_DIR="${METRICS_DIR:-/var/lib/node_exporter/textfile_collector}"
METRICS_FILE="${METRICS_DIR}/disk_space.prom"

# Create metrics directory if it doesn't exist (with fallback to /tmp)
if [[ ! -d "$METRICS_DIR" ]]; then
  mkdir -p "$METRICS_DIR" 2>/dev/null || {
    METRICS_DIR="/tmp"
    METRICS_FILE="${METRICS_DIR}/.disk_space.prom"
  }
fi

# Temporary file for atomic write
TEMP_FILE="${METRICS_FILE}.tmp"

# Function to emit metrics
emit_metrics() {
  {
    # Header
    echo "# HELP disk_usage_bytes Disk usage in bytes"
    echo "# TYPE disk_usage_bytes gauge"
    echo "# HELP disk_available_bytes Available disk space in bytes"
    echo "# TYPE disk_available_bytes gauge"
    echo "# HELP disk_usage_percent Disk usage percentage (0-100)"
    echo "# TYPE disk_usage_percent gauge"

    # Get disk stats for root and /home
    df -B1 / /home 2>/dev/null | tail -n +2 | while read -r filesystem size used available percent mountpoint; do
      size_num="${size%B}"
      used_num="${used%B}"
      avail_num="${available%B}"
      percent_num="${percent%\%}"

      # Sanitize mountpoint for label
      mp_label="${mountpoint//\//root}"
      [[ "$mp_label" == "root" ]] && mp_label="root_fs"
      [[ "$mp_label" == "home" ]] && mp_label="home_fs"

      echo "disk_usage_bytes{mountpoint=\"${mountpoint}\",device=\"${filesystem}\"} ${used_num}"
      echo "disk_available_bytes{mountpoint=\"${mountpoint}\",device=\"${filesystem}\"} ${avail_num}"
      echo "disk_usage_percent{mountpoint=\"${mountpoint}\",device=\"${filesystem}\"} ${percent_num}"
    done

    # Timestamp
    echo "# HELP disk_metrics_timestamp_seconds Timestamp of last metric collection"
    echo "# TYPE disk_metrics_timestamp_seconds gauge"
    echo "disk_metrics_timestamp_seconds $(date +%s)"

  } > "$TEMP_FILE"

  # Atomic move
  mv "$TEMP_FILE" "$METRICS_FILE"
  echo "Metrics written to: $METRICS_FILE" >&2
}

# Main
emit_metrics

# Also print to stdout for verification
echo ""
echo "=== DISK SPACE METRICS ==="
tail -n +6 "$METRICS_FILE" | head -15
echo "..."
