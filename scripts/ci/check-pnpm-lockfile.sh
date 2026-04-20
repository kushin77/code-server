#!/usr/bin/env bash
# @file        scripts/ci/check-pnpm-lockfile.sh
# @module      ci/monorepo
# @description Validates pnpm workspace bootstrap, catalog policy, and lockfile
#              immutability for issue #670.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

require_file "$ROOT_DIR/package.json" "root package.json is required"
require_file "$ROOT_DIR/pnpm-workspace.yaml" "pnpm workspace file is required"
require_file "$ROOT_DIR/pnpm-lock.yaml" "pnpm lockfile is required"

NODE_CMD=""

if command -v node >/dev/null 2>&1; then
    NODE_CMD="node"
elif command -v node.exe >/dev/null 2>&1; then
    NODE_CMD="node.exe"
else
    log_fatal "node or node.exe is required for pnpm workspace validation"
fi

PNPM_CMD=""

if command -v corepack >/dev/null 2>&1; then
    corepack enable >/dev/null 2>&1 || true
fi

if command -v pnpm >/dev/null 2>&1; then
    PNPM_CMD="pnpm"
elif command -v corepack >/dev/null 2>&1; then
    PNPM_CMD="corepack pnpm"
elif command -v npx >/dev/null 2>&1; then
    PNPM_CMD="npx pnpm@9.15.4"
else
    log_fatal "pnpm or corepack is required for lockfile governance validation"
fi

log_info "Validating pnpm lockfile immutability"
cd "$ROOT_DIR"

before_hash="$(sha256sum pnpm-lock.yaml | awk '{print $1}')"
${PNPM_CMD} install --frozen-lockfile --ignore-scripts >/dev/null
after_hash="$(sha256sum pnpm-lock.yaml | awk '{print $1}')"

if [[ "$before_hash" != "$after_hash" ]]; then
    log_error "pnpm-lock.yaml changed during frozen install"
    exit 1
fi

bash "$SCRIPT_DIR/validate-pnpm-workspace-catalog.sh"

log_info "pnpm workspace lockfile validation passed"