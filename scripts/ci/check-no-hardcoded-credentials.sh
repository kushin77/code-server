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

PATTERN='password=secret|replication_user_pwd|admin123|changeme-enterprise-pwd|changeme-sudo-pwd|CODE_SERVER_PASSWORD=\$\{CODE_SERVER_PASSWORD:-change-me\}'

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
