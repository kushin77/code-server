#!/usr/bin/env bash
# @file        scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh
# @module      operations/redeploy
# @description on-prem redeploy preflight checks and stale-session hygiene
#

set -euo pipefail

if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SCRIPT_DIR="$(pwd)/scripts/operations/redeploy/preflight/onprem"
fi

if [[ -f "$SCRIPT_DIR/../../../../_common/init.sh" ]]; then
  source "$SCRIPT_DIR/../../../../_common/init.sh"
elif [[ -f "$(pwd)/scripts/_common/init.sh" ]]; then
  source "$(pwd)/scripts/_common/init.sh"
else
  echo "FATAL: unable to locate scripts/_common/init.sh" >&2
  exit 1
fi

TARGET_HOST="${TARGET_HOST:-${DEPLOY_HOST:-192.168.168.31}}"
TARGET_USER="${TARGET_USER:-${DEPLOY_USER:-akushnir}}"
TARGET_REPO="${TARGET_REPO:-~/code-server-enterprise}"
EXEC_MODE="${EXEC_MODE:-auto}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
SSH_BIN="${SSH_BIN:-ssh}"
PRECHECK_SSH_TIMEOUT="${PRECHECK_SSH_TIMEOUT:-8}"
FIX_STALE_LOGS="false"
MAX_LOG_TAIL_AGE_SEC="${MAX_LOG_TAIL_AGE_SEC:-3600}"

usage() {
  cat <<'EOF'
Usage: redeploy-preflight.sh [--fix-stale-logs] [--host HOST] [--user USER] [--repo PATH] [--mode MODE] [--ssh-key PATH]

Options:
  --fix-stale-logs   Kill stale remote docker-compose logs -f processes older than threshold.
  --host HOST        Remote host. Default: 192.168.168.31
  --user USER        Remote SSH user. Default: akushnir
  --repo PATH        Remote repository path. Default: ~/code-server-enterprise
  --mode MODE        Connection mode: auto|ssh|local-on-host. Default: auto
  --ssh-key PATH     SSH private key path for deterministic auth.
  --ssh-bin CMD      SSH client binary (e.g. ssh, ssh.exe). Default: ssh
  -h, --help         Show this help text.

Environment:
  TARGET_HOST, TARGET_USER, TARGET_REPO, EXEC_MODE, SSH_KEY_PATH, SSH_BIN, PRECHECK_SSH_TIMEOUT, MAX_LOG_TAIL_AGE_SEC
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fix-stale-logs)
        FIX_STALE_LOGS="true"
        shift
        ;;
      --host)
        TARGET_HOST="$2"
        shift 2
        ;;
      --user)
        TARGET_USER="$2"
        shift 2
        ;;
      --repo)
        TARGET_REPO="$2"
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

remote() {
  local cmd="$1"
  local local_host
  local local_user
  local_host="$(hostname 2>/dev/null || true)"
  local_user="$(whoami 2>/dev/null || true)"

  if [[ "${EXEC_MODE}" == "local-on-host" ]] || [[ "${EXEC_MODE}" == "auto" && ( "${TARGET_HOST}" == "localhost" || "${TARGET_HOST}" == "127.0.0.1" || "${TARGET_HOST}" == "${local_host}" ) && "${TARGET_USER}" == "${local_user}" ]]; then
    bash -lc "$cmd"
    return 0
  fi

  local -a ssh_args
  ssh_args=(
    -o BatchMode=yes
    -o ConnectTimeout="${PRECHECK_SSH_TIMEOUT}"
    -o StrictHostKeyChecking=accept-new
  )

  if [[ -n "${SSH_KEY_PATH}" ]]; then
    if [[ ! -f "${SSH_KEY_PATH}" ]]; then
      log_fatal "SSH key path does not exist: ${SSH_KEY_PATH}"
    fi
    ssh_args+=( -i "${SSH_KEY_PATH}" )
  fi

  if ! "${SSH_BIN}" "${ssh_args[@]}" "${TARGET_USER}@${TARGET_HOST}" "echo OK" >/dev/null 2>&1; then
    log_error "Cannot establish non-interactive SSH session to ${TARGET_USER}@${TARGET_HOST}"
    log_error "Set SSH_KEY_PATH or run with --mode local-on-host directly on target host"
    log_error "If running from WSL, use --ssh-bin ssh.exe to use Windows SSH agent"
    log_error "Example: ssh ${TARGET_USER}@${TARGET_HOST} 'cd ~/code-server-enterprise && bash scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh --mode local-on-host --fix-stale-logs'"
    return 1
  fi

  "${SSH_BIN}" "${ssh_args[@]}" "${TARGET_USER}@${TARGET_HOST}" "$cmd"
}

