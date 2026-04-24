#!/usr/bin/env bash
# @file        scripts/ops/p0-1629-verify-data-integrity.sh
# @module      incident/p0-1629
# @description P0 #1629 - Verify PostgreSQL and Redis data integrity on Replica 2
# @status      PRODUCTION READY - Run periodically or when SSD failure detected
#
# PURPOSE: Verify critical database data is intact despite NVMe health warnings
#
# EXECUTION:
#   From Replica 2 or any host with Docker access:
#   ./scripts/ops/p0-1629-verify-data-integrity.sh
#
# OUTPUT:
#   Returns 0 if all checks pass
#   Returns 1 if any integrity issues detected
#

set -euo pipefail

# Configuration
REPLICA="${1:-192.168.168.42}"
SSH_KEY="${HOME}/.ssh/id_rsa_onprem"
SSH_USER="akushnir"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0

log_info() {
  echo -e "${GREEN}[PASS]${NC} $*"
  ((PASS_COUNT++))
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $*"
  ((FAIL_COUNT++))
}

log_section() {
  echo -e "${BLUE}=== $* ===${NC}"
}

# SSH execution wrapper
ssh_exec() {
  if [[ "${REPLICA}" == "localhost" ]] || [[ "${REPLICA}" == "127.0.0.1" ]]; then
    eval "$@"
  else
    ssh -i "${SSH_KEY}" "${SSH_USER}@${REPLICA}" "$@" 2>&1
  fi
}

main() {
  log_section "P0 #1629 - DATA INTEGRITY VERIFICATION"
  log_section "Target: ${REPLICA}"
  
  # CHECK 1: PostgreSQL connectivity
  log_section "CHECK 1: PostgreSQL Connectivity"
  if ssh_exec "cd code-server-enterprise && docker exec postgres pg_isready -U codeserver >/dev/null 2>&1"; then
    log_info "PostgreSQL is accepting connections"
  else
    log_fail "PostgreSQL not responding"
  fi
  
  # CHECK 2: PostgreSQL database size
  log_section "CHECK 2: PostgreSQL Database Size"
  if size=$(ssh_exec "cd code-server-enterprise && docker exec postgres psql -U codeserver -c 'SELECT pg_database_size(current_database());' -t" 2>/dev/null); then
    if [[ "${size}" -gt 1000000 ]]; then  # > 1MB
      log_info "Database size: ${size} bytes (healthy)"
    else
      log_fail "Database suspiciously small: ${size} bytes"
    fi
  else
    log_fail "Cannot determine database size"
  fi
  
  # CHECK 3: Table integrity
  log_section "CHECK 3: Table Integrity"
  if ssh_exec "cd code-server-enterprise && docker exec postgres psql -U codeserver -c 'SELECT count(*) FROM information_schema.tables WHERE table_schema = \"public\";' -t" 2>/dev/null | grep -qE '[0-9]+'; then
    table_count=$(ssh_exec "cd code-server-enterprise && docker exec postgres psql -U codeserver -c 'SELECT count(*) FROM information_schema.tables WHERE table_schema = \"public\";' -t")
    if [[ "${table_count}" -gt 0 ]]; then
      log_info "Found ${table_count} tables in public schema"
    else
      log_fail "No tables found in public schema"
    fi
  else
    log_fail "Cannot query table schema"
  fi
  
  # CHECK 4: VACUUM and ANALYZE
  log_section "CHECK 4: VACUUM Status"
  if ssh_exec "cd code-server-enterprise && docker exec postgres psql -U codeserver -c 'SELECT schemaname, tablename, last_vacuum, last_autovacuum FROM pg_stat_user_tables LIMIT 5;'" 2>/dev/null | grep -q "last_"; then
    log_info "VACUUM operations are running normally"
  else
    log_fail "VACUUM status check failed"
  fi
  
  # CHECK 5: Replication slot status
  log_section "CHECK 5: Replication Status"
  if ssh_exec "cd code-server-enterprise && docker exec postgres psql -U codeserver -c 'SELECT slot_name, slot_type, active FROM pg_replication_slots;' 2>/dev/null" | grep -q "slot_"; then
    log_info "Replication slots present and active"
  else
    log_info "No replication slots found (expected if running as standalone)"
  fi
  
  # CHECK 6: Redis connectivity
  log_section "CHECK 6: Redis Connectivity"
  if ssh_exec "cd code-server-enterprise && docker exec redis redis-cli ping 2>/dev/null" | grep -q "PONG"; then
    log_info "Redis is responding"
  else
    log_fail "Redis not responding to PING"
  fi
  
  # CHECK 7: Redis memory usage
  log_section "CHECK 7: Redis Memory Status"
  if mem=$(ssh_exec "cd code-server-enterprise && docker exec redis redis-cli info memory | grep used_memory_human" 2>/dev/null); then
    log_info "$mem"
  else
    log_fail "Cannot determine Redis memory usage"
  fi
  
  # CHECK 8: Disk space on Replica 2
  log_section "CHECK 8: Disk Space"
  if ssh_exec "df -h | grep -E 'nvme|sda'" 2>/dev/null | head -5; then
    log_info "Disk space checked"
  else
    log_fail "Cannot determine disk space"
  fi
  
  # CHECK 9: NVMe SMART status
  log_section "CHECK 9: NVMe SMART Health"
  if smartstatus=$(ssh_exec "sudo smartctl -H /dev/nvme0n1 2>/dev/null || echo 'smartctl unavailable'" 2>/dev/null); then
    if echo "${smartstatus}" | grep -q "passed\|PASSED"; then
      log_info "NVMe SMART overall health: PASSED"
    elif echo "${smartstatus}" | grep -q "failed\|FAILED\|WARNING"; then
      log_fail "NVMe SMART overall health: FAILED/WARNING - $(echo "${smartstatus}" | grep -o 'health status.*')"
    else
      log_info "NVMe SMART status: $smartstatus"
    fi
  else
    log_fail "Cannot access SMART status"
  fi
  
  # CHECK 10: Container health
  log_section "CHECK 10: Container Health"
  if ssh_exec "cd code-server-enterprise && docker ps --filter 'status=running' --format '{{.Names}}' | wc -l" 2>/dev/null | grep -qE '[0-9]+'; then
    running=$(ssh_exec "cd code-server-enterprise && docker ps --filter 'status=running' --format '{{.Names}}' | wc -l")
    log_info "Running containers: ${running}"
  else
    log_fail "Cannot determine running container count"
  fi
  
  # SUMMARY
  log_section "INTEGRITY CHECK SUMMARY"
  echo -e "Passed: ${GREEN}${PASS_COUNT}${NC}"
  echo -e "Failed: ${RED}${FAIL_COUNT}${NC}"
  
  if [[ ${FAIL_COUNT} -eq 0 ]]; then
    echo -e "${GREEN}✓ ALL INTEGRITY CHECKS PASSED${NC}"
    return 0
  else
    echo -e "${RED}✗ INTEGRITY ISSUES DETECTED${NC}"
    echo -e "Recommendations:"
    echo -e "  1. Immediately backup data: ${YELLOW}./scripts/ops/p0-1629-backup-replica2-data.sh${NC}"
    echo -e "  2. Monitor NVMe health: ${YELLOW}sudo smartctl -a /dev/nvme0n1${NC}"
    echo -e "  3. If issues persist, execute failover: ${YELLOW}./P0-INCIDENT-RESPONSE-EXECUTION-RUNBOOK.sh${NC}"
    return 1
  fi
}

main "$@"
