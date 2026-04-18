#!/usr/bin/env bash
# @file        scripts/operations/redeploy/onprem/failover-orchestrate.sh
# @module      operations/redeploy
# @description orchestrate deterministic failover or failback between .31 and .42 with health gates and evidence output
#

set -euo pipefail

if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SCRIPT_DIR="$(pwd)/scripts/operations/redeploy/onprem"
fi

if [[ -f "$SCRIPT_DIR/../../../_common/init.sh" ]]; then
  source "$SCRIPT_DIR/../../../_common/init.sh"
elif [[ -f "$(pwd)/scripts/_common/init.sh" ]]; then
  source "$(pwd)/scripts/_common/init.sh"
else
  echo "FATAL: unable to locate scripts/_common/init.sh" >&2
  exit 1
fi

PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
TARGET_USER="${TARGET_USER:-${DEPLOY_USER:-akushnir}}"
PRIMARY_REPO="${PRIMARY_REPO:-~/code-server-enterprise}"
REPLICA_REPO="${REPLICA_REPO:-~/code-server-enterprise-replica}"
PRIMARY_COMPOSE_BIN="${PRIMARY_COMPOSE_BIN:-docker-compose}"
REPLICA_COMPOSE_BIN="${REPLICA_COMPOSE_BIN:-docker-compose}"
SSH_BIN="${SSH_BIN:-ssh}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
SSH_TIMEOUT="${SSH_TIMEOUT:-8}"
EXEC_MODE="${EXEC_MODE:-ssh}"
ACTION="status"
LOCK_KEY="code-server-failover"
ACTIVE_HOST_STATE_FILE="${ACTIVE_HOST_STATE_FILE:-/tmp/code-server-active-host.state}"
EVIDENCE_DIR="${EVIDENCE_DIR:-/tmp/code-server-failover-evidence}"
LOCK_DIR="/tmp/${LOCK_KEY}.lock"
LOCK_HOST=""

usage() {
  cat <<'EOF'
Usage: failover-orchestrate.sh [--action ACTION] [--ssh-key PATH] [--ssh-bin CMD]

Actions:
  status    Show primary/replica health + active-host marker state (default)
  promote   Promote replica (.42) path and mark active host as replica
  failback  Return active host marker to primary (.31) after health gates

Options:
  --action ACTION       status|promote|failback
  --mode MODE           ssh|local-on-host (default: ssh)
  --ssh-key PATH        SSH private key for deterministic auth
  --ssh-bin CMD         SSH client binary (ssh, ssh.exe)
  --primary-host HOST   Override primary host IP/name
  --replica-host HOST   Override replica host IP/name
  --user USER           Override remote SSH user
  --primary-repo PATH   Repo path on primary host
  --replica-repo PATH   Repo path on replica host
  --primary-compose CMD Compose binary on primary host
  --replica-compose CMD Compose binary on replica host
  --lock-key KEY        Lock namespace key
  --help                Show this help

Environment:
  PRIMARY_HOST, REPLICA_HOST, TARGET_USER, PRIMARY_REPO, REPLICA_REPO,
  PRIMARY_COMPOSE_BIN, REPLICA_COMPOSE_BIN, SSH_BIN, SSH_KEY_PATH, SSH_TIMEOUT,
  ACTIVE_HOST_STATE_FILE, EVIDENCE_DIR
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --action)
        ACTION="$2"
        shift 2
        ;;
      --mode)
        EXEC_MODE="$2"
        shift 2
        ;;
      --ssh-key)
        SSH_KEY_PATH="$2"
        shift 2
        ;;
      --ssh-bin)
        SSH_BIN="$2"
        shift 2
        ;;
      --primary-host)
        PRIMARY_HOST="$2"
        shift 2
        ;;
      --replica-host)
        REPLICA_HOST="$2"
        shift 2
        ;;
      --user)
        TARGET_USER="$2"
        shift 2
        ;;
      --primary-repo)
        PRIMARY_REPO="$2"
        shift 2
        ;;
      --replica-repo)
        REPLICA_REPO="$2"
        shift 2
        ;;
      --primary-compose)
        PRIMARY_COMPOSE_BIN="$2"
        shift 2
        ;;
      --replica-compose)
        REPLICA_COMPOSE_BIN="$2"
        shift 2
        ;;
      --lock-key)
        LOCK_KEY="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_fatal "Unknown argument: $1"
        ;;
    esac
  done
}

