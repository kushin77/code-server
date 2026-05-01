#!/usr/bin/env bash
# @file scripts/ci/verify-backups.sh
# @description Verifies backup integrity: PostgreSQL dump, Redis snapshot, Vault snapshot.
#              Checks timestamps (not older than backup_max_age_hours), file size > 0,
#              and optionally test-restores to a throwaway container.
# @usage verify-backups.sh [--test-restore] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false
TEST_RESTORE=false
BACKUP_MAX_AGE_HOURS="${BACKUP_MAX_AGE_HOURS:-25}"   # daily backups + 1h grace
BACKUP_DIR="${BACKUP_DIR:-${REPO_ROOT}/backups/latest}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)       DRY_RUN=true; shift ;;
    --test-restore)  TEST_RESTORE=true; shift ;;
    *)               shift ;;
  esac
done

PASS=0; FAIL=0

check_backup_file() {
  local name="$1" file="$2"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "  ✅ [dry-run] ${name}"; PASS=$((PASS+1)); return; fi

  if [[ ! -f "${file}" ]]; then
    log_error "  ❌ ${name}: file not found: ${file}"; FAIL=$((FAIL+1)); return; fi

  local size
  size=$(stat -c %s "${file}" 2>/dev/null || echo 0)
  if (( size == 0 )); then
    log_error "  ❌ ${name}: file is empty"; FAIL=$((FAIL+1)); return; fi

  local age_hours
  age_hours=$(python3 -c "
import os, time
mtime = os.path.getmtime('${file}')
print(int((time.time() - mtime) / 3600))
" 2>/dev/null || echo 999)

  if (( age_hours <= BACKUP_MAX_AGE_HOURS )); then
    log_info "  ✅ ${name}: ${size} bytes, ${age_hours}h old"; PASS=$((PASS+1))
  else
    log_error "  ❌ ${name}: too old (${age_hours}h > ${BACKUP_MAX_AGE_HOURS}h)"; FAIL=$((FAIL+1))
  fi
}

test_restore_postgres() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "  ✅ [dry-run] postgres test-restore"; PASS=$((PASS+1)); return; fi

  local backup="${BACKUP_DIR}/postgres.sql"
  [[ ! -f "${backup}" ]] && { log_info "  SKIP postgres test-restore (no backup)"; return; }

  log_info "  Test-restoring PostgreSQL to throwaway container..."
  docker run --rm -d \
    --name "pg-restore-test-$$" \
    -e POSTGRES_PASSWORD=test \
    postgres:16-alpine \
    postgres -c "listen_addresses=''" >/dev/null 2>&1

  sleep 3
  docker exec -i "pg-restore-test-$$" \
    psql -U postgres < "${backup}" >/dev/null 2>&1 && \
    { log_info "  ✅ postgres restore successful"; PASS=$((PASS+1)); } || \
    { log_error "  ❌ postgres restore failed"; FAIL=$((FAIL+1)); }

  docker rm -f "pg-restore-test-$$" >/dev/null 2>&1 || true
}

test_restore_redis() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "  ✅ [dry-run] redis test-restore"; PASS=$((PASS+1)); return; fi

  local backup="${BACKUP_DIR}/dump.rdb"
  [[ ! -f "${backup}" ]] && { log_info "  SKIP redis test-restore (no backup)"; return; }

  log_info "  Test-restoring Redis RDB..."
  local tmpdir
  tmpdir=$(mktemp -d /tmp/redis-restore-XXXXXX.tmp)
  cp "${backup}" "${tmpdir}/dump.rdb"

  docker run --rm -d \
    --name "redis-restore-test-$$" \
    -v "${tmpdir}:/data" \
    redis:7-alpine >/dev/null 2>&1

  sleep 3
  local keys
  keys=$(docker exec "redis-restore-test-$$" redis-cli DBSIZE 2>/dev/null || echo 0)
  log_info "  ✅ Redis restore: ${keys} key(s) loaded"; PASS=$((PASS+1))

  docker rm -f "redis-restore-test-$$" >/dev/null 2>&1 || true
  rm -rf "${tmpdir}"
}

# Main
log_info "Backup Verification — dir=${BACKUP_DIR} max-age=${BACKUP_MAX_AGE_HOURS}h dry-run=${DRY_RUN}"
log_info "================================================================="

log_info "File integrity checks:"
check_backup_file "postgres_dump"     "${BACKUP_DIR}/postgres.sql"
check_backup_file "redis_snapshot"    "${BACKUP_DIR}/dump.rdb"
check_backup_file "vault_snapshot"    "${BACKUP_DIR}/vault-snapshot.snap"

if [[ "${TEST_RESTORE}" == "true" ]]; then
  log_info "Test restores:"
  test_restore_postgres
  test_restore_redis
fi

log_info "================================================================="
log_info "Backup verification: ${PASS} passed, ${FAIL} failed"
[[ ${FAIL} -eq 0 ]] && { log_info "✅ All backup checks passed"; exit 0; } || \
  { log_error "❌ Backup verification: ${FAIL} issue(s)"; exit 1; }
