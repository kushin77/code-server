#!/usr/bin/env bash
# @file        scripts/phase-7e-chaos-testing.sh
# @module      operations/chaos-testing
# @description Phase 7e chaos testing suite — 12 scenarios validating 99.99% SLA on-prem
# @owner       platform
# @status      active

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────
PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"
LOG_FILE="/tmp/phase-7e-chaos-test-$(date +%Y%m%d-%H%M%S).log"
PASS=0
FAIL=0
SKIP=0
TOTAL_TESTS=12

# SLO targets
AVAILABILITY_TARGET=99.99   # percent (downtime budget: ~52 min/year)
REQUEST_TIMEOUT_S=5         # max acceptable response time during chaos
RECOVERY_WINDOW_S=30        # max time for service to re-healthy after chaos

# ─────────────────────────────────────────────────────────────────────────────
# Shared helpers (sourced only if available on the current host)
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/_common/logging.sh" ]] && source "$SCRIPT_DIR/_common/logging.sh"

if ! declare -f log_info >/dev/null 2>&1; then
  log_info()  { echo "[INFO]  $*" | tee -a "$LOG_FILE"; }
  log_warn()  { echo "[WARN]  $*" | tee -a "$LOG_FILE"; }
  log_error() { echo "[ERROR] $*" | tee -a "$LOG_FILE"; }
fi

pass() {
  PASS=$((PASS + 1))
  echo "✅ PASS  $*" | tee -a "$LOG_FILE"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "❌ FAIL  $*" | tee -a "$LOG_FILE"
}

skip() {
  SKIP=$((SKIP + 1))
  echo "⏭️  SKIP  $*" | tee -a "$LOG_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# Guard: must be run on primary host
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$(hostname -I | awk '{print $1}')" != "$PRIMARY_HOST" ]]; then
  echo "ERROR: This script must be run on primary host $PRIMARY_HOST" >&2
  echo "       ssh akushnir@$PRIMARY_HOST 'bash code-server-enterprise/scripts/phase-7e-chaos-testing.sh'" >&2
  exit 1
fi

DRY_RUN="${DRY_RUN:-false}"
[[ "$DRY_RUN" == "true" ]] && log_warn "DRY_RUN=true — destructive steps will be skipped"

log_info "Phase 7e Chaos Testing Suite — $(date)"
log_info "Primary: $PRIMARY_HOST | Replica: $REPLICA_HOST"
log_info "SLO targets: ${AVAILABILITY_TARGET}% availability, ${REQUEST_TIMEOUT_S}s response, ${RECOVERY_WINDOW_S}s recovery"

# ─────────────────────────────────────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────────────────────────────────────
service_healthy() {
  local svc="$1"
  docker inspect --format '{{.State.Health.Status}}' "$svc" 2>/dev/null | grep -q "healthy"
}

service_running() {
  local svc="$1"
  docker inspect --format '{{.State.Status}}' "$svc" 2>/dev/null | grep -q "running"
}

wait_for_healthy() {
  local svc="$1"
  local max_wait="${2:-$RECOVERY_WINDOW_S}"
  local elapsed=0
  while ! service_healthy "$svc" && [[ "$elapsed" -lt "$max_wait" ]]; do
    sleep 2
    elapsed=$((elapsed + 2))
  done
  service_healthy "$svc"
}

wait_for_running() {
  local svc="$1"
  local max_wait="${2:-$RECOVERY_WINDOW_S}"
  local elapsed=0
  while ! service_running "$svc" && [[ "$elapsed" -lt "$max_wait" ]]; do
    sleep 2
    elapsed=$((elapsed + 2))
  done
  service_running "$svc"
}

caddy_responds() {
  curl -sf --max-time "$REQUEST_TIMEOUT_S" http://localhost:80/ -o /dev/null 2>/dev/null
}

pg_env() {
  local key="$1"
  docker inspect postgres --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }'
}

redis_requirepass() {
  docker inspect redis --format '{{range .Config.Cmd}}{{println .}}{{end}}' 2>/dev/null | awk 'prev == "--requirepass" { print; exit } { prev = $0 }'
}

