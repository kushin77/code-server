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
LOCAL_EXECUTION=false
TARGET_DEPLOY_DIR="${DEPLOY_DIR}"
TARGET_COMPOSE_FILE="${REMOTE_COMPOSE_FILE}"

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [--dry-run] [--local]

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
            --local)
                LOCAL_EXECUTION=true
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

resolve_target_paths() {
    if [[ "$LOCAL_EXECUTION" == true && ! -d "$TARGET_DEPLOY_DIR" ]]; then
        TARGET_DEPLOY_DIR="$PROJECT_DIR"
    fi

    TARGET_COMPOSE_FILE="${TARGET_DEPLOY_DIR}/docker-compose.yml"
}

run_target() {
    local command="$1"

    if [[ "$DRY_RUN" == true ]]; then
        if [[ "$LOCAL_EXECUTION" == true ]]; then
            log_info "[dry-run] local ${command}"
        else
            log_info "[dry-run] ssh ${DEPLOY_USER}@${DEPLOY_HOST} ${command}"
        fi
        return 0
    fi

    if [[ "$LOCAL_EXECUTION" == true ]]; then
        bash -lc "$command"
        return 0
    fi

    ssh_exec "$command"
}

upload_compose() {
    if [[ "$DRY_RUN" == true ]]; then
        if [[ "$LOCAL_EXECUTION" == true ]]; then
            if [[ "$LOCAL_COMPOSE_FILE" == "$TARGET_COMPOSE_FILE" ]]; then
                log_info "[dry-run] local compose file already matches target compose file"
            else
                log_info "[dry-run] copy ${LOCAL_COMPOSE_FILE} -> ${TARGET_COMPOSE_FILE}"
            fi
        else
            log_info "[dry-run] scp ${LOCAL_COMPOSE_FILE} ${DEPLOY_USER}@${DEPLOY_HOST}:${REMOTE_COMPOSE_FILE}"
        fi
        return 0
    fi

    if [[ "$LOCAL_EXECUTION" == true ]]; then
        if [[ "$LOCAL_COMPOSE_FILE" == "$TARGET_COMPOSE_FILE" ]]; then
            log_info "Local compose file already matches target compose file"
            return 0
        fi

        require_dir "$TARGET_DEPLOY_DIR"
        mkdir -p "$(dirname "$TARGET_COMPOSE_FILE")"
        copy_file "$LOCAL_COMPOSE_FILE" "$TARGET_COMPOSE_FILE"
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
    run_target "grep -qF '${PORTAL_CALLBACK_URL}' '${TARGET_COMPOSE_FILE}'"
    run_target "grep -qF '${IDE_CALLBACK_URL}' '${TARGET_COMPOSE_FILE}'"
    log_info "Verified target compose file contains the expected callback URLs"
}

redeploy_services() {
    run_target "cd '${TARGET_DEPLOY_DIR}' && (COMPOSE_PROFILES=portal docker-compose up -d --remove-orphans ${PORTAL_SERVICES[*]} || COMPOSE_PROFILES=portal docker compose up -d --remove-orphans ${PORTAL_SERVICES[*]})"
    log_info "Requested idempotent portal service redeploy"
}

wait_for_target_service() {
    local service_name="$1"
    local attempt

    for attempt in $(seq 1 12); do
        if run_target "docker inspect --format '{{.State.Running}}' '${service_name}' 2>/dev/null | grep -q true"; then
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
    run_target "curl -ksS -o /dev/null -D - 'https://kushnir.cloud/oauth2/start?rd=/' | grep -qi 'location: .*redirect_uri=https%3A%2F%2Fkushnir.cloud%2Foauth2%2Fcallback'"
    run_target "curl -ksS -o /dev/null -D - 'https://ide.kushnir.cloud/oauth2/start?rd=/' | grep -qi 'location: .*redirect_uri=https%3A%2F%2Fide.kushnir.cloud%2Foauth2%2Fcallback'"
    log_info "Verified apex and IDE OAuth start endpoints point to distinct callbacks"
}

main() {
    parse_args "$@"

    if [[ "$LOCAL_EXECUTION" == true ]]; then
        require_commands grep curl
        if [[ "$DRY_RUN" == false ]]; then
            require_command docker
        fi
    else
        require_commands ssh scp grep curl
    fi

    resolve_target_paths
    verify_local_compose

    if [[ "$DRY_RUN" == false && "$LOCAL_EXECUTION" == false ]]; then
        assert_deploy_access
    fi

    if [[ "$LOCAL_EXECUTION" == true ]]; then
        log_info "Uploading canonical compose file to ${TARGET_COMPOSE_FILE}"
    else
        log_info "Uploading canonical compose file to ${DEPLOY_USER}@${DEPLOY_HOST}:${REMOTE_COMPOSE_FILE}"
    fi
    upload_compose
    verify_remote_compose

    log_info "Redeploying portal services: ${PORTAL_SERVICES[*]}"
    redeploy_services

    wait_for_target_service "oauth2-proxy-portal"
    wait_for_target_service "caddy"

    verify_oauth_routes
    log_info "${SCRIPT_NAME} completed successfully"
}

main "$@"
