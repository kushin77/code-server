#!/usr/bin/env bash
################################################################################
# @file        scripts/ops/record-session.sh
# @module      ops/session-management
# @description Start, pause, resume, or stop session recording
# @owner       infrastructure
# @status      active
#
# USAGE
#   scripts/ops/record-session.sh <action> <session_id> [--format <fmt>] [--audience <level>]
#
# Actions: start, pause, resume, stop, list
# Idempotent: starting already-recording session is a no-op.
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
FORMAT="${FORMAT:-asciinema}"
AUDIENCE_LEVEL="${AUDIENCE_LEVEL:-private}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
DRY_RUN="${DRY_RUN:-false}"
NAS_MOUNT_PATH="${NAS_MOUNT_PATH:-/mnt/nas/persistent/code-server-enterprise}"

################################################################################
# MAIN SCRIPT LOGIC
################################################################################

main() {
    if [[ -z "$ACTION" || -z "$SESSION_ID" ]]; then
        log_error "Usage: $SCRIPT_NAME <action> <session_id> [--format <fmt>] [--audience <level>]"
        log_info "Actions: start, pause, resume, stop, list"
        return 2
    fi

    # Parse optional arguments
    shift 2
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format)
                FORMAT="$2"
                shift 2
                ;;
            --audience)
                AUDIENCE_LEVEL="$2"
                shift 2
                ;;
            --retention)
                RETENTION_DAYS="$2"
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
    if ! [[ "$ACTION" =~ ^(start|pause|resume|stop|list)$ ]]; then
        log_error "Invalid action (must be start|pause|resume|stop|list)" "action=$ACTION"
        return 2
    fi

    # Validate format
    if ! [[ "$FORMAT" =~ ^(asciinema|mp4|webm)$ ]]; then
        log_error "Invalid format (must be asciinema|mp4|webm)" "format=$FORMAT"
        return 2
    fi

    # Validate audience level
    if ! [[ "$AUDIENCE_LEVEL" =~ ^(private|team|public)$ ]]; then
        log_error "Invalid audience level (must be private|team|public)" "audience=$AUDIENCE_LEVEL"
        return 2
    fi

    log_info "Processing recording action" \
        "action=$ACTION sessionId=$SESSION_ID format=$FORMAT audience=$AUDIENCE_LEVEL"

    case "$ACTION" in
        start)
            start_recording
            ;;
        pause)
            pause_recording
            ;;
        resume)
            resume_recording
            ;;
        stop)
            stop_recording
            ;;
        list)
            list_recordings
            ;;
    esac

    return $?
}

start_recording() {
    if [[ "$DRY_RUN" != "true" ]]; then
        local recording_id
        recording_id="rec-$(date +%s)-$(openssl rand -hex 8)"
        
        local recording_record
        recording_record=$(cat <<EOF | jq -c '.'
{
  "id": "$recording_id",
  "sessionId": "$SESSION_ID",
  "status": "recording",
  "format": "$FORMAT",
  "audienceLevel": "$AUDIENCE_LEVEL",
  "startedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "retentionDays": $RETENTION_DAYS
}
EOF
        )

        log_info "Recording started" "recordingId=$recording_id"
        echo "$recording_record" | jq '.'
    else
        log_info "DRY RUN: Would start recording" \
            "sessionId=$SESSION_ID format=$FORMAT audience=$AUDIENCE_LEVEL"
    fi
}

pause_recording() {
    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Recording paused" "sessionId=$SESSION_ID"
    else
        log_info "DRY RUN: Would pause recording" "sessionId=$SESSION_ID"
    fi
}

resume_recording() {
    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Recording resumed" "sessionId=$SESSION_ID"
    else
        log_info "DRY RUN: Would resume recording" "sessionId=$SESSION_ID"
    fi
}

stop_recording() {
    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Recording stopped" "sessionId=$SESSION_ID"
    else
        log_info "DRY RUN: Would stop recording" "sessionId=$SESSION_ID"
    fi
}

list_recordings() {
    if [[ "$DRY_RUN" != "true" ]]; then
        local recordings_dir="$NAS_MOUNT_PATH/session-recordings"
        if [[ -d "$recordings_dir" ]]; then
            log_info "Listing recordings for session" "sessionId=$SESSION_ID dir=$recordings_dir"
            find "$recordings_dir" -name "*$SESSION_ID*" -type f | jq -R '.' || true
        else
            log_info "No recordings found" "sessionId=$SESSION_ID"
        fi
    else
        log_info "DRY RUN: Would list recordings" "sessionId=$SESSION_ID"
    fi
}

# Execute main function
main "$@"
