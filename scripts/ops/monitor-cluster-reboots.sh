#!/usr/bin/env bash
# @file scripts/ops/monitor-cluster-reboots.sh
# @description Detect cluster host down/recovery/reboot transitions and create GitHub issues.
# @usage monitor-cluster-reboots.sh [--dry-run] [--print-cron] [--setup-cron]

set -euo pipefail

trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"
source "${REPO_ROOT}/scripts/_common/github-api-client.sh"

STATE_FILE="${REBOOT_STATE_FILE:-${REPO_ROOT}/artifacts/cluster-host-reboot-state.json}"
LOG_FILE="${REBOOT_MONITOR_LOG_FILE:-${REPO_ROOT}/logs/cluster-host-reboot-monitor.log}"
GITHUB_REPO_SLUG="${GITHUB_REPO_SLUG:-kushin77/code-server}"
SSH_USER="${SSH_USER:-akushnir}"
SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-10}"
SSH_IDENTITY_FILE="${SSH_IDENTITY_FILE:-}"
CRON_SCHEDULE="${REBOOT_MONITOR_CRON_SCHEDULE:-*/5 * * * *}"
RECENT_BOOT_LOOKBACK_SECONDS="${RECENT_BOOT_LOOKBACK_SECONDS:-7200}"
DRY_RUN="false"
PRINT_CRON="false"
SETUP_CRON="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --print-cron)
      PRINT_CRON="true"
      shift
      ;;
    --setup-cron)
      SETUP_CRON="true"
      shift
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

mkdir -p "$(dirname "${STATE_FILE}")" "$(dirname "${LOG_FILE}")"

log_info() {
  printf '[%s] [INFO] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "${LOG_FILE}"
}

log_warn() {
  printf '[%s] [WARN] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "${LOG_FILE}" >&2
}

log_error() {
  printf '[%s] [ERROR] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "${LOG_FILE}" >&2
}

run_python() {
  python3 - "$@"
}

cron_entry() {
  printf '%s cd %q && /bin/bash %q >> %q 2>&1 # cluster-reboot-monitor\n' \
    "${CRON_SCHEDULE}" "${REPO_ROOT}" "${REPO_ROOT}/scripts/ops/monitor-cluster-reboots.sh" "${LOG_FILE}"
}

print_cron_entry() {
  cron_entry
}

setup_cron() {
  local entry
  entry="$(cron_entry)"

  if crontab -l 2>/dev/null | grep -Fq "cluster-reboot-monitor"; then
    log_info "Cluster reboot monitor cron entry already present"
    return 0
  fi

  (crontab -l 2>/dev/null; printf '%s\n' "${entry}") | crontab -
  log_info "Installed cluster reboot monitor cron entry: ${CRON_SCHEDULE}"
}

build_ssh_command() {
  local -a cmd=(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="${SSH_CONNECT_TIMEOUT}")
  if [[ -n "${SSH_IDENTITY_FILE}" ]]; then
    cmd+=(-i "${SSH_IDENTITY_FILE}")
  fi
  printf '%q ' "${cmd[@]}"
}

host_snapshot() {
  local host="$1"
  local ssh_prefix
  ssh_prefix="$(build_ssh_command)"
  local remote_cmd="printf 'boot_id=%s\n' \"\$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)\"; printf 'uptime_seconds=%s\n' \"\$(awk '{print int(\$1)}' /proc/uptime 2>/dev/null || echo 0)\"; printf 'hostname=%s\n' \"\$(hostname 2>/dev/null || echo ${host})\""
  local output

  if ! output=$(eval "${ssh_prefix}\"${SSH_USER}@${host}\" ${remote_cmd@Q}" 2>/dev/null); then
    printf '{"host":"%s","reachable":false,"boot_id":"","uptime_seconds":0,"hostname":"%s"}\n' "${host}" "${host}"
    return 0
  fi

  local boot_id=""
  local uptime_seconds="0"
  local hostname_value="${host}"
  while IFS='=' read -r key value; do
    case "$key" in
      boot_id) boot_id="$value" ;;
      uptime_seconds) uptime_seconds="$value" ;;
      hostname) hostname_value="$value" ;;
    esac
  done <<< "${output}"

  printf '{"host":"%s","reachable":true,"boot_id":"%s","uptime_seconds":%s,"hostname":"%s"}\n' \
    "${host}" "${boot_id}" "${uptime_seconds:-0}" "${hostname_value}"
}

load_previous_state() {
  if [[ -f "${STATE_FILE}" ]]; then
    cat "${STATE_FILE}"
  else
    printf '{}\n'
  fi
}

save_current_state() {
  local payload="$1"
  printf '%s\n' "${payload}" > "${STATE_FILE}"
}

