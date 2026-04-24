#!/usr/bin/env bash
# @file        scripts/ops/deploy-collab-9-staging.sh
# @module      ops/deployment
# @description Deploy Collaborative-9 features to staging environment
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

STAGING_HOST="${STAGING_HOST:-${REPLICA_1_IP:-${DEPLOY_HOST:-}}}"
STAGING_USER="${STAGING_USER:-${DEPLOY_USER:-${SSH_USER:-}}}"
SSH_KEY="${SSH_KEY:-${ONPREM_SSH_KEY:-$HOME/.ssh/id_rsa_onprem}}"
DEPLOY_PATH="${DEPLOY_PATH:-code-server-enterprise}"
DRY_RUN="${DRY_RUN:-0}"
FEATURE_FLAG="${FEATURE_WEBHOOK_ENABLED:-true}"

if [[ -z "$STAGING_HOST" ]]; then
	log_fatal "Set STAGING_HOST or REPLICA_1_IP or DEPLOY_HOST before running the staging deploy"
fi

if [[ -z "$STAGING_USER" ]]; then
	log_fatal "Set STAGING_USER or DEPLOY_USER before running the staging deploy"
fi

STAGING_SSH="${STAGING_USER}@${STAGING_HOST}"

log_info "Collab-9 staging deployment"
log_info "Target: $STAGING_HOST"
log_info "Feature flag: $FEATURE_FLAG"
log_info "Dry run: $DRY_RUN"

if [[ "$DRY_RUN" == "1" ]]; then
	log_info "Dry run requested; skipping remote changes"
	exit 0
fi

if ! ssh -i "$SSH_KEY" -o ConnectTimeout=5 "$STAGING_SSH" "whoami" >/dev/null 2>&1; then
	log_fatal "SSH connectivity failed to $STAGING_SSH"
fi

ssh -i "$SSH_KEY" "$STAGING_SSH" "cd ${DEPLOY_PATH} && git pull origin main && FEATURE_WEBHOOK_ENABLED=${FEATURE_FLAG} docker compose up -d code-server appsmith caddy && docker compose ps"

log_info "Staging deployment complete"
