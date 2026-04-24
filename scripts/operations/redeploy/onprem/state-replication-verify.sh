#!/usr/bin/env bash
# @file        scripts/operations/redeploy/onprem/state-replication-verify.sh
# @module      operations/redeploy
# @description verify code-server state drift and snapshot-restore viability between primary (.31) and replica (.42)
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

if [[ -f "$SCRIPT_DIR/../../../_common/ssh.sh" ]]; then
  source "$SCRIPT_DIR/../../../_common/ssh.sh"
elif [[ -f "$(pwd)/scripts/_common/ssh.sh" ]]; then
  source "$(pwd)/scripts/_common/ssh.sh"
fi

if ! declare -f ssh_exec_target >/dev/null 2>&1; then
  ssh_exec_target() {
    local target_host="$1"
    local target_user="$2"
    local target_cmd="$3"
    local ssh_key_path="${4:-}"
    local -a ssh_args

    read -r -a ssh_args <<< "${SSH_OPTS:--o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=10}"
    if [[ -n "$ssh_key_path" ]]; then
      ssh_args+=( -i "$ssh_key_path" )
    fi
    ssh "${ssh_args[@]}" "${target_user}@${target_host}" "$target_cmd"
  }
fi

PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
PRIMARY_USER="${PRIMARY_USER:-${DEPLOY_USER:-akushnir}}"
REPLICA_USER="${REPLICA_USER:-${DEPLOY_USER:-akushnir}}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
EXEC_MODE="${EXEC_MODE:-ssh}"
ACTION="drift-report"
EVIDENCE_DIR="${EVIDENCE_DIR:-/tmp/code-server-state-evidence}"
WORK_DIR=""

usage() {
  cat <<'EOF'
Usage: state-replication-verify.sh [--action ACTION] [--mode MODE] [--ssh-key PATH]

Actions:
  drift-report            Compare Tier-A metadata signatures on .31 vs .42 (default)
  snapshot-restore-test   Create Tier-A snapshot on .31, transfer to .42, and verify restore extraction
  replicate-tier-a        Synchronize Tier-A user state from primary to replica

Options:
  --action ACTION         drift-report|snapshot-restore-test|replicate-tier-a
  --mode MODE             ssh|local-on-host (default: ssh)
  --ssh-key PATH          SSH private key for deterministic auth
  --primary-host HOST     Primary host (default: 192.168.168.31)
  --replica-host HOST     Replica host (default: 192.168.168.42)
  --primary-user USER     Primary SSH user (default: akushnir)
  --replica-user USER     Replica SSH user (default: akushnir)
  --evidence-dir PATH     Evidence directory on primary host
  -h, --help              Show this help
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
      --primary-host)
        PRIMARY_HOST="$2"
        shift 2
        ;;
      --replica-host)
        REPLICA_HOST="$2"
        shift 2
        ;;
      --primary-user)
        PRIMARY_USER="$2"
        shift 2
        ;;
      --replica-user)
        REPLICA_USER="$2"
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

setup_workspace() {
  WORK_DIR="$(mktemp -d)"
  trap cleanup EXIT INT TERM
}

cleanup() {
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
}

run_primary_cmd() {
  local cmd="$1"
  if [[ "$EXEC_MODE" == "local-on-host" ]]; then
    bash -lc "$cmd"
  else
    ssh_exec_target "$PRIMARY_HOST" "$PRIMARY_USER" "$cmd" "$SSH_KEY_PATH"
  fi
}

run_replica_cmd() {
  local cmd="$1"
  ssh_exec_target "$REPLICA_HOST" "$REPLICA_USER" "$cmd" "$SSH_KEY_PATH"
}

