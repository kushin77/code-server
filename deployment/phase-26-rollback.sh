#!/bin/bash
# Phase 26-E: Emergency Rollback Script
# RTO: < 5 minutes
# Purpose: Immediately revert Phase 26 deployment to last known good state
# Execution: bash deployment/phase-26-rollback.sh
# Idempotent: Safe to run multiple times

set -euo pipefail

# ─── IMMUTABLE CONFIGURATION ─────────────────────────────────────────────────
readonly TARGET_HOST="192.168.168.31"
readonly STABLE_IMAGE="${STABLE_IMAGE:-code-server-patched:4.115.0}"
readonly COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.production.yml}"
readonly HEALTH_URL="http://${TARGET_HOST}:4000/health"
readonly METRICS_URL="http://${TARGET_HOST}:9090/api/v1/query"

ROLLBACK_START=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
readonly ROLLBACK_START

# ─── LOGGING ──────────────────────────────────────────────────────────────────
log()  { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] INFO  $*"; }
warn() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] WARN  $*" >&2; }
err()  { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] ERROR $*" >&2; }
die()  { err "$*"; echo "ROLLBACK FAILED — ESCALATE IMMEDIATELY"; exit 1; }

# ─── STEP 1: Record Current State ─────────────────────────────────────────────
step1_snapshot() {
  log "Step 1/5: Capturing current state snapshot..."

  ssh "akushnir@${TARGET_HOST}" "
    echo '=== Docker PS ==='
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null
    echo '=== Recent logs (last 20 lines) ==='
    docker logs code-server --tail=20 2>&1 || true
    echo '=== Canary containers ==='
    docker ps -a --filter name=canary --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null
  " 2>/dev/null || warn "Could not capture state snapshot (continuing)"
  log "Step 1 COMPLETE"
}

# ─── STEP 2: Remove Canary Containers ─────────────────────────────────────────
step2_remove_canary() {
  log "Step 2/5: Removing canary containers..."

  ssh "akushnir@${TARGET_HOST}" "
    cd code-server-enterprise
    # Remove any canary-tagged containers
    docker ps -a --filter name=canary -q | xargs -r docker rm -f
    # Also remove via docker-compose if manifest exists
    if docker-compose -f '${COMPOSE_FILE}' config --services 2>/dev/null | grep -q 'code-server-canary'; then
      docker-compose -f '${COMPOSE_FILE}' rm -fsv code-server-canary 2>/dev/null || true
    fi
    echo 'Canary containers removed'
  " || die "Failed to remove canary containers"

  log "Step 2 COMPLETE — Canary containers removed"
}

# ─── STEP 3: Restore Stable Version ───────────────────────────────────────────
step3_restore_stable() {
  log "Step 3/5: Restoring stable image (${STABLE_IMAGE})..."

  ssh "akushnir@${TARGET_HOST}" "
    cd code-server-enterprise
    # Restore stable image
    export STABLE_IMAGE='${STABLE_IMAGE}'
    docker-compose -f '${COMPOSE_FILE}' up -d --no-deps --force-recreate code-server
    echo 'Stable version restored'
  " || die "Failed to restore stable version"

  # Wait for container to start
  log "Waiting 15s for container startup..."
  sleep 15

  log "Step 3 COMPLETE — Stable version deployed"
}

# ─── STEP 4: Health Verification ──────────────────────────────────────────────
step4_verify_health() {
  log "Step 4/5: Verifying rollback health..."

  local attempts=0
  local max_attempts=12   # 60 seconds total (12 x 5s)

  while [[ ${attempts} -lt ${max_attempts} ]]; do
    local http_status
    http_status=$(curl -so /dev/null -w '%{http_code}' --max-time 5 "${HEALTH_URL}" 2>/dev/null || echo "000")

    if [[ "${http_status}" == "200" ]]; then
      log "  ✅ Health check passed (HTTP 200)"
      break
    fi

    attempts=$((attempts + 1))
    warn "  Health check returned ${http_status} (attempt ${attempts}/${max_attempts})..."
    sleep 5
  done

  if [[ ${attempts} -ge ${max_attempts} ]]; then
    die "Health check did not pass after ${max_attempts} attempts — ESCALATE IMMEDIATELY"
  fi

  # Also verify prometheus is still running
  local prom_status
  prom_status=$(curl -so /dev/null -w '%{http_code}' --max-time 5 "${METRICS_URL}?query=up" 2>/dev/null || echo "000")
  if [[ "${prom_status}" == "200" ]]; then
    log "  ✅ Prometheus still operational"
  else
    warn "  Prometheus may be degraded (HTTP ${prom_status}) — monitor closely"
  fi

  log "Step 4 COMPLETE — System healthy"
}

# ─── STEP 5: Report & Alert ────────────────────────────────────────────────────
step5_report() {
  log "Step 5/5: Generating rollback report..."

  local rollback_end
  rollback_end=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  # Calculate RTO
  local start_ts end_ts rto_seconds
  start_ts=$(date -d "${ROLLBACK_START}" +%s 2>/dev/null || date -j -f '%Y-%m-%dT%H:%M:%SZ' "${ROLLBACK_START}" +%s 2>/dev/null || echo 0)
  end_ts=$(date +%s)
  rto_seconds=$((end_ts - start_ts))

  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║              PHASE 26 ROLLBACK COMPLETE                      ║"
  echo "╠══════════════════════════════════════════════════════════════╣"
  echo "║  Started:    ${ROLLBACK_START}"
  echo "║  Completed:  ${rollback_end}"
  echo "║  RTO:        ${rto_seconds} seconds (threshold: < 300)"
  echo "║  Stable:     ${STABLE_IMAGE}"
  echo "║  Target:     ${TARGET_HOST}"
  echo "║  Status:     ✅ ROLLBACK COMPLETE"
  echo "╚══════════════════════════════════════════════════════════════╝"

  if [[ "${rto_seconds}" -gt 300 ]]; then
    warn "RTO exceeded 5-minute SLA target (took ${rto_seconds}s). Review and tune rollback procedure."
  else
    log "RTO within SLA target ✅ (${rto_seconds}s < 300s)"
  fi

  # Write rollback audit log
  ssh "akushnir@${TARGET_HOST}" "
    mkdir -p /home/akushnir/.rollback-logs
    echo '{\"start\":\"${ROLLBACK_START}\",\"end\":\"${rollback_end}\",\"rto\":${rto_seconds},\"stable\":\"${STABLE_IMAGE}\"}' \
      > /home/akushnir/.rollback-logs/rollback-\$(date +%Y%m%d-%H%M%S).json
    echo 'Rollback log written'
  " || warn "Could not write rollback audit log"

  log "Step 5 COMPLETE"
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
main() {
  echo ""
  log "╔══════════════════════════════════════════════╗"
  log "║     PHASE 26 EMERGENCY ROLLBACK INITIATED    ║"
  log "╚══════════════════════════════════════════════╝"
  log "  Target:  ${TARGET_HOST}"
  log "  Stable:  ${STABLE_IMAGE}"
  log "  RTO SLA: < 5 minutes"
  echo ""

  step1_snapshot
  step2_remove_canary
  step3_restore_stable
  step4_verify_health
  step5_report

  echo ""
  log "ROLLBACK COMPLETE — System restored to stable state"
  echo ""
}

main "$@"