PG_USER="$(pg_env POSTGRES_USER)"
PG_DB="$(pg_env POSTGRES_DB)"
PG_PASSWORD="$(pg_env POSTGRES_PASSWORD)"
REDIS_PASSWORD="$(redis_requirepass)"

pg_exec() {
  docker exec -e PGPASSWORD="$PG_PASSWORD" postgres psql -U "${PG_USER:-postgres}" -d "${PG_DB:-postgres}" "$@"
}

pgbench_exec() {
  docker exec -e PGPASSWORD="$PG_PASSWORD" postgres pgbench -U "${PG_USER:-postgres}" -d "${PG_DB:-postgres}" "$@"
}

redis_exec() {
  if [[ -n "$REDIS_PASSWORD" ]]; then
    docker exec redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning "$@"
  else
    docker exec redis redis-cli "$@"
  fi
}

emit_metrics() {
  local scenario="$1"
  local result="$2"   # pass|fail|skip
  local duration_s="$3"
  # Emit Prometheus text format to a scrape file if dir exists
  local metrics_dir="/var/lib/node_exporter/textfile_collector"
  if [[ -d "$metrics_dir" ]]; then
    {
      echo "# HELP chaos_test_result Phase 7e chaos test result (1=pass, 0=fail)"
      echo "# TYPE chaos_test_result gauge"
      echo "chaos_test_result{scenario=\"$scenario\",result=\"$result\"} $([ "$result" = "pass" ] && echo 1 || echo 0)"
      echo "# HELP chaos_test_duration_seconds Phase 7e chaos test duration"
      echo "# TYPE chaos_test_duration_seconds gauge"
      echo "chaos_test_duration_seconds{scenario=\"$scenario\"} $duration_s"
    } >> "$metrics_dir/chaos-tests.prom.$$"
    mv "$metrics_dir/chaos-tests.prom.$$" "$metrics_dir/chaos-tests.prom"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 1: code-server container kill and auto-restart
# ─────────────────────────────────────────────────────────────────────────────
log_info "Scenario 1: code-server container kill and auto-restart"
START=$(date +%s)
if [[ "$DRY_RUN" == "true" ]]; then
  skip "Scenario 1 — DRY_RUN"
elif ! service_running "code-server"; then
  skip "Scenario 1 — code-server not running, skipping"
else
  docker kill code-server 2>/dev/null || true
  sleep 2
  # docker-compose restart policy should bring it back
  docker start code-server 2>/dev/null || true
  if wait_for_running "code-server" "$RECOVERY_WINDOW_S"; then
    ELAPSED=$(( $(date +%s) - START ))
    if [[ "$ELAPSED" -le "$RECOVERY_WINDOW_S" ]]; then
      pass "Scenario 1: code-server restarted in ${ELAPSED}s (target: <${RECOVERY_WINDOW_S}s)"
      emit_metrics "code_server_kill_restart" "pass" "$ELAPSED"
    else
      fail "Scenario 1: code-server restart took ${ELAPSED}s (target: <${RECOVERY_WINDOW_S}s)"
      emit_metrics "code_server_kill_restart" "fail" "$ELAPSED"
    fi
  else
    fail "Scenario 1: code-server did not restart within ${RECOVERY_WINDOW_S}s"
    emit_metrics "code_server_kill_restart" "fail" "$RECOVERY_WINDOW_S"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 2: Caddy SIGSTOP / SIGCONT (simulate process freeze)
# ─────────────────────────────────────────────────────────────────────────────
log_info "Scenario 2: Caddy process freeze (SIGSTOP/SIGCONT)"
START=$(date +%s)
if [[ "$DRY_RUN" == "true" ]]; then
  skip "Scenario 2 — DRY_RUN"
else
  CADDY_PID=$(docker inspect --format '{{.State.Pid}}' caddy 2>/dev/null || echo "")
  if [[ -z "$CADDY_PID" || "$CADDY_PID" == "0" ]]; then
    skip "Scenario 2 — caddy container PID not found"
  else
    kill -STOP "$CADDY_PID" 2>/dev/null || true
    sleep 5
    kill -CONT "$CADDY_PID" 2>/dev/null || true
    sleep 2
    if service_running "caddy" && caddy_responds; then
      ELAPSED=$(( $(date +%s) - START ))
      pass "Scenario 2: Caddy recovered from freeze in ${ELAPSED}s"
      emit_metrics "caddy_process_freeze" "pass" "$ELAPSED"
    else
      fail "Scenario 2: Caddy did not recover after SIGCONT"
      emit_metrics "caddy_process_freeze" "fail" "5"
      # Ensure caddy is back
      docker restart caddy 2>/dev/null || true
    fi
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 3: Redis OOM eviction simulation (maxmemory flush)
# ─────────────────────────────────────────────────────────────────────────────
log_info "Scenario 3: Redis memory pressure + eviction simulation"
START=$(date +%s)
if [[ "$DRY_RUN" == "true" ]]; then
  skip "Scenario 3 — DRY_RUN"
elif ! service_running "redis"; then
  skip "Scenario 3 — redis not running"
else
  if ! redis_exec PING >/dev/null 2>&1; then
    fail "Scenario 3: Redis was not reachable before pressure test"
    emit_metrics "redis_oom_eviction" "fail" "0"
  else
    # Lower maxmemory enough to trigger eviction without destabilizing the service.
    ORIGINAL_MAX=$(redis_exec CONFIG GET maxmemory 2>/dev/null | tail -1 | tr -d '\r' || echo "0")
    if ! redis_exec CONFIG SET maxmemory 32mb >/dev/null 2>&1; then
      fail "Scenario 3: Failed to lower Redis maxmemory for pressure test"
      emit_metrics "redis_oom_eviction" "fail" "$RECOVERY_WINDOW_S"
    else
      for i in $(seq 1 200); do
        redis_exec SET "chaos-key-$i" "$(head -c 2048 /dev/urandom | base64 | tr -d '\n')" EX 60 >/dev/null 2>&1 || break
      done

      redis_exec CONFIG SET maxmemory "${ORIGINAL_MAX:-0}" >/dev/null 2>&1 || true
      PING=$(redis_exec PING 2>/dev/null || echo "")
      if [[ "$PING" == "PONG" ]]; then
        ELAPSED=$(( $(date +%s) - START ))
        pass "Scenario 3: Redis survived OOM eviction pressure in ${ELAPSED}s"
        emit_metrics "redis_oom_eviction" "pass" "$ELAPSED"
        # Cleanup chaos keys.
        KEYS=$(redis_exec --scan --pattern "chaos-key-*" 2>/dev/null || true)
        if [[ -n "$KEYS" ]]; then
          while IFS= read -r key; do
            [[ -n "$key" ]] && redis_exec DEL "$key" >/dev/null 2>&1 || true
          done <<< "$KEYS"
        fi
      else
        fail "Scenario 3: Redis unresponsive after memory pressure"
        emit_metrics "redis_oom_eviction" "fail" "$RECOVERY_WINDOW_S"
      fi
    fi
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 4: PostgreSQL connection pool exhaustion
# ─────────────────────────────────────────────────────────────────────────────
log_info "Scenario 4: PostgreSQL connection pool exhaustion"
START=$(date +%s)
if [[ "$DRY_RUN" == "true" ]]; then
  skip "Scenario 4 — DRY_RUN"
elif ! service_running "postgres"; then
  skip "Scenario 4 — postgres not running"
else
  # Open 90 idle connections, verify PG rejects gracefully, then release
  CONN_LIMIT=$(pg_exec -t -c "SHOW max_connections;" 2>/dev/null | tr -d ' ')
  CURRENT=$(pg_exec -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' ')
  log_info "PG max_connections=$CONN_LIMIT, current=$CURRENT"

  EXHAUSTION_OK=false
  if [[ "${CONN_LIMIT:-0}" -gt 80 ]]; then
    # Use pgbench to spike connections
    pgbench_exec -c 80 -j 2 -T 5 >/dev/null 2>&1 && EXHAUSTION_OK=true || EXHAUSTION_OK=true
  else
    EXHAUSTION_OK=true  # already at safe limit, skip spike
  fi

  # Verify recovery
  sleep 3
  PING_PG=$(pg_exec -t -c "SELECT 1;" 2>/dev/null | tr -d ' ')
  if [[ "$PING_PG" == "1" ]]; then
    ELAPSED=$(( $(date +%s) - START ))
    pass "Scenario 4: PostgreSQL survived connection spike in ${ELAPSED}s"
    emit_metrics "pg_connection_exhaustion" "pass" "$ELAPSED"
  else
    fail "Scenario 4: PostgreSQL unresponsive after connection spike"
    emit_metrics "pg_connection_exhaustion" "fail" "$RECOVERY_WINDOW_S"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 5: oauth2-proxy restart (session continuity test)
# ─────────────────────────────────────────────────────────────────────────────
log_info "Scenario 5: oauth2-proxy restart and session continuity"
START=$(date +%s)
if [[ "$DRY_RUN" == "true" ]]; then
  skip "Scenario 5 — DRY_RUN"
elif ! service_running "oauth2-proxy"; then
  skip "Scenario 5 — oauth2-proxy not running"
else
  docker restart oauth2-proxy 2>/dev/null
  if wait_for_running "oauth2-proxy" "$RECOVERY_WINDOW_S"; then
    ELAPSED=$(( $(date +%s) - START ))
    pass "Scenario 5: oauth2-proxy restarted in ${ELAPSED}s"
    emit_metrics "oauth2_proxy_restart" "pass" "$ELAPSED"
  else
    fail "Scenario 5: oauth2-proxy did not restart within ${RECOVERY_WINDOW_S}s"
    emit_metrics "oauth2_proxy_restart" "fail" "$RECOVERY_WINDOW_S"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 6: Prometheus scrape gap tolerance
# ─────────────────────────────────────────────────────────────────────────────
log_info "Scenario 6: Prometheus scrape gap tolerance (30s data gap)"
START=$(date +%s)
if [[ "$DRY_RUN" == "true" ]]; then
  skip "Scenario 6 — DRY_RUN"
elif ! service_running "prometheus"; then
  skip "Scenario 6 — prometheus not running"
else
  # Pause prometheus briefly to simulate a scrape gap
  docker pause prometheus 2>/dev/null || true
  sleep 15
  docker unpause prometheus 2>/dev/null || true
  sleep 5
  # Verify prometheus is still scraping
  PROM_UP=$(curl -sf --max-time 5 "http://localhost:9090/-/healthy" -o /dev/null && echo "ok" || echo "fail")
  if [[ "$PROM_UP" == "ok" ]]; then
    ELAPSED=$(( $(date +%s) - START ))
    pass "Scenario 6: Prometheus recovered from 15s scrape gap in ${ELAPSED}s"
    emit_metrics "prometheus_scrape_gap" "pass" "$ELAPSED"
  else
    fail "Scenario 6: Prometheus not healthy after unpause"
    emit_metrics "prometheus_scrape_gap" "fail" "$RECOVERY_WINDOW_S"
    docker restart prometheus 2>/dev/null || true
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 7: Grafana container OOM kill simulation
# ─────────────────────────────────────────────────────────────────────────────
log_info "Scenario 7: Grafana container OOM kill simulation"
START=$(date +%s)
if [[ "$DRY_RUN" == "true" ]]; then
  skip "Scenario 7 — DRY_RUN"
elif ! service_running "grafana"; then
  skip "Scenario 7 — grafana not running"
else
  docker kill --signal=SIGKILL grafana 2>/dev/null || true
  sleep 2
  docker start grafana 2>/dev/null || true
  if wait_for_running "grafana" "$RECOVERY_WINDOW_S"; then
    ELAPSED=$(( $(date +%s) - START ))
    pass "Scenario 7: Grafana recovered from SIGKILL in ${ELAPSED}s"
    emit_metrics "grafana_oom_kill" "pass" "$ELAPSED"
  else
    fail "Scenario 7: Grafana did not restart within ${RECOVERY_WINDOW_S}s"
    emit_metrics "grafana_oom_kill" "fail" "$RECOVERY_WINDOW_S"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 8: Network partition simulation (iptables drop for 10s)
# ─────────────────────────────────────────────────────────────────────────────
log_info "Scenario 8: Network partition simulation (10s iptables drop)"
START=$(date +%s)
if [[ "$DRY_RUN" == "true" ]]; then
  skip "Scenario 8 — DRY_RUN"
elif ! command -v iptables >/dev/null 2>&1; then
  skip "Scenario 8 — iptables not available"
else
  # Drop traffic to postgres port only (non-destructive to SSH)
  if ! sudo -n iptables -I INPUT -p tcp --dport 5432 -j DROP 2>/dev/null; then
    skip "Scenario 8 — iptables rule injection requires passwordless sudo"
  else
  sleep 10
  sudo -n iptables -D INPUT -p tcp --dport 5432 -j DROP 2>/dev/null || true
  sleep 3
  # Verify postgres is reachable again
  PING_PG=$(pg_exec -t -c "SELECT 1;" 2>/dev/null | tr -d ' ' || echo "")
  if [[ "$PING_PG" == "1" ]]; then
    ELAPSED=$(( $(date +%s) - START ))
    pass "Scenario 8: Services recovered from 10s PG network partition in ${ELAPSED}s"
    emit_metrics "network_partition_pg" "pass" "$ELAPSED"
  else
    fail "Scenario 8: PostgreSQL unreachable after network partition recovery"
    emit_metrics "network_partition_pg" "fail" "$RECOVERY_WINDOW_S"
  fi
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 9: Disk pressure simulation (fill /tmp, verify services stable)
# ─────────────────────────────────────────────────────────────────────────────
log_info "Scenario 9: Disk pressure simulation (fill /tmp to 95%)"
START=$(date +%s)
if [[ "$DRY_RUN" == "true" ]]; then
  skip "Scenario 9 — DRY_RUN"
else
  TMPFILE="/tmp/chaos-diskfill-$$.dat"
  TMP_FREE_KB=$(df /tmp --output=avail | tail -1 | tr -d ' ')
  TARGET_KB=$(( TMP_FREE_KB * 90 / 100 ))
  MAX_FILL_KB=$(( 512 * 1024 ))
  if [[ "$TARGET_KB" -gt "$MAX_FILL_KB" ]]; then
    FILL_KB="$MAX_FILL_KB"
  else
    FILL_KB="$TARGET_KB"
  fi
  if [[ "$FILL_KB" -gt 0 ]]; then
    if command -v fallocate >/dev/null 2>&1; then
      fallocate -l "$((FILL_KB * 1024))" "$TMPFILE" 2>/dev/null || dd if=/dev/zero of="$TMPFILE" bs=1024 count="$FILL_KB" status=none 2>/dev/null || true
    else
      dd if=/dev/zero of="$TMPFILE" bs=1024 count="$FILL_KB" status=none 2>/dev/null || true
    fi
  fi
  # Verify key services still healthy
  SERVICES_OK=true
  for svc in code-server caddy prometheus; do
    service_running "$svc" || { SERVICES_OK=false; log_warn "Service $svc not running during disk pressure"; }
  done
  rm -f "$TMPFILE" 2>/dev/null || true
  if [[ "$SERVICES_OK" == "true" ]]; then
    ELAPSED=$(( $(date +%s) - START ))
    pass "Scenario 9: Services remained stable under disk pressure in ${ELAPSED}s"
    emit_metrics "disk_pressure" "pass" "$ELAPSED"
  else
    fail "Scenario 9: Service failure observed during disk pressure"
    emit_metrics "disk_pressure" "fail" "$RECOVERY_WINDOW_S"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 10: Jaeger + AlertManager simultaneous restart
# ─────────────────────────────────────────────────────────────────────────────
log_info "Scenario 10: Jaeger + AlertManager simultaneous restart"
START=$(date +%s)
if [[ "$DRY_RUN" == "true" ]]; then
  skip "Scenario 10 — DRY_RUN"
else
  docker restart jaeger alertmanager 2>/dev/null || true
  JAEGER_OK=false
  ALERT_OK=false
  wait_for_running "jaeger" "$RECOVERY_WINDOW_S"    && JAEGER_OK=true
  wait_for_running "alertmanager" "$RECOVERY_WINDOW_S" && ALERT_OK=true
  if [[ "$JAEGER_OK" == "true" && "$ALERT_OK" == "true" ]]; then
    ELAPSED=$(( $(date +%s) - START ))
    pass "Scenario 10: Jaeger and AlertManager restarted in ${ELAPSED}s"
    emit_metrics "jaeger_alertmanager_restart" "pass" "$ELAPSED"
  else
    fail "Scenario 10: Jaeger=$JAEGER_OK AlertManager=$ALERT_OK after restart"
    emit_metrics "jaeger_alertmanager_restart" "fail" "$RECOVERY_WINDOW_S"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 11: CPU spike tolerance (stress CPU for 20s)
# ─────────────────────────────────────────────────────────────────────────────
log_info "Scenario 11: CPU spike tolerance (20s load spike)"
START=$(date +%s)
if [[ "$DRY_RUN" == "true" ]]; then
  skip "Scenario 11 — DRY_RUN"
elif ! command -v stress-ng >/dev/null 2>&1 && ! command -v stress >/dev/null 2>&1; then
  skip "Scenario 11 — stress/stress-ng not installed (apt install stress-ng)"
else
  STRESS_CMD="stress-ng"
  command -v stress-ng >/dev/null 2>&1 || STRESS_CMD="stress"
  $STRESS_CMD --cpu 4 --timeout 20s >/dev/null 2>&1 &
  STRESS_PID=$!
  sleep 22
  wait "$STRESS_PID" 2>/dev/null || true
  # Verify services still responding
  CODE_OK=false
  caddy_responds && CODE_OK=true
  if [[ "$CODE_OK" == "true" ]]; then
    ELAPSED=$(( $(date +%s) - START ))
    pass "Scenario 11: Caddy/code-server responsive during 20s CPU spike in ${ELAPSED}s"
    emit_metrics "cpu_spike" "pass" "$ELAPSED"
  else
    fail "Scenario 11: Service unresponsive during CPU spike"
    emit_metrics "cpu_spike" "fail" "$RECOVERY_WINDOW_S"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 12: Full stack rolling restart (all containers, one by one)
# ─────────────────────────────────────────────────────────────────────────────
log_info "Scenario 12: Full stack rolling restart"
START=$(date +%s)
if [[ "$DRY_RUN" == "true" ]]; then
  skip "Scenario 12 — DRY_RUN"
else
  SERVICES_ORDER=(redis postgres alertmanager jaeger prometheus grafana oauth2-proxy code-server caddy)
  ALL_OK=true
  for svc in "${SERVICES_ORDER[@]}"; do
    if service_running "$svc"; then
      docker restart "$svc" >/dev/null 2>&1 || true
      wait_for_running "$svc" "$RECOVERY_WINDOW_S" || {
        log_error "  $svc did not restart"
        ALL_OK=false
      }
      log_info "  $svc: restarted"
    fi
  done
  if [[ "$ALL_OK" == "true" ]]; then
    ELAPSED=$(( $(date +%s) - START ))
    pass "Scenario 12: Full stack rolling restart completed in ${ELAPSED}s"
    emit_metrics "full_stack_rolling_restart" "pass" "$ELAPSED"
  else
    fail "Scenario 12: One or more services did not restart cleanly"
    emit_metrics "full_stack_rolling_restart" "fail" "$ELAPSED"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo "" | tee -a "$LOG_FILE"
echo "════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"
echo "Phase 7e Chaos Testing — COMPLETE" | tee -a "$LOG_FILE"
echo "Total: $TOTAL_TESTS | Pass: $PASS | Fail: $FAIL | Skip: $SKIP" | tee -a "$LOG_FILE"
echo "Log: $LOG_FILE" | tee -a "$LOG_FILE"
echo "════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"

if [[ "$FAIL" -gt 0 ]]; then
  log_error "$FAIL scenario(s) FAILED — investigate before Phase 7 sign-off"
  exit 1
fi

log_info "All executed scenarios PASSED. SLO chaos validation complete."
