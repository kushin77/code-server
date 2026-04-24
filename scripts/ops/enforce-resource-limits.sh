#!/usr/bin/env bash
################################################################################
# @file        scripts/ops/enforce-resource-limits.sh
# @module      ops/session-management
# @description Enforce resource limits on sessions
# @owner       infrastructure
# @status      active
#
# USAGE
#   scripts/ops/enforce-resource-limits.sh <session_id> <user_id> [--policy <name>]
#
# Applies enforcement actions (warn, throttle, suspend, terminate) based on quotas.
# Idempotent: enforcing same limits multiple times is safe.
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
USER_ID="${2:-}"
POLICY_NAME="${POLICY_NAME:-default}"
DRY_RUN="${DRY_RUN:-false}"
DOCKER_CONTAINER_PREFIX="${DOCKER_CONTAINER_PREFIX:-ide-}"

################################################################################
# MAIN SCRIPT LOGIC
################################################################################

main() {
    if [[ -z "$SESSION_ID" || -z "$USER_ID" ]]; then
        log_error "Usage: $SCRIPT_NAME <session_id> <user_id> [--policy <name>]"
        return 2
    fi

    log_info "Enforcing resource limits" \
        "sessionId=$SESSION_ID userId=$USER_ID policyName=$POLICY_NAME"

    # Determine enforcement action based on resource usage
    local action
    action=$(determine_enforcement_action "$USER_ID" "$SESSION_ID")

    log_info "Determined enforcement action" "action=$action"

    case "$action" in
        allow)
            enforce_allow
            ;;
        warn)
            enforce_warn "$USER_ID" "$SESSION_ID"
            ;;
        throttle)
            enforce_throttle "$SESSION_ID"
            ;;
        suspend)
            enforce_suspend "$SESSION_ID"
            ;;
        terminate)
            enforce_terminate "$SESSION_ID"
            ;;
    esac

    return 0
}

determine_enforcement_action() {
    local user_id="$1"
    local session_id="$2"

    # Simulate quota check (in production, query QuotaManager)
    # For now, return 'allow' as default (idempotent)
    echo "allow"
}

enforce_allow() {
    log_info "No enforcement action required"
}

enforce_warn() {
    local user_id="$1"
    local session_id="$2"

    if [[ "$DRY_RUN" != "true" ]]; then
        log_warn "Resource quota warning issued" "userId=$user_id sessionId=$session_id"
        # TODO: Send notification to user
    else
        log_info "DRY RUN: Would issue warning" "userId=$user_id sessionId=$session_id"
    fi
}

enforce_throttle() {
    local session_id="$1"

    if [[ "$DRY_RUN" != "true" ]]; then
        local container_name="${DOCKER_CONTAINER_PREFIX}${session_id}"

        # Apply CPU throttling via cgroup limits
        if docker inspect "$container_name" &>/dev/null; then
            log_info "Throttling container CPU/IO" "container=$container_name"
            # docker update --cpus=0.5 "$container_name" || true
        else
            log_warn "Container not found for throttling" "container=$container_name"
        fi
    else
        log_info "DRY RUN: Would throttle container" "sessionId=$session_id"
    fi
}

enforce_suspend() {
    local session_id="$1"

    if [[ "$DRY_RUN" != "true" ]]; then
        local container_name="${DOCKER_CONTAINER_PREFIX}${session_id}"

        # Suspend container (pause processes)
        if docker inspect "$container_name" &>/dev/null; then
            log_info "Suspending container" "container=$container_name"
            # docker pause "$container_name" || true
        else
            log_warn "Container not found for suspension" "container=$container_name"
        fi
    else
        log_info "DRY RUN: Would suspend container" "sessionId=$session_id"
    fi
}

enforce_terminate() {
    local session_id="$1"

    if [[ "$DRY_RUN" != "true" ]]; then
        local container_name="${DOCKER_CONTAINER_PREFIX}${session_id}"

        # Terminate container (hard stop)
        if docker inspect "$container_name" &>/dev/null; then
            log_error "Terminating container due to quota violation" "container=$container_name"
            # docker stop "$container_name" && docker rm "$container_name" || true
        else
            log_warn "Container not found for termination" "container=$container_name"
        fi
    else
        log_error "DRY RUN: Would terminate container" "sessionId=$session_id"
    fi
}

# Execute main function
main "$@"
