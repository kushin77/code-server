#!/usr/bin/env bash
# @file        scripts/ops/fix-ollama-init-container.sh
# @module      operations/containers
# @description Fix ollama-init container startup issues on cluster nodes
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
CONTAINER_NAME="ollama-init"
REPO_PATH="/home/${EXEC_USER}/code-server-enterprise"
COMPOSE_FILE="${REPO_PATH}/docker-compose.yml"

require_value() {
    local value="$1"
    local message="$2"

    if [[ -z "$value" ]]; then
        log_fatal "$message"
    fi
}

require_value "$PRIMARY_HOST" "Set DEPLOY_HOST or REPLICA_1_IP before fixing ollama-init"
require_value "$REPLICA_HOST" "Set STANDBY_HOST or REPLICA_2_IP before fixing ollama-init"
require_value "$EXEC_USER" "Set DEPLOY_USER or SSH_USER before fixing ollama-init"

check_container_state() {
    local host="$1"
    local state

    state=$(ssh "${EXEC_USER}@${host}" "docker ps -a --filter name=${CONTAINER_NAME} --format '{{.State}}' 2>/dev/null || echo unknown" || echo error)
    log_info "Container state on $host: $state"
}

check_compose_config() {
    local host="$1"
    ssh "${EXEC_USER}@${host}" "grep -A20 '${CONTAINER_NAME}:' ${COMPOSE_FILE} | head -25" >/dev/null 2>&1 || true
}

restart_container() {
    local host="$1"

    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would restart ${CONTAINER_NAME} on $host"
        return 0
    fi

    ssh "${EXEC_USER}@${host}" "cd ${REPO_PATH} && docker-compose up -d ${CONTAINER_NAME}" || {
        log_error "Failed to restart ${CONTAINER_NAME} on $host"
        return 1
    }
}

verify_container_running() {
    local host="$1"
    ssh "${EXEC_USER}@${host}" "docker ps --filter name=${CONTAINER_NAME} --format '{{.Status}}'" >/dev/null 2>&1 || return 1
}

main() {
    for host in "$PRIMARY_HOST" "$REPLICA_HOST"; do
        check_container_state "$host"
        check_compose_config "$host"
        restart_container "$host"
        verify_container_running "$host" || log_warn "${CONTAINER_NAME} may still be starting on $host"
    done

    log_info "Ollama init container remediation complete"
}

main "$@"