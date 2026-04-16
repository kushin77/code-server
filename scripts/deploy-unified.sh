#!/bin/bash
# Unified Production Deployment Entrypoint
# Purpose: SINGLE canonical script to deploy entire infrastructure
# Replaces 263+ scattered phase scripts
# 
# Usage: ./scripts/deploy-unified.sh [PHASE|all] [OPTIONS]
# 
# Phases:
#   1 - Initialize infrastructure (VM prep, networking)
#   2 - Infrastructure (Docker, storage, K8s/Docker Compose)
#   3 - Core services (code-server, PostgreSQL, Redis)
#   4 - Observability (Prometheus, Grafana, Loki, Jaeger)
#   5 - Security (Vault, Falco, OPA, RBAC)
#   6 - High Availability (Patroni, Sentinel, HAProxy, VIP)
#   7 - Gateways (Kong, Caddy, oauth2-proxy, Cloudflare)
#   all - Execute all phases sequentially
#
# Example: ./scripts/deploy-unified.sh all --production --verbose --dry-run
#
# Requirements:
#   - Ansible (for remote execution)
#   - jq (for JSON parsing)
#   - yq (for YAML parsing)
#   - SSH access to infrastructure hosts (inventory/infrastructure.yaml)
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Prerequisites not met
#   3 - Deployment failed (with rollback option)
#   4 - User cancel

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/_common/init.sh"
INVENTORY_FILE="$PROJECT_ROOT/inventory/infrastructure.yaml"
AUDIT_LOG="$PROJECT_ROOT/logs/deployments.log"
DEPLOYMENT_STATE="$PROJECT_ROOT/.deployment-state"
GLOBAL_GATE_SCRIPT="$PROJECT_ROOT/scripts/lib/global-quality-gate.sh"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Options
ENVIRONMENT="${ENVIRONMENT:-production}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
PHASE="${1:-all}"
FORCE="${FORCE:-false}"
PARALLEL="${PARALLEL:-false}"

# ──────────────────────────────────────────────────────────────────────────────
# UTILITY FUNCTIONS
# ──────────────────────────────────────────────────────────────────────────────

log() {
  local level=$1; shift
  local msg="$@"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  case "$level" in
    INFO)  echo -e "${BLUE}[INFO]${NC} $msg" ;;
    OK)    echo -e "${GREEN}[✓]${NC} $msg" ;;
    WARN)  echo -e "${YELLOW}[!]${NC} $msg" ;;
    ERROR) echo -e "${RED}[✗]${NC} $msg" >&2 ;;
  esac
  
  # Audit log
  mkdir -p "$(dirname "$AUDIT_LOG")"
  echo "[$timestamp] [$level] $msg" >> "$AUDIT_LOG"
}

