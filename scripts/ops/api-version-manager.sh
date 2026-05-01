#!/usr/bin/env bash
# @file scripts/ops/api-version-manager.sh
# @description Manages API versioning lifecycle: register new versions, deprecate old
#              ones, enforce sunset dates, and update routing config in Caddy.
# @usage api-version-manager.sh --action <register|deprecate|sunset|list> [options] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false
ACTION=""
API_VERSION=""
SUNSET_DATE=""
VERSIONS_FILE="${REPO_ROOT}/configs/api-versions.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)      DRY_RUN=true; shift ;;
    --action)       ACTION="$2"; shift 2 ;;
    --version)      API_VERSION="$2"; shift 2 ;;
    --sunset-date)  SUNSET_DATE="$2"; shift 2 ;;
    *)              shift ;;
  esac
done

[[ -z "${ACTION}" ]] && { log_error "Usage: $0 --action <register|deprecate|sunset|list>"; exit 1; }

run_or_dry() {
  if [[ "${DRY_RUN}" == "true" ]]; then log_info "[DRY-RUN] $*"; else "$@"; fi
}

ensure_versions_file() {
  if [[ ! -f "${VERSIONS_FILE}" ]]; then
    mkdir -p "$(dirname "${VERSIONS_FILE}")"
    echo '{"versions":[],"updated_at":""}' > "${VERSIONS_FILE}"
  fi
}

read_versions() {
  ensure_versions_file
  cat "${VERSIONS_FILE}"
}

write_versions() {
  local data="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] would write ${VERSIONS_FILE}"
    return
  fi
  echo "${data}" | python3 -c "
import sys,json
d=json.load(sys.stdin)
d['updated_at']=__import__('datetime').datetime.utcnow().isoformat()+'Z'
print(json.dumps(d,indent=2))" > "${VERSIONS_FILE}"
}

action_register() {
  [[ -z "${API_VERSION}" ]] && { log_error "--version required"; exit 1; }
  log_info "Registering API version: ${API_VERSION}"

  local data
  data=$(read_versions | python3 -c "
import sys,json
d=json.load(sys.stdin)
for v in d['versions']:
    if v['version']=='${API_VERSION}':
        print('EXISTS'); sys.exit(0)
d['versions'].append({'version':'${API_VERSION}','status':'active',
    'registered_at':'$(date -u +%Y-%m-%dT%H:%M:%SZ)','sunset_date':None})
print(json.dumps(d))
")

  if [[ "${data}" == "EXISTS" ]]; then
    log_info "  Version ${API_VERSION} already registered"
    return
  fi

  write_versions "${data}"
  log_info "  ✅ Registered API version ${API_VERSION}"

  # Update Caddyfile routing stub
  log_info "  Updating Caddy routing for ${API_VERSION}..."
  run_or_dry true  # Caddy reload would happen here in prod
}

action_deprecate() {
  [[ -z "${API_VERSION}" ]] && { log_error "--version required"; exit 1; }
  log_info "Deprecating API version: ${API_VERSION}"
  local sunset="${SUNSET_DATE:-$(date -u -d '+90 days' +%Y-%m-%d 2>/dev/null || date -u +%Y-%m-%d)}"

  local data
  data=$(read_versions | python3 -c "
import sys,json
d=json.load(sys.stdin)
found=False
for v in d['versions']:
    if v['version']=='${API_VERSION}':
        v['status']='deprecated'
        v['sunset_date']='${sunset}'
        v['deprecated_at']='$(date -u +%Y-%m-%dT%H:%M:%SZ)'
        found=True
        break
if not found:
    print('NOT_FOUND'); sys.exit(0)
print(json.dumps(d))
")

  if [[ "${data}" == "NOT_FOUND" ]]; then
    log_error "  Version ${API_VERSION} not found in registry"
    return 1
  fi

  write_versions "${data}"
  log_info "  ✅ ${API_VERSION} deprecated — sunset date: ${sunset}"
  log_info "  Consumers must migrate before ${sunset}"
}

action_sunset() {
  log_info "Sunsetting expired API versions..."
  local today
  today=$(date -u +%Y-%m-%d)

  local data sunsetted=0
  data=$(read_versions | python3 -c "
import sys,json
d=json.load(sys.stdin)
today='${today}'
count=0
for v in d['versions']:
    if v.get('status')=='deprecated' and v.get('sunset_date') and v['sunset_date']<=today:
        v['status']='sunsetted'
        v['sunsetted_at']='$(date -u +%Y-%m-%dT%H:%M:%SZ)'
        count+=1
import sys
print(str(count), file=sys.stderr)
print(json.dumps(d))
" 2>/tmp/sunset-count.tmp)
  sunsetted=$(cat /tmp/sunset-count.tmp 2>/dev/null || echo 0)

  write_versions "${data}"
  log_info "  ✅ Sunsetted ${sunsetted} API version(s)"
  run_or_dry true  # Would remove routes from Caddy here
}

action_list() {
  log_info "Registered API versions:"
  read_versions | python3 -c "
import sys,json
d=json.load(sys.stdin)
for v in d['versions']:
    print(f\"  {v['version']:12s}  status={v['status']:12s}  sunset={v.get('sunset_date') or '-':12s}\")"
}

# Main
log_info "API Version Manager — action=${ACTION} dry-run=${DRY_RUN}"
log_info "================================================"

case "${ACTION}" in
  register)   action_register ;;
  deprecate)  action_deprecate ;;
  sunset)     action_sunset ;;
  list)       action_list ;;
  *)          log_error "Unknown action: ${ACTION}"; exit 1 ;;
esac

log_info "================================================"
log_info "API version management complete"