collect_state_signature() {
  local host_role="$1"
  local output_file="$2"
  local runner
  local remote_script

  if [[ "$host_role" == "primary" ]]; then
    runner="run_primary_cmd"
  else
    runner="run_replica_cmd"
  fi

  read -r -d '' remote_script <<'EOS' || true
set -euo pipefail
if ! docker inspect code-server >/dev/null 2>&1; then
  echo "ERROR|code-server container missing"
  exit 2
fi
for p in /home/coder/workspace /home/coder/.local/share/code-server/User /home/coder/.local/share/code-server/extensions; do
  if docker exec code-server sh -lc "[ -e '$p' ]" >/dev/null 2>&1; then
    files=$(docker exec code-server sh -lc "find '$p' -type f 2>/dev/null | wc -l | tr -d ' '")
    bytes=$(docker exec code-server sh -lc "du -sb '$p' 2>/dev/null | awk '{print \$1}'")
    sig=$(docker exec code-server sh -lc "find '$p' -type f -printf '%P|%s|%T@\\n' 2>/dev/null | sort | sha256sum | awk '{print \$1}'")
    echo "$p|present|$files|$bytes|$sig"
  else
    echo "$p|missing|0|0|missing"
  fi
done
EOS

  "$runner" "$remote_script" > "$output_file"
}

generate_drift_report() {
  local ts
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  local report_file="$WORK_DIR/drift-${ts}.json"

  collect_state_signature primary "$WORK_DIR/primary.sig"
  collect_state_signature replica "$WORK_DIR/replica.sig"

  python3 - "$WORK_DIR/primary.sig" "$WORK_DIR/replica.sig" "$report_file" <<'PY'
import json
import sys

primary_file, replica_file, report_file = sys.argv[1:4]

def parse(path):
    items = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            parts = line.split("|")
            if len(parts) != 5:
                continue
            p, status, files, bytes_, sig = parts
            items[p] = {
                "status": status,
                "files": int(files),
                "bytes": int(bytes_),
                "signature": sig,
            }
    return items

primary = parse(primary_file)
replica = parse(replica_file)

paths = sorted(set(primary) | set(replica))
drift = []
for p in paths:
    l = primary.get(p)
    r = replica.get(p)
    if l != r:
        drift.append({"path": p, "primary": l, "replica": r})

report = {
    "kind": "code-server-state-drift-report",
    "drift_count": len(drift),
    "drift_detected": bool(drift),
    "paths_compared": paths,
    "drift": drift,
}

with open(report_file, "w", encoding="utf-8") as handle:
    json.dump(report, handle, indent=2)
PY

  run_primary_cmd "mkdir -p ${EVIDENCE_DIR}"
  run_primary_cmd "cat > ${EVIDENCE_DIR}/state-drift-${ts}.json" < "$report_file"

  log_info "Drift report written: ${EVIDENCE_DIR}/state-drift-${ts}.json"
  cat "$report_file"
}

run_snapshot_restore_test() {
  local ts archive_local archive_remote extract_dir report_file
  local primary_snapshot_cmd
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  archive_local="$WORK_DIR/tierA-${ts}.tgz"
  archive_remote="/tmp/code-server-tierA-${ts}.tgz"
  extract_dir="/tmp/code-server-restore-verify-${ts}"
  report_file="$WORK_DIR/snapshot-restore-${ts}.json"

  read -r -d '' primary_snapshot_cmd <<EOS || true
set -euo pipefail
if ! docker inspect code-server >/dev/null 2>&1; then
  echo "code-server container missing on primary" >&2
  exit 2
fi
docker exec code-server sh -lc 'set -eu; tar -czf /tmp/code-server-tierA-${ts}.tgz -C /home/coder workspace .local/share/code-server/User .local/share/code-server/extensions'
docker cp code-server:/tmp/code-server-tierA-${ts}.tgz /tmp/code-server-tierA-${ts}.tgz
EOS

  run_primary_cmd "$primary_snapshot_cmd"

  run_primary_cmd "cat /tmp/code-server-tierA-${ts}.tgz" > "$archive_local"
  run_replica_cmd "cat > ${archive_remote}" < "$archive_local"

  run_replica_cmd "set -euo pipefail; mkdir -p ${extract_dir}; tar -xzf ${archive_remote} -C ${extract_dir}; tar -tzf ${archive_remote} >/dev/null"

  local manifest_hash
  manifest_hash="$(run_replica_cmd "tar -tzf ${archive_remote} | sort | sha256sum | awk '{print \$1}'")"

  cat > "$report_file" <<EOF
{
  "kind": "code-server-snapshot-restore-test",
  "timestamp_utc": "${ts}",
  "primary_host": "${PRIMARY_HOST}",
  "replica_host": "${REPLICA_HOST}",
  "archive_remote": "${archive_remote}",
  "extract_dir": "${extract_dir}",
  "manifest_hash": "${manifest_hash}",
  "status": "pass"
}
EOF

  run_primary_cmd "mkdir -p ${EVIDENCE_DIR}"
  run_primary_cmd "cat > ${EVIDENCE_DIR}/snapshot-restore-${ts}.json" < "$report_file"

  log_info "Snapshot/restore report written: ${EVIDENCE_DIR}/snapshot-restore-${ts}.json"
  cat "$report_file"
}

