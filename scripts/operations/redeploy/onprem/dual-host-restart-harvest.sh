#!/usr/bin/env bash
# @file        scripts/operations/redeploy/onprem/dual-host-restart-harvest.sh
# @module      operations/redeploy
# @description restart primary and replica hosts with preflight, conflict detection, and evidence capture
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
REPLICA_REPO="${REPLICA_REPO:-~/code-server-enterprise}"
EXEC_MODE="${EXEC_MODE:-ssh}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
SSH_BIN="${SSH_BIN:-ssh}"
EVIDENCE_DIR="${EVIDENCE_DIR:-artifacts/triage}"

usage() {
  cat <<'EOF'
Usage: dual-host-restart-harvest.sh [--mode MODE] [--ssh-key PATH] [--ssh-bin CMD]

Options:
  --mode MODE           ssh|local-on-host (default: ssh)
  --ssh-key PATH        SSH private key for deterministic auth
  --ssh-bin CMD         SSH client binary (ssh, ssh.exe)
  --primary-host HOST   Primary host (default: 192.168.168.31)
  --replica-host HOST   Replica host (default: 192.168.168.42)
  --primary-repo PATH   Repo path on primary host (default: ~/code-server-enterprise)
  --replica-repo PATH   Repo path on replica host (default: ~/code-server-enterprise)
  --user USER           SSH user for both hosts (default: akushnir)
  --evidence-dir PATH   Local evidence directory (default: artifacts/triage)
  -h, --help            Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
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
      --primary-repo)
        PRIMARY_REPO="$2"
        shift 2
        ;;
      --replica-repo)
        REPLICA_REPO="$2"
        shift 2
        ;;
      --user)
        TARGET_USER="$2"
        shift 2
        ;;
      --evidence-dir)
        EVIDENCE_DIR="$2"
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
  local host="$1"
  local repo="$2"
  local cmd="$3"
  local local_host
  local local_user
  local_host="$(hostname 2>/dev/null || true)"
  local_user="$(whoami 2>/dev/null || true)"

  if [[ "${EXEC_MODE}" == "local-on-host" && "${host}" == "${local_host}" && "${TARGET_USER}" == "${local_user}" ]]; then
    bash -lc "cd ${repo} && ${cmd}"
    return 0
  fi

  local -a ssh_args
  ssh_args=(
    -o BatchMode=yes
    -o ConnectTimeout=8
    -o StrictHostKeyChecking=accept-new
  )

  if [[ -n "${SSH_KEY_PATH}" ]]; then
    if [[ ! -f "${SSH_KEY_PATH}" ]]; then
      log_fatal "SSH key path does not exist: ${SSH_KEY_PATH}"
    fi
    ssh_args+=( -i "${SSH_KEY_PATH}" )
  fi

  if ! "${SSH_BIN}" "${ssh_args[@]}" "${TARGET_USER}@${host}" "echo OK" >/dev/null 2>&1; then
    if [[ "${SSH_BIN}" == "ssh" ]] && command -v ssh.exe >/dev/null 2>&1; then
      log_warn "Default ssh failed; retrying with ssh.exe for Windows agent compatibility"
      SSH_BIN="ssh.exe"
      if ! "${SSH_BIN}" "${ssh_args[@]}" "${TARGET_USER}@${host}" "echo OK" >/dev/null 2>&1; then
        log_fatal "Cannot establish non-interactive SSH session to ${TARGET_USER}@${host}"
      fi
    else
      log_fatal "Cannot establish non-interactive SSH session to ${TARGET_USER}@${host}"
    fi
  fi

  "${SSH_BIN}" "${ssh_args[@]}" "${TARGET_USER}@${host}" "cd ${repo} && ${cmd}"
}

timestamp() {
  date -u +%Y%m%dT%H%M%SZ
}

capture_ports() {
  local host="$1"
  local repo="$2"
  local outfile="$3"
  remote "$host" "$repo" "docker ps --format '{{.Names}}\t{{.Ports}}'" > "$outfile"
}

capture_compose_ps() {
  local host="$1"
  local repo="$2"
  local outfile="$3"
  local cmd
  cmd=$(cat <<'EOF'
set -euo pipefail
if command -v docker-compose >/dev/null 2>&1; then
  compose_cmd="docker-compose"
elif docker compose version >/dev/null 2>&1; then
  compose_cmd="docker compose"
else
  echo "compose=missing"
  exit 1
fi
${compose_cmd} ps
EOF
)

  remote "$host" "$repo" "$cmd" > "$outfile"
}

capture_compose_logs() {
  local host="$1"
  local repo="$2"
  local outfile="$3"
  local cmd
  cmd=$(cat <<'EOF'
set -euo pipefail
if command -v docker-compose >/dev/null 2>&1; then
  compose_cmd="docker-compose"
elif docker compose version >/dev/null 2>&1; then
  compose_cmd="docker compose"
else
  echo "compose=missing"
  exit 1
fi
${compose_cmd} logs --since=2h --no-color 2>&1 || true
EOF
)

  remote "$host" "$repo" "$cmd" > "$outfile"
}

