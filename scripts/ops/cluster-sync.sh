#!/usr/bin/env bash
# @file        scripts/ops/cluster-sync.sh
# @module      ops/deployment
# @description Idempotent cluster synchronization: ensures all replicas run identical
#              code (same git commit), identical .env (bootstrapped per replica mode),
#              and identical docker-compose services. IaC, immutable, idempotent.
#              Safe to run multiple times — converges cluster to desired state.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

REPLICA_1_HOST="${REPLICA_1_HOST:-192.168.168.31}"
REPLICA_2_HOST="${REPLICA_2_HOST:-192.168.168.42}"
SSH_USER="${SSH_USER:-akushnir}"
REPO_DIR="${REPO_DIR:-code-server-enterprise}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_GIT_PULL="${SKIP_GIT_PULL:-0}"

# Expected minimum service count per replica
MIN_SERVICES="${MIN_SERVICES:-17}"

# ============================================================================
# HELPERS
# ============================================================================

run_on() {
  local host="$1"; shift
  ssh "${SSH_USER}@${host}" "$@"
}

scp_to() {
  local src="$1"
  local host="$2"
  local dst="$3"
  scp "${src}" "${SSH_USER}@${host}:${dst}"
}

replica_healthy() {
  local host="$1"
  local count
  count=$(run_on "${host}" "cd ${REPO_DIR} && docker-compose ps --format '{{.Names}}' | wc -l" 2>/dev/null || echo 0)
  [[ "${count}" -ge "${MIN_SERVICES}" ]]
}

service_count() {
  local host="$1"
  run_on "${host}" "cd ${REPO_DIR} && docker-compose ps --format '{{.Names}}' | wc -l" 2>/dev/null || echo 0
}

get_commit() {
  local host="$1"
  run_on "${host}" "cd ${REPO_DIR} && git rev-parse HEAD" 2>/dev/null || echo "unknown"
}

get_local_commit() {
  git -C "$(dirname "${SCRIPT_DIR}")" rev-parse HEAD 2>/dev/null || echo "unknown"
}

bootstrap_env_on() {
  local host="$1"
  local mode="$2"  # primary | secondary
  log_info "  Bootstrapping .env on ${host} (mode=${mode})"
  if [[ "${DRY_RUN}" == "0" ]]; then
    run_on "${host}" "cd ${REPO_DIR} && REPLICA_MODE=${mode} ENV_FILE=.env bash scripts/ops/bootstrap-env.sh"
  else
    log_info "  [DRY_RUN] Would run bootstrap-env.sh on ${host}"
  fi
}

deploy_on() {
  local host="$1"
  log_info "  Running docker-compose up -d on ${host}"
  if [[ "${DRY_RUN}" == "0" ]]; then
    run_on "${host}" "cd ${REPO_DIR} && docker-compose up -d 2>&1 | grep -E 'Starting|Started|Running|Healthy|Error' | tail -10" || true
  else
    log_info "  [DRY_RUN] Would run docker-compose up -d on ${host}"
  fi
}

verify_on() {
  local host="$1"
  local label="$2"
  local count
  count=$(service_count "${host}")
  if [[ "${count}" -lt "${MIN_SERVICES}" ]]; then
    log_error "${label} (${host}): only ${count} services running (need ${MIN_SERVICES}+)"
    return 1
  fi
  local crashing
  crashing=$(run_on "${host}" "cd ${REPO_DIR} && docker-compose ps --format '{{.Names}}\t{{.Status}}' | grep -c 'Restarting'" 2>/dev/null || echo 0)
  if [[ "${crashing}" -gt 0 ]]; then
    log_error "${label} (${host}): ${crashing} service(s) in Restarting state"
    run_on "${host}" "cd ${REPO_DIR} && docker-compose ps --format '{{.Names}}\t{{.Status}}' | grep Restarting" || true
    return 1
  fi
  log_info "${label} (${host}): ✅ ${count} services, 0 restarting"
}

# ============================================================================
# PHASES
# ============================================================================

phase_git_sync() {
  log_info "--- Phase 1: Git Synchronization ---"
  local local_commit
  local_commit="$(get_local_commit)"
  log_info "Local HEAD : ${local_commit}"

  for host in "${REPLICA_1_HOST}" "${REPLICA_2_HOST}"; do
    local remote_commit
    remote_commit="$(get_commit "${host}")"
    log_info "  ${host}: ${remote_commit}"

    if [[ "${remote_commit}" != "${local_commit}" ]]; then
      log_warn "  ${host}: commit mismatch — pulling latest"
      if [[ "${DRY_RUN}" == "0" ]] && [[ "${SKIP_GIT_PULL}" == "0" ]]; then
        run_on "${host}" "cd ${REPO_DIR} && git fetch origin && git reset --hard origin/main" 2>&1 | tail -3
      fi
    else
      log_info "  ${host}: ✅ up to date"
    fi
  done
}

phase_env_bootstrap() {
  log_info ""
  log_info "--- Phase 2: Environment Bootstrap ---"

  log_info "Replica 1 (${REPLICA_1_HOST}) — primary mode"
  bootstrap_env_on "${REPLICA_1_HOST}" "primary"

  log_info "Replica 2 (${REPLICA_2_HOST}) — secondary mode (avoids K8s port conflicts)"
  bootstrap_env_on "${REPLICA_2_HOST}" "secondary"
}

phase_deploy() {
  log_info ""
  log_info "--- Phase 3: Service Deployment (Parallel) ---"

  # Deploy both replicas in parallel as per cluster architecture requirements
  log_info "Deploying both replicas simultaneously..."
  if [[ "${DRY_RUN}" == "0" ]]; then
    deploy_on "${REPLICA_1_HOST}" &
    local pid1=$!
    deploy_on "${REPLICA_2_HOST}" &
    local pid2=$!
    wait "${pid1}" && wait "${pid2}"
  else
    log_info "[DRY_RUN] Would deploy both replicas in parallel"
  fi
}

phase_verify() {
  log_info ""
  log_info "--- Phase 4: Health Verification ---"
  local failed=0

  verify_on "${REPLICA_1_HOST}" "Replica 1" || ((failed++)) || true
  verify_on "${REPLICA_2_HOST}" "Replica 2" || ((failed++)) || true

  if [[ "${failed}" -gt 0 ]]; then
    log_error "${failed} replica(s) failed health check"
    return 1
  fi

  log_info ""
  log_info "✅ Cluster sync complete — both replicas healthy"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  log_info "==================================================="
  log_info "KC Cluster-Sync — IaC, Immutable, Idempotent"
  log_info "==================================================="
  log_info "Replica 1   : ${REPLICA_1_HOST}"
  log_info "Replica 2   : ${REPLICA_2_HOST}"
  log_info "DRY_RUN     : ${DRY_RUN}"
  log_info "SKIP_GIT_PULL: ${SKIP_GIT_PULL}"
  log_info ""

  phase_git_sync
  phase_env_bootstrap
  phase_deploy
  phase_verify
}

main "$@"
