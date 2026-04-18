#!/usr/bin/env bash
# @file        scripts/operations/redeploy/onprem/redeploy-remote-execute.sh
# @module      operations/redeploy
# @description run deterministic on-prem redeploy over ssh with immutable and idempotent checks
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../_common/init.sh"

TARGET_HOST="${TARGET_HOST:-${DEPLOY_HOST:-192.168.168.31}}"
TARGET_USER="${TARGET_USER:-${DEPLOY_USER:-akushnir}}"
TARGET_REPO="${TARGET_REPO:-~/code-server-enterprise}"
COMPOSE_BIN="${COMPOSE_BIN:-auto}"
RESOLVED_COMPOSE_BIN=""
EXEC_MODE="${EXEC_MODE:-auto}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
SSH_BIN="${SSH_BIN:-ssh}"
REDEPLOY_SSH_TIMEOUT="${REDEPLOY_SSH_TIMEOUT:-8}"
FIX_STALE_LOGS="false"
DRY_RUN="false"
ALLOW_RECREATE="false"
ALL_SERVICES="false"
REDEPLOY_SERVICES="code-server oauth2-proxy caddy postgres redis pgbouncer"

usage() {
  cat <<'EOF'
Usage: redeploy-remote-execute.sh [--host HOST] [--user USER] [--repo PATH] [--compose-bin CMD] [--mode MODE] [--ssh-key PATH] [--ssh-bin CMD] [--fix-stale-logs] [--dry-run] [--allow-recreate] [--all-services] [--services "svc1 svc2"]

Options:
  --host HOST         Remote host. Default: 192.168.168.31
  --user USER         Remote user. Default: akushnir
  --repo PATH         Remote repository path. Default: ~/code-server-enterprise
  --compose-bin CMD   docker compose command on remote host: auto|docker-compose|docker compose. Default: auto
  --mode MODE         Connection mode: auto|ssh|local-on-host. Default: auto
  --ssh-key PATH      SSH private key path for deterministic auth
  --ssh-bin CMD       SSH client binary (e.g. ssh, ssh.exe). Default: ssh
  --fix-stale-logs    Run remote stale log-tail cleanup as part of preflight
  --dry-run           Print remote commands without applying changes
  --allow-recreate    Allow compose to recreate resources when needed
  --all-services      Redeploy all compose services (may trigger prompts for drifted volumes)
  --services "..."    Space-separated service list to redeploy
  -h, --help          Show this help

Environment:
  TARGET_HOST, TARGET_USER, TARGET_REPO, COMPOSE_BIN, EXEC_MODE, SSH_KEY_PATH, SSH_BIN, REDEPLOY_SSH_TIMEOUT
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
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
      --compose-bin)
        COMPOSE_BIN="$2"
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
      --fix-stale-logs)
        FIX_STALE_LOGS="true"
        shift
        ;;
      --dry-run)
        DRY_RUN="true"
        shift
        ;;
      --allow-recreate)
        ALLOW_RECREATE="true"
        shift
        ;;
      --all-services)
        ALL_SERVICES="true"
        shift
        ;;
      --services)
        REDEPLOY_SERVICES="$2"
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
    -o ConnectTimeout="${REDEPLOY_SSH_TIMEOUT}"
    -o StrictHostKeyChecking=accept-new
  )

  if [[ -n "${SSH_KEY_PATH}" ]]; then
    if [[ ! -f "${SSH_KEY_PATH}" ]]; then
      log_fatal "SSH key path does not exist: ${SSH_KEY_PATH}"
    fi
    ssh_args+=( -i "${SSH_KEY_PATH}" )
  fi

  "${SSH_BIN}" "${ssh_args[@]}" "${TARGET_USER}@${TARGET_HOST}" "$cmd"
}

