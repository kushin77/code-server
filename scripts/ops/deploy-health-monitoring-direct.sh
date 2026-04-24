#!/usr/bin/env bash
# @file        scripts/ops/deploy-health-monitoring-direct.sh
# @module      ops/deployment
# @description Deploy health monitoring services directly to cluster nodes
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

REPLICA_31_HOST="${REPLICA_31_HOST:-${REPLICA_1_IP:-${DEPLOY_HOST:-}}}"
REPLICA_42_HOST="${REPLICA_42_HOST:-${REPLICA_2_IP:-}}"
SSH_USER="${SSH_USER:-${DEPLOY_USER:-}}"
SSH_KEY="${SSH_KEY:-${ONPREM_SSH_KEY:-$HOME/.ssh/id_rsa_onprem}}"
DEPLOY_PATH="${DEPLOY_PATH:-code-server-enterprise}"
MONITORING_SCHEME="${MONITORING_SCHEME:-https}"

if [[ -z "$REPLICA_31_HOST" || -z "$REPLICA_42_HOST" ]]; then
	log_fatal "Set REPLICA_31_HOST/REPLICA_42_HOST or REPLICA_1_IP/REPLICA_2_IP before deploying monitoring"
fi

if [[ -z "$SSH_USER" ]]; then
	log_fatal "Set SSH_USER or DEPLOY_USER before deploying monitoring"
fi

deploy_to_host() {
	local host="$1"
	local name="$2"

	log_info "Deploying health monitoring to $name ($SSH_USER@$host)..."
	ssh -i "$SSH_KEY" "$SSH_USER@$host" "cd ${DEPLOY_PATH} && docker compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d prometheus"
}

deploy_to_host "$REPLICA_31_HOST" "Replica 31" &
PID_31=$!
deploy_to_host "$REPLICA_42_HOST" "Replica 42" &
PID_42=$!

wait "$PID_31" && log_info "Replica 31 deployment complete" || log_error "Replica 31 deployment failed"
wait "$PID_42" && log_info "Replica 42 deployment complete" || log_error "Replica 42 deployment failed"

log_info "Deployment complete"
log_info "Scrape targets: ${MONITORING_SCHEME}://${REPLICA_31_HOST}:9090/targets"
log_info "Alert rules: ${MONITORING_SCHEME}://${REPLICA_31_HOST}:9090/rules"
log_info "Health check: curl -k ${MONITORING_SCHEME}://${REPLICA_31_HOST}/health"
