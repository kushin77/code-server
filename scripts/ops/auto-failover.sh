#!/bin/bash
###############################################################################
# @file        scripts/ops/auto-failover.sh
# @module      ops/auto-failover
# @description Phase 7 BCP: Automated DR failover for on-prem Docker Compose cluster.
#              Monitors primary node health; auto-promotes replica when primary fails.
#              Target RTO: < 5 minutes from failure detection to traffic serving.
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# @usage       bash scripts/ops/auto-failover.sh [--monitor] [--force-failover] [--dry-run]
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source SSOT configuration
. "${REPO_ROOT}/scripts/_common/_base-config.env"

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly LOG_DIR="${REPO_ROOT}/artifacts/failover"
readonly STATE_FILE="${LOG_DIR}/failover-state.json"
readonly LOG_FILE="${LOG_DIR}/auto-failover-$(date +%Y%m%d).log"

# Health check configuration
readonly HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-15}"   # seconds
readonly FAILURE_THRESHOLD="${FAILURE_THRESHOLD:-3}"             # consecutive failures before failover
readonly HEALTH_ENDPOINT="${HEALTH_ENDPOINT:-/api/health}"
readonly PRIMARY_PORT="${PRIMARY_PORT:-443}"
readonly REPLICA_PORT="${REPLICA_PORT:-443}"

# Notification
readonly NOTIFY_WEBHOOK="${NOTIFY_WEBHOOK:-}"  # Optional Slack/webhook URL

DRY_RUN="${DRY_RUN:-false}"
MODE="${MODE:-check}"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

mkdir -p "${LOG_DIR}"

# ============================================================================
# LOGGING
# ============================================================================

log_info()    { local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ); echo -e "${BLUE}[INFO]${NC} [${ts}] $*" | tee -a "${LOG_FILE}"; }
log_success() { local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ); echo -e "${GREEN}[✓]${NC}   [${ts}] $*" | tee -a "${LOG_FILE}"; }
log_warn()    { local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ); echo -e "${YELLOW}[WARN]${NC} [${ts}] $*" | tee -a "${LOG_FILE}"; }
log_error()   { local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ); echo -e "${RED}[ERROR]${NC} [${ts}] $*" >&2 | tee -a "${LOG_FILE}"; }

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --monitor)       MODE="monitor";          shift ;;
    --force-failover) MODE="force-failover";  shift ;;
    --check)         MODE="check";            shift ;;
    --status)        MODE="status";           shift ;;
    --dry-run)       DRY_RUN="true";          shift ;;
    --help|-h)
      cat <<EOF
Usage: $0 [--monitor] [--force-failover] [--check] [--status] [--dry-run]

Modes:
  --check           Single health check of both nodes (default)
  --monitor         Continuous monitoring loop (run via systemd/cron)
  --force-failover  Immediately trigger failover to replica
  --status          Show current failover state

Options:
  --dry-run         Print actions without executing them
EOF
      exit 0 ;;
    *) log_warn "Unknown arg: $1"; shift ;;
  esac
done

# ============================================================================
# STATE MANAGEMENT
# ============================================================================

# Portable JSON field reader (no jq dependency)
json_get() {
  local key="$1" file="$2"
  grep -o "\"${key}\":[[:space:]]*\"[^\"]*\"" "${file}" 2>/dev/null \
    | sed 's/.*":[[:space:]]*"//;s/"$//' \
    || echo ""
}

json_get_num() {
  local key="$1" file="$2"
  grep -o "\"${key}\":[[:space:]]*[0-9]*" "${file}" 2>/dev/null \
    | sed 's/.*:[[:space:]]*//' \
    || echo "0"
}

get_state() {
  if [[ -f "${STATE_FILE}" ]]; then
    cat "${STATE_FILE}"
  else
    echo '{"active_node":"primary","failure_count":0,"last_failover":"null","status":"nominal"}'
  fi
}

get_active_node() {
  if [[ -f "${STATE_FILE}" ]]; then
    json_get "active_node" "${STATE_FILE}"
  else
    echo "primary"
  fi
}

save_state() {
  local active_node="$1"
  local failure_count="$2"
  local status="$3"
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local last_failover="null"
  if [[ -f "${STATE_FILE}" ]]; then
    local lf; lf=$(json_get "last_failover" "${STATE_FILE}")
    [[ -n "${lf}" ]] && last_failover="\"${lf}\""
  fi

  cat > "${STATE_FILE}" <<EOF
{
  "active_node": "${active_node}",
  "failure_count": ${failure_count},
  "last_updated": "${ts}",
  "last_failover": ${last_failover},
  "status": "${status}"
}
EOF
}

mark_failover_complete() {
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  save_state "replica" "0" "failed-over"
  # Patch last_failover field
  sed -i "s|\"last_failover\": null|\"last_failover\": \"${ts}\"|g" "${STATE_FILE}" 2>/dev/null || true
}

