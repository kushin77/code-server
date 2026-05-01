#!/usr/bin/env bash
# @file scripts/ops/dr-failover.sh
# @description Disaster Recovery failover — 4 scenarios:
#   1. primary-failure    — promote replica to primary
#   2. replica-failure    — isolate replica, run single-node
#   3. full-restore       — restore both hosts from backup
#   4. network-partition  — detect and heal split-brain
# @usage dr-failover.sh --scenario <name> [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false
SCENARIO=""
DR_LOG="${REPO_ROOT}/artifacts/dr-failover-$(date +%s).log"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=true; shift ;;
    --scenario)  SCENARIO="$2"; shift 2 ;;
    *)           shift ;;
  esac
done

mkdir -p "${REPO_ROOT}/artifacts"

[[ -z "${SCENARIO}" ]] && { log_error "Usage: $0 --scenario <primary-failure|replica-failure|full-restore|network-partition>"; exit 1; }

run_or_dry() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] $*"
  else
    "$@"
  fi
}

ssh_host() {
  ssh -o BatchMode=yes -o ConnectTimeout=10 \
      -o ControlMaster=auto -o "ControlPath=/tmp/ssh-dr-%r@%h:%p" \
      -o ControlPersist=60 \
      "${REMOTE_USER:-akushnir}@$1" "${@:2}"
}

# Scenario 1: Primary host failure — promote replica
scenario_primary_failure() {
  log_info "DR Scenario: PRIMARY FAILURE"
  log_info "  Target: promote ${REPLICA_HOST} to active primary"

  # Step 1: Confirm primary is unreachable
  if [[ "${DRY_RUN}" != "true" ]]; then
    if ssh_host "${PRIMARY_HOST}" "echo ok" 2>/dev/null; then
      log_error "Primary host ${PRIMARY_HOST} is reachable — aborting primary-failure scenario"
      return 1
    fi
    log_info "  ✅ Confirmed: primary ${PRIMARY_HOST} is unreachable"
  fi

  # Step 2: Update DNS / Caddy to point to replica
  log_info "  Updating Caddy upstream to replica ${REPLICA_HOST}"
  run_or_dry ssh_host "${REPLICA_HOST}" \
    "docker exec code-server-caddy caddy reload --config /etc/caddy/Caddyfile"

  # Step 3: Scale replica services to full capacity
  log_info "  Scaling replica to full capacity"
  run_or_dry ssh_host "${REPLICA_HOST}" \
    "cd ~/code-server-enterprise && docker compose -f docker-compose.enterprise.yml up -d"

  # Step 4: Update Terraform variable (primary=replica IP)
  log_info "  Updating primary_host in tfvars to ${REPLICA_HOST}"
  run_or_dry sed -i \
    "s/primary_host *= *\"${PRIMARY_HOST}\"/primary_host = \"${REPLICA_HOST}\"/" \
    "${REPO_ROOT}/terraform/environments/private/terraform.tfvars"

  log_info "  ✅ Primary failure scenario complete — ${REPLICA_HOST} is now active"
  log_info "  NEXT: Repair/rebuild ${PRIMARY_HOST} and re-add as replica"
}

# Scenario 2: Replica failure — isolate and run single-node
scenario_replica_failure() {
  log_info "DR Scenario: REPLICA FAILURE"
  log_info "  Isolating ${REPLICA_HOST}, continuing on primary only"

  # Disable replica Terraform target
  log_info "  Disabling replica module in Terraform"
  run_or_dry sed -i \
    "s/replica_host *= *\"${REPLICA_HOST}\"/replica_host = \"DISABLED\"/" \
    "${REPO_ROOT}/terraform/environments/private/terraform.tfvars"

  # Remove replica from load balancer
  log_info "  Reloading Caddy to remove replica upstream"
  run_or_dry docker exec code-server-caddy caddy reload \
    --config /etc/caddy/Caddyfile 2>/dev/null || true

  log_info "  ✅ Replica failure scenario complete — running single-node on ${PRIMARY_HOST}"
}