issue_exists() {
  local marker="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '0\n'
    return 0
  fi

  local token
  token="$(github_get_token)"
  run_python <<'PY' "$token" "$GITHUB_REPO_SLUG" "$marker"
import json
import sys
import urllib.parse
import urllib.request

token, repo_slug, marker = sys.argv[1:4]
query = urllib.parse.quote(f'repo:{repo_slug} type:issue "{marker}"')
request = urllib.request.Request(
    f'https://api.github.com/search/issues?q={query}&per_page=1',
    headers={
        'Authorization': f'token {token}',
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'code-server-cluster-reboot-monitor',
    },
)
with urllib.request.urlopen(request, timeout=30) as response:
    data = json.loads(response.read().decode() or '{}')
print('1' if data.get('total_count', 0) > 0 else '0')
PY
}

create_issue() {
  local title="$1"
  local body="$2"
  local labels_json="$3"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY RUN] Would create issue: ${title}"
    return 0
  fi

  local payload
  payload=$(run_python <<'PY' "$title" "$body" "$labels_json"
import json, sys
print(json.dumps({
    'title': sys.argv[1],
    'body': sys.argv[2],
    'labels': json.loads(sys.argv[3]),
}))
PY
)

  local token
  token="$(github_get_token)"
  run_python <<'PY' "$token" "$GITHUB_REPO_SLUG" "$payload"
import json
import sys
import urllib.request

token, repo_slug, payload_json = sys.argv[1:4]
request = urllib.request.Request(
    f'https://api.github.com/repos/{repo_slug}/issues',
    data=payload_json.encode(),
    headers={
        'Authorization': f'token {token}',
        'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json',
        'User-Agent': 'code-server-cluster-reboot-monitor',
    },
    method='POST',
)
with urllib.request.urlopen(request, timeout=30) as response:
    response.read()
PY
  log_info "Created GitHub issue: ${title}"
}

emit_event_issue() {
  local event_type="$1"
  local host="$2"
  local hostname_value="$3"
  local current_json="$4"
  local previous_json="$5"
  local marker="$6"
  local title="$7"

  if [[ "$(issue_exists "${marker}")" == "1" ]]; then
    log_info "Issue already exists for marker ${marker}"
    return 0
  fi

  local body
  body=$(run_python <<'PY' "$event_type" "$host" "$hostname_value" "$current_json" "$previous_json" "$marker"
import json, sys
event_type, host, hostname_value, current_json, previous_json, marker = sys.argv[1:7]
current_state = json.loads(current_json)
previous_state = json.loads(previous_json) if previous_json else {}
lines = [
    f'Event type: `{event_type}`',
    f'Host: `{host}`',
    f'Remote hostname: `{hostname_value}`',
    f'Current reachable: `{current_state.get("reachable", False)}`',
]
if current_state.get('boot_id'):
    lines.append(f'Current boot id: `{current_state.get("boot_id")}`')
lines.append(f'Current uptime seconds: `{current_state.get("uptime_seconds", 0)}`')
if previous_state:
    lines.append('')
    lines.append('Previous state:')
    lines.append(f'- reachable: `{previous_state.get("reachable", False)}`')
    if previous_state.get('boot_id'):
      lines.append(f'- boot id: `{previous_state.get("boot_id")}`')
    lines.append(f'- uptime seconds: `{previous_state.get("uptime_seconds", 0)}`')
lines.extend(['', marker])
print('\n'.join(lines))
PY
)

  local labels='["P1", "automation", "github", "infrastructure", "cluster", "host-monitoring"]'
  if [[ "${event_type}" == "recovered" ]]; then
    labels='["P2", "automation", "github", "infrastructure", "cluster", "host-monitoring"]'
  fi
  create_issue "${title}" "${body}" "${labels}"
}

