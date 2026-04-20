#!/usr/bin/env bash
# @file        scripts/ci/check-do-not-use-config-surfaces.sh
# @module      ci/governance
# @description Enforce pointer-only retirement for do-not-use config surfaces and block active-path references.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

require_pointer_stub() {
  local relative_path="$1"
  local required_pointer="$2"
  local path="$REPO_ROOT/$relative_path"

  require_file "$path"

  if ! grep -q '^# .*pointer-only stub\.$' "$path"; then
    log_error "Missing pointer-only stub marker in $relative_path"
    exit 1
  fi

  if ! grep -qF "$required_pointer" "$path"; then
    log_error "Missing required canonical pointer '$required_pointer' in $relative_path"
    exit 1
  fi

  local line_count
  line_count="$(wc -l < "$path")"
  if [[ "$line_count" -gt 8 ]]; then
    log_error "Retired surface exceeds pointer-only size budget in $relative_path (lines=$line_count)"
    exit 1
  fi
}

require_no_reference() {
  local pattern="$1"
  shift

  local scan_targets=("$@")
  local result_file
  result_file="$(mktemp)"

  if grep -RInE "$pattern" "${scan_targets[@]}" \
    --exclude='check-do-not-use-config-surfaces.sh' \
    --exclude='do-not-use-config-surfaces-guard.yml' \
    --exclude='check-compose-hardening-guard.sh' \
    --exclude='enforce-global-dedup.sh' \
    --exclude-dir='archives' \
    --exclude-dir='_archive' >"$result_file" 2>/dev/null; then
    log_error "Unexpected active-path references detected for pattern: $pattern"
    cat "$result_file" >&2 || true
    rm -f "$result_file"
    exit 1
  fi

  rm -f "$result_file"
}

require_pointer_stub "scripts/docker-compose.yml" "Canonical file: /docker-compose.yml"
require_pointer_stub "config/systemd/terminal-output-optimizer.service" "config/systemd/latency-monitor.service"
require_pointer_stub "docs/status/AUTONOMOUS-OPEN-ISSUE-STATUS-2026-04-18.md" "config/issues/agent-execution-manifest.json"

require_no_reference 'terminal-output-optimizer\.service' \
  "$REPO_ROOT/Makefile" "$REPO_ROOT/scripts" "$REPO_ROOT/docs" "$REPO_ROOT/.github" "$REPO_ROOT/config"

require_no_reference 'AUTONOMOUS-OPEN-ISSUE-STATUS-2026-04-18\.md' \
  "$REPO_ROOT/Makefile" "$REPO_ROOT/scripts" "$REPO_ROOT/docs" "$REPO_ROOT/.github" "$REPO_ROOT/config"

log_success "Do-not-use config surface guard passed"