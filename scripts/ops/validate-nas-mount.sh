#!/usr/bin/env bash
# @file        scripts/ops/validate-nas-mount.sh
# @module      ops/infrastructure
# @description Validates NAS connectivity and export availability for production replicas
# @owner       akushnir
# @status      stable
#
# Implementation of Phase 3 NAS Mount Handling:
# - Pings NAS host (192.168.168.56)
# - Validates NFS/SMB export visibility
# - Provides fail-fast signals for deployment orchestration
#
# Usage: bash scripts/ops/validate-nas-mount.sh [--host IP] [--export PATH] [--strict]
#

set -euo pipefail

# Initialize repository context
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Initialize repository context
init_repo

# Default configuration
NAS_HOST="${NAS_HOST:-192.168.168.56}"
NAS_EXPORT="${NAS_EXPORT:-/export/appsmith}"
STRICT_MODE=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      NAS_HOST="$2"
      shift 2
      ;;
    --export)
      NAS_EXPORT="$2"
      shift 2
      ;;
    --strict)
      STRICT_MODE=1
      shift
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

log_info "Starting NAS validation for $NAS_HOST..."

# 1. Connectivity Check (Ping)
log_debug "Pinging NAS host: $NAS_HOST"
if ! ping -c 1 -W 2 "$NAS_HOST" > /dev/null 2>&1; then
    if [[ "$STRICT_MODE" == "1" ]]; then
        log_fatal "NAS host $NAS_HOST is unreachable. Strict mode enabled, aborting."
    else
        log_warn "NAS host $NAS_HOST is unreachable. Deployments using NAS mounts will fail."
        exit 1
    fi
fi
log_info "✅ NAS host $NAS_HOST is reachable"

# 2. Export Validation (if showmount is available)
if command -v showmount > /dev/null 2>&1; then
    log_debug "Checking exports on $NAS_HOST"
    if ! showmount -e "$NAS_HOST" 2>/dev/null | grep -q "$NAS_EXPORT"; then
        log_warn "Export $NAS_EXPORT not found on $NAS_HOST"
        [[ "$STRICT_MODE" == "1" ]] && log_fatal "Required export missing in strict mode."
        exit 1
    fi
    log_info "✅ NAS export $NAS_EXPORT is available"
else
    log_warn "showmount not found, skipping deep export validation"
fi

log_info "SUCCESS: NAS validation passed for $NAS_HOST"
exit 0
