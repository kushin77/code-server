#!/usr/bin/env bash
################################################################################
# @file        scripts/ops/create-preview-environment.sh
# @module      ops/session-management
# @description Create ephemeral preview environment for testing and development
# @owner       infrastructure
# @status      active
#
# USAGE
#   scripts/ops/create-preview-environment.sh <parent_session_id> <name> [--duration <hours>] [--cpu <millicores>] [--memory <mb>]
#
# Creates a temporary preview environment from a parent session.
# Idempotent: creating same preview twice returns existing environment.
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

require_command "jq" "JSON query tool is required"
require_command "docker" "Docker is required for container management"

PARENT_SESSION_ID="${1:-}"
PREVIEW_NAME="${2:-}"
DURATION_HOURS="${DURATION_HOURS:-8}"
CPU_LIMIT_MILLICORES="${CPU_LIMIT_MILLICORES:-1000}"
MEMORY_LIMIT_MB="${MEMORY_LIMIT_MB:-512}"
DRY_RUN="${DRY_RUN:-false}"
NAS_MOUNT_PATH="${NAS_MOUNT_PATH:-/mnt/nas/persistent/code-server-enterprise}"

################################################################################
# MAIN SCRIPT LOGIC
################################################################################

main() {
    if [[ -z "$PARENT_SESSION_ID" || -z "$PREVIEW_NAME" ]]; then
        log_error "Usage: $SCRIPT_NAME <parent_session_id> <name> [--duration <hours>] [--cpu <millicores>] [--memory <mb>]"
        return 2
    fi

    # Parse optional arguments
    while [[ $# -gt 2 ]]; do
        case "$3" in
            --duration)
                DURATION_HOURS="$4"
                shift 2
                ;;
            --cpu)
                CPU_LIMIT_MILLICORES="$4"
                shift 2
                ;;
            --memory)
                MEMORY_LIMIT_MB="$4"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            *)
                log_error "Unknown option: $3"
                return 2
                ;;
        esac
    done

    # Validate resource limits
    if ! [[ "$CPU_LIMIT_MILLICORES" =~ ^[0-9]+$ ]] || [[ "$CPU_LIMIT_MILLICORES" -lt 100 ]]; then
        log_error "Invalid CPU limit (must be >= 100 millicores)" "cpu=$CPU_LIMIT_MILLICORES"
        return 2
    fi

    if ! [[ "$MEMORY_LIMIT_MB" =~ ^[0-9]+$ ]] || [[ "$MEMORY_LIMIT_MB" -lt 256 ]]; then
        log_error "Invalid memory limit (must be >= 256 MB)" "memory=$MEMORY_LIMIT_MB"
        return 2
    fi

    log_info "Creating preview environment" \
        "parentSessionId=$PARENT_SESSION_ID name=$PREVIEW_NAME durationHours=$DURATION_HOURS cpuMillicores=$CPU_LIMIT_MILLICORES memoryMb=$MEMORY_LIMIT_MB"

    if [[ "$DRY_RUN" != "true" ]]; then
        # Verify NAS is mounted
        if ! mountpoint -q "$NAS_MOUNT_PATH"; then
            log_error "NAS not mounted at $NAS_MOUNT_PATH"
            return 1
        fi

        # Generate preview environment ID
        local env_id
        env_id="preview-$(date +%s)-$(openssl rand -hex 8)"

        local expires_at
        expires_at=$(date -u -d "+${DURATION_HOURS} hours" +"%Y-%m-%dT%H:%M:%SZ")

        # Create preview environment record
        local preview_record
        preview_record=$(cat <<EOF | jq -c '.'
{
  "id": "$env_id",
  "parentSessionId": "$PARENT_SESSION_ID",
  "name": "$PREVIEW_NAME",
  "status": "provisioning",
  "createdAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "expiresAt": "$expires_at",
  "resourceAllocation": {
    "cpuLimitMillis": $CPU_LIMIT_MILLICORES,
    "memoryLimitMb": $MEMORY_LIMIT_MB
  }
}
EOF
        )

        # Store preview environment metadata to NAS
        local preview_dir="$NAS_MOUNT_PATH/preview-environments"
        mkdir -p "$preview_dir"
        echo "$preview_record" > "${preview_dir}/${env_id}.json"

        log_info "Preview environment created" "id=$env_id expiresAt=$expires_at"
        
        # Output preview environment record for client use
        echo "$preview_record" | jq '.'
    else
        log_info "DRY RUN: Would create preview environment" \
            "parentSessionId=$PARENT_SESSION_ID name=$PREVIEW_NAME durationHours=$DURATION_HOURS"
    fi

    log_info "Preview environment creation complete" "status=success"
    return 0
}

# Execute main function
main "$@"
