#!/usr/bin/env bash
# @file        scripts/ci/validate-monorepo-target.sh
# @module      ci/monorepo
# @description Validates monorepo architecture contract and component inventory
#              for issue #669 execution readiness.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARCH_FILE="$ROOT_DIR/config/monorepo/target-architecture.yml"
INV_FILE="$ROOT_DIR/config/monorepo/component-inventory.yml"

require_file "$ARCH_FILE" "target architecture file is required"
require_file "$INV_FILE" "component inventory file is required"

check_contains() {
    local file="$1"
    local token="$2"
    if ! grep -Fq "$token" "$file"; then
        log_error "Missing token '$token' in $file"
        return 1
    fi
}

log_info "Validating monorepo target architecture contract"
check_contains "$ARCH_FILE" "owner_map:"
check_contains "$ARCH_FILE" "dependency_direction_rules:"
check_contains "$ARCH_FILE" "migration_slices:"
check_contains "$ARCH_FILE" "risk:"

log_info "Validating component inventory classification"
check_contains "$INV_FILE" "classification:"
check_contains "$INV_FILE" "apps:"
check_contains "$INV_FILE" "packages:"
check_contains "$INV_FILE" "infra:"
check_contains "$INV_FILE" "docs:"

log_info "Monorepo target validation passed"
