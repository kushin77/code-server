#!/usr/bin/env bash
# @file        scripts/operations/redeploy/onprem/operator-run-mode.sh
# @module      operations/redeploy
# @description provide in-workspace operator entrypoint for preflight, redeploy, failover and failback with evidence output
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../_common/init.sh"

ACTION="status"
EXEC_MODE="${EXEC_MODE:-ssh}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
SSH_BIN="${SSH_BIN:-ssh}"
EVIDENCE_FILE="${EVIDENCE_FILE:-}"

usage() {
  cat <<'EOF'
Usage: operator-run-mode.sh [--action ACTION] [--mode MODE] [--ssh-key PATH] [--ssh-bin CMD] [--evidence-file PATH]

Actions:
  preflight  run deterministic redeploy preflight checks
  redeploy   run deterministic preflight + redeploy wrapper
  status     run failover status report
  promote    promote replica path (.42)
  failback   fail back to primary (.31)

Options:
  --action ACTION          preflight|redeploy|status|promote|failback
  --mode MODE              ssh|local-on-host (default: ssh)
  --ssh-key PATH           SSH key path for non-interactive auth
  --ssh-bin CMD            SSH binary override (ssh|ssh.exe)
  --evidence-file PATH     Explicit evidence output path
  -h, --help               Show this help

Environment:
  EXEC_MODE, SSH_KEY_PATH, SSH_BIN, EVIDENCE_FILE
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
      --evidence-file)
        EVIDENCE_FILE="$2"
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

build_common_flags() {
  local -a flags
  flags=(--mode "$EXEC_MODE" --ssh-bin "$SSH_BIN")
  if [[ -n "$SSH_KEY_PATH" ]]; then
    flags+=(--ssh-key "$SSH_KEY_PATH")
  fi
  printf '%s\n' "${flags[@]}"
}

emit_evidence() {
  local action_name="$1"
  local status="$2"
  local details="$3"
  local timestamp
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

  if [[ -z "$EVIDENCE_FILE" ]]; then
    EVIDENCE_FILE="/tmp/operator-run-mode-${action_name}-${timestamp}.json"
  fi

  cat > "$EVIDENCE_FILE" <<EOF
{
  "timestamp_utc": "${timestamp}",
  "action": "${action_name}",
  "status": "${status}",
  "execution_mode": "${EXEC_MODE}",
  "details": "${details}"
}
EOF

  log_info "Operator evidence written: ${EVIDENCE_FILE}"
}

run_action() {
  local -a flags
  local -a fo_flags
  mapfile -t flags < <(build_common_flags)
  fo_flags=(--ssh-bin "$SSH_BIN")
  fo_flags+=(--mode "$EXEC_MODE")
  if [[ -n "$SSH_KEY_PATH" ]]; then
    fo_flags+=(--ssh-key "$SSH_KEY_PATH")
  fi

  case "$ACTION" in
    preflight)
      bash "$SCRIPT_DIR/../preflight/onprem/redeploy-preflight.sh" "${flags[@]}" --fix-stale-logs
      emit_evidence "$ACTION" "success" "Preflight checks completed"
      ;;
    redeploy)
      bash "$SCRIPT_DIR/../preflight/onprem/redeploy-preflight.sh" "${flags[@]}" --fix-stale-logs
      bash "$SCRIPT_DIR/redeploy-remote-execute.sh" "${flags[@]}" --fix-stale-logs
      emit_evidence "$ACTION" "success" "Redeploy wrapper completed"
      ;;
    status)
      bash "$SCRIPT_DIR/failover-orchestrate.sh" --action status "${fo_flags[@]}"
      emit_evidence "$ACTION" "success" "Failover status completed"
      ;;
    promote)
      bash "$SCRIPT_DIR/failover-orchestrate.sh" --action promote "${fo_flags[@]}"
      emit_evidence "$ACTION" "success" "Replica promotion completed"
      ;;
    failback)
      bash "$SCRIPT_DIR/failover-orchestrate.sh" --action failback "${fo_flags[@]}"
      emit_evidence "$ACTION" "success" "Primary failback completed"
      ;;
    *)
      log_fatal "Invalid --action '${ACTION}'. Allowed: preflight|redeploy|status|promote|failback"
      ;;
  esac
}

main() {
  parse_args "$@"
  run_action
}

main "$@"
