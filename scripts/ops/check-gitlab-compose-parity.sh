#!/usr/bin/env bash
set -euo pipefail

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

log_info() {
  echo "[INFO] $*"
}

log_error() {
  echo "[ERROR] $*" >&2
}

log_warning() {
  echo "[WARN] $*"
}

# Verify the canonical GitLab compose config is in sync across both hosts.
# Usage:
#   scripts/ops/check-gitlab-compose-parity.sh [primary_host] [replica_host]

PRIMARY_HOST="${1:-192.168.168.31}"
REPLICA_HOST="${2:-192.168.168.42}"
REMOTE_USER="${REMOTE_USER:-akushnir}"
REMOTE_COMPOSE_PATH="${REMOTE_COMPOSE_PATH:-~/code-server-enterprise/docker-compose.enterprise.yml}"
LOCAL_COMPOSE_PATH="${LOCAL_COMPOSE_PATH:-docker-compose.enterprise.yml}"

if [[ ! -f "${LOCAL_COMPOSE_PATH}" ]]; then
  log_error "Local compose file not found: ${LOCAL_COMPOSE_PATH}"
  exit 1
fi

LOCAL_SHA="$(sha256sum "${LOCAL_COMPOSE_PATH}" | awk '{print $1}')"
log_info "Local compose sha256: ${LOCAL_SHA}"

check_host() {
  local host="$1"
  local role="$2"

  log_info "Checking ${role} host ${host}..."

  local remote_sha
  remote_sha="$((ssh -o BatchMode=yes "${REMOTE_USER}@${host}" "sha256sum ${REMOTE_COMPOSE_PATH}" 2>/dev/null || true) | awk '{print $1}')"
  if [[ -z "${remote_sha}" ]]; then
    log_error "Could not read remote compose checksum on ${host}"
    return 1
  fi

  log_info "${role} compose sha256: ${remote_sha}"
  if [[ "${remote_sha}" != "${LOCAL_SHA}" ]]; then
    log_error "${role} compose drift detected"
    return 1
  fi

  ssh -o BatchMode=yes "${REMOTE_USER}@${host}" \
    "grep -Fq \"DB_NAME:-gitlabdb\" ${REMOTE_COMPOSE_PATH}"
  ssh -o BatchMode=yes "${REMOTE_USER}@${host}" \
    "! grep -Eq \"redis_host|redis_database\" ${REMOTE_COMPOSE_PATH}"
  ssh -o BatchMode=yes "${REMOTE_USER}@${host}" \
    "grep -Fq \"worker_processes\" ${REMOTE_COMPOSE_PATH}"
  ssh -o BatchMode=yes "${REMOTE_USER}@${host}" \
    "grep -Fq \"= 0\" ${REMOTE_COMPOSE_PATH}"
  ssh -o BatchMode=yes "${REMOTE_USER}@${host}" \
    "grep -q \"memory: 4G\" ${REMOTE_COMPOSE_PATH}"

  local help_code
  help_code="$(ssh -o BatchMode=yes "${REMOTE_USER}@${host}" "curl -s -o /dev/null -w '%{http_code}' http://localhost:8101/help || true")"
  log_info "${role} /help status: ${help_code}"
  if [[ "${help_code}" != "200" ]]; then
    log_error "${role} GitLab endpoint is not healthy"
    return 1
  fi

  local gitlab_state
  gitlab_state="$(ssh -o BatchMode=yes "${REMOTE_USER}@${host}" "docker inspect code-server-gitlab --format 'health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} restarts={{.RestartCount}}'")"
  log_info "${role} GitLab state: ${gitlab_state}"

  local unhealthy
  unhealthy="$(ssh -o BatchMode=yes "${REMOTE_USER}@${host}" "docker ps --format '{{.Names}} {{.Status}}' | awk '/unhealthy|Restarting/' || true")"
  if [[ -n "${unhealthy}" ]]; then
    log_warning "${role} has non-healthy containers:"
    echo "${unhealthy}"
  else
    log_info "${role} has no unhealthy/restarting containers"
  fi
}

check_host "${PRIMARY_HOST}" "primary"
check_host "${REPLICA_HOST}" "replica"

log_info "GitLab compose parity and endpoint checks passed"