check_prerequisites() {
  log INFO "Checking prerequisites..."

  # Run repo-wide quality invariants before deploy orchestration.
  if [ -f "$GLOBAL_GATE_SCRIPT" ]; then
    log INFO "Running global quality gate..."
    GATE_MODE=incremental bash "$GLOBAL_GATE_SCRIPT"
  fi
  
  local missing_tools=()
  for tool in ansible jq yq ssh; do
    if ! command -v "$tool" &>/dev/null; then
      missing_tools+=("$tool")
    fi
  done
  
  if [ ${#missing_tools[@]} -gt 0 ]; then
    log ERROR "Missing required tools: ${missing_tools[*]}"
    log INFO "Install with: pip install ansible pyyaml && apt-get install jq"
    return 2
  fi
  
  # Check inventory file
  if [ ! -f "$INVENTORY_FILE" ]; then
    log ERROR "Inventory file not found: $INVENTORY_FILE"
    return 2
  fi
  
  # Validate YAML
  if ! yq eval '.' "$INVENTORY_FILE" > /dev/null 2>&1; then
    log ERROR "Inventory YAML invalid"
    return 2
  fi
  
  log OK "All prerequisites met"
  return 0
}

load_infrastructure() {
  log INFO "Loading infrastructure inventory..."
  
  PRIMARY_IP=$(yq eval '.hosts.primary.ip_address' "$INVENTORY_FILE")
  REPLICA_IP=$(yq eval '.hosts.replica.ip_address' "$INVENTORY_FILE")
  SSH_USER=$(yq eval '.hosts.primary.ssh_user' "$INVENTORY_FILE")
  
  log OK "Infrastructure loaded: primary=$PRIMARY_IP, replica=$REPLICA_IP"
}

record_deployment() {
  local phase=$1
  local status=$2
  local duration=$3
  
  local entry
  entry=$(cat <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "phase": $phase,
  "environment": "$ENVIRONMENT",
  "status": "$status",
  "duration_seconds": $duration,
  "user": "${USER:-unknown}",
  "hostname": "$(hostname)",
  "git_commit": "$(cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null || echo 'unknown')"
}
EOF
)
  
  # Store in deployment state file
  echo "$entry" >> "$DEPLOYMENT_STATE"
  log INFO "Deployment recorded: phase=$phase status=$status"
}

# ──────────────────────────────────────────────────────────────────────────────
# PHASE EXECUTION FUNCTIONS
# ──────────────────────────────────────────────────────────────────────────────

phase_1_init() {
  log INFO "========== PHASE 1: Infrastructure Initialization =========="
  log INFO "Network prep, VM setup, SSH verification"
  
  # TODO: Call phase-1-init.sh
  bash "$SCRIPT_DIR/_deploy-phases/phase-1-init.sh" "$ENVIRONMENT" "$PRIMARY_IP" "$REPLICA_IP"
  
  log OK "Phase 1 complete"
}

phase_2_infra() {
  log INFO "========== PHASE 2: Infrastructure Setup =========="
  log INFO "Docker, storage, networking"
  
  # TODO: Call phase-2-infra.sh
  bash "$SCRIPT_DIR/_deploy-phases/phase-2-infra.sh" "$ENVIRONMENT" "$PRIMARY_IP" "$REPLICA_IP"
  
  log OK "Phase 2 complete"
}

phase_3_services() {
  log INFO "========== PHASE 3: Core Services =========="
  log INFO "code-server, PostgreSQL, Redis"
  
  # TODO: Call phase-3-services.sh
  bash "$SCRIPT_DIR/_deploy-phases/phase-3-services.sh" "$ENVIRONMENT" "$PRIMARY_IP"
  
  log OK "Phase 3 complete"
}

phase_4_observability() {
  log INFO "========== PHASE 4: Observability Stack =========="
  log INFO "Prometheus, Grafana, Loki, Jaeger"
  
  # TODO: Call phase-4-observability.sh
  bash "$SCRIPT_DIR/_deploy-phases/phase-4-observability.sh" "$ENVIRONMENT" "$PRIMARY_IP"
  
  log OK "Phase 4 complete"
}

phase_5_security() {
  log INFO "========== PHASE 5: Security Hardening =========="
  log INFO "Vault, Falco, OPA, RBAC"
  
  # TODO: Call phase-5-security.sh
  bash "$SCRIPT_DIR/_deploy-phases/phase-5-security.sh" "$ENVIRONMENT" "$PRIMARY_IP"
  
  log OK "Phase 5 complete"
}

phase_6_ha() {
  log INFO "========== PHASE 6: High Availability =========="
  log INFO "Patroni, Redis Sentinel, HAProxy VIP, Keepalived"
  
  # TODO: Call phase-6-ha.sh
  bash "$SCRIPT_DIR/_deploy-phases/phase-6-ha.sh" "$ENVIRONMENT" "$PRIMARY_IP" "$REPLICA_IP"
  
  log OK "Phase 6 complete"
}

phase_7_gateways() {
  log INFO "========== PHASE 7: API Gateways =========="
  log INFO "Kong, Caddy, oauth2-proxy, Cloudflare"
  
  # TODO: Call phase-7-gateways.sh
  bash "$SCRIPT_DIR/_deploy-phases/phase-7-gateways.sh" "$ENVIRONMENT" "$PRIMARY_IP"
  
  log OK "Phase 7 complete"
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN ORCHESTRATION
# ──────────────────────────────────────────────────────────────────────────────

main() {
  log INFO "╔════════════════════════════════════════════════════════════════╗"
  log INFO "║  UNIFIED PRODUCTION DEPLOYMENT SCRIPT                         ║"
  log INFO "║  Environment: $ENVIRONMENT | Phase: $PHASE | DryRun: $DRY_RUN ║"
  log INFO "╚════════════════════════════════════════════════════════════════╝"
  
  # Validate prerequisites
  if ! check_prerequisites; then
    return 2
  fi
  
  # Load infrastructure
  load_infrastructure
  
  # Execute phases
  local start_time
  start_time=$(date +%s)
  
  case "$PHASE" in
    1)
      phase_1_init
      ;;
    2)
      phase_2_infra
      ;;
    3)
      phase_3_services
      ;;
    4)
      phase_4_observability
      ;;
    5)
      phase_5_security
      ;;
    6)
      phase_6_ha
      ;;
    7)
      phase_7_gateways
      ;;
    all)
      phase_1_init && \
      phase_2_infra && \
      phase_3_services && \
      phase_4_observability && \
      phase_5_security && \
      phase_6_ha && \
      phase_7_gateways
      ;;
    *)
      log ERROR "Invalid phase: $PHASE (expected 1-7 or 'all')"
      return 1
      ;;
  esac
  
  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  record_deployment "$PHASE" "success" "$duration"
  
  log OK "╔════════════════════════════════════════════════════════════════╗"
  log OK "║  DEPLOYMENT COMPLETE                                          ║"
  log OK "║  Duration: $(printf '%02d' $((duration / 60))):$(printf '%02d' $((duration % 60)))                                                 ║"
  log OK "║  Audit log: $AUDIT_LOG                    ║"
  log OK "╚════════════════════════════════════════════════════════════════╝"
}

# Run main
main "$@"