check_local_prereqs() {
  log_section "Local Prerequisites"
  require_commands awk sed grep
  require_command "${SSH_BIN}"
  log_success "Local prerequisites satisfied"
}

check_remote_baseline() {
  log_section "Remote Baseline"

  remote "hostname; date" | sed 's/^/[remote] /'

  remote "test -d ${TARGET_REPO}" >/dev/null
  log_success "Remote repo exists: ${TARGET_REPO}"

  remote "cd ${TARGET_REPO} && git rev-parse --abbrev-ref HEAD && git rev-parse --short HEAD" | sed 's/^/[git] /'

  local dirty_summary
  dirty_summary=$(remote "cd ${TARGET_REPO} && git status --porcelain | cut -c1-2 | sort | uniq -c || true")
  if [[ -n "${dirty_summary}" ]]; then
    log_warn "Remote repo has working-tree changes"
    echo "${dirty_summary}" | sed 's/^/[git-dirty] /'
  else
    log_success "Remote repo working tree is clean"
  fi
}

check_redeploy_safety() {
  log_section "Redeploy Safety Checks"

  local docker_info_output

  if ! remote "command -v docker-compose >/dev/null 2>&1 || docker compose version >/dev/null 2>&1"; then
    log_error "Docker Compose is not available in execution environment"
    log_error "For Windows/WSL shells, enable Docker Desktop WSL integration or run on 192.168.168.31"
    return 1
  fi

  docker_info_output=$(remote "docker info 2>&1 || true")
  if echo "${docker_info_output}" | grep -Eqi "could not be found in this WSL 2 distro|cannot connect to the docker daemon|error during connect"; then
    log_error "Docker daemon is not reachable in execution environment"
    log_error "For Windows/WSL shells, enable Docker Desktop WSL integration or run on 192.168.168.31"
    return 1
  fi

  if ! remote "cd ${TARGET_REPO} && (docker-compose config >/dev/null 2>&1 || docker compose config >/dev/null 2>&1)"; then
    log_error "Compose configuration validation failed in execution environment"
    log_error "Ensure Docker/Compose is installed and reachable in the target runtime"
    log_error "For production validation, run from 192.168.168.31 with --mode local-on-host"
    return 1
  fi
  log_success "Compose configuration renders successfully"

  local compose_ps_output
  if compose_ps_output=$(remote "cd ${TARGET_REPO} && (docker-compose ps || docker compose ps)" 2>&1); then
    echo "${compose_ps_output}" | sed 's/^/[compose] /'
    if echo "${compose_ps_output}" | grep -Eqi "could not be found in this WSL 2 distro|cannot connect to the docker daemon|error during connect"; then
      log_error "Compose process inspection indicates Docker is unavailable in runtime"
      return 1
    fi
  else
    echo "${compose_ps_output}" | sed 's/^/[compose] /'
    log_warn "Unable to fetch compose process table from execution environment"
  fi

  local deploy_procs
  deploy_procs=$(remote "ps -eo pid=,etimes=,cmd= | awk '/terraform apply|docker-compose logs -f|docker compose logs -f|docker-compose up -d|docker compose up -d/ && !/awk/ && !/grep/ {print}' || true")
  if [[ -n "${deploy_procs}" ]]; then
    log_warn "Active deploy-related processes detected"
    echo "${deploy_procs}" | sed 's/^/[proc] /'
  else
    log_success "No active deploy-related long-running process detected"
  fi
}

cleanup_stale_log_tails() {
  if [[ "${FIX_STALE_LOGS}" != "true" ]]; then
    return 0
  fi

  log_section "Stale Log Tail Cleanup"

  local stale_pids
  stale_pids=$(remote "ps -eo pid=,etimes=,cmd= | awk '\$2>${MAX_LOG_TAIL_AGE_SEC} && /docker-compose logs -f|docker compose logs -f/ {print \$1}' || true")

  if [[ -z "${stale_pids}" ]]; then
    log_success "No stale docker-compose logs -f processes older than ${MAX_LOG_TAIL_AGE_SEC}s"
    return 0
  fi

  echo "${stale_pids}" | sed 's/^/[stale-pid] /'
  remote "echo '${stale_pids}' | xargs -r kill"
  log_success "Stale docker-compose log tail processes terminated"
}

main() {
  parse_args "$@"

  if [[ "${EXEC_MODE}" != "auto" && "${EXEC_MODE}" != "ssh" && "${EXEC_MODE}" != "local-on-host" ]]; then
    log_fatal "Invalid --mode value: ${EXEC_MODE}. Allowed: auto, ssh, local-on-host"
  fi

  check_local_prereqs
  check_remote_baseline
  check_redeploy_safety
  cleanup_stale_log_tails
  log_success "On-prem redeploy preflight completed"
}

main "$@"
