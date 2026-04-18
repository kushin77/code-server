#!/usr/bin/env bash
# @file        scripts/deploy/redeploy-portal-oauth-routing.sh
# @module      deployment/oauth
# @description idempotently redeploy portal oauth routing on the primary host
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPT_NAME="$(basename "$0")"

readonly LOCAL_COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"
readonly REMOTE_COMPOSE_FILE="${DOCKER_COMPOSE_FILE}"
readonly PORTAL_CALLBACK_URL="${OAUTH2_PROXY_PORTAL_REDIRECT_URL:-https://kushnir.cloud/oauth2/callback}"
readonly IDE_CALLBACK_URL="${OAUTH2_PROXY_IDE_REDIRECT_URL:-${OAUTH2_REDIRECT_URL:-https://ide.kushnir.cloud/oauth2/callback}}"
readonly PORTAL_SERVICES=(oauth2-proxy-portal caddy appsmith)

DRY_RUN=false

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [--dry-run]

Uploads the canonical docker-compose.yml to the primary host and
recreates only the portal routing services with COMPOSE_PROFILES=portal.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_fatal "Unknown option: $1"
                ;;
        esac
    done
}

run_remote() {
    local command="$1"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[dry-run] ssh ${DEPLOY_USER}@${DEPLOY_HOST} ${command}"
        return 0
    fi

    ssh_exec "$command"
}

upload_compose() {
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[dry-run] scp ${LOCAL_COMPOSE_FILE} ${DEPLOY_USER}@${DEPLOY_HOST}:${REMOTE_COMPOSE_FILE}"
        return 0
    fi

    ssh_upload "${LOCAL_COMPOSE_FILE}" "${REMOTE_COMPOSE_FILE}"
}

verify_local_compose() {
    require_file "${LOCAL_COMPOSE_FILE}"

    if ! grep -qF "${PORTAL_CALLBACK_URL}" "${LOCAL_COMPOSE_FILE}"; then
        log_fatal "Local compose file does not contain the portal callback URL: ${PORTAL_CALLBACK_URL}"
    fi

    if ! grep -qF "${IDE_CALLBACK_URL}" "${LOCAL_COMPOSE_FILE}"; then
        log_fatal "Local compose file does not contain the IDE callback URL: ${IDE_CALLBACK_URL}"
    fi

    log_info "Verified local compose file contains distinct IDE and portal callback URLs"
}

verify_remote_compose() {
    run_remote "grep -qF '${PORTAL_CALLBACK_URL}' '${REMOTE_COMPOSE_FILE}'"
    run_remote "grep -qF '${IDE_CALLBACK_URL}' '${REMOTE_COMPOSE_FILE}'"
    log_info "Verified remote compose file contains the expected callback URLs"
}

redeploy_services() {
    run_remote "cd '${DEPLOY_DIR}' && COMPOSE_PROFILES=portal docker compose up -d --remove-orphans ${PORTAL_SERVICES[*]}"
    log_info "Requested idempotent portal service redeploy"
}

wait_for_remote_service() {
    local service_name="$1"
    local attempt

    for attempt in $(seq 1 12); do
        if run_remote "docker inspect --format '{{.State.Running}}' '${service_name}' 2>/dev/null | grep -q true"; then
            log_info "Service is running: ${service_name}"
            return 0
        fi
        if [[ "$DRY_RUN" == false ]]; then
            sleep 5
        fi
    done

    log_fatal "Timed out waiting for service: ${service_name}"
}

verify_oauth_routes() {
    run_remote "curl -ksS -o /dev/null -D - 'https://kushnir.cloud/oauth2/start?rd=/' | grep -qi 'location: .*redirect_uri=https%3A%2F%2Fkushnir.cloud%2Foauth2%2Fcallback'"
    run_remote "curl -ksS -o /dev/null -D - 'https://ide.kushnir.cloud/oauth2/start?rd=/' | grep -qi 'location: .*redirect_uri=https%3A%2F%2Fide.kushnir.cloud%2Foauth2%2Fcallback'"
    log_info "Verified apex and IDE OAuth start endpoints point to distinct callbacks"
}

main() {
    parse_args "$@"

    require_commands ssh scp grep curl
    verify_local_compose

    if [[ "$DRY_RUN" == false ]]; then
        assert_deploy_access
    fi

    log_info "Uploading canonical compose file to ${DEPLOY_USER}@${DEPLOY_HOST}:${REMOTE_COMPOSE_FILE}"
    upload_compose
    verify_remote_compose

    log_info "Redeploying portal services: ${PORTAL_SERVICES[*]}"
    redeploy_services

    wait_for_remote_service "oauth2-proxy-portal"
    wait_for_remote_service "caddy"

    verify_oauth_routes
    log_info "${SCRIPT_NAME} completed successfully"
}

main "$@"
