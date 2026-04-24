#!/usr/bin/env bash
# @file        scripts/ops/secret-rotation.sh
# @module      ops/secrets
# @description Rotate secrets through Google Secret Manager, refresh .env atomically, and restart affected services

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

DRY_RUN="${DRY_RUN:-0}"
TARGET_DEPLOY_HOST="${TARGET_DEPLOY_HOST:-${DEPLOY_HOST}}"
TARGET_DEPLOY_USER="${TARGET_DEPLOY_USER:-${DEPLOY_USER}}"
GSM_PROJECT="${GSM_PROJECT:-gcp-eiq}"
REMOTE_REPO_DIR="${REMOTE_REPO_DIR:-${DEPLOY_DIR}}"
AUDIT_DIR="${AUDIT_DIR:-artifacts/incidents}"
ROTATION_TIMESTAMP="${ROTATION_TIMESTAMP:-$(date -u +%Y%m%d%H%M%S)}"
AUDIT_LOG="${AUDIT_LOG:-$AUDIT_DIR/rotation-$ROTATION_TIMESTAMP.log}"

declare -a SECRET_SPECS=(
    "prod-portal-oauth2-cookie-secret|OAUTH2_PROXY_COOKIE_SECRET|hex|16|oauth2-proxy cookie secret|oauth2-proxy oauth2-proxy-portal"
    "prod-redis-password|REDIS_PASSWORD|hex|16|redis auth password|redis redis-sentinel-1 redis-sentinel-arbiter oauth2-proxy oauth2-proxy-portal session-broker"
    "prod-code-server-admin-password|CODE_SERVER_PASSWORD|base64|24|code-server admin password|session-broker"
    "prod-ide-session-lb-secret|IDE_SESSION_LB_SECRET|hex|16|caddy sticky-session secret|caddy"
)

declare -a ROTATED_SERVICES=()
declare -A SERVICE_SEEN=()

mkdir -p "$AUDIT_DIR"
: > "$AUDIT_LOG"

audit_note() {
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$AUDIT_LOG"
}

finish_audit() {
    local exit_code="$1"

    if [ "$exit_code" -eq 0 ]; then
        audit_note "status=success dry_run=$DRY_RUN target=${TARGET_DEPLOY_USER}@${TARGET_DEPLOY_HOST}"
    else
        audit_note "status=failure exit_code=$exit_code dry_run=$DRY_RUN target=${TARGET_DEPLOY_USER}@${TARGET_DEPLOY_HOST}"
    fi
}

trap 'finish_audit $?' EXIT

log_stage() {
    log_info "========== $1 =========="
    audit_note "stage=$1"
}

append_services() {
    local service

    for service in "$@"; do
        if [ -n "${SERVICE_SEEN[$service]:-}" ]; then
            continue
        fi

        SERVICE_SEEN["$service"]=1
        ROTATED_SERVICES+=("$service")
    done
}

generate_secret_value() {
    local format="$1"
    local length="$2"

    case "$format" in
        hex)
            openssl rand -hex "$length"
            ;;
        base64)
            openssl rand -base64 "$length"
            ;;
        *)
            log_fatal "Unsupported secret format: $format"
            ;;
    esac
}

validate_secret_value() {
    local secret_name="$1"
    local secret_value="$2"
    local format="$3"
    local length="$4"

    case "$format" in
        hex)
            if ! [[ "$secret_value" =~ ^[0-9a-fA-F]+$ ]]; then
                log_fatal "Generated value for $secret_name is not hex"
            fi

            if [ "${#secret_value}" -ne $((length * 2)) ]; then
                log_fatal "Generated value for $secret_name has unexpected hex length"
            fi
            ;;
        base64)
            if ! [[ "$secret_value" =~ ^[A-Za-z0-9+/=]+$ ]]; then
                log_fatal "Generated value for $secret_name is not base64-like"
            fi

            if [ -z "$secret_value" ]; then
                log_fatal "Generated value for $secret_name is empty"
            fi
            ;;
        *)
            log_fatal "Unsupported secret format: $format"
            ;;
    esac
}

ensure_gsm_secret_exists() {
    local secret_id="$1"

    if gcloud --quiet --project "$GSM_PROJECT" secrets describe "$secret_id" >/dev/null 2>&1; then
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would create GSM secret: $secret_id"
        audit_note "would_create_secret=$secret_id"
        return 0
    fi

    log_info "Creating GSM secret: $secret_id"
    audit_note "create_secret=$secret_id"
    gcloud --quiet --project "$GSM_PROJECT" secrets create "$secret_id" --replication-policy=automatic >/dev/null
}

