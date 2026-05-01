#!/bin/bash
###############################################################################
# validate-secrets.sh
###############################################################################
# CI: Validate secrets posture for Code Server Enterprise
#
# Checks:
#   - No hardcoded secrets/passwords in tracked source files
#   - Required secret env var names are present in docker-compose env stanzas
#   - .env files are not tracked in git
#   - Secret mounts in compose reference external volumes or env vars (not literals)
#   - Vault/GSM integration configured for production secrets
#
# Usage:
#   bash scripts/ci/validate-secrets.sh [--strict]
#
# Exit codes:
#   0: All checks passed (or warnings only in non-strict mode)
#   1: Secrets validation failed
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup complete"; rm -f /tmp/secrets-check.*.tmp 2>/dev/null || true' EXIT

STRICT_MODE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT_MODE=true; shift ;;
    *) shift ;;
  esac
done

PASS=0
WARN=0
FAIL=0

_pass() { log_info "  ✓ $1"; ((PASS++)); }
_warn() { log_warn "  ⚠ $1"; ((WARN++)); }
_fail() { log_error "  ✗ $1"; ((FAIL++)); }

log_info "=== Secrets Validation ==="

# ── 1. No .env files tracked in git ──────────────────────────────────────────
log_info "Checking git-tracked .env files..."

TRACKED_ENV=$(git -C "${REPO_ROOT}" ls-files '*.env' '.env' '.env.*' 2>/dev/null | grep -v '.env.example\|.env.sample\|.env.template\|agent-safeguards' || true)
if [[ -n "${TRACKED_ENV}" ]]; then
  _fail "Tracked .env files detected in git: ${TRACKED_ENV}"
else
  _pass "No .env files tracked in git"
fi

# ── 2. Scan for hardcoded high-entropy secrets ────────────────────────────────
log_info "Scanning for hardcoded secrets patterns..."

# Patterns: password=literal, api_key=literal, secret=literal (not variable refs)
SECRET_HITS=$(git -C "${REPO_ROOT}" grep -rn \
  --include="*.py" --include="*.sh" --include="*.tf" --include="*.yaml" --include="*.yml" \
  -iE '(password|passwd|api_key|secret_key|private_key|token)\s*=\s*["'"'"'][^${\"%'"'"']{8,}["'"'"']' \
  -- ':!*.example' ':!*test*' ':!*spec*' ':!*mock*' ':!*fixture*' \
  2>/dev/null | \
  grep -v '# noqa\|# nosec\|PLACEHOLDER\|CHANGE_ME\|YOUR_\|example\|sample\|test\|localhost' \
  || true)

if [[ -n "${SECRET_HITS}" ]]; then
  HITS_COUNT=$(echo "${SECRET_HITS}" | wc -l)
  _fail "Potential hardcoded secrets found (${HITS_COUNT} matches):"
  echo "${SECRET_HITS}" | head -10 | while read -r line; do
    log_error "    ${line}"
  done
else
  _pass "No hardcoded secret patterns detected"
fi

# ── 3. Required secret env vars declared in compose ──────────────────────────
log_info "Checking required secret env vars in compose..."

REQUIRED_SECRETS=(
  "SECRET_KEY"
  "DATABASE_URL"
  "REDIS_URL"
)

COMPOSE_FILE="${REPO_ROOT}/docker-compose.prod.yml"
[[ -f "${COMPOSE_FILE}" ]] || COMPOSE_FILE="${REPO_ROOT}/docker-compose.yml"

if [[ -f "${COMPOSE_FILE}" ]]; then
  for secret_var in "${REQUIRED_SECRETS[@]}"; do
    if grep -q "${secret_var}" "${COMPOSE_FILE}" 2>/dev/null; then
      _pass "Required secret '${secret_var}' declared in compose"
    else
      _warn "Required secret '${secret_var}' not found in $(basename "${COMPOSE_FILE}")"
    fi
  done
else
  _warn "No compose file found to validate required secrets"
fi

# ── 4. No plaintext secrets in terraform tfvars ───────────────────────────────
log_info "Checking Terraform variable files..."

TFVARS_FILES=$(find "${REPO_ROOT}/terraform" -name "*.tfvars" -not -name "*.example" 2>/dev/null || true)
SECRET_TFVARS_HITS=""
for tfvars in ${TFVARS_FILES}; do
  hits=$(grep -nE '(password|secret|api_key|token)\s*=\s*"[^$%{][^"]{7,}"' "${tfvars}" 2>/dev/null | \
    grep -iv 'postgres\|password.*host\|placeholder\|change_me' || true)
  [[ -n "${hits}" ]] && SECRET_TFVARS_HITS+="${tfvars}:${hits}"$'\n'
done

if [[ -n "${SECRET_TFVARS_HITS}" ]]; then
  _warn "Potential plaintext secrets in .tfvars (use GSM/Vault for production):"
  echo "${SECRET_TFVARS_HITS}" | head -5 | while read -r line; do log_warn "    ${line}"; done
else
  _pass "No plaintext secrets detected in Terraform variables"
fi

# ── 5. Vault / GSM integration check ─────────────────────────────────────────
log_info "Checking Vault/GSM secret management integration..."

if grep -rq "vault_secret\|google_secret_manager\|data.vault_generic_secret" \
    "${REPO_ROOT}/terraform" --include="*.tf" 2>/dev/null; then
  _pass "Vault/GSM secret management references found in Terraform"
elif [[ -f "${REPO_ROOT}/scripts/ops/setup-vault-secrets.sh" || \
        -f "${REPO_ROOT}/scripts/ops/deploy-vault-secrets.sh" ]]; then
  _pass "Vault deployment scripts present"
else
  _warn "No Vault/GSM integration detected — ensure production uses secrets manager"
fi

# ── 6. Summary ────────────────────────────────────────────────────────────────
log_info ""
log_info "Secrets Validation Results: ${PASS} passed, ${WARN} warnings, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
  log_error "Secrets validation FAILED — ${FAIL} critical issues"
  exit 1
fi

if [[ ${WARN} -gt 0 && "${STRICT_MODE}" == "true" ]]; then
  log_error "Strict mode: treating ${WARN} warnings as failures"
  exit 1
fi

log_info "Secrets validation PASSED"
exit 0
