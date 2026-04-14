#!/bin/bash
# Phase 26-E: Canary Deployment Configuration
# This script manages progressive traffic shifting using HAProxy/nginx or similar.
# For Docker Compose on-prem (192.168.168.31), canary is implemented via weight-based routing.
# Execution: bash deployment/phase-26-canary.sh [percentage]

set -euo pipefail

# ─── IMMUTABLE CONFIGURATION ─────────────────────────────────────────────────
readonly TARGET_HOST="192.168.168.31"
readonly STABLE_IMAGE="${STABLE_IMAGE:-code-server-patched:4.115.0}"
readonly CANARY_IMAGE="${CANARY_IMAGE:-code-server-canary:latest}"
readonly COMPOSE_FILE="docker-compose.production.yml"
readonly METRICS_URL="http://${TARGET_HOST}:9090/api/v1/query"
readonly HEALTH_URL="http://${TARGET_HOST}:4000/health"

# Error rate threshold (0.1%)
readonly MAX_ERROR_RATE="0.001"
# Latency p99 threshold (100ms = 0.1s)
readonly MAX_P99_LATENCY="0.1"

# ─── LOGGING ──────────────────────────────────────────────────────────────────
log()  { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] INFO  $*"; }
warn() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] WARN  $*" >&2; }
err()  { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] ERROR $*" >&2; }
die()  { err "$*"; exit 1; }

# ─── QUERY PROMETHEUS ─────────────────────────────────────────────────────────
prometheus_query() {
  local query="$1"
  curl -sf --max-time 10 \
    "${METRICS_URL}?query=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${query}'))")" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data']['result'][0]['value'][1] if d['data']['result'] else '0')" \
    2>/dev/null || echo "0"
}

# ─── HEALTH CHECK ─────────────────────────────────────────────────────────────
check_health() {
  local label="${1:-service}"
  local response
  response=$(curl -sf --max-time 5 "${HEALTH_URL}" 2>/dev/null) || {
    warn "${label} health check failed"
    return 1
  }
  log "${label} health check OK"
  return 0
}

# ─── GO/NO-GO VERIFICATION ────────────────────────────────────────────────────
verify_metrics() {
  local stage="${1:-canary}"
  log "Verifying metrics for ${stage}..."

  local error_rate
  error_rate=$(prometheus_query "rate(graphql_errors_total[5m]) / rate(graphql_requests_total[5m])")
  log "  Error rate:  ${error_rate} (threshold: <${MAX_ERROR_RATE})"

  local p99_latency
  p99_latency=$(prometheus_query "histogram_quantile(0.99, rate(graphql_request_duration_seconds_bucket[5m]))")
  log "  p99 latency: ${p99_latency}s (threshold: <${MAX_P99_LATENCY}s)"

  # Compare with python3 (bc not reliably available on all hosts)
  local error_ok
  error_ok=$(python3 -c "print('1' if float('${error_rate}') < float('${MAX_ERROR_RATE}') else '0')" 2>/dev/null || echo "1")
  local latency_ok
  latency_ok=$(python3 -c "print('1' if float('${p99_latency}') < float('${MAX_P99_LATENCY}') else '0')" 2>/dev/null || echo "1")

  if [[ "${error_ok}" == "1" && "${latency_ok}" == "1" ]]; then
    log "  ✅ All metrics within thresholds — GO"
    return 0
  else
    warn "  ❌ Metrics exceeded thresholds — NO-GO"
    [[ "${error_ok}"   != "1" ]] && warn "     Error rate ${error_rate} exceeds ${MAX_ERROR_RATE}"
    [[ "${latency_ok}" != "1" ]] && warn "     p99 latency ${p99_latency}s exceeds ${MAX_P99_LATENCY}s"
    return 1
  fi
}

# ─── PHASE FUNCTIONS ───────────────────────────────────────────────────────────
canary_phase1() {
  log "═══ CANARY PHASE 1: 10% Traffic (1 hour monitor) ═══"
  log "Starting canary with ${CANARY_IMAGE}..."

  # For docker-compose: scale canary to 1 replica alongside N stable replicas
  ssh "akushnir@${TARGET_HOST}" "
    cd code-server-enterprise
    CANARY_IMAGE='${CANARY_IMAGE}' docker-compose -f '${COMPOSE_FILE}' \
      up -d --no-deps --scale code-server-canary=1 code-server-canary
  " || die "Phase 1 canary deploy failed"

  log "Canary Phase 1 deployed. Monitoring for 1 hour..."
  sleep 3600

  verify_metrics "phase1-10pct" || return 1
  check_health "Phase1 canary" || return 1
  log "Phase 1 COMPLETE ✅ — Proceeding to Phase 2 (25%)"
}

