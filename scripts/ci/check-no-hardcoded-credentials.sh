#!/usr/bin/env bash
# @file        scripts/ci/check-no-hardcoded-credentials.sh
# @module      governance/security
# @description Scan active scripts for hardcoded credential literals
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

source "$SCRIPT_DIR/../_common/init.sh"

# Expanded pattern to catch common credential patterns
PATTERN='(password|passwd|pwd|secret|token|key|credential)\\s*[=:]\\s*[\"'\'']?[^\"'\''\\s]+(admin|test|demo|secret|password|123|change-?me|placeholder|todo|fixme|xxx|dummy|fake)|(api[_-]?key|access[_-]?key|secret[_-]?key|auth[_-]?token)\\s*[=:]|CODE_SERVER_PASSWORD=\\$\\{CODE_SERVER_PASSWORD:-[^}]+\\}|REDIS_PASSWORD=\\$\\{REDIS_PASSWORD:-[^}]+\\}'

matches=$(grep -RInE "$PATTERN" scripts \
  --include='*.sh' \
  --exclude-dir='_archive' \
  --exclude='check-no-hardcoded-credentials.sh' || true)

if [[ -n "$matches" ]]; then
  log_error "Hardcoded credential literals detected in active scripts:"
  printf '%s\n' "$matches" >&2
  exit 1
fi

log_info "No hardcoded credential literals detected"