capture_preflight() {
  local host="$1"
  local repo="$2"
  local outfile="$3"
  local cmd="bash scripts/operations/redeploy/onprem/operator-run-mode.sh --action preflight --mode local-on-host --fix-stale-logs"
  remote "$host" "$repo" "$cmd" > "$outfile" 2>&1
}

capture_redeploy() {
  local host="$1"
  local repo="$2"
  local outfile="$3"
  local cmd="bash scripts/operations/redeploy/onprem/operator-run-mode.sh --action redeploy --mode local-on-host --fix-stale-logs"
  remote "$host" "$repo" "$cmd" > "$outfile" 2>&1
}

find_replica_port_conflicts() {
  local ports_file="$1"
  local report_file="$2"
  local conflicts=()
  local container_name
  local container_ports

  while IFS=$'\t' read -r container_name container_ports; do
    [[ -z "${container_name}" ]] && continue
    for reserved_port in 80 443 2019; do
      if [[ "${container_ports}" == *":${reserved_port}->"* ]]; then
        conflicts+=("${container_name}|${reserved_port}|${container_ports}")
      fi
    done
  done < "$ports_file"

  if [[ "${#conflicts[@]}" -eq 0 ]]; then
    return 0
  fi

  {
    echo "# Replica port conflict report"
    echo
    echo "Replica host: ${REPLICA_HOST}"
    echo
    echo "The following reserved host ports are already in use:"
    echo
    for conflict in "${conflicts[@]}"; do
      IFS='|' read -r container_name reserved_port container_ports <<< "$conflict"
      echo "- ${container_name} binds host port ${reserved_port}: ${container_ports}"
    done
  } > "$report_file"

  return 1
}

write_summary() {
  local summary_file="$1"
  local outcome="$2"
  local conflict_file="$3"
  local primary_preflight="$4"
  local replica_preflight="$5"
  local primary_redeploy="$6"
  local replica_redeploy="$7"
  local primary_ports_pre="$8"
  local replica_ports_pre="$9"
  local primary_ports_post="${10}"
  local replica_ports_post="${11}"
  local primary_logs="${12}"
  local replica_logs="${13}"

  {
    echo "# Dual-host restart and log-harvest evidence"
    echo
    echo "Outcome: ${outcome}"
    echo "Timestamp UTC: $(timestamp)"
    echo
    echo "## Evidence Files"
    echo "- Primary preflight: ${primary_preflight}"
    echo "- Replica preflight: ${replica_preflight}"
    echo "- Primary redeploy: ${primary_redeploy}"
    echo "- Replica redeploy: ${replica_redeploy}"
    echo "- Primary ports before: ${primary_ports_pre}"
    echo "- Replica ports before: ${replica_ports_pre}"
    echo "- Primary ports after: ${primary_ports_post}"
    echo "- Replica ports after: ${replica_ports_post}"
    echo "- Primary logs (since 2h): ${primary_logs}"
    echo "- Replica logs (since 2h): ${replica_logs}"
    if [[ -n "${conflict_file}" ]]; then
      echo "- Replica conflict report: ${conflict_file}"
    fi
  } > "$summary_file"
}

