#!/usr/bin/env bash
# @file        scripts/operations/redeploy/onprem/full-redeploy-certify.sh
# @module      operations/redeploy
# @description certify full redeploy lifecycle with preflight, deploy, post-verify, rollback, and evidence bundle
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

TARGET_HOST="${TARGET_HOST:-${DEPLOY_HOST:-192.168.168.31}}"
TARGET_USER="${TARGET_USER:-${DEPLOY_USER:-akushnir}}"
TARGET_REPO="${TARGET_REPO:-~/code-server-enterprise}"
EXEC_MODE="${EXEC_MODE:-ssh}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
SSH_BIN="${SSH_BIN:-ssh}"
EVIDENCE_DIR="${EVIDENCE_DIR:-artifacts/triage}"
ROLLBACK_COMMIT="${ROLLBACK_COMMIT:-}"

usage() {
  cat <<'EOF'
Usage: full-redeploy-certify.sh [--host HOST] [--user USER] [--repo PATH] [--mode MODE] [--ssh-key PATH] [--ssh-bin CMD] [--rollback-commit SHA]

Options:
  --host HOST           Target host. Default: 192.168.168.31
  --user USER           SSH user. Default: akushnir
  --repo PATH           Remote repository path. Default: ~/code-server-enterprise
  --mode MODE           ssh|local-on-host (default: ssh)
  --ssh-key PATH        SSH private key for deterministic auth
  --ssh-bin CMD         SSH client binary
  --rollback-commit SHA Optional explicit rollback commit; defaults to parent commit of current HEAD
  --evidence-dir PATH   Evidence directory. Default: artifacts/triage
  -h, --help            Show this help
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
      --rollback-commit)
        ROLLBACK_COMMIT="$2"
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
  local cmd="$1"
  local local_host
  local local_user
  local_host="$(hostname 2>/dev/null || true)"
  local_user="$(whoami 2>/dev/null || true)"

  if [[ "${EXEC_MODE}" == "local-on-host" && "${TARGET_HOST}" == "${local_host}" && "${TARGET_USER}" == "${local_user}" ]]; then
    bash -lc "cd ${TARGET_REPO} && ${cmd}"
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

  if ! "${SSH_BIN}" "${ssh_args[@]}" "${TARGET_USER}@${TARGET_HOST}" "echo OK" >/dev/null 2>&1; then
    log_fatal "Cannot establish non-interactive SSH session to ${TARGET_USER}@${TARGET_HOST}"
  fi

  "${SSH_BIN}" "${ssh_args[@]}" "${TARGET_USER}@${TARGET_HOST}" "cd ${TARGET_REPO} && ${cmd}"
}

timestamp() {
  date -u +%Y%m%dT%H%M%SZ
}

capture() {
  local file_path="$1"
  shift
  local cmd="$*"
  remote "$cmd" > "$file_path" 2>&1
}

capture_raw() {
  local file_path="$1"
  shift
  local cmd="$*"
  remote "$cmd" > "$file_path"
}

record_manifest() {
  local manifest_file="$1"
  shift
  {
    echo "# Redeploy certification evidence"
    echo "timestamp_utc=$(timestamp)"
    echo "target_host=${TARGET_HOST}"
    echo "target_repo=${TARGET_REPO}"
    echo "current_commit=${CURRENT_COMMIT:-unknown}"
    echo "rollback_commit=${ROLLBACK_COMMIT:-unknown}"
    echo "deployment_status=${DEPLOYMENT_STATUS}"
    echo "rollback_status=${ROLLBACK_STATUS}"
    echo
    echo "## Evidence Files"
    for item in "$@"; do
      echo "- ${item}"
    done
  } > "$manifest_file"
}

collect_bundle_checksums() {
  local checksum_file="$1"
  shift
  : > "$checksum_file"
  for artifact in "$@"; do
    if [[ -f "$artifact" ]]; then
      sha256sum "$artifact" >> "$checksum_file"
    fi
  done
}