rotate_gsm_secret() {
    local secret_id="$1"
    local env_name="$2"
    local format="$3"
    local length="$4"
    local description="$5"

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would rotate $env_name via GSM secret $secret_id ($description)"
        audit_note "would_rotate=$env_name secret_id=$secret_id description=$description"
        return 0
    fi

    local secret_value
    secret_value="$(generate_secret_value "$format" "$length")"
    validate_secret_value "$env_name" "$secret_value" "$format" "$length"

    ensure_gsm_secret_exists "$secret_id"

    log_info "Rotating $env_name via GSM secret: $secret_id"
    audit_note "rotate=$env_name secret_id=$secret_id description=$description"
    printf '%s' "$secret_value" | gcloud --quiet --project "$GSM_PROJECT" secrets versions add "$secret_id" --data-file=- >/dev/null
    log_info "  ✓ Added new GSM version for $secret_id"
}

refresh_remote_env_and_restart() {
    local services=("$@")
    local service_args=()
    local service

    for service in "${services[@]}"; do
        service_args+=("$service")
    done

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would refresh remote .env on $TARGET_DEPLOY_USER@$TARGET_DEPLOY_HOST"
        log_info "[DRY-RUN] Would atomically replace .env, restart: ${services[*]}"
        audit_note "would_refresh_env target=${TARGET_DEPLOY_USER}@${TARGET_DEPLOY_HOST} services=${services[*]}"
        return 0
    fi

    log_info "Refreshing remote .env on $TARGET_DEPLOY_USER@$TARGET_DEPLOY_HOST"
    audit_note "refresh_env target=${TARGET_DEPLOY_USER}@${TARGET_DEPLOY_HOST} services=${services[*]}"

    ssh $SSH_OPTS "$TARGET_DEPLOY_USER@$TARGET_DEPLOY_HOST" bash -s -- "$REMOTE_REPO_DIR" "$ROTATION_TIMESTAMP" "${service_args[@]}" <<'REMOTE'
set -euo pipefail

repo_dir="$1"
rotation_stamp="$2"
shift 2
services=("$@")

cd "$repo_dir"

backup_path=".env.rotation.bak.$rotation_stamp"

restore_env() {
    if [[ -f "$backup_path" ]]; then
        cp "$backup_path" .env
        docker compose up -d --force-recreate "${services[@]}" >/dev/null
    fi
}

trap restore_env ERR

if [[ -f .env ]]; then
    cp .env "$backup_path"
fi

bash scripts/fetch-gsm-secrets.sh --non-interactive > .env.new
mv .env.new .env
docker compose up -d --force-recreate "${services[@]}" >/dev/null
docker compose ps --status running "${services[@]}" >/dev/null
trap - ERR
REMOTE

    log_info "  ✓ Remote .env refreshed and services restarted"
}

verify_rotation() {
    local service_list="$1"

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would verify restarted services: $service_list"
        audit_note "would_verify_services=$service_list"
        return 0
    fi

    ssh $SSH_OPTS "$TARGET_DEPLOY_USER@$TARGET_DEPLOY_HOST" "set -euo pipefail; cd $REMOTE_REPO_DIR && docker compose ps --status running $service_list" >/dev/null
    log_info "  ✓ Remote service health check passed"
    audit_note "verified_services=$service_list"
}

main() {
    log_stage "SECRET ROTATION PROCEDURE"
    log_info "Target: $TARGET_DEPLOY_USER@$TARGET_DEPLOY_HOST"
    log_info "Dry-run mode: $([ "$DRY_RUN" -eq 1 ] && echo 'YES' || echo 'NO')"
    log_info "GSM project: $GSM_PROJECT"
    log_info "Audit log: $AUDIT_LOG"

    audit_note "rotation_started target=${TARGET_DEPLOY_USER}@${TARGET_DEPLOY_HOST} dry_run=$DRY_RUN gsm_project=$GSM_PROJECT audit_log=$AUDIT_LOG"

    if [ "$DRY_RUN" -eq 0 ]; then
        require_command gcloud
        require_command openssl
        require_command ssh
    fi

    log_stage "STEP 1: Rotate Secret Versions in Google Secret Manager"

    local spec
    for spec in "${SECRET_SPECS[@]}"; do
        IFS='|' read -r secret_id env_name format length description services <<< "$spec"
        rotate_gsm_secret "$secret_id" "$env_name" "$format" "$length" "$description"
        append_services $services
    done

    log_stage "STEP 2: Refresh Deployment Host Environment"
    refresh_remote_env_and_restart "${ROTATED_SERVICES[@]}"

    log_stage "STEP 3: Verify Restarted Services"
    verify_rotation "${ROTATED_SERVICES[*]}"

    log_stage "SECRET ROTATION COMPLETE"
    log_info "All configured secrets rotated successfully"
    audit_note "rotation_complete services=${ROTATED_SERVICES[*]}"
}

main "$@"