main() {
  if [[ "${PRINT_CRON}" == "true" ]]; then
    print_cron_entry
    return 0
  fi

  if [[ "${SETUP_CRON}" == "true" ]]; then
    setup_cron
    return 0
  fi

  local previous_state_json current_state_json
  previous_state_json="$(load_previous_state)"

  local -a hosts=()
  [[ -n "${PRIMARY_HOST:-}" ]] && hosts+=("${PRIMARY_HOST}")
  [[ -n "${REPLICA_HOST:-}" ]] && hosts+=("${REPLICA_HOST}")
  if [[ ${#hosts[@]} -eq 0 ]]; then
    log_error "PRIMARY_HOST and REPLICA_HOST are not configured"
    exit 1
  fi

  log_info "Checking cluster reboot state for hosts: ${hosts[*]}"

  if [[ "${previous_state_json}" == "{}" ]]; then
    log_info "No previous reboot monitor state found; establishing baseline without retroactive issue creation"
  fi

  current_state_json=$(run_python <<'PY' "$previous_state_json" "${hosts[@]}"
import json, sys
previous = json.loads(sys.argv[1] or '{}')
hosts = sys.argv[2:]
result = {host: previous.get(host, {}) for host in hosts}
print(json.dumps(result))
PY
)

  local snapshots="[]"
  local host
  for host in "${hosts[@]}"; do
    local snapshot
    snapshot="$(host_snapshot "${host}")"
    snapshots=$(run_python <<'PY' "$snapshots" "$snapshot"
import json, sys
items = json.loads(sys.argv[1])
items.append(json.loads(sys.argv[2]))
print(json.dumps(items))
PY
)
  done

  local next_state
  next_state=$(run_python <<'PY' "$previous_state_json" "$snapshots"
import json, sys
previous = json.loads(sys.argv[1] or '{}')
snapshots = json.loads(sys.argv[2])
result = dict(previous)
for item in snapshots:
    result[item['host']] = item
print(json.dumps(result, sort_keys=True))
PY
)

  local events
  events=$(run_python <<'PY' "$previous_state_json" "$snapshots" "$RECENT_BOOT_LOOKBACK_SECONDS"
import json, sys
previous = json.loads(sys.argv[1] or '{}')
snapshots = json.loads(sys.argv[2])
recent_boot_lookback_seconds = int(sys.argv[3])
events = []
for current in snapshots:
    host = current['host']
    prev = previous.get(host, {})
    prev_reachable = bool(prev.get('reachable', False))
    cur_reachable = bool(current.get('reachable', False))
    if not prev and cur_reachable:
        if int(current.get('uptime_seconds', 0)) <= recent_boot_lookback_seconds:
            events.append({'event_type': 'rebooted', 'host': host, 'current': current, 'previous': prev})
        continue
    if prev_reachable and not cur_reachable:
        events.append({'event_type': 'down', 'host': host, 'current': current, 'previous': prev})
        continue
    if not prev_reachable and cur_reachable:
        events.append({'event_type': 'recovered', 'host': host, 'current': current, 'previous': prev})
    if prev_reachable and cur_reachable and prev.get('boot_id') and current.get('boot_id') and prev.get('boot_id') != current.get('boot_id'):
        events.append({'event_type': 'rebooted', 'host': host, 'current': current, 'previous': prev})
print(json.dumps(events))
PY
)

  local event_count
  event_count=$(run_python <<'PY' "$events"
import json, sys
print(len(json.loads(sys.argv[1] or '[]')))
PY
)
  log_info "Detected ${event_count} host transition event(s)"

  if [[ "${event_count}" != "0" ]]; then
    while IFS= read -r event_json; do
      [[ -z "${event_json}" ]] && continue
      local event_type host_name hostname_value marker title current_json previous_json boot_id
      event_type=$(run_python <<'PY' "$event_json"
import json, sys
print(json.loads(sys.argv[1])['event_type'])
PY
)
      host_name=$(run_python <<'PY' "$event_json"
import json, sys
print(json.loads(sys.argv[1])['host'])
PY
)
      hostname_value=$(run_python <<'PY' "$event_json"
import json, sys
print(json.loads(sys.argv[1])['current'].get('hostname', json.loads(sys.argv[1])['host']))
PY
)
      current_json=$(run_python <<'PY' "$event_json"
import json, sys
print(json.dumps(json.loads(sys.argv[1])['current']))
PY
)
      previous_json=$(run_python <<'PY' "$event_json"
import json, sys
print(json.dumps(json.loads(sys.argv[1]).get('previous', {})))
PY
)
      boot_id=$(run_python <<'PY' "$event_json"
import json, sys
print(json.loads(sys.argv[1])['current'].get('boot_id', 'unknown'))
PY
)

      case "${event_type}" in
        down)
          marker="cluster-host-event: down:${host_name}:$(date -u +'%Y%m%dT%H%M')"
          title="[cluster][host-down] ${host_name} became unreachable"
          ;;
        recovered)
          marker="cluster-host-event: recovered:${host_name}:${boot_id}"
          title="[cluster][host-recovered] ${host_name} is reachable again"
          ;;
        rebooted)
          marker="cluster-host-event: rebooted:${host_name}:${boot_id}"
          title="[cluster][host-rebooted] ${host_name} booted with a new boot id"
          ;;
        *)
          log_warn "Skipping unknown event type ${event_type}"
          continue
          ;;
      esac

      emit_event_issue "${event_type}" "${host_name}" "${hostname_value}" "${current_json}" "${previous_json}" "${marker}" "${title}"
    done < <(run_python <<'PY' "$events"
import json, sys
for item in json.loads(sys.argv[1] or '[]'):
    print(json.dumps(item))
PY
)
  fi

  save_current_state "${next_state}"
  log_info "Saved cluster reboot monitor state to ${STATE_FILE}"
}

main "$@"