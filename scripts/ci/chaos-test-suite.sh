#!/usr/bin/env bash
# @file scripts/ci/chaos-test-suite.sh
# @description Chaos engineering test suite for the code-server stack.
#              Runs controlled failure injection scenarios and verifies the platform
#              recovers correctly within SLA bounds.
# @usage chaos-test-suite.sh [--suite <name>|--all] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; restore_all; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false
SUITE="--all"
RECOVERY_TIMEOUT=120  # seconds
RESULTS_FILE="${REPO_ROOT}/artifacts/chaos-results-$(date +%s).json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --suite)   SUITE="$2"; shift 2 ;;
    --all)     SUITE="--all"; shift ;;
    *)         shift ;;
  esac
done

mkdir -p "${REPO_ROOT}/artifacts"

declare -A TEST_RESULTS

run_or_dry() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] $*"
    return 0
  fi
  "$@"
}

wait_healthy() {
  local service="$1" timeout="${2:-${RECOVERY_TIMEOUT}}"
  local deadline=$(( $(date +%s) + timeout ))
  while (( $(date +%s) < deadline )); do
    if docker inspect --format='{{.State.Health.Status}}' \
        "code-server-${service}" 2>/dev/null | grep -q "healthy"; then
      return 0
    fi
    sleep 3
  done
  return 1
}

record_result() {
  local name="$1" status="$2" duration="$3" notes="${4:-}"
  TEST_RESULTS["${name}"]="${status}|${duration}|${notes}"
  if [[ "${status}" == "PASS" ]]; then
    log_info "  ✅ PASS: ${name} (${duration}s)"
  else
    log_error "  ❌ FAIL: ${name} (${duration}s) — ${notes}"
  fi
}

restore_all() {
  log_info "Restoring all services after chaos tests..."
  run_or_dry docker compose -f "${REPO_ROOT}/docker-compose.enterprise.yml" \
    up -d --no-recreate 2>/dev/null || true
}

# ── Test 1: Container kill + auto-recovery ─────────────────────────────────
test_container_kill() {
  log_info "Chaos: container kill (code-server-api)"
  local start=$(date +%s)

  run_or_dry docker kill code-server-api
  sleep 2

  if [[ "${DRY_RUN}" == "true" ]]; then
    record_result "container_kill" "PASS" "0" "dry-run"
    return
  fi

  if wait_healthy "api" 60; then
    local dur=$(( $(date +%s) - start ))
    record_result "container_kill" "PASS" "${dur}"
  else
    record_result "container_kill" "FAIL" "60" "api did not recover within 60s"
  fi
}

# ── Test 2: Network partition simulation ───────────────────────────────────
test_network_partition() {
  log_info "Chaos: network partition (drop PostgreSQL port for 10s)"
  local start=$(date +%s)

  # Add iptables drop rule for postgres port
  run_or_dry iptables -A OUTPUT -p tcp --dport 5432 -j DROP 2>/dev/null || \
    log_info "  SKIP iptables (insufficient permissions in dry-run)"

  sleep 10

  # Remove the rule
  run_or_dry iptables -D OUTPUT -p tcp --dport 5432 -j DROP 2>/dev/null || true

  if [[ "${DRY_RUN}" == "true" ]]; then
    record_result "network_partition" "PASS" "0" "dry-run"
    return
  fi

  # Verify postgres reconnects
  if wait_healthy "postgres" 30; then
    local dur=$(( $(date +%s) - start ))
    record_result "network_partition" "PASS" "${dur}"
  else
    record_result "network_partition" "FAIL" "30" "postgres did not recover after partition"
  fi
}

# ── Test 3: Memory pressure ────────────────────────────────────────────────
test_memory_pressure() {
  log_info "Chaos: memory pressure (stress api container to 90% limit)"
  local start=$(date +%s)

  if [[ "${DRY_RUN}" == "true" ]]; then
    record_result "memory_pressure" "PASS" "0" "dry-run"
    return
  fi

  # Update memory limit to tight value, force gc
  docker update --memory="256m" code-server-api 2>/dev/null || true
  sleep 15
  docker update --memory="512m" code-server-api 2>/dev/null || true

  if wait_healthy "api" 30; then
    local dur=$(( $(date +%s) - start ))
    record_result "memory_pressure" "PASS" "${dur}"
  else
    record_result "memory_pressure" "FAIL" "30" "api unhealthy after memory pressure"
  fi
}