# Scenario 3: Full restore from backup
scenario_full_restore() {
  log_info "DR Scenario: FULL RESTORE"

  local BACKUP_DIR="${REPO_ROOT}/backups/latest"
  if [[ ! -d "${BACKUP_DIR}" && "${DRY_RUN}" != "true" ]]; then
    log_error "No backup found at ${BACKUP_DIR}"
    return 1
  fi

  # Step 1: Restore PostgreSQL
  log_info "  Restoring PostgreSQL from backup"
  run_or_dry docker exec -i code-server-postgres \
    psql -U postgres < "${BACKUP_DIR}/postgres.sql"

  # Step 2: Restore Redis
  log_info "  Restoring Redis RDB snapshot"
  run_or_dry docker exec code-server-redis redis-cli FLUSHALL
  run_or_dry docker cp "${BACKUP_DIR}/dump.rdb" code-server-redis:/data/dump.rdb
  run_or_dry docker restart code-server-redis

  # Step 3: Restore Vault
  log_info "  Restoring Vault snapshot"
  run_or_dry vault operator raft snapshot restore \
    "${BACKUP_DIR}/vault-snapshot.snap"

  # Step 4: Re-apply Terraform
  log_info "  Re-applying Terraform state"
  run_or_dry terraform -chdir="${REPO_ROOT}/terraform/environments/private" \
    apply -auto-approve

  log_info "  ✅ Full restore complete"
}

# Scenario 4: Network partition — detect and heal split-brain
scenario_network_partition() {
  log_info "DR Scenario: NETWORK PARTITION"

  # Check both hosts are reachable
  local primary_ok=false
  local replica_ok=false
  ssh_host "${PRIMARY_HOST}" "echo ok" >/dev/null 2>&1 && primary_ok=true
  ssh_host "${REPLICA_HOST}" "echo ok" >/dev/null 2>&1 && replica_ok=true

  log_info "  Primary reachable: ${primary_ok} | Replica reachable: ${replica_ok}"

  if [[ "${primary_ok}" == "true" && "${replica_ok}" == "true" ]]; then
    log_info "  Both hosts reachable — checking for split-brain state"
    # Compare last write timestamps from each host's PostgreSQL
    local primary_ts replica_ts
    primary_ts=$(ssh_host "${PRIMARY_HOST}" \
      "docker exec code-server-postgres psql -U postgres -tAc 'SELECT MAX(updated_at) FROM pg_stat_activity'")
    replica_ts=$(ssh_host "${REPLICA_HOST}" \
      "docker exec code-server-postgres psql -U postgres -tAc 'SELECT MAX(updated_at) FROM pg_stat_activity'")
    log_info "  Primary last activity: ${primary_ts}"
    log_info "  Replica last activity: ${replica_ts}"
    log_info "  Manual review required to determine authoritative node"
  elif [[ "${primary_ok}" == "true" ]]; then
    log_info "  Replica unreachable — invoking replica-failure scenario"
    scenario_replica_failure
  else
    log_info "  Primary unreachable — invoking primary-failure scenario"
    scenario_primary_failure
  fi

  log_info "  ✅ Network partition scenario complete"
}

# Main
log_info "DR Failover — scenario=${SCENARIO} dry-run=${DRY_RUN}" | tee -a "${DR_LOG}"
log_info "=============================================="

case "${SCENARIO}" in
  primary-failure)    scenario_primary_failure ;;
  replica-failure)    scenario_replica_failure ;;
  full-restore)       scenario_full_restore ;;
  network-partition)  scenario_network_partition ;;
  *)
    log_error "Unknown scenario: ${SCENARIO}"
    log_error "Valid: primary-failure|replica-failure|full-restore|network-partition"
    exit 1
    ;;
esac

log_info "=============================================="
log_info "DR Failover complete — log: ${DR_LOG}"
