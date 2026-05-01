#!/usr/bin/env bash
# @file scripts/ci/tenant-pipeline.sh
# @description CI pipeline for tenant operations: provision, validate, promote, deprovision.
#              Run with --action to perform a single step or --all for the full cycle.
# @usage tenant-pipeline.sh --tenant <id> --action <provision|validate|deprovision|all> [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false
TENANT_ID=""
ACTION=""
ADMIN_EMAIL="${ADMIN_EMAIL:-ops@code-server.internal}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --tenant)  TENANT_ID="$2"; shift 2 ;;
    --action)  ACTION="$2"; shift 2 ;;
    --email)   ADMIN_EMAIL="$2"; shift 2 ;;
    *)         shift ;;
  esac
done

[[ -z "${TENANT_ID}" ]] && { log_error "Usage: $0 --tenant <id> --action <action>"; exit 1; }
[[ -z "${ACTION}" ]]    && { log_error "Usage: $0 --tenant <id> --action <action>"; exit 1; }

run_or_dry() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] $*"
  else
    "$@"
  fi
}

action_provision() {
  log_info "Pipeline: Provision tenant ${TENANT_ID}"
  run_or_dry bash "${REPO_ROOT}/scripts/ops/provision-tenant.sh" \
    --tenant "${TENANT_ID}" \
    --email  "${ADMIN_EMAIL}" \
    ${DRY_RUN:+--dry-run}
}

action_validate() {
  log_info "Pipeline: Validate tenant ${TENANT_ID}"
  local config="${REPO_ROOT}/configs/tenants/${TENANT_ID}.yml"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "  ✅ [dry-run] config exists"; return; fi

  if [[ ! -f "${config}" ]]; then
    log_error "  ❌ tenant config missing: ${config}"
    return 1
  fi
  log_info "  ✅ tenant config exists"

  # Validate schema exists in PG
  local schema_exists
  schema_exists=$(docker exec code-server-postgres psql -U postgres -d code_server -tAc \
    "SELECT 1 FROM information_schema.schemata WHERE schema_name='tenant_${TENANT_ID}'" 2>/dev/null || echo "")
  [[ "${schema_exists}" == "1" ]] && \
    log_info "  ✅ PG schema exists" || log_info "  ⚠️  PG schema not found (may not be live)"
}

action_deprovision() {
  log_info "Pipeline: Deprovision tenant ${TENANT_ID}"

  run_or_dry docker exec code-server-postgres psql -U postgres -d code_server \
    -c "DROP SCHEMA IF EXISTS \"tenant_${TENANT_ID}\" CASCADE;" 2>/dev/null || true

  if [[ "${DRY_RUN}" != "true" ]]; then
    VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}" \
      vault policy delete "tenant-${TENANT_ID}" 2>/dev/null || true
    rm -f "${REPO_ROOT}/configs/tenants/${TENANT_ID}.yml"
    rm -rf "${REPO_ROOT}/workspaces/${TENANT_ID}"
    log_info "  ✅ Tenant ${TENANT_ID} deprovisioned"
  else
    log_info "  [DRY-RUN] would drop PG schema, delete Vault policy, remove configs"
  fi
}

# Main
log_info "Tenant Pipeline — tenant=${TENANT_ID} action=${ACTION} dry-run=${DRY_RUN}"
log_info "================================================================"

case "${ACTION}" in
  provision)    action_provision ;;
  validate)     action_validate ;;
  deprovision)  action_deprovision ;;
  all)
    action_provision
    action_validate
    ;;
  *)
    log_error "Unknown action: ${ACTION}. Valid: provision|validate|deprovision|all"
    exit 1
    ;;
esac

log_info "================================================================"
log_info "Tenant pipeline complete: ${TENANT_ID} / ${ACTION}"
