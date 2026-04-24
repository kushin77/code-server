#!/usr/bin/env bash
# @file        scripts/ci/run-public-edge-burst.sh
# @module      ci/e2e
# @description Run a lightweight burst test against the public edge and auth redirect path.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

require_command curl
require_command awk

TEST_BASE_URL="${TEST_BASE_URL:-https://ide.kushnir.cloud}"
BURST_REQUESTS="${BURST_REQUESTS:-15}"
BURST_PARALLEL="${BURST_PARALLEL:-5}"
BURST_TIMEOUT_SECONDS="${BURST_TIMEOUT_SECONDS:-10}"
BURST_PATHS="${BURST_PATHS:-/,/oauth2/start?rd=/}"
BURST_ALLOWED_STATUSES="${BURST_ALLOWED_STATUSES:-200,301,302,303,307,308,401,403}"
BURST_EVIDENCE_FILE="${BURST_EVIDENCE_FILE:-}"

if [[ -n "$BURST_EVIDENCE_FILE" ]]; then
  mkdir -p "$(dirname "$BURST_EVIDENCE_FILE")"
fi

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

is_allowed_status() {
  local status="$1"
  local allowed_status
  local -a allowed_statuses

  IFS=',' read -r -a allowed_statuses <<< "$BURST_ALLOWED_STATUSES"
  for allowed_status in "${allowed_statuses[@]}"; do
    if [[ "$status" == "$allowed_status" ]]; then
      return 0
    fi
  done

  return 1
}

burst_path() {
  local path="$1"
  local safe_name="$2"
  local path_dir="$temp_dir/$safe_name"
  local request_index

  mkdir -p "$path_dir"

  for request_index in $(seq 1 "$BURST_REQUESTS"); do
    (
      local response
      response="$(curl -skS --max-time "$BURST_TIMEOUT_SECONDS" -o /dev/null -w '%{http_code} %{time_total}' "$TEST_BASE_URL$path")"
      printf '%s\n' "$response" > "$path_dir/$request_index"
    ) &

    if (( request_index % BURST_PARALLEL == 0 )); then
      wait
    fi
  done

  wait

  cat "$path_dir"/* > "$path_dir/results.txt"
}

summarize_path() {
  local path="$1"
  local safe_name="$2"
  local results_file="$temp_dir/$safe_name/results.txt"
  local summary

  summary="$(awk '
    {
      status[$1]++;
      total++;
      sum += $2;
      if (min == "" || $2 < min) min = $2;
      if ($2 > max) max = $2;
    }
    END {
      for (s in status) {
        printf("status %s=%d ", s, status[s]);
      }
      printf("total=%d avg=%.3f min=%.3f max=%.3f", total, sum / total, min, max);
    }
  ' "$results_file")"

  log_info "Burst summary for $path: $summary"

  if [[ -n "$BURST_EVIDENCE_FILE" ]]; then
    {
      printf 'Path: %s\n' "$path"
      printf '%s\n' "$summary"
      printf '\n'
    } >> "$BURST_EVIDENCE_FILE"
  fi

  while IFS= read -r line; do
    local status
    local time_total

    status="${line%% *}"
    time_total="${line#* }"

    if ! is_allowed_status "$status"; then
      log_error "Unexpected status for $path: $status (time ${time_total}s)"
      return 1
    fi
  done < "$results_file"
}

if [[ -n "$BURST_EVIDENCE_FILE" ]]; then
  : > "$BURST_EVIDENCE_FILE"
  {
    printf '## Public edge burst evidence\n\n'
    printf 'Base URL: %s\n' "$TEST_BASE_URL"
    printf 'Requests per path: %s\n' "$BURST_REQUESTS"
    printf 'Parallelism: %s\n' "$BURST_PARALLEL"
    printf 'Allowed statuses: %s\n\n' "$BURST_ALLOWED_STATUSES"
  } >> "$BURST_EVIDENCE_FILE"
fi

log_info "Running public edge burst against $TEST_BASE_URL"

IFS=',' read -r -a burst_paths <<< "$BURST_PATHS"
for path in "${burst_paths[@]}"; do
  safe_name="${path//\//_}"
  safe_name="${safe_name//\?/__}"
  safe_name="${safe_name//&/__}"
  safe_name="${safe_name//=/_}"
  burst_path "$path" "$safe_name"
  summarize_path "$path" "$safe_name"
done

log_info "Public edge burst completed successfully"