main() {
  parse_args "$@"

  if [[ "${EXEC_MODE}" != "ssh" && "${EXEC_MODE}" != "local-on-host" ]]; then
    log_fatal "Invalid --mode value: ${EXEC_MODE}. Allowed: ssh, local-on-host"
  fi

  mkdir -p "${EVIDENCE_DIR}"

  local ts
  ts="$(timestamp)"
  local prefix="${EVIDENCE_DIR}/dual-host-restart-${ts}"
  local primary_ports_pre="${prefix}-primary-ports-before.tsv"
  local replica_ports_pre="${prefix}-replica-ports-before.tsv"
  local primary_compose_ps_pre="${prefix}-primary-compose-ps-before.txt"
  local replica_compose_ps_pre="${prefix}-replica-compose-ps-before.txt"
  local primary_logs="${prefix}-primary-logs-since-2h.txt"
  local replica_logs="${prefix}-replica-logs-since-2h.txt"
  local primary_preflight="${prefix}-primary-preflight.log"
  local replica_preflight="${prefix}-replica-preflight.log"
  local primary_redeploy="${prefix}-primary-redeploy.log"
  local replica_redeploy="${prefix}-replica-redeploy.log"
  local primary_ports_post="${prefix}-primary-ports-after.tsv"
  local replica_ports_post="${prefix}-replica-ports-after.tsv"
  local primary_compose_ps_post="${prefix}-primary-compose-ps-after.txt"
  local replica_compose_ps_post="${prefix}-replica-compose-ps-after.txt"
  local replica_conflict_report=""
  local summary_file="${prefix}-issue-comment.md"
  local primary_preflight_rc=0
  local replica_preflight_rc=0
  local primary_redeploy_rc=0
  local replica_redeploy_rc=0

  log_section "Pre-Restart Evidence"
  capture_ports "${PRIMARY_HOST}" "${PRIMARY_REPO}" "${primary_ports_pre}"
  capture_ports "${REPLICA_HOST}" "${REPLICA_REPO}" "${replica_ports_pre}"
  capture_compose_ps "${PRIMARY_HOST}" "${PRIMARY_REPO}" "${primary_compose_ps_pre}"
  capture_compose_ps "${REPLICA_HOST}" "${REPLICA_REPO}" "${replica_compose_ps_pre}"
  capture_compose_logs "${PRIMARY_HOST}" "${PRIMARY_REPO}" "${primary_logs}"
  capture_compose_logs "${REPLICA_HOST}" "${REPLICA_REPO}" "${replica_logs}"

  if ! find_replica_port_conflicts "${replica_ports_pre}" "${prefix}-replica-port-conflict.md"; then
    replica_conflict_report="${prefix}-replica-port-conflict.md"
    write_summary "${summary_file}" "blocked by replica reserved-port collision" "${replica_conflict_report}" "${primary_preflight}" "${replica_preflight}" "${primary_redeploy}" "${replica_redeploy}" "${primary_ports_pre}" "${replica_ports_pre}" "${primary_ports_post}" "${replica_ports_post}" "${primary_logs}" "${replica_logs}"
    log_error "Replica reserved-port collision detected; evidence written to ${replica_conflict_report}"
    log_error "Issue comment template: ${summary_file}"
    return 1
  fi

  log_section "Preflight"
  if capture_preflight "${PRIMARY_HOST}" "${PRIMARY_REPO}" "${primary_preflight}"; then
    primary_preflight_rc=0
  else
    primary_preflight_rc=$?
  fi
  if capture_preflight "${REPLICA_HOST}" "${REPLICA_REPO}" "${replica_preflight}"; then
    replica_preflight_rc=0
  else
    replica_preflight_rc=$?
  fi

  if [[ "${primary_preflight_rc}" -ne 0 || "${replica_preflight_rc}" -ne 0 ]]; then
    write_summary "${summary_file}" "blocked by preflight failure" "${replica_conflict_report}" "${primary_preflight}" "${replica_preflight}" "${primary_redeploy}" "${replica_redeploy}" "${primary_ports_pre}" "${replica_ports_pre}" "${primary_ports_post}" "${replica_ports_post}" "${primary_logs}" "${replica_logs}"
    log_error "Preflight failed on at least one host"
    log_error "Issue comment template: ${summary_file}"
    return 1
  fi

  log_section "Dual-Host Redeploy"
  if capture_redeploy "${PRIMARY_HOST}" "${PRIMARY_REPO}" "${primary_redeploy}"; then
    primary_redeploy_rc=0
  else
    primary_redeploy_rc=$?
  fi
  if capture_redeploy "${REPLICA_HOST}" "${REPLICA_REPO}" "${replica_redeploy}"; then
    replica_redeploy_rc=0
  else
    replica_redeploy_rc=$?
  fi

  capture_ports "${PRIMARY_HOST}" "${PRIMARY_REPO}" "${primary_ports_post}"
  capture_ports "${REPLICA_HOST}" "${REPLICA_REPO}" "${replica_ports_post}"
  capture_compose_ps "${PRIMARY_HOST}" "${PRIMARY_REPO}" "${primary_compose_ps_post}"
  capture_compose_ps "${REPLICA_HOST}" "${REPLICA_REPO}" "${replica_compose_ps_post}"

  if [[ "${primary_redeploy_rc}" -ne 0 || "${replica_redeploy_rc}" -ne 0 ]]; then
    write_summary "${summary_file}" "redeploy completed with host-side failures" "${replica_conflict_report}" "${primary_preflight}" "${replica_preflight}" "${primary_redeploy}" "${replica_redeploy}" "${primary_ports_pre}" "${replica_ports_pre}" "${primary_ports_post}" "${replica_ports_post}" "${primary_logs}" "${replica_logs}"
    log_error "One or both hosts returned a non-zero redeploy status"
    log_error "Issue comment template: ${summary_file}"
    return 1
  fi

  write_summary "${summary_file}" "success" "${replica_conflict_report}" "${primary_preflight}" "${replica_preflight}" "${primary_redeploy}" "${replica_redeploy}" "${primary_ports_pre}" "${replica_ports_pre}" "${primary_ports_post}" "${replica_ports_post}" "${primary_logs}" "${replica_logs}"
  log_success "Dual-host restart and log-harvest completed"
  log_info "Issue comment template: ${summary_file}"
}

main "$@"