ssh_common_args() {
  local -a args
  args=(
    -o BatchMode=yes
    -o ConnectTimeout="${SSH_TIMEOUT}"
    -o StrictHostKeyChecking=accept-new
  )

  if [[ -n "$SSH_KEY_PATH" ]]; then
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
      log_fatal "SSH key path does not exist: ${SSH_KEY_PATH}"
    fi
    args+=( -i "$SSH_KEY_PATH" )
  fi

  printf '%s\n' "${args[@]}"
}

remote() {
  local host="$1"
  local cmd="$2"
  local -a args
  mapfile -t args < <(ssh_common_args)
  "$SSH_BIN" "${args[@]}" "${TARGET_USER}@${host}" "$cmd"
}

run_primary_cmd() {
  local cmd="$1"
  if [[ "$EXEC_MODE" == "local-on-host" ]]; then
    bash -lc "$cmd"
  else
    remote "$PRIMARY_HOST" "$cmd"
  fi
}

run_replica_cmd() {
  local cmd="$1"
  remote "$REPLICA_HOST" "$cmd"
}

check_reachability() {
  local host="$1"
  local -a args
  mapfile -t args < <(ssh_common_args)
  if ! "$SSH_BIN" "${args[@]}" "${TARGET_USER}@${host}" "echo OK" >/dev/null 2>&1; then
    if [[ "${SSH_BIN}" == "ssh" ]] && command -v ssh.exe >/dev/null 2>&1; then
      log_warn "Default ssh failed; retrying with ssh.exe for Windows agent compatibility"
      SSH_BIN="ssh.exe"
      if ! "$SSH_BIN" "${args[@]}" "${TARGET_USER}@${host}" "echo OK" >/dev/null 2>&1; then
        log_fatal "SSH reachability failed for ${TARGET_USER}@${host}"
      fi
    else
      log_fatal "SSH reachability failed for ${TARGET_USER}@${host}"
    fi
  fi
}

replica_ingress_health() {
  local attempts=3
  local i=0

  for i in $(seq 1 "$attempts"); do
    if run_replica_cmd "curl --max-time 5 -fsS http://127.0.0.1:18080/oauth2/start?rd=/ >/dev/null"; then
      echo healthy
      return 0
    fi
    sleep 1
  done

  echo unhealthy
  return 1
}

acquire_lock() {
  run_primary_cmd "set -euo pipefail; if mkdir '${LOCK_DIR}' 2>/dev/null; then printf '%s\\n' '$$' > '${LOCK_DIR}/owner.pid'; echo LOCK_OK; else echo LOCK_BUSY; exit 2; fi"
  LOCK_HOST="$PRIMARY_HOST"
}

release_lock() {
  if [[ -z "$LOCK_HOST" ]]; then
    return 0
  fi

  run_primary_cmd "set -euo pipefail; rm -f '${LOCK_DIR}/owner.pid' || true; rmdir '${LOCK_DIR}' || true" >/dev/null 2>&1 || true
}

primary_health() {
  local state
  state="$(run_primary_cmd "set -euo pipefail; if docker inspect code-server >/dev/null 2>&1; then docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' code-server; else echo missing; fi")"
  if [[ "$state" == "healthy" || "$state" == "running" ]]; then
    echo HEALTHY
    return 0
  fi
  echo UNHEALTHY
  return 1
}

replica_health() {
  local state
  state="$(run_replica_cmd "set -euo pipefail; if docker inspect code-server >/dev/null 2>&1; then docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' code-server; else echo missing; fi")"
  if [[ "$state" == "healthy" || "$state" == "running" ]]; then
    echo HEALTHY
    return 0
  fi
  echo UNHEALTHY
  return 1
}

write_active_host_marker() {
  local marker_host="$1"
  run_primary_cmd "set -euo pipefail; echo ${marker_host} > ${ACTIVE_HOST_STATE_FILE}; cat ${ACTIVE_HOST_STATE_FILE}"
}

