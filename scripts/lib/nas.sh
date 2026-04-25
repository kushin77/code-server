#!/bin/bash
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# Purpose: Provides health monitoring and exponential backoff retry helpers for NAS operations
# Author: Infrastructure Team
# Date: 2026-04-25
# Related issues: #1536

# All configuration via environment variables with sensible defaults.
# No hardcoded paths, thresholds, or credentials.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly NAS_MOUNT_PATH="${NAS_MOUNT_PATH:-/mnt/nas}"
readonly NAS_LATENCY_THRESHOLD_MS="${NAS_LATENCY_THRESHOLD_MS:-50}"
readonly NAS_MAX_RETRIES="${NAS_MAX_RETRIES:-5}"
source "${SCRIPT_DIR}/../_common/hosts.sh"

: "${NAS_MOUNT_PATH:=/mnt/nas}"
: "${NAS_LATENCY_THRESHOLD_MS:=50}"
: "${NAS_RETRY_ATTEMPTS:=5}"
: "${NAS_RETRY_BASE_DELAY_SECONDS:=2}"

nas_log() {
  printf '[nas] %s\n' "$*" >&2
}

nas_mount_latency_ms() {
  local mount_path="${1:-${NAS_MOUNT_PATH}}"
  local start_ms end_ms

  start_ms=$(date +%s%3N)
  stat -f "${mount_path}" >/dev/null 2>&1 || return 1
  end_ms=$(date +%s%3N)

  echo "$((end_ms - start_ms))"
}

check_nas_health() {
  local mount_path="${1:-${NAS_MOUNT_PATH}}"
  local threshold_ms="${2:-${NAS_LATENCY_THRESHOLD_MS}}"
  local latency_ms

  if ! latency_ms=$(nas_mount_latency_ms "${mount_path}"); then
    nas_log "NAS mount not reachable: ${mount_path}"
    return 1
  fi

  if (( latency_ms > threshold_ms )); then
    nas_log "NAS mount latency ${latency_ms}ms exceeds threshold ${threshold_ms}ms"
    return 1
  fi

  nas_log "NAS mount healthy: ${latency_ms}ms at ${mount_path}"
}

retry_with_backoff() {
  local attempts="${1:-${NAS_RETRY_ATTEMPTS}}"
  local base_delay="${2:-${NAS_RETRY_BASE_DELAY_SECONDS}}"
  shift 2 || true

  local attempt=1
  local delay_seconds

  until "$@"; do
    if (( attempt >= attempts )); then
      return 1
    fi

    delay_seconds=$((base_delay * 2 ** (attempt - 1)))
    nas_log "Attempt ${attempt} failed; retrying in ${delay_seconds}s"
    sleep "${delay_seconds}"
    attempt=$((attempt + 1))
  done
}

benchmark_nas_mount() {
  local mount_path="${1:-${NAS_MOUNT_PATH}}"

  nas_mount_latency_ms "${mount_path}"
}

export -f nas_log nas_mount_latency_ms check_nas_health retry_with_backoff benchmark_nas_mount
