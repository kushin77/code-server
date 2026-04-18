#!/usr/bin/env bash
# @file        scripts/ci/prepare-playwright-storage-state.sh
# @module      testing/ci
# @description Prepare base64 secret payload from a local Playwright storage state JSON file.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/_common/init.sh
source "$ROOT_DIR/scripts/_common/init.sh"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ci/prepare-playwright-storage-state.sh /path/to/storage-state.json

Output:
  Prints a single-line base64 payload suitable for GitHub secret PLAYWRIGHT_STORAGE_STATE_B64.
EOF
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    return 0
  fi

  local state_file="${1:-}"
  if [[ -z "$state_file" ]]; then
    log_fatal "Missing required argument: storage state file path"
  fi

  if [[ ! -f "$state_file" ]]; then
    log_fatal "Storage state file not found: $state_file"
  fi

  if [[ ! -s "$state_file" ]]; then
    log_fatal "Storage state file is empty: $state_file"
  fi

  log_info "Encoding Playwright storage state to single-line base64"
  base64 -w 0 "$state_file"
  printf '\n'
  log_info "Use this value for GitHub secret PLAYWRIGHT_STORAGE_STATE_B64"
}

main "$@"