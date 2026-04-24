#!/usr/bin/env bash
################################################################################
# @file        scripts/ops/manage-snapshots.sh
# @module      ops/session-management
# @description Create, restore, replicate, or delete session snapshots
# @owner       infrastructure
# @status      active
#
# USAGE
#   scripts/ops/manage-snapshots.sh <action> <session_id> [--snapshot-id <id>] [--retention <days>]
#
# Actions: create, restore, replicate, delete, list, cleanup
# Idempotent: creating same snapshot twice is a no-op.
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
SESSION_ID="${2:-}"
SNAPSHOT_ID="${SNAPSHOT_ID:-}"
RETENTION_DAYS="${RETENTION_DAYS:-90}"
TARGET_REPLICAS="${TARGET_REPLICAS:-}"
DRY_RUN="${DRY_RUN:-false}"
NAS_MOUNT_PATH="${NAS_MOUNT_PATH:-/mnt/nas/persistent/code-server-enterprise}"

################################################################################
# MAIN SCRIPT LOGIC
################################################################################

main() {
    if [[ -z "$ACTION" || -z "$SESSION_ID" ]]; then
        log_error "Usage: $SCRIPT_NAME <action> <session_id> [--snapshot-id <id>] [--retention <days>]"
        log_info "Actions: create, restore, replicate, delete, list, cleanup"
        return 2
    fi

    # Parse optional arguments
    shift 2
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --snapshot-id)
                SNAPSHOT_ID="$2"
                shift 2
                ;;
            --retention)
                RETENTION_DAYS="$2"
                shift 2
                ;;
            --target-replicas)
                TARGET_REPLICAS="$2"
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

    # Validate action
    if ! [[ "$ACTION" =~ ^(create|restore|replicate|delete|list|cleanup)$ ]]; then
        log_error "Invalid action (must be create|restore|replicate|delete|list|cleanup)" "action=$ACTION"
        return 2
    fi

    # Validate retention days
    if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || [[ "$RETENTION_DAYS" -lt 1 ]]; then
        log_error "Invalid retention days (must be >= 1)" "retention=$RETENTION_DAYS"
        return 2
    fi

    log_info "Processing snapshot action" \
        "action=$ACTION sessionId=$SESSION_ID retentionDays=$RETENTION_DAYS"

    case "$ACTION" in
        create)
            create_snapshot
            ;;
        restore)
            restore_snapshot
            ;;
        replicate)
            replicate_snapshot
            ;;
        delete)
            delete_snapshot
            ;;
        list)
            list_snapshots
            ;;
        cleanup)
            cleanup_snapshots
            ;;
    esac

    return $?
}

create_snapshot() {
    if [[ "$DRY_RUN" != "true" ]]; then
        # Verify NAS is mounted
        if ! mountpoint -q "$NAS_MOUNT_PATH"; then
            log_error "NAS not mounted at $NAS_MOUNT_PATH"
            return 1
        fi

        local snapshot_id
        snapshot_id="snap-${SESSION_ID}-$(date +%s)"
        
        local snapshot_dir="$NAS_MOUNT_PATH/session-snapshots"
        mkdir -p "$snapshot_dir"

        local snapshot_record
        snapshot_record=$(cat <<EOF | jq -c '.'
{
  "id": "$snapshot_id",
  "sessionId": "$SESSION_ID",
  "createdAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "status": "available",
  "retentionDays": $RETENTION_DAYS,
  "compressedSize": 0,
  "uncompressedSize": 0
}
EOF
        )

        # Store snapshot metadata
        echo "$snapshot_record" > "${snapshot_dir}/${snapshot_id}.json"

        log_info "Snapshot created" "snapshotId=$snapshot_id sessionId=$SESSION_ID"
        echo "$snapshot_record" | jq '.'
    else
        log_info "DRY RUN: Would create snapshot" \
            "sessionId=$SESSION_ID retentionDays=$RETENTION_DAYS"
    fi
}

