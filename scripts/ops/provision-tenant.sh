#!/usr/bin/env bash
# @file scripts/ops/provision-tenant.sh
# @description Provision a new tenant (isolated workspace + DB schema + Vault namespace).
#              Creates per-tenant resources: PostgreSQL schema, Redis key prefix,
#              Vault policy, and workspace directory.
# @usage provision-tenant.sh --tenant <id> --email <admin-email> [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false
TENANT_ID=""
ADMIN_EMAIL=""
TENANT_LOG="${REPO_ROOT}/artifacts/provision-tenant-$(date +%s).log"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --tenant)  TENANT_ID="$2"; shift 2 ;;
    --email)   ADMIN_EMAIL="$2"; shift 2 ;;
    *)         shift ;;
  esac
done

[[ -z "${TENANT_ID}" ]] && { log_error "Usage: $0 --tenant <id> --email <admin-email>"; exit 1; }
[[ -z "${ADMIN_EMAIL}" ]] && { log_error "Usage: $0 --tenant <id> --email <admin-email>"; exit 1; }

# Validate tenant ID: alphanumeric + hyphens, 3-32 chars
if ! echo "${TENANT_ID}" | grep -qE '^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$'; then
  log_error "Invalid tenant ID '${TENANT_ID}'. Must be 3-32 lowercase alphanumeric + hyphens."
  exit 1
fi

mkdir -p "${REPO_ROOT}/artifacts"

run_or_dry() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] $*"
  else
    "$@"
  fi
}

create_pg_schema() {
  log_info "Creating PostgreSQL schema: tenant_${TENANT_ID}"
  run_or_dry docker exec code-server-postgres psql -U postgres -d code_server << SQL
CREATE SCHEMA IF NOT EXISTS "tenant_${TENANT_ID}";
GRANT USAGE ON SCHEMA "tenant_${TENANT_ID}" TO code_server;
GRANT CREATE ON SCHEMA "tenant_${TENANT_ID}" TO code_server;
INSERT INTO tenants (id, admin_email, schema_name, created_at)
  VALUES ('${TENANT_ID}', '${ADMIN_EMAIL}', 'tenant_${TENANT_ID}', NOW())
  ON CONFLICT (id) DO NOTHING;
SQL
  log_info "  ✅ PostgreSQL schema created"
}

create_vault_policy() {
  log_info "Creating Vault policy: tenants/${TENANT_ID}"
  local policy_hcl
  policy_hcl=$(cat << VAULT_POLICY
path "secret/data/tenants/${TENANT_ID}/*" {
  capabilities = ["create","read","update","delete","list"]
}
path "secret/metadata/tenants/${TENANT_ID}/*" {
  capabilities = ["read","list","delete"]
}
VAULT_POLICY
)
  if [[ "${DRY_RUN}" != "true" ]]; then
    echo "${policy_hcl}" | VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}" \
      vault policy write "tenant-${TENANT_ID}" -
    log_info "  ✅ Vault policy created: tenant-${TENANT_ID}"
  else
    log_info "[DRY-RUN] would create Vault policy tenant-${TENANT_ID}"
  fi
}

create_workspace_dir() {
  local workspace_dir="${REPO_ROOT}/workspaces/${TENANT_ID}"
  log_info "Creating workspace directory: ${workspace_dir}"
  run_or_dry mkdir -p "${workspace_dir}"
  run_or_dry chmod 750 "${workspace_dir}"
  log_info "  ✅ Workspace directory created"
}

register_tenant_config() {
  local config_file="${REPO_ROOT}/configs/tenants/${TENANT_ID}.yml"
  log_info "Writing tenant config: ${config_file}"
  if [[ "${DRY_RUN}" != "true" ]]; then
    mkdir -p "$(dirname "${config_file}")"
    cat > "${config_file}" << YAML
# Tenant: ${TENANT_ID}
# Provisioned: $(date -u +%Y-%m-%dT%H:%M:%SZ)
id: "${TENANT_ID}"
admin_email: "${ADMIN_EMAIL}"
schema: "tenant_${TENANT_ID}"
vault_policy: "tenant-${TENANT_ID}"
workspace_path: "workspaces/${TENANT_ID}"
YAML
    log_info "  ✅ Tenant config written"
  else
    log_info "[DRY-RUN] would write ${config_file}"
  fi
}

# Main
log_info "Provision Tenant — id=${TENANT_ID} email=${ADMIN_EMAIL} dry-run=${DRY_RUN}" \
  | tee -a "${TENANT_LOG}"
log_info "================================================================="

create_pg_schema
create_vault_policy
create_workspace_dir
register_tenant_config

log_info "================================================================="
log_info "Tenant '${TENANT_ID}' provisioned successfully"
log_info "Log: ${TENANT_LOG}"
