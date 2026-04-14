#!/bin/bash
################################################################################
# Phase 15: Performance & Load Testing Master Controller
# Purpose: Orchestrate Phase 15 deployment after Phase 14 Stage 3 completion
# Auto-trigger: April 15, 2026 @ 03:00 UTC (post-Phase-14)
# Timeline: 30 min (quick) or 24h+ (extended load test)
# IaC: Immutable (terraform 1.6.x), Idempotent (safe to apply multiple times)
################################################################################

set -euo pipefail

# Configuration
PHASE=15
PHASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${PHASE_DIR}/logs"
TERRAFORM_DIR="${PHASE_DIR}"
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
LOG_FILE="${LOG_DIR}/phase-${PHASE}-controller-${TIMESTAMP}.log"
STATE_FILE="${LOG_DIR}/phase-${PHASE}-state-${TIMESTAMP}.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Ensure directories exist
mkdir -p "${LOG_DIR}" "${TERRAFORM_DIR}"

# Functions
log() {
    echo -e "${BLUE}[$(date -u +'%Y-%m-%d %H:%M:%S UTC')]${NC} $*" | tee -a "${LOG_FILE}"
}

success() {
    echo -e "${GREEN}[✓]${NC} $*" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[✗]${NC} $*" | tee -a "${LOG_FILE}" >&2
}

warn() {
    echo -e "${YELLOW}[!]${NC} $*" | tee -a "${LOG_FILE}"
}

save_state() {
    cat > "${STATE_FILE}" <<EOF
{
  "phase": ${PHASE},
  "started": "$(date -u -Iseconds)",
  "mode": "${MODE}",
  "duration_target": "${DURATION_TARGET}",
  "terraform_version": "$(terraform version -json | jq -r '.terraform_version')",
  "git_commit": "$(git rev-parse HEAD)",
  "git_branch": "$(git symbolic-ref --short HEAD)"
}
EOF
    log "State saved to ${STATE_FILE}"
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v terraform &> /dev/null; then
        error "terraform not found"; return 1
    fi
    success "terraform available"
    
    if ! command -v docker &> /dev/null; then
        error "docker not found"; return 1
    fi
    success "docker available"
    
    return 0
}

validate_terraform() {
    log "Validating terraform configuration..."
    cd "${TERRAFORM_DIR}"
    terraform init -upgrade=false -lock=true > /dev/null 2>&1
    terraform validate > "${LOG_FILE}.tfvalidate" 2>&1 || return 1
    success "Terraform validation passed"
    return 0
}

main() {
    log "Phase 15: Performance & Load Testing Master Controller"
    check_prerequisites || exit 1
    validate_terraform || exit 1
    save_state
    success "Phase 15 ready for execution"
}

MODE="${1:-quick}"
DURATION_TARGET="${2:-30}"
main "$@"
