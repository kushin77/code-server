#!/usr/bin/env bash
# @file domain-variability-enforcer.sh
# @module infrastructure/governance
# @description P3-1531: Enforce domain and config variability - replace hardcoded domains with env vars
# @governance GOV-002: IaC, Immutable, Idempotent - All domain references must be env-var driven
# @usage domain-variability-enforcer.sh [--check] [--fix] [--report]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPORT_FILE="${REPO_ROOT}/artifacts/domain-variability-report.json"
MODE="${1:---check}"

log_error() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2; }
log_info() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"; }
log_warning() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WARN] $*"; }
log_success() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS] $*"; }

TARGET_PATTERNS=(
  'Caddyfile'
  'Caddyfile.*'
  'docker-compose*.yml'
  'docker/**/*.yml'
  'docker/**/*.yaml'
  'config/**/*.cfg'
  'config/**/*.yml'
  'config/**/*.yaml'
  'config/**/*.tpl'
  'monitoring/**/*.yml'
  'monitoring/**/*.yaml'
  'scripts/**/*.sh'
  'scripts/**/*.env'
  'terraform/**/*.tf'
  'terraform/**/*.tfvars'
)

FORBIDDEN_REGEX='kushnir[.]cloud|kushnir[.]local|code-server[.]ai|192[.]168[.]168[.](31|42|56)'

collect_target_files() {
  git -C "${REPO_ROOT}" ls-files -- "${TARGET_PATTERNS[@]}"
}

scan_file() {
  local file="$1"
  awk -v file="${file}" -v regex="${FORBIDDEN_REGEX}" '
    /^[[:space:]]*#/ { next }
    {
      line = $0
      sub(/[[:space:]]+#.*$/, "", line)
      if (line ~ /^[[:space:]]*apiVersion:[[:space:]]*code-server[.]ai\/v1[[:space:]]*$/) {
        next
      }
      if (line ~ regex) {
        printf "%s\t%d\t%s\n", file, NR, $0
      }
    }
  ' "${file}"
}

json_escape() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  printf '%s' "${value}"
}

write_report() {
  local status="$1"
  shift
  local -a violations=("$@")

  mkdir -p "$(dirname "${REPORT_FILE}")"
  {
    printf '{\n'
    printf '  "scan_timestamp": "%s",\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    printf '  "status": "%s",\n' "${status}"
    printf '  "violations": [\n'

    local first="true"
    local entry file line text
    for entry in "${violations[@]}"; do
      IFS=$'\t' read -r file line text <<< "${entry}"
      if [[ "${first}" == "false" ]]; then
        printf ',\n'
      fi
      first="false"
      printf '    {"file": "%s", "line": %s, "text": "%s"}' \
        "$(json_escape "${file}")" \
        "${line}" \
        "$(json_escape "${text}")"
    done

    printf '\n  ]\n'
    printf '}\n'
  } > "${REPORT_FILE}"
}

find_hardcoded_domains() {
  log_info "Scanning for hardcoded domain and host references..."

  local -a violations=()
  local file match_count=0

  while IFS= read -r file; do
    [[ -z "${file}" ]] && continue
    [[ "${file}" == "scripts/ci/domain-variability-enforcer.sh" ]] && continue
    while IFS=$'\t' read -r path line text; do
      [[ -z "${path}" ]] && continue
      violations+=("${path}	${line}	${text}")
      match_count=$((match_count + 1))
      log_warning "${path}:${line}: ${text}"
    done < <(scan_file "${REPO_ROOT}/${file}" || true)
  done < <(collect_target_files)

  if [[ ${#violations[@]} -gt 0 ]]; then
    write_report "FOUND_VIOLATIONS" "${violations[@]}"
    log_error "Found ${match_count} hardcoded domain or host references"
    return 1
  fi

  write_report "CLEAN"
  log_success "No hardcoded domain or host references found"
  return 0
}

apply_fixes() {
  log_info "Applying best-effort domain substitutions..."

  local files_modified=0
  local file

  while IFS= read -r file; do
    [[ -z "${file}" ]] && continue
    case "${file}" in
      *"/Caddyfile"|*"/Caddyfile.example"|"Caddyfile")
        if grep -q 'kushnir.local, \*\.kushnir.local' "${REPO_ROOT}/${file}" 2>/dev/null; then
          perl -0pi -e 's/kushnir\.local, \*\.kushnir\.local/{\$APEX_DOMAIN}, *.{\$APEX_DOMAIN}/g' "${REPO_ROOT}/${file}"
          files_modified=$((files_modified + 1))
        fi
        ;;
      *"docker/oauth2-service.yml")
        if grep -q 'auth\.kushnir\.cloud\|api\.kushnir\.cloud\|noreply@kushnir\.cloud' "${REPO_ROOT}/${file}" 2>/dev/null; then
          perl -0pi -e 's#https://auth\.kushnir\.cloud#https://auth.\$\{APEX_DOMAIN\}#g; s#https://api\.kushnir\.cloud#https://api.\$\{APEX_DOMAIN\}#g; s#noreply@kushnir\.cloud#noreply@\$\{APEX_DOMAIN\}#g' "${REPO_ROOT}/${file}"
          files_modified=$((files_modified + 1))
        fi
        ;;
      *"monitoring/alertmanager.yml")
        if grep -q 'ops@kushnir\.cloud\|alertmanager@kushnir\.cloud\|smtp\.kushnir\.cloud:587' "${REPO_ROOT}/${file}" 2>/dev/null; then
          perl -0pi -e 's#ops@kushnir\.cloud#\$\{ALERTMANAGER_EMAIL_TO\}#g; s#alertmanager@kushnir\.cloud#\$\{ALERTMANAGER_EMAIL_FROM\}#g; s#smtp\.kushnir\.cloud:587#\$\{SMTP_HOST\}#g' "${REPO_ROOT}/${file}"
          files_modified=$((files_modified + 1))
        fi
        ;;
    esac
  done < <(collect_target_files)

  log_info "Modified ${files_modified} files"
  return 0
}

main() {
  case "${MODE}" in
    --check)
      find_hardcoded_domains
      ;;
    --fix)
      apply_fixes
      find_hardcoded_domains
      ;;
    --report)
      find_hardcoded_domains
      if command -v jq >/dev/null 2>&1; then
        jq '.' "${REPORT_FILE}"
      else
        cat "${REPORT_FILE}"
      fi
      ;;
    *)
      log_error "Unknown mode: ${MODE}"
      echo "Usage: domain-variability-enforcer.sh [--check|--fix|--report]"
      exit 1
      ;;
  esac
}

main "$@"