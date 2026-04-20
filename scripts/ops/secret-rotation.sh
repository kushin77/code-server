#!/usr/bin/env bash
# @file        scripts/ops/secret-rotation.sh
# @module      ops/secrets
# @description Rotate all secrets through Google Secret Manager and restart affected services

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

DRY_RUN="${DRY_RUN:-0}"
TARGET_DEPLOY_HOST="${DEPLOY_HOST:-192.168.168.31}"
TARGET_DEPLOY_USER="${DEPLOY_USER:-akushnir}"
GSM_PROJECT="${GSM_PROJECT:-gcp-eiq}"
REMOTE_REPO_DIR="${REMOTE_REPO_DIR:-~/code-server-enterprise}"

declare -a SECRET_SPECS=(
    "prod-portal-oauth2-cookie-secret|OAUTH2_PROXY_COOKIE_SECRET|hex|16|oauth2-proxy cookie secret|oauth2-proxy oauth2-proxy-portal"
    "prod-redis-password|REDIS_PASSWORD|hex|16|redis auth password|redis redis-sentinel-1 redis-sentinel-arbiter oauth2-proxy oauth2-proxy-portal session-broker"
    "prod-code-server-admin-password|CODE_SERVER_PASSWORD|base64|24|code-server admin password|session-broker"
    "prod-ide-session-lb-secret|IDE_SESSION_LB_SECRET|hex|16|caddy sticky-session secret|caddy"
)

log_stage() {
    log_info "========== $1 =========="
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

ensure_gsm_secret_exists() {
    local secret_id="$1"

    if gcloud --quiet --project "$GSM_PROJECT" secrets describe "$secret_id" >/dev/null 2>&1; then
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would create GSM secret: $secret_id"
        return 0
    fi

    log_info "Creating GSM secret: $secret_id"
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
        return 0
    fi

    local secret_value
    secret_value="$(generate_secret_value "$format" "$length")"

    ensure_gsm_secret_exists "$secret_id"

    log_info "Rotating $env_name via GSM secret: $secret_id"
    printf '%s' "$secret_value" | gcloud --quiet --project "$GSM_PROJECT" secrets versions add "$secret_id" --data-file=- >/dev/null
    log_info "  ✓ Added new GSM version for $secret_id"
}

refresh_remote_services() {
    local service_list="$1"

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would refresh remote deployment on $DEPLOY_USER@$DEPLOY_HOST"
        log_info "[DRY-RUN] Would source scripts/fetch-gsm-secrets.sh on the host and restart: $service_list"
        return 0
    fi

    log_info "Refreshing remote secrets on $DEPLOY_USER@$DEPLOY_HOST"
    ssh "$DEPLOY_USER@$DEPLOY_HOST" "set -euo pipefail; cd $REMOTE_REPO_DIR && source scripts/fetch-gsm-secrets.sh --non-interactive >/dev/null 2>&1 && docker compose up -d --force-recreate $service_list" >/dev/null
    log_info "  ✓ Remote services restarted"
}

verify_rotation() {
    local service_list="$1"

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would verify restarted services: $service_list"
        return 0
    fi

    ssh "$DEPLOY_USER@$DEPLOY_HOST" "set -euo pipefail; cd $REMOTE_REPO_DIR && docker compose ps --status running $service_list" >/dev/null
    log_info "  ✓ Remote service health check passed"
}

main() {
    log_stage "SECRET ROTATION PROCEDURE"
    log_info "Target: $TARGET_DEPLOY_USER@$TARGET_DEPLOY_HOST"
    log_info "Dry-run mode: $([ "$DRY_RUN" -eq 1 ] && echo 'YES' || echo 'NO')"
    log_info "GSM project: $GSM_PROJECT"
    echo ""

    if [ "$DRY_RUN" -eq 0 ]; then
        require_command gcloud
        require_command openssl
        require_command ssh
    fi
    
    # === Step 1: Rotate Secret Versions in GSM ===
    log_stage "STEP 1: Rotate Secret Versions in Google Secret Manager"

    local rotated_services=""
    local spec
    for spec in "${SECRET_SPECS[@]}"; do
        IFS='|' read -r secret_id env_name format length description services <<< "$spec"
        rotate_gsm_secret "$secret_id" "$env_name" "$format" "$length" "$description"
        if [ -n "$rotated_services" ]; then
            rotated_services="$rotated_services $services"
        else
            rotated_services="$services"
        fi
    done
    echo ""
    
    # normalize service list while preserving order for readability
    rotated_services="$(printf '%s\n' $rotated_services | awk 'NF && !seen[$0]++ {printf sep $0; sep=" "}')"

    # === Step 2: Refresh Deployment Host Environment and Restart Services ===
    log_stage "STEP 2: Refresh Deployment Host Environment"

    refresh_remote_services "$rotated_services"
    echo ""
    
    # === Step 3: Verify Services ===
    log_stage "STEP 3: Verify Restarted Services"

    verify_rotation "$rotated_services"
    echo ""
    
    log_stage "SECRET ROTATION COMPLETE"
    log_info "✅ All configured secrets rotated successfully"
    exit 0
}

main "$@"
