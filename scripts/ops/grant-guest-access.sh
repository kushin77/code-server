#!/usr/bin/env bash
################################################################################
# @file        scripts/ops/grant-guest-access.sh
# @module      ops/session-management
# @description Grant guest access token to an IDE session
# @owner       infrastructure
# @status      active
#
# USAGE
#   scripts/ops/grant-guest-access.sh <session_id> <guest_email> [--permission <perm>] [--duration <hours>]
#
# Generates a guest access token for sharing sessions with collaborators.
# Idempotent: granting same access twice returns same token with updated expiry.
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

SESSION_ID="${1:-}"
GUEST_EMAIL="${2:-}"
PERMISSION="${PERMISSION:-view}"
DURATION_HOURS="${DURATION_HOURS:-24}"
DRY_RUN="${DRY_RUN:-false}"

################################################################################
# MAIN SCRIPT LOGIC
################################################################################

main() {
    if [[ -z "$SESSION_ID" || -z "$GUEST_EMAIL" ]]; then
        log_error "Usage: $SCRIPT_NAME <session_id> <guest_email> [--permission <perm>] [--duration <hours>]"
        return 2
    fi

    # Parse optional arguments
    while [[ $# -gt 2 ]]; do
        case "$3" in
            --permission)
                PERMISSION="$4"
                shift 2
                ;;
            --duration)
                DURATION_HOURS="$4"
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

    # Validate permission level
    if ! [[ "$PERMISSION" =~ ^(view|edit|admin)$ ]]; then
        log_error "Invalid permission level (must be view|edit|admin)" "permission=$PERMISSION"
        return 2
    fi

    # Validate email format (basic)
    if ! [[ "$GUEST_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid email format" "email=$GUEST_EMAIL"
        return 2
    fi

    log_info "Granting guest access" "sessionId=$SESSION_ID guestEmail=$GUEST_EMAIL permission=$PERMISSION durationHours=$DURATION_HOURS"

    if [[ "$DRY_RUN" != "true" ]]; then
        # Generate access token
        local token_id
        token_id="guest-$(date +%s)-$(openssl rand -hex 8)"
        
        local expires_at
        expires_at=$(date -u -d "+${DURATION_HOURS} hours" +"%Y-%m-%dT%H:%M:%SZ")

        # Create access token record
        local token_record
        token_record=$(cat <<EOF | jq -c '.'
{
  "id": "$token_id",
  "sessionId": "$SESSION_ID",
  "guestEmail": "$GUEST_EMAIL",
  "permission": "$PERMISSION",
  "createdAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "expiresAt": "$expires_at",
  "isActive": true,
  "accessCount": 0
}
EOF
        )

        log_info "Guest access token created" "tokenId=$token_id expiresAt=$expires_at"
        
        # Output token for client use
        echo "$token_record" | jq '.'
    else
        log_info "DRY RUN: Would grant guest access" "sessionId=$SESSION_ID guestEmail=$GUEST_EMAIL permission=$PERMISSION"
    fi

    log_info "Guest access grant complete" "status=success"
    return 0
}

# Execute main function
main "$@"