check_ssh_access() {
  log_section "SSH Reachability"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Skipping active SSH reachability check"
    return 0
  fi

  if [[ "${EXEC_MODE}" == "local-on-host" ]]; then
    log_success "Local-on-host mode selected; SSH reachability check not required"
    return 0
  fi

  local -a ssh_args
  ssh_args=(
    -o BatchMode=yes
    -o ConnectTimeout="${REDEPLOY_SSH_TIMEOUT}"
    -o StrictHostKeyChecking=accept-new
  )

  if [[ -n "${SSH_KEY_PATH}" ]]; then
    if [[ ! -f "${SSH_KEY_PATH}" ]]; then
      log_fatal "SSH key path does not exist: ${SSH_KEY_PATH}"
    fi
    ssh_args+=( -i "${SSH_KEY_PATH}" )
  fi

  if ! "${SSH_BIN}" "${ssh_args[@]}" "${TARGET_USER}@${TARGET_HOST}" "echo OK" >/dev/null 2>&1; then
    if [[ "${SSH_BIN}" == "ssh" ]] && command -v ssh.exe >/dev/null 2>&1; then
      log_warn "Default ssh failed; retrying with ssh.exe for Windows agent compatibility"
      SSH_BIN="ssh.exe"
      if ! "${SSH_BIN}" "${ssh_args[@]}" "${TARGET_USER}@${TARGET_HOST}" "echo OK" >/dev/null 2>&1; then
        log_error "SSH auth failed for ${TARGET_USER}@${TARGET_HOST}."
        log_error "Set SSH_KEY_PATH or run from target host with --mode local-on-host"
        log_fatal "Example: ssh ${TARGET_USER}@${TARGET_HOST} 'cd ~/code-server-enterprise && bash scripts/operations/redeploy/onprem/redeploy-remote-execute.sh --mode local-on-host --fix-stale-logs'"
      fi
    else
      log_error "SSH auth failed for ${TARGET_USER}@${TARGET_HOST}."
      log_error "Set SSH_KEY_PATH or run from target host with --mode local-on-host"
      log_error "If running from WSL, use --ssh-bin ssh.exe to use Windows SSH agent"
      log_fatal "Example: ssh ${TARGET_USER}@${TARGET_HOST} 'cd ~/code-server-enterprise && bash scripts/operations/redeploy/onprem/redeploy-remote-execute.sh --mode local-on-host --fix-stale-logs'"
    fi
  fi

  log_success "SSH authenticated to ${TARGET_USER}@${TARGET_HOST}"
}

resolve_remote_compose_bin() {
  log_section "Compose Command Resolution"

  if [[ "${COMPOSE_BIN}" != "auto" ]]; then
    RESOLVED_COMPOSE_BIN="${COMPOSE_BIN}"
    log_success "Using caller-selected compose command: ${RESOLVED_COMPOSE_BIN}"
    return 0
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    RESOLVED_COMPOSE_BIN="docker compose"
    log_info "[DRY-RUN] Assuming compose command: ${RESOLVED_COMPOSE_BIN}"
    return 0
  fi

  if remote "command -v docker-compose >/dev/null 2>&1"; then
    RESOLVED_COMPOSE_BIN="docker-compose"
    log_success "Resolved compose command on target: ${RESOLVED_COMPOSE_BIN}"
    return 0
  fi

  if remote "docker compose version >/dev/null 2>&1"; then
    RESOLVED_COMPOSE_BIN="docker compose"
    log_success "Resolved compose command on target: ${RESOLVED_COMPOSE_BIN}"
    return 0
  fi

  log_fatal "Unable to resolve compose command on target host (tried docker-compose and docker compose)"
}

run_remote_preflight() {
  log_section "Remote Preflight"

  local preflight_cmd="cd ${TARGET_REPO} && bash scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh --mode local-on-host"
  if [[ "$FIX_STALE_LOGS" == "true" ]]; then
    preflight_cmd+=" --fix-stale-logs"
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Remote preflight payload:"
    echo "$preflight_cmd"
    return 0
  fi

  remote "$preflight_cmd"
  log_success "Preflight completed"
}

run_remote_redeploy() {
  log_section "Remote Redeploy"

  local rollout_cmd
  local up_args
  local service_args
  if [[ "${ALLOW_RECREATE}" == "true" ]]; then
    up_args="-d"
  else
    up_args="-d --no-recreate"
  fi

  if [[ "${ALL_SERVICES}" == "true" ]]; then
    service_args=""
  else
    service_args="${REDEPLOY_SERVICES}"
  fi

  rollout_cmd=$(cat <<EOF
set -euo pipefail
export COMPOSE_INTERACTIVE_NO_CLI=1
cd ${TARGET_REPO}

git rev-parse --abbrev-ref HEAD
git rev-parse --short HEAD
git status --short

${RESOLVED_COMPOSE_BIN} config >/tmp/code-server-compose-rendered.yaml
${RESOLVED_COMPOSE_BIN} up ${up_args} ${service_args}

${RESOLVED_COMPOSE_BIN} ps
${RESOLVED_COMPOSE_BIN} logs --tail=100 code-server oauth2-proxy caddy
EOF
)

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Remote command payload:"
    echo "$rollout_cmd"
    return 0
  fi

  remote "$rollout_cmd"
  log_success "Redeploy completed"
}

main() {
  parse_args "$@"

  if [[ "${EXEC_MODE}" != "auto" && "${EXEC_MODE}" != "ssh" && "${EXEC_MODE}" != "local-on-host" ]]; then
    log_fatal "Invalid --mode value: ${EXEC_MODE}. Allowed: auto, ssh, local-on-host"
  fi

  require_command "${SSH_BIN}"
  check_ssh_access
  run_remote_preflight
  resolve_remote_compose_bin
  run_remote_redeploy
}

main "$@"
