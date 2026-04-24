#!/usr/bin/env bash
# @file        scripts/ops/deploy-collab-9-production-canary.sh
# @module      ops/deployment
# @description Deploy Collaborative-9 to a production canary rollout
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

REPLICA_1_HOST="${REPLICA_1_HOST:-${REPLICA_1_IP:-${DEPLOY_HOST:-}}}"
REPLICA_2_HOST="${REPLICA_2_HOST:-${REPLICA_2_IP:-}}"
REPLICA_1_USER="${REPLICA_1_USER:-${DEPLOY_USER:-${SSH_USER:-}}}"
REPLICA_2_USER="${REPLICA_2_USER:-${DEPLOY_USER:-${SSH_USER:-}}}"
SSH_KEY="${SSH_KEY:-${ONPREM_SSH_KEY:-$HOME/.ssh/id_rsa_onprem}}"
DEPLOY_PATH="${DEPLOY_PATH:-code-server-enterprise}"
WEB_SCHEME="${WEB_SCHEME:-http}"
FEATURE_ENABLED="${FEATURE_WEBHOOK_ENABLED:-true}"
ROLLOUT_PERCENTAGE="${WEBHOOK_ROLLOUT_PERCENTAGE:-5}"

if [[ -z "$REPLICA_1_HOST" || -z "$REPLICA_2_HOST" ]]; then
	log_fatal "Set REPLICA_1_HOST/REPLICA_2_HOST or REPLICA_1_IP/REPLICA_2_IP before running the canary deploy"
fi

if [[ -z "$REPLICA_1_USER" || -z "$REPLICA_2_USER" ]]; then
	log_fatal "Set REPLICA_1_USER/REPLICA_2_USER or DEPLOY_USER before running the canary deploy"
fi

deploy_to_replica() {
	local host="$1"
	local user="$2"
	local name="$3"

	log_info "Deploying to $name ($user@$host)..."
	ssh -i "$SSH_KEY" "$user@$host" "cd ${DEPLOY_PATH} && git pull origin main && FEATURE_WEBHOOK_ENABLED=${FEATURE_ENABLED} WEBHOOK_ROLLOUT_PERCENTAGE=${ROLLOUT_PERCENTAGE} docker compose up -d code-server appsmith caddy && docker compose ps"
}

log_info "Starting production canary rollout"

deploy_to_replica "$REPLICA_1_HOST" "$REPLICA_1_USER" "Replica 1"
deploy_to_replica "$REPLICA_2_HOST" "$REPLICA_2_USER" "Replica 2"

log_info "Canary rollout complete"
log_info "1. Monitor metrics in Grafana: ${WEB_SCHEME}://${REPLICA_1_HOST}:3000"
log_info "2. Check logs in Loki: ${WEB_SCHEME}://${REPLICA_1_HOST}:3100"
log_info "3. View traces in Jaeger: ${WEB_SCHEME}://${REPLICA_1_HOST}:16686"