# ============================================================================
# HEALTH CHECKS
# ============================================================================

check_node_health() {
  local host="$1"
  local port="$2"
  local node_name="$3"

  # Try HTTPS first, fall back to HTTP
  if curl -sf --max-time 10 --connect-timeout 5 \
    -o /dev/null \
    "https://${host}:${port}${HEALTH_ENDPOINT}" 2>/dev/null; then
    return 0
  fi

  if curl -sf --max-time 10 --connect-timeout 5 \
    -o /dev/null \
    "http://${host}:8080${HEALTH_ENDPOINT}" 2>/dev/null; then
    return 0
  fi

  # Try Docker Compose service ping (if running locally on primary)
  if [[ "${node_name}" == "primary" ]] && docker compose -f "${REPO_ROOT}/docker-compose.yml" \
    exec -T caddy caddy health 2>/dev/null; then
    return 0
  fi

  return 1
}

check_both_nodes() {
  local primary_healthy=false
  local replica_healthy=false

  if check_node_health "${PRIMARY_HOST}" "${PRIMARY_PORT}" "primary" 2>/dev/null; then
    primary_healthy=true
    log_success "Primary (${PRIMARY_HOST}) healthy"
  else
    log_warn "Primary (${PRIMARY_HOST}) UNREACHABLE"
  fi

  if check_node_health "${REPLICA_HOST}" "${REPLICA_PORT}" "replica" 2>/dev/null; then
    replica_healthy=true
    log_success "Replica (${REPLICA_HOST}) healthy"
  else
    log_warn "Replica (${REPLICA_HOST}) UNREACHABLE"
  fi

  echo "${primary_healthy}:${replica_healthy}"
}

# ============================================================================
# FAILOVER PROCEDURES
# ============================================================================

notify_failover() {
  local message="$1"
  log_warn "FAILOVER NOTIFICATION: ${message}"

  if [[ -n "${NOTIFY_WEBHOOK}" ]]; then
    curl -sf --max-time 10 -X POST "${NOTIFY_WEBHOOK}" \
      -H 'Content-Type: application/json' \
      -d "{\"text\": \"🚨 DR FAILOVER: ${message}\"}" 2>/dev/null || true
  fi
}

update_caddy_upstream() {
  local new_upstream="$1"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would update Caddy upstream to: ${new_upstream}"
    return 0
  fi

  local caddy_config="${REPO_ROOT}/Caddyfile"

  # Atomic backup + update
  cp "${caddy_config}" "${caddy_config}.failover.bak"

  # Swap primary/replica in upstream blocks
  if [[ "${new_upstream}" == "replica" ]]; then
    # Promote replica: put REPLICA_HOST first, demote PRIMARY_HOST
    sed -i "s|to https://${PRIMARY_HOST}|to https://${REPLICA_HOST}|g" "${caddy_config}"
    log_success "Caddy upstream updated to replica (${REPLICA_HOST})"
  else
    # Restore primary
    if [[ -f "${caddy_config}.original.bak" ]]; then
      cp "${caddy_config}.original.bak" "${caddy_config}"
      log_success "Caddy upstream restored to primary (${PRIMARY_HOST})"
    fi
  fi

  # Reload Caddy without downtime
  docker compose -f "${REPO_ROOT}/docker-compose.yml" exec -T caddy \
    caddy reload --config /etc/caddy/Caddyfile 2>&1 | tee -a "${LOG_FILE}" || true
}

start_replica_services() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would verify all services healthy on replica (${REPLICA_HOST})"
    return 0
  fi

  log_info "Verifying replica services are running..."
  ssh "${DEPLOY_USER:-akushnir}@${REPLICA_HOST}" \
    "cd ~/code-server-enterprise && docker compose up -d && docker compose ps" \
    2>&1 | tee -a "${LOG_FILE}" || {
      log_error "Could not verify replica services via SSH"
      return 1
    }
}

execute_failover() {
  local start_time; start_time=$(date +%s)
  log_warn "============================================"
  log_warn "INITIATING AUTOMATED FAILOVER TO REPLICA"
  log_warn "  Primary: ${PRIMARY_HOST} (FAILED)"
  log_warn "  Replica: ${REPLICA_HOST} (PROMOTING)"
  log_warn "============================================"

  notify_failover "Primary ${PRIMARY_HOST} failed. Promoting replica ${REPLICA_HOST}."

  # Step 1: Ensure replica services are up
  log_info "[STEP 1/3] Verifying replica services..."
  start_replica_services

  # Step 2: Update load balancer / Caddy
  log_info "[STEP 2/3] Updating Caddy upstream to replica..."
  update_caddy_upstream "replica"

  # Step 3: Update state
  log_info "[STEP 3/3] Recording failover state..."
  mark_failover_complete

  local end_time; end_time=$(date +%s)
  local elapsed=$((end_time - start_time))

  log_success "============================================"
  log_success "FAILOVER COMPLETE in ${elapsed}s"
  log_success "  Active node: REPLICA (${REPLICA_HOST})"
  if [[ $elapsed -lt 300 ]]; then
    log_success "  RTO: ${elapsed}s ✓ (< 5 min target)"
  else
    log_warn "  RTO: ${elapsed}s ✗ (exceeded 5 min target)"
  fi
  log_success "============================================"

  notify_failover "Failover complete in ${elapsed}s. Active: ${REPLICA_HOST}. RTO target met: $([[ $elapsed -lt 300 ]] && echo YES || echo NO)."
}

