#!/usr/bin/env bash
# @file        scripts/ops/fix-root-owned-files.sh
# @module      operations/git
# @description Fix root-owned files blocking git pull
# @owner       infrastructure
# @status      production-ready

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

PRIMARY_HOST="${DEPLOY_HOST:-${REPLICA_1_IP:-}}"
REPLICA_HOST="${STANDBY_HOST:-${REPLICA_2_IP:-}}"
EXEC_USER="${DEPLOY_USER:-${SSH_USER:-}}"
DRY_RUN="${DRY_RUN:-0}"
REPO_PATH="/home/${EXEC_USER}/code-server-enterprise"

require_value() {
    local value="$1"
    local message="$2"

    if [[ -z "$value" ]]; then
        log_fatal "$message"
    fi
}

require_value "$PRIMARY_HOST" "Set DEPLOY_HOST or REPLICA_1_IP before fixing root-owned files"
require_value "$REPLICA_HOST" "Set STANDBY_HOST or REPLICA_2_IP before fixing root-owned files"
require_value "$EXEC_USER" "Set DEPLOY_USER or SSH_USER before fixing root-owned files"

check_root_owned_files() {
    local host="$1"
    local root_owned_count

    root_owned_count=$(ssh "${EXEC_USER}@${host}" "find ${REPO_PATH} -user root 2>/dev/null | wc -l" || echo 0)
    if [ "$root_owned_count" -eq 0 ]; then
        log_info "No root-owned files found on $host"
        return 0
    fi

    log_warn "Found $root_owned_count root-owned files on $host"
    ssh "${EXEC_USER}@${host}" "find ${REPO_PATH} -user root -type f 2>/dev/null | head -10 || true" | sed 's/^/  /'
    return 1
}

fix_file_ownership() {
    local host="$1"

    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would run: sudo chown -R ${EXEC_USER}:${EXEC_USER} ${REPO_PATH}"
        return 0
    fi

    ssh "${EXEC_USER}@${host}" "sudo chown -R ${EXEC_USER}:${EXEC_USER} ${REPO_PATH}" || {
        log_error "Failed to change ownership on $host"
        return 1
    }
}

main() {
    for host in "$PRIMARY_HOST" "$REPLICA_HOST"; do
        check_root_owned_files "$host" || true
        fix_file_ownership "$host"
    done

    log_info "Root-owned file remediation complete"
}

main "$@"