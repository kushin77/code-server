#!/bin/bash
###############################################################################
# @file        scripts/phase5/deploy-edge-agents-onprem.sh
# @module      phase5/edge-agents
# @description Q3 Phase 5: Deploy edge agents to on-prem nodes (primary + replica)
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# @usage       bash scripts/phase5/deploy-edge-agents-onprem.sh [--dry-run] [--node primary|replica|both]
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source SSOT configuration
. "${REPO_ROOT}/scripts/_common/_base-config.env"

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly LOG_DIR="${REPO_ROOT}/artifacts/phase5"
readonly LOG_FILE="${LOG_DIR}/edge-deploy-$(date +%Y%m%d-%H%M%S).log"
readonly EDGE_AGENT_SERVICE="edge-agent"
readonly EDGE_AGENT_PORT="${EDGE_AGENT_PORT:-8060}"
readonly DEPLOY_USER="${DEPLOY_USER:-akushnir}"

DRY_RUN="${DRY_RUN:-false}"
NODE_TARGET="${NODE_TARGET:-both}"

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

log_info()    { echo -e "${BLUE}[INFO]${NC}    $*" | tee -a "${LOG_FILE}"; }
log_success() { echo -e "${GREEN}[✓]${NC}      $*" | tee -a "${LOG_FILE}"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $*" | tee -a "${LOG_FILE}"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $*" >&2 | tee -a "${LOG_FILE}"; }

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)       DRY_RUN="true";         shift ;;
    --node)          NODE_TARGET="$2";        shift 2 ;;
    --node=*)        NODE_TARGET="${1#*=}";   shift ;;
    --help|-h)
      echo "Usage: $0 [--dry-run] [--node primary|replica|both]"
      exit 0 ;;
    *) log_warn "Unknown arg: $1"; shift ;;
  esac
done

# ============================================================================
# VALIDATION
# ============================================================================

validate_prerequisites() {
  log_info "Validating prerequisites..."

  : "${PRIMARY_HOST:?PRIMARY_HOST must be set}"
  : "${REPLICA_HOST:?REPLICA_HOST must be set}"

  # Verify docker compose file has edge-agent service
  if ! grep -q "^  ${EDGE_AGENT_SERVICE}:" "${REPO_ROOT}/docker-compose.yml"; then
    log_error "edge-agent service not found in docker-compose.yml"
    exit 1
  fi

  log_success "Prerequisites validated"
}

# ============================================================================
# NODE DEPLOYMENT
# ============================================================================

deploy_to_node() {
  local node_name="$1"
  local node_host="$2"
  local is_local="${3:-false}"

  log_info "Deploying edge-agent to ${node_name} (${node_host})..."

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would deploy edge-agent service to ${node_host}"
    log_info "[DRY-RUN]   docker compose up -d --build ${EDGE_AGENT_SERVICE}"
    log_info "[DRY-RUN]   health check: http://${node_host}:${EDGE_AGENT_PORT}/health"
    return 0
  fi

  if [[ "${is_local}" == "true" ]]; then
    # Local deployment
    cd "${REPO_ROOT}"
    docker compose up -d --build "${EDGE_AGENT_SERVICE}" 2>&1 | tee -a "${LOG_FILE}"
  else
    # Remote deployment via SSH
    ssh "${DEPLOY_USER}@${node_host}" \
      "cd ~/code-server-enterprise && git pull origin main && docker compose up -d --build ${EDGE_AGENT_SERVICE}" \
      2>&1 | tee -a "${LOG_FILE}"
  fi

  log_info "Waiting for edge-agent health check on ${node_host}:${EDGE_AGENT_PORT}..."
  local retries=0
  while [[ $retries -lt 12 ]]; do
    if curl -sf --max-time 5 "http://${node_host}:${EDGE_AGENT_PORT}/health" > /dev/null 2>&1; then
      log_success "Edge-agent healthy on ${node_name} (${node_host}:${EDGE_AGENT_PORT})"
      return 0
    fi
    retries=$((retries + 1))
    sleep 5
  done

  log_warn "Edge-agent health check timed out on ${node_host} (may still be starting)"
  return 0
}

register_edge_agents() {
  log_info "Registering edge agents with control plane..."

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would register agents via scripts/edge-agent/register-edge-agent.sh"
    return 0
  fi

  if [[ "${NODE_TARGET}" == "primary" || "${NODE_TARGET}" == "both" ]]; then
    AGENT_ID="primary-${PRIMARY_HOST}" \
    EDGE_LOCATION="onprem-primary" \
    CONTROL_PLANE="http://${PRIMARY_HOST}:8080" \
    bash "${REPO_ROOT}/scripts/edge-agent/register-edge-agent.sh" \
      --agent-id="primary-${PRIMARY_HOST}" \
      --location="onprem-primary" \
      --control-plane="http://localhost:8080" 2>&1 | tee -a "${LOG_FILE}" || true
  fi

  if [[ "${NODE_TARGET}" == "replica" || "${NODE_TARGET}" == "both" ]]; then
    AGENT_ID="replica-${REPLICA_HOST}" \
    EDGE_LOCATION="onprem-replica" \
    CONTROL_PLANE="http://${PRIMARY_HOST}:8080" \
    bash "${REPO_ROOT}/scripts/edge-agent/register-edge-agent.sh" \
      --agent-id="replica-${REPLICA_HOST}" \
      --location="onprem-replica" \
      --control-plane="http://${PRIMARY_HOST}:8080" 2>&1 | tee -a "${LOG_FILE}" || true
  fi

  log_success "Edge agent registration complete"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  log_info "=========================================="
  log_info "Q3 Phase 5: On-Prem Edge Agent Deployment"
  log_info "  Target: ${NODE_TARGET}  Dry-Run: ${DRY_RUN}"
  log_info "=========================================="

  validate_prerequisites

  case "${NODE_TARGET}" in
    primary)
      deploy_to_node "primary" "${PRIMARY_HOST}" "true"
      ;;
    replica)
      deploy_to_node "replica" "${REPLICA_HOST}" "false"
      ;;
    both)
      deploy_to_node "primary" "${PRIMARY_HOST}" "true"
      deploy_to_node "replica" "${REPLICA_HOST}" "false"
      ;;
    *)
      log_error "Invalid --node value: ${NODE_TARGET}. Use: primary, replica, or both"
      exit 1
      ;;
  esac

  register_edge_agents

  log_success "=========================================="
  log_success "Edge agent deployment complete"
  log_success "  Primary: http://${PRIMARY_HOST}:${EDGE_AGENT_PORT}/health"
  log_success "  Replica: http://${REPLICA_HOST}:${EDGE_AGENT_PORT}/health"
  log_info  "  Log: ${LOG_FILE}"
  log_success "=========================================="
}

main "$@"
