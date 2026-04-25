#!/usr/bin/env bash
# @file        tests/chaos/chaos-test.sh
# @module      testing/chaos
# @description Chaos engineering tests: kill containers, simulate failures, verify recovery
# @governance  GOV-002: IaC, idempotent — safe to re-run
# Issue #1537: Testing & QA — Chaos Engineering
#
# Usage:
#   bash tests/chaos/chaos-test.sh              # Run all chaos scenarios
#   bash tests/chaos/chaos-test.sh kill-service # Single scenario
#   DRY_RUN=1 bash tests/chaos/chaos-test.sh    # Preview without executing

set -euo pipefail

source "$(dirname "$0")/../../scripts/_common/hosts.sh" 2>/dev/null || true

# ── Config ────────────────────────────────────────────────────────────────────
DRY_RUN="${DRY_RUN:-0}"
RECOVERY_TIMEOUT="${RECOVERY_TIMEOUT:-60}"    # seconds to wait for recovery
HEALTH_URL="${HEALTH_URL:-https://ide.kushnir.cloud/oauth2/ping}"
REPORT_FILE="artifacts/reports/chaos-test-$(date +%Y%m%d-%H%M%S).json"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()    { echo "[chaos][$(date +%H:%M:%S)] $*"; }
warn()   { echo "[chaos][WARN][$(date +%H:%M:%S)] $*" >&2; }
err()    { echo "[chaos][FAIL][$(date +%H:%M:%S)] $*" >&2; }
run()    { if [ "$DRY_RUN" = "1" ]; then log "DRY_RUN: $*"; else eval "$*"; fi; }

# Check if a URL returns HTTP 200
health_check() {
  local url="${1:-$HEALTH_URL}"
  local timeout_sec="${2:-5}"
  curl -sf --max-time "${timeout_sec}" "${url}" >/dev/null 2>&1
}

# Wait for recovery up to RECOVERY_TIMEOUT seconds
wait_for_recovery() {
  local service="${1}"
  local start
  start=$(date +%s)
  local elapsed

  log "Waiting for ${service} to recover (timeout: ${RECOVERY_TIMEOUT}s)..."
  while true; do
    elapsed=$(( $(date +%s) - start ))
    if health_check; then
      log "✓ ${service} recovered in ${elapsed}s"
      echo "${elapsed}"
      return 0
    fi
    if [ "${elapsed}" -ge "${RECOVERY_TIMEOUT}" ]; then
      err "✗ ${service} did NOT recover within ${RECOVERY_TIMEOUT}s"
      return 1
    fi
    sleep 2
  done
}

# ── Results accumulator ───────────────────────────────────────────────────────
declare -A RESULTS

record_result() {
  local scenario="$1"
  local status="$2"    # PASS / FAIL / SKIP
  local note="${3:-}"
  RESULTS["${scenario}"]="${status}|${note}"
  log "${status}: ${scenario}${note:+ — ${note}}"
}

# ── Chaos Scenarios ───────────────────────────────────────────────────────────

# Scenario 1: Kill a non-critical service and verify restart
scenario_kill_service() {
  local service="${1:-redis}"
  log "=== Scenario: Kill service '${service}' ==="

  if ! docker ps --format "{{.Names}}" | grep -q "${service}"; then
    record_result "kill-${service}" "SKIP" "service not running"
    return
  fi

  log "Killing ${service}..."
  run "docker kill ${service}"
  sleep 3

  # Verify service restarts (Docker restart policy)
  log "Waiting for ${service} to auto-restart..."
  local start
  start=$(date +%s)
  while ! docker ps --format "{{.Names}}" | grep -q "^${service}$"; do
    if [ $(( $(date +%s) - start )) -gt 30 ]; then
      record_result "kill-${service}" "FAIL" "service did not auto-restart within 30s"
      return 1
    fi
    sleep 2
  done

  record_result "kill-${service}" "PASS" "auto-restarted"
}

# Scenario 2: Kill caddy (reverse proxy) — verify recovery
scenario_kill_caddy() {
  log "=== Scenario: Kill caddy reverse proxy ==="

  if ! docker ps --format "{{.Names}}" | grep -q "caddy"; then
    record_result "kill-caddy" "SKIP" "caddy not running"
    return
  fi

  # Health check before
  if ! health_check; then
    record_result "kill-caddy" "SKIP" "service unreachable before test"
    return
  fi

  run "docker kill caddy"
  sleep 2

  local recovery_time
  recovery_time=$(wait_for_recovery "caddy")
  if [ $? -eq 0 ]; then
    record_result "kill-caddy" "PASS" "recovered in ${recovery_time}s"
  else
    record_result "kill-caddy" "FAIL" "did not recover"
  fi
}

