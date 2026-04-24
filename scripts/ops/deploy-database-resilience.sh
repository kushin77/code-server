#!/usr/bin/env bash
# @file        scripts/ops/deploy-database-resilience.sh
# @module      ops/deployment
# @description Deploy database resilience and high-availability modules
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

DEPLOY_LAYER="${DEPLOY_LAYER:-all}"
DRY_RUN="${DRY_RUN:-0}"
REPLICAS="${REPLICAS:-}"
SSH_USER="${SSH_USER:-${DEPLOY_USER:-}}"
SSH_KEY="${SSH_KEY:-${ONPREM_SSH_KEY:-$HOME/.ssh/id_rsa_onprem}}"
PRIMARY_HOST="${PRIMARY_HOST:-${DEPLOY_HOST:-${REPLICA_1_IP:-}}}"
REPLICA_HOST="${REPLICA_HOST:-${REPLICA_2_IP:-}}"
ARBITER_HOST="${ARBITER_HOST:-${REPLICA_3_IP:-${ARBITER_IP:-}}}"
NAS_HOST="${NAS_HOST:-}"
NAS_MOUNT_POINT="${NAS_MOUNT_POINT:-/mnt/nas/persistent}"

require_value() {
	local value="$1"
	local message="$2"

	if [[ -z "$value" ]]; then
		log_fatal "$message"
	fi
}

run_step() {
	local name="$1"
	local script="$2"

	log_info "=== ${name} ==="

	if [[ "$DRY_RUN" == "1" ]]; then
		log_info "[DRY-RUN] Would run: bash ${script}"
		return 0
	fi

	if [[ ! -f "$script" ]]; then
		log_fatal "Missing required script: $script"
	fi

	bash "$script"
}

resolve_replicas() {
	if [[ -n "$REPLICAS" ]]; then
		return 0
	fi

	if [[ -n "${REPLICA_1_IP:-}" && -n "${REPLICA_2_IP:-}" ]]; then
		REPLICAS="${REPLICA_1_IP},${REPLICA_2_IP}"
		return 0
	fi

	log_fatal "Set REPLICAS or REPLICA_1_IP/REPLICA_2_IP before deploying database resilience"
}

export SSH_USER SSH_KEY REPLICAS PRIMARY_HOST REPLICA_HOST ARBITER_HOST NAS_HOST NAS_MOUNT_POINT

if [[ -z "$SSH_USER" ]]; then
	log_fatal "Set SSH_USER or DEPLOY_USER before deploying database resilience"
fi

resolve_replicas

log_info "Deploying database resilience for replicas: $REPLICAS"
log_info "Selected layer: $DEPLOY_LAYER"

if [[ "$DEPLOY_LAYER" == "all" ]]; then
	run_step "Pre-flight checks" "${REPO_ROOT}/scripts/ops/pre-flight-deployment-check.sh"
	run_step "NAS validation" "${REPO_ROOT}/scripts/ops/validate-nas-mount.sh"
fi

case "$DEPLOY_LAYER" in
	all)
		run_step "PostgreSQL replication" "${REPO_ROOT}/scripts/ops/setup-postgres-replication.sh"
		run_step "Database backup strategy" "${REPO_ROOT}/scripts/ops/setup-database-backup-strategy.sh"
		run_step "Enhanced health checks" "${REPO_ROOT}/scripts/ops/setup-enhanced-health-checks.sh"
		run_step "Automated failover monitoring" "${REPO_ROOT}/scripts/ops/setup-automated-failover-monitoring.sh"
		run_step "Network partition recovery" "${REPO_ROOT}/scripts/ops/setup-network-partition-recovery.sh"
		;;
	replication)
		run_step "PostgreSQL replication" "${REPO_ROOT}/scripts/ops/setup-postgres-replication.sh"
		;;
	backup)
		run_step "Database backup strategy" "${REPO_ROOT}/scripts/ops/setup-database-backup-strategy.sh"
		;;
	health)
		run_step "Enhanced health checks" "${REPO_ROOT}/scripts/ops/setup-enhanced-health-checks.sh"
		;;
	failover)
		run_step "Automated failover monitoring" "${REPO_ROOT}/scripts/ops/setup-automated-failover-monitoring.sh"
		;;
	partition)
		run_step "Network partition recovery" "${REPO_ROOT}/scripts/ops/setup-network-partition-recovery.sh"
		;;
	*)
		log_fatal "Unknown DEPLOY_LAYER: $DEPLOY_LAYER"
		;;
esac

log_info "Database resilience deployment complete"
log_info "Layer deployed: $DEPLOY_LAYER"
