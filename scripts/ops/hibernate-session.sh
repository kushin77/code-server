#!/usr/bin/env bash
################################################################################
# @file        scripts/ops/hibernate-session.sh
# @module      ops/session-management
# @description Hibernate an IDE session by snapshotting state and stopping container
# @owner       infrastructure
# @status      active
#
# USAGE
#   scripts/ops/hibernate-session.sh <session_id> <container_name>
#
################################################################################

set -euo pipefail

# Get directory of this script and source the canonical initialization module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

SCRIPT_NAME="$(basename "$0")"

################################################################################
# CONFIGURATION & VALIDATION
################################################################################

require_command "docker" "Docker is required for hibernation"

################################################################################
# MAIN SCRIPT LOGIC
################################################################################

main() {
    local session_id="${1:-}"
    local container_name="${2:-}"

    if [[ -z "$session_id" || -z "$container_name" ]]; then
        log_error "Usage: $SCRIPT_NAME <session_id> <container_name>"
        return 2
    fi

    log_info "Hibernating session ${session_id} (container: ${container_name})"

    # 1. Commit container state to image (idempotent snapshot)
    local snapshot_tag="kc-hibernate-${session_id}"
    log_info "Creating snapshot: ${snapshot_tag}"
    
    # We use -p to pause the container during commit for consistency
    if ! docker commit -p "${container_name}" "${snapshot_tag}"; then
        log_error "Failed to create snapshot for ${session_id}"
        return 1
    fi

    # 2. Stop and Remove container (freeing up CPU/RAM)
    log_info "Removing active container ${container_name}"
    docker stop "${container_name}" >/dev/null 2>&1 || true
    docker rm "${container_name}" >/dev/null 2>&1 || true

    log_info "Session ${session_id} successfully hibernated"
    return 0
}

main "$@"