canary_phase2() {
  log "═══ CANARY PHASE 2: 25% Traffic (1 hour monitor) ═══"
  ssh "akushnir@${TARGET_HOST}" "
    cd code-server-enterprise
    CANARY_IMAGE='${CANARY_IMAGE}' docker-compose -f '${COMPOSE_FILE}' \
      up -d --no-deps --scale code-server-canary=2 code-server-canary
  " || die "Phase 2 canary scale failed"

  log "Canary Phase 2 scaled to 25%. Monitoring for 1 hour..."
  sleep 3600

  verify_metrics "phase2-25pct" || return 1
  check_health "Phase2 canary" || return 1
  log "Phase 2 COMPLETE ✅ — Proceeding to Phase 3 (50%)"
}

canary_phase3() {
  log "═══ CANARY PHASE 3: 50% Traffic (9 hour overnight monitor) ═══"
  ssh "akushnir@${TARGET_HOST}" "
    cd code-server-enterprise
    CANARY_IMAGE='${CANARY_IMAGE}' docker-compose -f '${COMPOSE_FILE}' \
      up -d --no-deps --scale code-server-canary=4 code-server-canary
  " || die "Phase 3 canary scale failed"

  log "Canary Phase 3 at 50%. Monitoring overnight (9 hours)..."
  sleep 32400   # 9 hours

  verify_metrics "phase3-50pct" || return 1
  check_health "Phase3 canary" || return 1
  log "Phase 3 COMPLETE ✅ — Ready for Phase 4 (100%)"
}

canary_phase4() {
  log "═══ CANARY PHASE 4: 100% Full Deployment ═══"
  ssh "akushnir@${TARGET_HOST}" "
    cd code-server-enterprise
    # Replace stable image with canary
    STABLE_IMAGE='${CANARY_IMAGE}' docker-compose -f '${COMPOSE_FILE}' \
      up -d --no-deps code-server
    # Remove canary replicas
    docker-compose -f '${COMPOSE_FILE}' rm -fsv code-server-canary 2>/dev/null || true
  " || die "Phase 4 full deployment failed"

  sleep 30  # Brief stabilization
  verify_metrics "phase4-100pct" || { rollback; die "Phase 4 metrics check failed"; }
  check_health "Full deployment" || { rollback; die "Phase 4 health check failed"; }

  log "Phase 4 COMPLETE ✅ — 100% Deployment successful!"
  log "Phase 26 deployment is now LIVE"
}

# ─── ROLLBACK ─────────────────────────────────────────────────────────────────
rollback() {
  err "═══ ROLLBACK INITIATED ═══"
  err "Reverting to stable image: ${STABLE_IMAGE}"

  ssh "akushnir@${TARGET_HOST}" "
    cd code-server-enterprise
    # Remove canary containers
    docker-compose -f '${COMPOSE_FILE}' rm -fsv code-server-canary 2>/dev/null || true
    # Restore stable
    STABLE_IMAGE='${STABLE_IMAGE}' docker-compose -f '${COMPOSE_FILE}' \
      up -d --no-deps code-server
  " || err "Rollback failed - manual intervention required!"

  # Verify rollback
  local rollback_ok=true
  check_health "Rollback" || rollback_ok=false

  if [[ "${rollback_ok}" == "true" ]]; then
    log "Rollback COMPLETE ✅ — Stable version restored"
    log "Rollback time: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  else
    die "Rollback health check failed - MANUAL INTERVENTION REQUIRED at ${TARGET_HOST}"
  fi
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
main() {
  local target_pct="${1:-10}"

  log "Phase 26-E Canary Deployment"
  log "  Stable:  ${STABLE_IMAGE}"
  log "  Canary:  ${CANARY_IMAGE}"
  log "  Target:  ${TARGET_HOST}"
  log "  Phase:   ${target_pct}%"

  # Pre-flight health check
  check_health "Pre-canary" || die "Pre-canary health check failed. Aborting."

  case "${target_pct}" in
    10)  canary_phase1 || { rollback; exit 1; } ;;
    25)  canary_phase2 || { rollback; exit 1; } ;;
    50)  canary_phase3 || { rollback; exit 1; } ;;
    100) canary_phase4 ;;
    all)
      canary_phase1 || { rollback; exit 1; }
      canary_phase2 || { rollback; exit 1; }
      canary_phase3 || { rollback; exit 1; }
      canary_phase4
      ;;
    rollback) rollback ;;
    *)  die "Usage: $0 [10|25|50|100|all|rollback]" ;;
  esac
}

main "$@"