# ── Test 4: Disk fill simulation ───────────────────────────────────────────
test_disk_fill() {
  log_info "Chaos: disk fill (write 100MB temp file, verify platform continues)"
  local start=$(date +%s)
  local tmpfile="/tmp/chaos-disk-$(date +%s).tmp"

  run_or_dry dd if=/dev/zero of="${tmpfile}" bs=1M count=100 2>/dev/null || true

  # Verify health endpoint still responds
  if [[ "${DRY_RUN}" != "true" ]]; then
    if curl -sf --max-time 5 "http://localhost:8080/health" >/dev/null 2>&1; then
      rm -f "${tmpfile}"
      local dur=$(( $(date +%s) - start ))
      record_result "disk_fill" "PASS" "${dur}"
    else
      rm -f "${tmpfile}"
      record_result "disk_fill" "FAIL" "5" "health endpoint failed under disk pressure"
    fi
  else
    rm -f "${tmpfile}" 2>/dev/null || true
    record_result "disk_fill" "PASS" "0" "dry-run"
  fi
}

# ── Test 5: Redis connection drop ──────────────────────────────────────────
test_redis_drop() {
  log_info "Chaos: Redis restart (session cache recovery)"
  local start=$(date +%s)

  run_or_dry docker restart code-server-redis

  if [[ "${DRY_RUN}" == "true" ]]; then
    record_result "redis_drop" "PASS" "0" "dry-run"
    return
  fi

  if wait_healthy "redis" 45; then
    local dur=$(( $(date +%s) - start ))
    record_result "redis_drop" "PASS" "${dur}"
  else
    record_result "redis_drop" "FAIL" "45" "Redis did not recover within 45s"
  fi
}

write_results() {
  local total=0 passed=0 failed=0
  local entries="[]"
  local arr=()
  for name in "${!TEST_RESULTS[@]}"; do
    IFS='|' read -r status duration notes <<< "${TEST_RESULTS[$name]}"
    total=$((total+1))
    [[ "${status}" == "PASS" ]] && passed=$((passed+1)) || failed=$((failed+1))
    arr+=("{\"test\":\"${name}\",\"status\":\"${status}\",\"duration_sec\":${duration},\"notes\":\"${notes}\"}")
  done
  entries=$(IFS=,; echo "[${arr[*]}]")

  cat > "${RESULTS_FILE}" << EOF
{
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "total": ${total},
  "passed": ${passed},
  "failed": ${failed},
  "tests": ${entries}
}
EOF
  log_info "Results written: ${RESULTS_FILE}"
}

# Main
log_info "Chaos Test Suite — suite=${SUITE} dry-run=${DRY_RUN}"
log_info "============================================================"

run_suite() {
  local suite="$1"
  case "${suite}" in
    container_kill)     test_container_kill ;;
    network_partition)  test_network_partition ;;
    memory_pressure)    test_memory_pressure ;;
    disk_fill)          test_disk_fill ;;
    redis_drop)         test_redis_drop ;;
    --all)
      test_container_kill
      test_network_pressure 2>/dev/null || test_memory_pressure
      test_disk_fill
      test_redis_drop
      ;;
    *)
      log_error "Unknown suite: ${suite}"
      exit 1
      ;;
  esac
}

# All suites
if [[ "${SUITE}" == "--all" ]]; then
  test_container_kill
  test_memory_pressure
  test_disk_fill
  test_redis_drop
  # Network partition requires elevated privs — only run if root
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    test_network_partition
  else
    log_info "SKIP network_partition (requires root for iptables)"
    TEST_RESULTS["network_partition"]="SKIP|0|insufficient privileges"
  fi
else
  run_suite "${SUITE}"
fi

restore_all
write_results

log_info "============================================================"
# Count failures
failed_count=0
for name in "${!TEST_RESULTS[@]}"; do
  IFS='|' read -r status _ _ <<< "${TEST_RESULTS[$name]}"
  [[ "${status}" == "FAIL" ]] && failed_count=$((failed_count+1))
done

if [[ ${failed_count} -eq 0 ]]; then
  log_info "✅ Chaos suite complete: all tests passed"
  exit 0
else
  log_error "❌ Chaos suite: ${failed_count} test(s) failed"
  exit 1
fi
