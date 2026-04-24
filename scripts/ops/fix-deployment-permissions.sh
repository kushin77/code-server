#!/usr/bin/env bash
# @file        scripts/ops/fix-deployment-permissions.sh
# @module      ops/hygiene
# @description Fix deployment directory permissions on cluster nodes
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

REPLICAS="${REPLICAS:-}"
SSH_USER="${SSH_USER:-${DEPLOY_USER:-}}"
SSH_KEY="${SSH_KEY:-${ONPREM_SSH_KEY:-$HOME/.ssh/id_rsa_onprem}}"
REPO_HOME="${REPO_HOME:-/home/${SSH_USER}}"
REPO_PATH="${REPO_PATH:-${REPO_HOME}/code-server-enterprise}"
DOCKER_DIR="${DOCKER_DIR:-${REPO_HOME}/.docker}"
DRY_RUN="${DRY_RUN:-0}"

require_value() {
	local value="$1"
	local message="$2"

	if [[ -z "$value" ]]; then
		log_fatal "$message"
	fi
}

resolve_replicas() {
	if [[ -n "$REPLICAS" ]]; then
		return 0
	fi

	if [[ -n "${REPLICA_1_IP:-}" && -n "${REPLICA_2_IP:-}" ]]; then
		REPLICAS="${REPLICA_1_IP},${REPLICA_2_IP}"
		return 0
	fi

	log_fatal "Set REPLICAS or REPLICA_1_IP/REPLICA_2_IP before fixing deployment permissions"
}

fix_permissions_on_host() {
	local host="$1"

	log_info "Fixing permissions on $host"

	if [[ "$DRY_RUN" == "1" ]]; then
		log_info "[DRY-RUN] Would run ownership fixes on $host"
		return 0
	fi

	ssh -i "$SSH_KEY" "$SSH_USER@$host" bash -s <<EOF
set -euo pipefail
for dir in "$REPO_PATH" "$DOCKER_DIR"; do
  if [[ -d "\$dir" ]]; then
	sudo chown -R "$SSH_USER:$SSH_USER" "\$dir"
  fi
done
EOF
}

require_value "$SSH_USER" "Set SSH_USER or DEPLOY_USER before fixing deployment permissions"
resolve_replicas

log_info "Fixing permissions on replicas: $REPLICAS"

IFS=',' read -ra replica_array <<< "$REPLICAS"
for replica in "${replica_array[@]}"; do
	replica="${replica// /}"
	[[ -z "$replica" ]] && continue
	fix_permissions_on_host "$replica"
done

log_info "Deployment permissions fixed"