run_replicate_tier_a() {
  local ts archive_local archive_remote report_file
  local primary_snapshot_cmd
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  archive_local="$WORK_DIR/tierA-sync-${ts}.tgz"
  archive_remote="/tmp/code-server-tierA-sync-${ts}.tgz"
  report_file="$WORK_DIR/replicate-tier-a-${ts}.json"

  read -r -d '' primary_snapshot_cmd <<EOS || true
set -euo pipefail
if ! docker inspect code-server >/dev/null 2>&1; then
  echo "code-server container missing on primary" >&2
  exit 2
fi
docker exec code-server sh -lc 'set -eu; tar -czf /tmp/code-server-tierA-sync-${ts}.tgz -C /home/coder workspace .local/share/code-server/User .local/share/code-server/extensions'
docker cp code-server:/tmp/code-server-tierA-sync-${ts}.tgz /tmp/code-server-tierA-sync-${ts}.tgz
EOS

  run_primary_cmd "$primary_snapshot_cmd"
  run_primary_cmd "cat /tmp/code-server-tierA-sync-${ts}.tgz" > "$archive_local"
  run_replica_cmd "cat > ${archive_remote}" < "$archive_local"

  run_replica_cmd "set -euo pipefail;
if ! docker inspect code-server >/dev/null 2>&1; then
  echo 'code-server container missing on replica' >&2;
  exit 2;
fi;
docker exec code-server sh -lc 'set -eu; mkdir -p /home/coder/workspace /home/coder/.local/share/code-server/User /home/coder/.local/share/code-server/extensions';
cat ${archive_remote} | docker exec -i code-server sh -lc 'set -eu; tar -xzf - -C /home/coder'"

  cat > "$report_file" <<EOF
{
  "kind": "code-server-tier-a-replication",
  "timestamp_utc": "${ts}",
  "primary_host": "${PRIMARY_HOST}",
  "replica_host": "${REPLICA_HOST}",
  "archive_remote": "${archive_remote}",
  "status": "pass"
}
EOF

  run_primary_cmd "mkdir -p ${EVIDENCE_DIR}"
  run_primary_cmd "cat > ${EVIDENCE_DIR}/replicate-tier-a-${ts}.json" < "$report_file"

  log_info "Tier-A replication report written: ${EVIDENCE_DIR}/replicate-tier-a-${ts}.json"
  cat "$report_file"
}

main() {
  parse_args "$@"

  case "$ACTION" in
    drift-report|snapshot-restore-test|replicate-tier-a)
      ;;
    *)
      log_fatal "Invalid --action '${ACTION}'. Allowed: drift-report|snapshot-restore-test|replicate-tier-a"
      ;;
  esac

  setup_workspace
  require_command ssh

  if declare -f assert_ssh_target >/dev/null 2>&1; then
    if [[ "$EXEC_MODE" != "local-on-host" ]]; then
      assert_ssh_target "$PRIMARY_HOST" "$PRIMARY_USER" "$SSH_KEY_PATH"
    fi
    assert_ssh_target "$REPLICA_HOST" "$REPLICA_USER" "$SSH_KEY_PATH"
  else
    if [[ "$EXEC_MODE" != "local-on-host" ]]; then
      ssh_exec_target "$PRIMARY_HOST" "$PRIMARY_USER" "echo OK" "$SSH_KEY_PATH" >/dev/null
    fi
    ssh_exec_target "$REPLICA_HOST" "$REPLICA_USER" "echo OK" "$SSH_KEY_PATH" >/dev/null
  fi

  if [[ "$ACTION" == "drift-report" ]]; then
    generate_drift_report
  elif [[ "$ACTION" == "replicate-tier-a" ]]; then
    run_replicate_tier_a
  else
    run_snapshot_restore_test
  fi
}

main "$@"