verify_primary_path() {
  local status_file="$1"
  local fail=0

  capture_raw "$status_file" "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

  if ! remote "curl -fsS http://127.0.0.1:8080/healthz >/dev/null"; then
    log_error "Primary health endpoint failed on ${TARGET_HOST}"
    fail=1
  fi

  for service in code-server caddy oauth2-proxy redis postgres grafana alertmanager jaeger; do
    if ! remote "docker inspect -f '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' ${service} >/dev/null 2>&1"; then
      log_error "Missing primary service: ${service}"
      fail=1
    fi
  done

  return $fail
}

verify_replica_path() {
  local status_file="$1"
  local fail=0

  capture_raw "$status_file" "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

  if ! remote "curl -fsSI http://127.0.0.1:18080/ >/dev/null"; then
    log_error "Replica edge endpoint failed on ${TARGET_HOST}"
    fail=1
  fi

  for service in caddy-replica oauth2-proxy-portal appsmith session-broker; do
    if ! remote "docker inspect -f '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' ${service} >/dev/null 2>&1"; then
      log_error "Missing replica service: ${service}"
      fail=1
    fi
  done

  return $fail
}

run_rollback() {
  local rollback_log="$1"
  if [[ -z "${ROLLBACK_COMMIT}" ]]; then
    log_error "Rollback commit not available"
    return 1
  fi

  capture "$rollback_log" "set -euo pipefail; git reset --hard '${ROLLBACK_COMMIT}'; bash scripts/operations/redeploy/onprem/redeploy-remote-execute.sh --mode local-on-host --fix-stale-logs"
}

