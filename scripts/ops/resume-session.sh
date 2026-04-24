#!/usr/bin/env bash
################################################################################
# @file        scripts/ops/resume-session.sh
# @module      ops/session-management
# @description Resume a hibernated IDE session from its state snapshot
# @owner       infrastructure
# @status      active
#
# USAGE
#   scripts/ops/resume-session.sh <session_id> <container_name> <port>
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

require_command "docker" "Docker is required for resume"

################################################################################
# MAIN SCRIPT LOGIC
################################################################################

main() {
    local session_id="${1:-}"
    local container_name="${2:-}"
    local port="${3:-}"

    if [[ -z "$session_id" || -z "$container_name" || -z "$port" ]]; then
        log_error "Usage: $SCRIPT_NAME <session_id> <container_name> <port>"
        return 2
    fi

    log_info "Resuming session ${session_id} on port ${port}"

    local snapshot_tag="kc-hibernate-${session_id}"

    # 1. Start a new container from the snapshot image
    log_info "Starting container from snapshot ${snapshot_tag}"
    
    # Simple run command for simulation; in production, this would use the full 
    # kc-ide service compose parameters
    if ! docker run -d --name "${container_name}" -p "${port}:8443" "${snapshot_tag}"; then
        log_error "Failed to start container for ${session_id}"
        return 1
    fi

    log_info "Session ${session_id} successfully resumed"
    return 0
}

main "$@"