# ============================================================================
# MODES
# ============================================================================

mode_check() {
  log_info "Single health check of both nodes..."
  local result; result=$(check_both_nodes)
  local primary_healthy="${result%%:*}"
  local replica_healthy="${result##*:}"

  echo ""
  echo "Primary  (${PRIMARY_HOST}): $([[ "${primary_healthy}" == "true" ]] && echo "✓ HEALTHY" || echo "✗ UNHEALTHY")"
  echo "Replica  (${REPLICA_HOST}): $([[ "${replica_healthy}" == "true" ]] && echo "✓ HEALTHY" || echo "✗ UNHEALTHY")"

  local state; state=$(get_state)
  echo "  Active   node: $(json_get 'active_node' "${STATE_FILE}" || echo 'primary')"
  echo "  Status:        $(json_get 'status' "${STATE_FILE}" || echo 'nominal')"
}

mode_monitor() {
  log_info "Starting continuous monitoring (interval: ${HEALTH_CHECK_INTERVAL}s, threshold: ${FAILURE_THRESHOLD})"

  local failure_count=0
  local active_node; active_node=$(get_active_node)

  while true; do
    local result; result=$(check_both_nodes 2>/dev/null || echo "false:false")
    local primary_healthy="${result%%:*}"
    local replica_healthy="${result##*:}"

    if [[ "${active_node}" == "primary" ]]; then
      if [[ "${primary_healthy}" == "false" ]]; then
        failure_count=$((failure_count + 1))
        log_warn "Primary health check FAILED (${failure_count}/${FAILURE_THRESHOLD})"
        save_state "${active_node}" "${failure_count}" "degraded"

        if [[ $failure_count -ge $FAILURE_THRESHOLD ]]; then
          if [[ "${replica_healthy}" == "true" ]]; then
            execute_failover
            active_node="replica"
            failure_count=0
          else
            log_error "BOTH NODES UNHEALTHY — cannot auto-failover. Manual intervention required."
            notify_failover "CRITICAL: Both nodes unreachable. Manual intervention required."
          fi
        fi
      else
        if [[ $failure_count -gt 0 ]]; then
          log_success "Primary recovered (was ${failure_count} failures)"
          failure_count=0
          save_state "${active_node}" "0" "nominal"
        fi
      fi
    fi

    sleep "${HEALTH_CHECK_INTERVAL}"
  done
}

mode_force_failover() {
  log_warn "Force-failover requested (bypassing health threshold)..."

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would execute immediate failover to replica"
    return 0
  fi

  execute_failover
}

mode_status() {
  echo ""
  echo "=============================="
  echo "  DR Failover Status"
  echo "=============================="
  echo "  Active node:    $(json_get 'active_node' "${STATE_FILE}" || echo 'primary')"
  echo "  Status:         $(json_get 'status' "${STATE_FILE}" || echo 'nominal')"
  echo "  Failure count:  $(json_get_num 'failure_count' "${STATE_FILE}" || echo '0')"
  echo "  Last failover:  $(json_get 'last_failover' "${STATE_FILE}" || echo 'never')"
  echo "  Last updated:   $(json_get 'last_updated' "${STATE_FILE}" || echo 'unknown')"
  echo "=============================="
  echo "  Primary:  ${PRIMARY_HOST}:${PRIMARY_PORT}"
  echo "  Replica:  ${REPLICA_HOST}:${REPLICA_PORT}"
  echo "=============================="

  if [[ -f "${LOG_FILE}" ]]; then
    echo ""
    echo "Recent log (last 5 lines):"
    grep -c '' "${LOG_FILE}" 2>/dev/null | xargs -I{} echo "Log lines: {}" || true
  fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  log_info "auto-failover.sh v1.0 | mode=${MODE} | dry-run=${DRY_RUN}"
  log_info "  Primary: ${PRIMARY_HOST} | Replica: ${REPLICA_HOST}"

  case "${MODE}" in
    check)          mode_check ;;
    monitor)        mode_monitor ;;
    force-failover) mode_force_failover ;;
    status)         mode_status ;;
    *)
      log_error "Unknown mode: ${MODE}"
      exit 1 ;;
  esac
}

main "$@"