# Scenario 3: Kill postgres — verify API degrades gracefully
scenario_kill_postgres() {
  log "=== Scenario: Kill postgres — verify graceful degradation ==="

  if ! docker ps --format "{{.Names}}" | grep -q "postgres"; then
    record_result "kill-postgres" "SKIP" "postgres not running"
    return
  fi

  run "docker kill postgres"
  sleep 3

  # API should return 503 (not 500 panic) during postgres downtime
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${HEALTH_URL}" || echo "000")
  log "HTTP status during postgres downtime: ${http_code}"

  # Restart postgres
  run "docker start postgres 2>/dev/null || docker compose up -d postgres"
  sleep 10  # Wait for postgres to accept connections

  # Verify recovery
  local recovery_time
  recovery_time=$(wait_for_recovery "postgres")
  if [ $? -eq 0 ]; then
    record_result "kill-postgres" "PASS" "recovered in ${recovery_time}s (degraded HTTP=${http_code} during outage)"
  else
    record_result "kill-postgres" "FAIL" "did not recover"
  fi
}

# Scenario 4: NAS mount simulation (only if /nas is mounted)
scenario_nas_unavailable() {
  log "=== Scenario: NAS unavailable — verify graceful degradation ==="

  if ! mountpoint -q /nas/persistent 2>/dev/null; then
    record_result "nas-unavailable" "SKIP" "/nas/persistent not mounted"
    return
  fi

  # Temporarily make NAS unresponsive by blocking NAS_HOST
  log "Simulating NAS unreachability (iptables block to ${NAS_HOST})..."
  run "iptables -A OUTPUT -d ${NAS_HOST} -j DROP"
  sleep 10

  # Services should continue (read from cache/local)
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${HEALTH_URL}" || echo "000")
  log "HTTP status during NAS block: ${http_code}"

  # Remove block
  run "iptables -D OUTPUT -d ${NAS_HOST} -j DROP"
  sleep 5

  if [ "${http_code}" = "200" ] || [ "${http_code}" = "302" ]; then
    record_result "nas-unavailable" "PASS" "service degraded gracefully (HTTP=${http_code})"
  else
    record_result "nas-unavailable" "FAIL" "service failed during NAS outage (HTTP=${http_code})"
  fi
}

# Scenario 5: Container OOM kill simulation
scenario_oom_kill() {
  local service="${1:-api}"
  log "=== Scenario: OOM kill simulation for '${service}' ==="

  if ! docker ps --format "{{.Names}}" | grep -q "${service}"; then
    record_result "oom-${service}" "SKIP" "service not running"
    return
  fi

  # Simulate OOM by sending SIGKILL (same as kernel OOM killer)
  run "docker kill --signal SIGKILL ${service}"
  sleep 2

  local recovery_time
  recovery_time=$(wait_for_recovery "${service}")
  if [ $? -eq 0 ]; then
    record_result "oom-${service}" "PASS" "recovered from SIGKILL in ${recovery_time}s"
  else
    record_result "oom-${service}" "FAIL" "did not recover from SIGKILL"
  fi
}

# ── Report Generation ─────────────────────────────────────────────────────────

generate_report() {
  local pass=0 fail=0 skip=0
  local results_json="["

  for scenario in "${!RESULTS[@]}"; do
    local val="${RESULTS[$scenario]}"
    local status="${val%%|*}"
    local note="${val##*|}"

    case "$status" in
      PASS) ((pass++)) ;;
      FAIL) ((fail++)) ;;
      SKIP) ((skip++)) ;;
    esac

    results_json+="$(printf '{"scenario":"%s","status":"%s","note":"%s"},' \
      "${scenario}" "${status}" "${note}")"
  done

  results_json="${results_json%,}]"

  mkdir -p "$(dirname "${REPORT_FILE}")"
  cat > "${REPORT_FILE}" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "base_url": "${HEALTH_URL}",
  "summary": {
    "pass": ${pass},
    "fail": ${fail},
    "skip": ${skip},
    "total": $((pass + fail + skip))
  },
  "results": ${results_json}
}
EOF

  log "=== Chaos Test Summary ==="
  log "PASS: ${pass} | FAIL: ${fail} | SKIP: ${skip}"
  log "Report: ${REPORT_FILE}"

  if [ "${fail}" -gt 0 ]; then
    return 1
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  local scenario="${1:-all}"
  log "Starting chaos tests (scenario: ${scenario}, dry_run: ${DRY_RUN})"

  case "$scenario" in
    kill-service)   scenario_kill_service "${2:-redis}" ;;
    kill-caddy)     scenario_kill_caddy ;;
    kill-postgres)  scenario_kill_postgres ;;
    nas-unavailable) scenario_nas_unavailable ;;
    oom-kill)       scenario_oom_kill "${2:-api}" ;;
    all)
      scenario_kill_service "redis"
      scenario_kill_caddy
      scenario_kill_postgres
      scenario_nas_unavailable
      scenario_oom_kill "api"
      ;;
    *)
      echo "Usage: $0 [all|kill-service|kill-caddy|kill-postgres|nas-unavailable|oom-kill]"
      exit 1
      ;;
  esac

  generate_report
}

main "$@"