main() {
  parse_args "$@"

  if [[ "${EXEC_MODE}" != "ssh" && "${EXEC_MODE}" != "local-on-host" ]]; then
    log_fatal "Invalid --mode value: ${EXEC_MODE}. Allowed: ssh, local-on-host"
  fi

  mkdir -p "${EVIDENCE_DIR}"

  local ts
  ts="$(timestamp)"
  local prefix="${EVIDENCE_DIR}/redeploy-certify-${ts}"
  local preflight_log="${prefix}-preflight.log"
  local deploy_log="${prefix}-deploy.log"
  local verify_log="${prefix}-verify.log"
  local rollback_log="${prefix}-rollback.log"
  local status_table="${prefix}-status-table.txt"
  local post_status_table="${prefix}-post-status-table.txt"
  local rollback_status_table="${prefix}-rollback-status-table.txt"
  local manifest_file="${prefix}-manifest.txt"
  local checksum_file="${prefix}-manifest.sha256"
  local role="primary"
  local DEPLOYMENT_STATUS="unknown"
  local ROLLBACK_STATUS="unknown"
  local preflight_rc=0
  local deploy_rc=0
  local verify_rc=0
  local rollback_rc=0
  local evidence_items=()

  if [[ "${TARGET_HOST}" == "192.168.168.42" ]]; then
    role="replica"
  elif [[ "${TARGET_HOST}" != "192.168.168.31" ]]; then
    role="custom"
  fi

  log_section "Certify Redeploy"
  CURRENT_COMMIT="$(remote "git rev-parse HEAD")"
  if [[ -z "${ROLLBACK_COMMIT}" ]]; then
    ROLLBACK_COMMIT="$(remote "git rev-parse HEAD^ 2>/dev/null || git rev-parse HEAD")"
  fi

  if [[ -n "$(remote "git status --porcelain")" ]]; then
    log_fatal "Remote working tree is dirty on ${TARGET_HOST}; certification requires a clean tree"
  fi

  if remote "bash scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh --mode local-on-host --fix-stale-logs" > "$preflight_log" 2>&1; then
    preflight_rc=0
  else
    preflight_rc=$?
  fi

  if [[ "$preflight_rc" -ne 0 ]]; then
    DEPLOYMENT_STATUS="blocked-preflight"
    ROLLBACK_STATUS="not-attempted"
    capture_raw "$status_table" "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
    record_manifest "$manifest_file" "$preflight_log" "$status_table"
    collect_bundle_checksums "$checksum_file" "$manifest_file" "$preflight_log" "$status_table"
    evidence_items=("$preflight_log" "$status_table" "$manifest_file" "$checksum_file")
    log_error "Preflight failed; certification stopped before deploy"
    log_error "Rollback guidance: revert the pending change or restore the last known good commit ${ROLLBACK_COMMIT}"
    return 1
  fi

  if remote "bash scripts/operations/redeploy/onprem/redeploy-remote-execute.sh --mode local-on-host --fix-stale-logs" > "$deploy_log" 2>&1; then
    deploy_rc=0
  else
    deploy_rc=$?
  fi

  if [[ "$deploy_rc" -ne 0 ]]; then
    DEPLOYMENT_STATUS="deploy-failed"
    ROLLBACK_STATUS="not-attempted"
    capture_raw "$status_table" "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
    record_manifest "$manifest_file" "$preflight_log" "$deploy_log" "$status_table"
    collect_bundle_checksums "$checksum_file" "$manifest_file" "$preflight_log" "$deploy_log" "$status_table"
    evidence_items=("$preflight_log" "$deploy_log" "$status_table" "$manifest_file" "$checksum_file")
    log_error "Deploy failed; rollback guidance: restore ${ROLLBACK_COMMIT} and rerun deploy"
    return 1
  fi

  if [[ "$role" == "replica" ]]; then
    if verify_replica_path "$post_status_table" > "$verify_log" 2>&1; then
      verify_rc=0
    else
      verify_rc=$?
    fi
  else
    if verify_primary_path "$post_status_table" > "$verify_log" 2>&1; then
      verify_rc=0
    else
      verify_rc=$?
    fi
  fi

  if [[ "$verify_rc" -ne 0 ]]; then
    log_warn "Post-verify failed; triggering automatic rollback to ${ROLLBACK_COMMIT}"
    if run_rollback "$rollback_log"; then
      rollback_rc=0
      if [[ "$role" == "replica" ]]; then
        if verify_replica_path "$rollback_status_table" >> "$rollback_log" 2>&1; then
          DEPLOYMENT_STATUS="rolled-back"
          verify_rc=0
        else
          rollback_rc=$?
        fi
      else
        if verify_primary_path "$rollback_status_table" >> "$rollback_log" 2>&1; then
          DEPLOYMENT_STATUS="rolled-back"
          verify_rc=0
        else
          rollback_rc=$?
        fi
      fi
      ROLLBACK_STATUS="applied"
    else
      rollback_rc=$?
      ROLLBACK_STATUS="failed"
    fi
  else
    DEPLOYMENT_STATUS="success"
    ROLLBACK_STATUS="not-required"
  fi

  evidence_items=("$preflight_log" "$deploy_log" "$verify_log" "$status_table" "$post_status_table")
  if [[ -f "$rollback_log" ]]; then
    evidence_items+=("$rollback_log")
  fi
  if [[ -f "$rollback_status_table" ]]; then
    evidence_items+=("$rollback_status_table")
  fi
  record_manifest "$manifest_file" "${evidence_items[@]}"
  collect_bundle_checksums "$checksum_file" "$manifest_file" "${evidence_items[@]}"

  if [[ "$verify_rc" -ne 0 || "$rollback_rc" -ne 0 ]]; then
    log_error "Redeploy certification failed"
    log_error "Rollback commit: ${ROLLBACK_COMMIT}"
    log_error "Evidence manifest: ${manifest_file}"
    log_error "Evidence checksum: ${checksum_file}"
    return 1
  fi

  log_success "Redeploy certification passed"
  log_info "Evidence manifest: ${manifest_file}"
  log_info "Evidence checksum: ${checksum_file}"
}

main "$@"