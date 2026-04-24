#!/usr/bin/env bash
# @file        scripts/ops/fix-error-triage-service.sh
# @module      operations/services
# @description Fix error-triage.service startup failures
# @owner       Platform Engineering
# @status      production-ready

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

PRIMARY_HOST="${DEPLOY_HOST:-${REPLICA_1_IP:-}}"
REPLICA_HOST="${STANDBY_HOST:-${REPLICA_2_IP:-}}"
EXEC_USER="${DEPLOY_USER:-${SSH_USER:-}}"
DRY_RUN="${DRY_RUN:-0}"
SERVICE_NAME="error-triage.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"

require_value() {
    local value="$1"
    local message="$2"

    if [[ -z "$value" ]]; then
        log_fatal "$message"
    fi
}

require_value "$PRIMARY_HOST" "Set DEPLOY_HOST or REPLICA_1_IP before fixing error triage"
require_value "$REPLICA_HOST" "Set STANDBY_HOST or REPLICA_2_IP before fixing error triage"
require_value "$EXEC_USER" "Set DEPLOY_USER or SSH_USER before fixing error triage"

check_service_file() {
    local host="$1"
    local exists

    exists=$(ssh "${EXEC_USER}@${host}" "[ -f $SERVICE_PATH ] && echo EXISTS || echo MISSING" || echo ERROR)
    case "$exists" in
        EXISTS)
            return 0
            ;;
        MISSING)
            log_error "Service file not found at $SERVICE_PATH on $host"
            return 1
            ;;
        *)
            log_error "Cannot check service file on $host"
            return 1
            ;;
    esac
}

check_service_status() {
    local host="$1"
    ssh "${EXEC_USER}@${host}" "systemctl status ${SERVICE_NAME} --no-pager" >/dev/null 2>&1 || return 1
}

fix_service_configuration() {
    local host="$1"

    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would restart ${SERVICE_NAME} on $host"
        return 0
    fi

    ssh "${EXEC_USER}@${host}" "sudo systemctl restart ${SERVICE_NAME}" || {
        log_error "Failed to restart ${SERVICE_NAME} on $host"
        return 1
    }
}

main() {
    log_info "Checking error triage service on primary and standby hosts"
    for host in "$PRIMARY_HOST" "$REPLICA_HOST"; do
        check_service_file "$host" || true
        if check_service_status "$host"; then
            log_info "Service is active on $host"
        else
            log_warn "Service is not active on $host"
        fi
    done

    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] No changes will be made"
        return 0
    fi

    for host in "$PRIMARY_HOST" "$REPLICA_HOST"; do
        fix_service_configuration "$host"
    done

    log_info "Fix complete; review service logs if the issue persists"
    log_info "See repository docs under /home/${EXEC_USER}/code-server-enterprise/docs"
}

main "$@"