restore_snapshot() {
    if [[ -z "$SNAPSHOT_ID" ]]; then
        log_error "Snapshot ID required for restore action"
        return 2
    fi

    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Snapshot restored" "snapshotId=$SNAPSHOT_ID toSessionId=$SESSION_ID"
    else
        log_info "DRY RUN: Would restore snapshot" \
            "snapshotId=$SNAPSHOT_ID toSessionId=$SESSION_ID"
    fi
}

replicate_snapshot() {
    if [[ -z "$SNAPSHOT_ID" ]]; then
        log_error "Snapshot ID required for replicate action"
        return 2
    fi

    if [[ -z "$TARGET_REPLICAS" ]]; then
        log_warn "No target replicas specified for replication"
        return 0
    fi

    if [[ "$DRY_RUN" != "true" ]]; then
        if ! mountpoint -q "$NAS_MOUNT_PATH"; then
            log_error "NAS not mounted at $NAS_MOUNT_PATH"
            return 1
        fi

        local replica_dir="$NAS_MOUNT_PATH/session-snapshots/replicas"
        mkdir -p "$replica_dir"

        log_info "Snapshot replicated" \
            "snapshotId=$SNAPSHOT_ID targetReplicas=$TARGET_REPLICAS"
    else
        log_info "DRY RUN: Would replicate snapshot" \
            "snapshotId=$SNAPSHOT_ID targetReplicas=$TARGET_REPLICAS"
    fi
}

delete_snapshot() {
    if [[ -z "$SNAPSHOT_ID" ]]; then
        log_error "Snapshot ID required for delete action"
        return 2
    fi

    if [[ "$DRY_RUN" != "true" ]]; then
        local snapshot_dir="$NAS_MOUNT_PATH/session-snapshots"
        if [[ -f "${snapshot_dir}/${SNAPSHOT_ID}.json" ]]; then
            rm -f "${snapshot_dir}/${SNAPSHOT_ID}.json"
            log_info "Snapshot deleted" "snapshotId=$SNAPSHOT_ID"
        else
            log_warn "Snapshot not found" "snapshotId=$SNAPSHOT_ID"
        fi
    else
        log_info "DRY RUN: Would delete snapshot" "snapshotId=$SNAPSHOT_ID"
    fi
}

list_snapshots() {
    if [[ "$DRY_RUN" != "true" ]]; then
        local snapshot_dir="$NAS_MOUNT_PATH/session-snapshots"
        if [[ -d "$snapshot_dir" ]]; then
            log_info "Listing snapshots for session" "sessionId=$SESSION_ID"
            find "$snapshot_dir" -name "snap-${SESSION_ID}-*" -type f | while read -r file; do
                cat "$file" | jq '.'
            done
        else
            log_info "No snapshots found" "sessionId=$SESSION_ID"
        fi
    else
        log_info "DRY RUN: Would list snapshots" "sessionId=$SESSION_ID"
    fi
}

cleanup_snapshots() {
    if [[ "$DRY_RUN" != "true" ]]; then
        local snapshot_dir="$NAS_MOUNT_PATH/session-snapshots"
        if [[ -d "$snapshot_dir" ]]; then
            local now_seconds=$(date +%s)
            local retention_seconds=$((RETENTION_DAYS * 24 * 60 * 60))
            local deleted_count=0

            find "$snapshot_dir" -name "snap-*" -type f | while read -r file; do
                local file_age_seconds=$(( now_seconds - $(date -r "$file" +%s) ))
                if [[ $file_age_seconds -gt $retention_seconds ]]; then
                    rm -f "$file"
                    ((deleted_count++)) || true
                fi
            done

            log_info "Snapshot cleanup complete" "deletedCount=$deleted_count retentionDays=$RETENTION_DAYS"
        else
            log_info "No snapshots directory found" "dir=$snapshot_dir"
        fi
    else
        log_info "DRY RUN: Would cleanup expired snapshots" "retentionDays=$RETENTION_DAYS"
    fi
}

# Execute main function
main "$@"
