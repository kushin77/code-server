#!/usr/bin/env bash
# @file        scripts/ci/check-error-handling-consistency.sh
# @module      ci/scripts
# @description Verify active shell scripts use canonical error-handling baseline (set -euo pipefail + _common init)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

STRICT_MODE="${STRICT_MODE:-0}"

for arg in "$@"; do
  case "$arg" in
    --strict) STRICT_MODE=1 ;;
  esac
done

fail=0

mapfile -t scripts < <(
  git ls-files \
    'scripts/ci/*.sh' \
    'scripts/security/*.sh' \
    'scripts/operations/redeploy/**/*.sh' \
    'scripts/validate-config-ssot.sh' \
    'scripts/apply-governance.sh' \
    'scripts/mandatory-redeploy.sh' \
    | grep -v 'scripts/_archive/' \
    | grep -v 'node_modules/' || true
)

for script in "${scripts[@]}"; do
  [[ ! -f "$script" ]] && continue

  if ! grep -qE '^set -euo pipefail' "$script"; then
    log_warn "Missing strict mode in $script"
    fail=1
  fi

  if [[ "$script" != scripts/_common/* ]]; then
    if ! grep -qE 'source[[:space:]]+"\$SCRIPT_DIR/(\.\./)*_common/init\.sh"' "$script"; then
      log_warn "Missing _common/init.sh sourcing in $script"
      fail=1
    fi
  fi
done

if [[ "$fail" -ne 0 ]]; then
  if [[ "$STRICT_MODE" == "1" ]]; then
    log_fatal "Error-handling consistency check failed (strict mode)"
  fi
  log_warn "Error-handling consistency warnings detected (advisory mode)"
  exit 0
fi

log_info "Error-handling consistency check passed"
