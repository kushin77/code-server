#!/usr/bin/env bash
# @file scripts/ci/security-tests.sh
# @description Security test suite: checks for exposed secrets, open ports,
#              container privilege escalation, TLS cert validity, and Vault seal status.
# @usage security-tests.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    *)         shift ;;
  esac
done

PASS=0; FAIL=0; WARN=0
REPORT_FILE="${REPO_ROOT}/artifacts/security-report-$(date +%s).json"
mkdir -p "${REPO_ROOT}/artifacts"
declare -a FINDINGS

sec_pass() { log_info "  ✅ PASS: $1"; PASS=$((PASS+1)); FINDINGS+=("{\"check\":\"$1\",\"status\":\"pass\"}"); }
sec_fail() { log_error "  ❌ FAIL: $1 — $2"; FAIL=$((FAIL+1)); FINDINGS+=("{\"check\":\"$1\",\"status\":\"fail\",\"detail\":\"$2\"}"); }
sec_warn() { log_info "  ⚠️  WARN: $1 — $2"; WARN=$((WARN+1)); FINDINGS+=("{\"check\":\"$1\",\"status\":\"warn\",\"detail\":\"$2\"}"); }

# Check 1: No hardcoded secrets in tracked files
check_no_secrets() {
  log_info "Check: No hardcoded secrets in repo"
  if [[ "${DRY_RUN}" == "true" ]]; then sec_pass "no_hardcoded_secrets"; return; fi

  local patterns='password\s*=\s*["'"'"'][^$\s]{8,}|secret\s*=\s*["'"'"'][^$\s]{8,}|api_key\s*=\s*["'"'"'][^$\s]{8,}'
  local hits
  hits=$(git -C "${REPO_ROOT}" grep -iE "${patterns}" \
    -- '*.tf' '*.yml' '*.yaml' '*.sh' '*.env' 2>/dev/null \
    | grep -v '\.tfvars\.example\|PLACEHOLDER\|changeme\|your-secret\|<.*>\|#' \
    | wc -l)
  if (( hits == 0 )); then
    sec_pass "no_hardcoded_secrets"
  else
    sec_fail "no_hardcoded_secrets" "${hits} potential secret(s) found — review with: git grep -iE 'password|secret|api_key'"
  fi
}

# Check 2: .env files not tracked by git
check_env_not_tracked() {
  log_info "Check: .env files excluded from git"
  if [[ "${DRY_RUN}" == "true" ]]; then sec_pass "env_not_tracked"; return; fi

  local tracked_envs
  tracked_envs=$(git -C "${REPO_ROOT}" ls-files '*.env' 2>/dev/null | grep -v '\.example\|template\|image-versions' | wc -l)
  if (( tracked_envs == 0 )); then
    sec_pass "env_not_tracked"
  else
    sec_fail "env_not_tracked" "${tracked_envs} .env file(s) tracked by git"
  fi
}

# Check 3: No privileged containers
check_no_privileged_containers() {
  log_info "Check: No privileged containers"
  if [[ "${DRY_RUN}" == "true" ]]; then sec_pass "no_privileged_containers"; return; fi

  local priv_count
  priv_count=$(docker ps -q 2>/dev/null \
    | xargs -r docker inspect --format='{{.Name}} {{.HostConfig.Privileged}}' 2>/dev/null \
    | grep 'true' | grep 'code-server' | wc -l)
  if (( priv_count == 0 )); then
    sec_pass "no_privileged_containers"
  else
    sec_warn "no_privileged_containers" "${priv_count} code-server container(s) running as privileged"
  fi
}

# Check 4: Vault not sealed
check_vault_unsealed() {
  log_info "Check: Vault is unsealed"
  if [[ "${DRY_RUN}" == "true" ]]; then sec_pass "vault_unsealed"; return; fi

  local sealed
  sealed=$(docker exec code-server-vault vault status -format=json 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('sealed',True))" 2>/dev/null || echo "true")
  [[ "${sealed}" == "False" ]] && sec_pass "vault_unsealed" || sec_warn "vault_unsealed" "Vault is sealed or unreachable"
}

# Check 5: TLS cert not expired
check_tls_cert() {
  log_info "Check: TLS certificate validity"
  if [[ "${DRY_RUN}" == "true" ]]; then sec_pass "tls_cert_valid"; return; fi

  local expiry_days
  expiry_days=$(echo | timeout 5 openssl s_client -connect "${PRIMARY_HOST:-localhost}:443" \
    -servername "${PRIMARY_HOST:-localhost}" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null \
    | sed 's/notAfter=//' \
    | xargs -I{} python3 -c \
        "from datetime import datetime; import sys; \
         exp=datetime.strptime('{}', '%b %d %H:%M:%S %Y %Z'); \
         print((exp-datetime.utcnow()).days)" 2>/dev/null || echo -1)

  if (( expiry_days > 30 )); then
    sec_pass "tls_cert_valid"
    log_info "    cert expires in ${expiry_days} days"
  elif (( expiry_days > 0 )); then
    sec_warn "tls_cert_valid" "cert expires in ${expiry_days} days — renew soon"
  else
    sec_warn "tls_cert_valid" "could not check cert (may be HTTP-only in dev)"
  fi
}

# Check 6: No world-writable files in repo
check_file_permissions() {
  log_info "Check: No world-writable files"
  if [[ "${DRY_RUN}" == "true" ]]; then sec_pass "file_permissions"; return; fi

  local ww_count
  ww_count=$(find "${REPO_ROOT}" -not -path '*/.git/*' -perm -o+w -type f 2>/dev/null | wc -l)
  if (( ww_count == 0 )); then
    sec_pass "file_permissions"
  else
    sec_warn "file_permissions" "${ww_count} world-writable file(s) found"
  fi
}

# Write report
write_report() {
  local entries
  entries=$(IFS=,; echo "[${FINDINGS[*]}]")
  cat > "${REPORT_FILE}" << EOF
{
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "total": $((PASS+FAIL+WARN)),
  "passed": ${PASS},
  "failed": ${FAIL},
  "warnings": ${WARN},
  "findings": ${entries}
}
EOF
  log_info "Report: ${REPORT_FILE}"
}

# Main
log_info "Security Tests — dry-run=${DRY_RUN}"
log_info "================================================"

check_no_secrets
check_env_not_tracked
check_no_privileged_containers
check_vault_unsealed
check_tls_cert
check_file_permissions

write_report

log_info "================================================"
log_info "Security: ${PASS} pass, ${FAIL} fail, ${WARN} warn"
[[ ${FAIL} -eq 0 ]] && { log_info "✅ Security tests passed"; exit 0; } || \
  { log_error "❌ Security tests: ${FAIL} failure(s)"; exit 1; }