collect_health_snapshot() {
  local ts
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  local primary_state
  local replica_state
  local active_state

  primary_state="$(primary_health 2>/dev/null || echo UNHEALTHY)"
  replica_state="$(replica_health 2>/dev/null || echo UNHEALTHY)"
  active_state="$(run_primary_cmd "cat ${ACTIVE_HOST_STATE_FILE} 2>/dev/null || echo ${PRIMARY_HOST}")"

  run_primary_cmd "mkdir -p ${EVIDENCE_DIR}"
  run_primary_cmd "cat > ${EVIDENCE_DIR}/failover-${ts}.json <<'EOF'
{
  \"timestamp_utc\": \"${ts}\",
  \"action\": \"${ACTION}\",
  \"primary_host\": \"${PRIMARY_HOST}\",
  \"replica_host\": \"${REPLICA_HOST}\",
  \"primary_health\": \"${primary_state}\",
  \"replica_health\": \"${replica_state}\",
  \"active_host\": \"${active_state}\"
}
EOF"
  log_info "Evidence written: ${EVIDENCE_DIR}/failover-${ts}.json"
}

run_primary_redeploy() {
  run_primary_cmd "set -euo pipefail; cd ${PRIMARY_REPO}; bash scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh --mode local-on-host --fix-stale-logs; bash scripts/operations/redeploy/onprem/redeploy-remote-execute.sh --mode local-on-host --fix-stale-logs"
}

run_replica_promote() {
  # Replica path uses docker/docker-compose.yml to avoid host conflicts with db/cache services.
  run_replica_cmd "set -euo pipefail; cd ${REPLICA_REPO}; set -a; [ -f .env ] && . ./.env || true; set +a; ${REPLICA_COMPOSE_BIN} -f docker/docker-compose.yml up -d code-server oauth2-proxy code-server-profile-backup"

  # Ensure alternate ingress endpoint exists for validation when 80/443 are unavailable.
  run_replica_cmd "set -euo pipefail; cd ${REPLICA_REPO}; cat > /tmp/Caddyfile.replica <<'EOF'
:80 {
  reverse_proxy oauth2-proxy:4180
}
EOF
docker rm -f caddy-replica >/dev/null 2>&1 || true
docker run -d --name caddy-replica --restart unless-stopped --network docker_enterprise -p 18080:80 -v /tmp/Caddyfile.replica:/etc/caddy/Caddyfile:ro caddy:2.7.6 >/dev/null
for i in \$(seq 1 15); do
  if curl -fsS http://127.0.0.1:18080/oauth2/start?rd=/ >/dev/null; then
    exit 0
  fi
  sleep 2
done
exit 1"
}

status_report() {
  log_section "Failover Status"
  local active_marker
  active_marker="$(run_primary_cmd "cat ${ACTIVE_HOST_STATE_FILE} 2>/dev/null || echo ${PRIMARY_HOST}")"
  log_info "Active host marker: ${active_marker}"
  log_info "Primary health: $(primary_health)"
  log_info "Replica health: $(replica_health)"
  log_info "Replica ingress check: $(replica_ingress_health || true)"
}

promote_replica() {
  log_section "Promote Replica"
  run_replica_promote
  replica_health >/dev/null
  write_active_host_marker "$REPLICA_HOST" >/dev/null
  log_success "Replica promotion gates passed and active marker updated"
}

failback_primary() {
  log_section "Failback Primary"
  run_primary_redeploy
  primary_health >/dev/null
  write_active_host_marker "$PRIMARY_HOST" >/dev/null
  log_success "Primary failback gates passed and active marker updated"
}

main() {
  parse_args "$@"

  case "$ACTION" in
    status|promote|failback)
      ;;
    *)
      log_fatal "Invalid --action '${ACTION}'. Allowed: status|promote|failback"
      ;;
  esac

  require_command "$SSH_BIN"
  if [[ "$EXEC_MODE" != "local-on-host" ]]; then
    check_reachability "$PRIMARY_HOST"
  fi
  check_reachability "$REPLICA_HOST"

  trap release_lock EXIT INT TERM
  acquire_lock >/dev/null || log_fatal "Another redeploy/failover actor is active on ${PRIMARY_HOST}"

  case "$ACTION" in
    status)
      status_report
      ;;
    promote)
      promote_replica
      status_report
      ;;
    failback)
      failback_primary
      status_report
      ;;
  esac

  collect_health_snapshot
}

main "$@"
