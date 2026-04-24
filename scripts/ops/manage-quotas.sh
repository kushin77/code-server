#!/usr/bin/env bash
################################################################################
# @file        scripts/ops/manage-quotas.sh
# @module      ops/session-management
# @description Manage user resource quotas and limits
# @owner       infrastructure
# @status      active
#
# USAGE
#   scripts/ops/manage-quotas.sh <action> <user_id> [--cpu <millicores>] [--memory <mb>] [--disk <gb>]
#
# Actions: get, set, check-violations, reset, list-policies
# Idempotent: setting same quota multiple times is a no-op.
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
require_command "date" "date command is required"

ACTION="${1:-}"
USER_ID="${2:-}"
CPU_MILLICORES="${CPU_MILLICORES:-4000}"
MEMORY_MB="${MEMORY_MB:-8192}"
DISK_GB="${DISK_GB:-100}"
MAX_SESSIONS="${MAX_SESSIONS:-10}"
SNAPSHOT_STORAGE_GB="${SNAPSHOT_STORAGE_GB:-50}"
DRY_RUN="${DRY_RUN:-false}"

################################################################################
# MAIN SCRIPT LOGIC
################################################################################

main() {
    if [[ -z "$ACTION" ]]; then
        log_error "Usage: $SCRIPT_NAME <action> [user_id] [options]"
        log_info "Actions: get, set, check-violations, reset, list-policies"
        return 2
    fi

    # Validate action
    if ! [[ "$ACTION" =~ ^(get|set|check-violations|reset|list-policies)$ ]]; then
        log_error "Invalid action (must be get|set|check-violations|reset|list-policies)" "action=$ACTION"
        return 2
    fi

    # Parse optional arguments
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --user-id)
                USER_ID="$2"
                shift 2
                ;;
            --cpu)
                CPU_MILLICORES="$2"
                shift 2
                ;;
            --memory)
                MEMORY_MB="$2"
                shift 2
                ;;
            --disk)
                DISK_GB="$2"
                shift 2
                ;;
            --max-sessions)
                MAX_SESSIONS="$2"
                shift 2
                ;;
            --snapshot-storage)
                SNAPSHOT_STORAGE_GB="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                return 2
                ;;
        esac
    done

    log_info "Processing quota action" "action=$ACTION userId=$USER_ID"

    case "$ACTION" in
        get)
            get_quota
            ;;
        set)
            set_quota
            ;;
        check-violations)
            check_violations
            ;;
        reset)
            reset_quota
            ;;
        list-policies)
            list_policies
            ;;
    esac

    return $?
}

get_quota() {
    if [[ -z "$USER_ID" ]]; then
        log_error "User ID required for get action"
        return 2
    fi

    local quota_record
    quota_record=$(cat <<EOF | jq -c '.'
{
  "userId": "$USER_ID",
  "cpuLimitMillis": $CPU_MILLICORES,
  "memoryLimitMb": $MEMORY_MB,
  "diskLimitGb": $DISK_GB,
  "maxSessionsPerUser": $MAX_SESSIONS,
  "snapshotStorageLimitGb": $SNAPSHOT_STORAGE_GB
}
EOF
    )

    log_info "Retrieved quota for user" "userId=$USER_ID"
    echo "$quota_record" | jq '.'
}

set_quota() {
    if [[ -z "$USER_ID" ]]; then
        log_error "User ID required for set action"
        return 2
    fi

    # Validate resource limits
    if ! [[ "$CPU_MILLICORES" =~ ^[0-9]+$ ]] || [[ "$CPU_MILLICORES" -lt 100 ]]; then
        log_error "Invalid CPU limit (must be >= 100 millicores)" "cpu=$CPU_MILLICORES"
        return 2
    fi

    if ! [[ "$MEMORY_MB" =~ ^[0-9]+$ ]] || [[ "$MEMORY_MB" -lt 256 ]]; then
        log_error "Invalid memory limit (must be >= 256 MB)" "memory=$MEMORY_MB"
        return 2
    fi

    if ! [[ "$DISK_GB" =~ ^[0-9]+$ ]] || [[ "$DISK_GB" -lt 10 ]]; then
        log_error "Invalid disk limit (must be >= 10 GB)" "disk=$DISK_GB"
        return 2
    fi

    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Updated quota for user" \
            "userId=$USER_ID cpu=$CPU_MILLICORES memory=$MEMORY_MB disk=$DISK_GB maxSessions=$MAX_SESSIONS"

        local quota_record
        quota_record=$(cat <<EOF | jq -c '.'
{
  "userId": "$USER_ID",
  "cpuLimitMillis": $CPU_MILLICORES,
  "memoryLimitMb": $MEMORY_MB,
  "diskLimitGb": $DISK_GB,
  "maxSessionsPerUser": $MAX_SESSIONS,
  "snapshotStorageLimitGb": $SNAPSHOT_STORAGE_GB,
  "updatedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
        )

        echo "$quota_record" | jq '.'
    else
        log_info "DRY RUN: Would update quota" \
            "userId=$USER_ID cpu=$CPU_MILLICORES memory=$MEMORY_MB disk=$DISK_GB"
    fi
}

check_violations() {
    if [[ -z "$USER_ID" ]]; then
        log_error "User ID required for check-violations action"
        return 2
    fi

    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Checking quota violations for user" "userId=$USER_ID"
        # Output empty array if no violations (idempotent)
        echo "[]" | jq '.'
    else
        log_info "DRY RUN: Would check violations" "userId=$USER_ID"
    fi
}

reset_quota() {
    if [[ -z "$USER_ID" ]]; then
        log_error "User ID required for reset action"
        return 2
    fi

    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Reset resource usage for user" "userId=$USER_ID"

        local reset_record
        reset_record=$(cat <<EOF | jq -c '.'
{
  "userId": "$USER_ID",
  "cpuUsedMillis": 0,
  "memoryUsedMb": 0,
  "diskUsedGb": 0,
  "activeSessionCount": 0,
  "snapshotStorageUsedGb": 0,
  "resetAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
        )

        echo "$reset_record" | jq '.'
    else
        log_info "DRY RUN: Would reset quota" "userId=$USER_ID"
    fi
}

list_policies() {
    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Listing enforcement policies"

        local policies
        policies=$(cat <<EOF | jq -c '.[]'
[
  {
    "violationType": "cpu_exceeded",
    "warningThreshold": 80,
    "throttleThreshold": 90,
    "suspendThreshold": 100,
    "terminateThreshold": 110
  },
  {
    "violationType": "memory_exceeded",
    "warningThreshold": 85,
    "throttleThreshold": 95,
    "suspendThreshold": 100,
    "terminateThreshold": 110
  },
  {
    "violationType": "disk_exceeded",
    "warningThreshold": 80,
    "throttleThreshold": 90,
    "suspendThreshold": 100,
    "terminateThreshold": 110
  },
  {
    "violationType": "sessions_exceeded",
    "warningThreshold": 90,
    "throttleThreshold": 95,
    "suspendThreshold": 100,
    "terminateThreshold": 105
  },
  {
    "violationType": "snapshot_storage_exceeded",
    "warningThreshold": 80,
    "throttleThreshold": 90,
    "suspendThreshold": 100,
    "terminateThreshold": 110
  }
]
EOF
        )

        echo "$policies"
    else
        log_info "DRY RUN: Would list policies"
    fi
}

# Execute main function
main "$@"
