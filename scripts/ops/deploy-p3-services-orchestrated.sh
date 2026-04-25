#!/bin/bash
# @file scripts/ops/deploy-p3-services-orchestrated.sh
# @description P3 Services Deployment Orchestration (IaC-driven)
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# @author GitHub Copilot
# @date 2026-04-25
# @related P3 Services Deployment

set -euo pipefail

################################################################################
# DEPLOYMENT ORCHESTRATION FOR P3 SERVICES
# 
# Orchestrates deployment across:
# 1. DNS Infrastructure (Terraform)
# 2. P3 Services (docker-compose or Kubernetes)
# 3. Verification (integration tests)
# 4. Monitoring (health checks)
################################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
DEPLOYMENT_ID="$(date +'%Y%m%d-%H%M%S')"
DEPLOYMENT_LOG="artifacts/deployment-${DEPLOYMENT_ID}.log"
DEPLOYMENT_REPORT="artifacts/deployment-report-${DEPLOYMENT_ID}.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Deployment flags
DRY_RUN="${DRY_RUN:-false}"
SKIP_DNS="${SKIP_DNS:-false}"
SKIP_SERVICES="${SKIP_SERVICES:-false}"
SKIP_VERIFICATION="${SKIP_VERIFICATION:-false}"
ENVIRONMENT="${ENVIRONMENT:-development}"

################################################################################
# LOGGING & REPORTING
################################################################################

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$DEPLOYMENT_LOG"
}

pass() {
  echo -e "${GREEN}[✓]${NC} $*" | tee -a "$DEPLOYMENT_LOG"
}

fail() {
  echo -e "${RED}[✗]${NC} $*" | tee -a "$DEPLOYMENT_LOG"
}

warn() {
  echo -e "${YELLOW}[⚠]${NC} $*" | tee -a "$DEPLOYMENT_LOG"
}

info() {
  echo -e "${CYAN}[ℹ]${NC} $*" | tee -a "$DEPLOYMENT_LOG"
}

################################################################################
# DEPLOYMENT STATE TRACKING
################################################################################

declare -a DEPLOYMENT_STEPS=()
declare -A STEP_STATUS=()
declare -A STEP_DURATION=()
TOTAL_DURATION=0

track_step() {
  local step_name="$1"
  DEPLOYMENT_STEPS+=("$step_name")
  STEP_STATUS["$step_name"]="PENDING"
}

start_step() {
  local step_name="$1"
  STEP_STATUS["$step_name"]="IN_PROGRESS"
  log "Starting: $step_name"
  echo "${step_name}_START=$(date +%s)" >> "$DEPLOYMENT_LOG"
}

complete_step() {
  local step_name="$1"
  local status="${2:-SUCCESS}"
  
  STEP_STATUS["$step_name"]="$status"
  log "Completed: $step_name ($status)"
}

################################################################################
# PREREQUISITE CHECKS
################################################################################

check_prerequisites() {
  log "════════════════════════════════════════════════════════"
  log "CHECKING DEPLOYMENT PREREQUISITES"
  log "════════════════════════════════════════════════════════"
  
  local all_ok=true
  
  # Check Git
  if command -v git &> /dev/null; then
    pass "Git available ($(git --version | cut -d' ' -f3))"
  else
    fail "Git not found"
    all_ok=false
  fi
  
  # Check bash
  if command -v bash &> /dev/null; then
    pass "Bash available ($(bash --version | head -1))"
  else
    fail "Bash not found"
    all_ok=false
  fi
  
  # Check Terraform (optional)
  if command -v terraform &> /dev/null; then
    pass "Terraform available ($(terraform version | head -1 | cut -d'v' -f2))"
  else
    warn "Terraform not available (DNS deployment will be skipped)"
  fi
  
  # Check Docker (optional)
  if command -v docker &> /dev/null; then
    pass "Docker available ($(docker --version))"
  else
    warn "Docker not available (service deployment will need alternative)"
  fi
  
  # Check docker-compose (optional)
  if command -v docker-compose &> /dev/null; then
    pass "docker-compose available ($(docker-compose --version))"
  elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    pass "docker compose available (integrated plugin)"
  else
    warn "docker-compose not available (service deployment will need alternative)"
  fi
  
  # Check configuration file
  if [[ -f "$REPO_ROOT/scripts/_common/_p3-services-config.env" ]]; then
    pass "P3 configuration file present"
  else
    fail "P3 configuration file missing"
    all_ok=false
  fi
  
  # Check verification script
  if [[ -f "$REPO_ROOT/scripts/ci/verify-p3-services-full-integration.sh" ]]; then
    pass "Verification script present"
  else
    fail "Verification script missing"
    all_ok=false
  fi
  
  if [[ "$all_ok" == "false" ]]; then
    fail "Some prerequisites missing"
    return 1
  fi
  
  pass "All prerequisites met"
  return 0
}

################################################################################
# PHASE 1: DNS INFRASTRUCTURE DEPLOYMENT
################################################################################

deploy_dns_infrastructure() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "PHASE 1: DNS INFRASTRUCTURE DEPLOYMENT"
  log "════════════════════════════════════════════════════════"
  
  start_step "DNS_INFRASTRUCTURE"
  
  # Check if Terraform is available
  if ! command -v terraform &> /dev/null; then
    warn "Terraform not available - skipping DNS deployment"
    warn "To deploy DNS: export TF_VAR_cloudflare_api_token=... && terraform -C terraform apply"
    complete_step "DNS_INFRASTRUCTURE" "SKIPPED"
    return 0
  fi
  
  # Validate Terraform configuration
  log "Validating Terraform configuration..."
  if terraform -C "$REPO_ROOT/terraform" validate > /dev/null 2>&1; then
    pass "Terraform validation successful"
  else
    fail "Terraform validation failed"
    complete_step "DNS_INFRASTRUCTURE" "FAILED"
    return 1
  fi
  
  # Plan deployment
  log "Planning Terraform deployment..."
  if [[ "$DRY_RUN" == "true" ]]; then
    info "DRY RUN: Showing plan only"
    terraform -C "$REPO_ROOT/terraform" plan || warn "Plan failed"
    complete_step "DNS_INFRASTRUCTURE" "PLANNED"
    return 0
  fi
  
  # Check for required variables
  if [[ -z "${TF_VAR_cloudflare_api_token:-}" ]]; then
    warn "TF_VAR_cloudflare_api_token not set - skipping Terraform apply"
    info "To deploy DNS: export TF_VAR_cloudflare_api_token=your_token"
    complete_step "DNS_INFRASTRUCTURE" "SKIPPED"
    return 0
  fi
  
  # Apply Terraform
  log "Applying Terraform configuration..."
  if terraform -C "$REPO_ROOT/terraform" apply -auto-approve > /tmp/tf-apply.log 2>&1; then
    pass "Terraform apply successful"
    complete_step "DNS_INFRASTRUCTURE" "SUCCESS"
  else
    fail "Terraform apply failed"
    cat /tmp/tf-apply.log >> "$DEPLOYMENT_LOG"
    complete_step "DNS_INFRASTRUCTURE" "FAILED"
    return 1
  fi
}

################################################################################
# PHASE 2: P3 SERVICES DEPLOYMENT
################################################################################

deploy_p3_services() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "PHASE 2: P3 SERVICES DEPLOYMENT"
  log "════════════════════════════════════════════════════════"
  
  start_step "P3_SERVICES"
  
  # Source P3 configuration
  log "Loading P3 configuration..."
  if [[ ! -f "$REPO_ROOT/scripts/_common/_p3-services-config.env" ]]; then
    fail "P3 configuration file not found"
    complete_step "P3_SERVICES" "FAILED"
    return 1
  fi
  
  # shellcheck disable=SC1090
  source "$REPO_ROOT/scripts/_common/_p3-services-config.env"
  pass "P3 configuration loaded"
  
  # Check Docker availability
  if ! command -v docker &> /dev/null; then
    warn "Docker not available - cannot deploy services"
    info "Manual deployment required or use alternative container runtime"
    complete_step "P3_SERVICES" "SKIPPED"
    return 0
  fi
  
  # Check docker-compose availability
  local docker_compose_cmd="docker-compose"
  if ! command -v docker-compose &> /dev/null; then
    if docker compose version &> /dev/null 2>&1; then
      docker_compose_cmd="docker compose"
    else
      warn "docker-compose/docker compose not available"
      complete_step "P3_SERVICES" "SKIPPED"
      return 0
    fi
  fi
  
  log "Using: $docker_compose_cmd"
  
  # Pull latest images
  log "Pulling service images..."
  if [[ "$DRY_RUN" == "true" ]]; then
    info "DRY RUN: Would pull images"
  else
    if $docker_compose_cmd pull 2>&1 | tee -a "$DEPLOYMENT_LOG"; then
      pass "Images pulled successfully"
    else
      warn "Failed to pull some images (may already be present)"
    fi
  fi
  
  # Start services
  log "Starting P3 services..."
  if [[ "$DRY_RUN" == "true" ]]; then
    info "DRY RUN: Would deploy services"
    info "Command: $docker_compose_cmd up -d reputation-engine execution-scheduler paperclip opa"
    complete_step "P3_SERVICES" "PLANNED"
    return 0
  fi
  
  if $docker_compose_cmd up -d reputation-engine execution-scheduler paperclip opa 2>&1 | tee -a "$DEPLOYMENT_LOG"; then
    pass "P3 services started successfully"
    
    # Wait for services to stabilize
    log "Waiting for services to stabilize (30s)..."
    sleep 30
    
    complete_step "P3_SERVICES" "SUCCESS"
  else
    fail "Failed to start P3 services"
    complete_step "P3_SERVICES" "FAILED"
    return 1
  fi
}

################################################################################
# PHASE 3: VERIFICATION
################################################################################

verify_deployment() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "PHASE 3: DEPLOYMENT VERIFICATION"
  log "════════════════════════════════════════════════════════"
  
  start_step "VERIFICATION"
  
  # Source P3 configuration
  source "$REPO_ROOT/scripts/_common/_p3-services-config.env"
  
  # Run integration verification
  if [[ ! -f "$REPO_ROOT/scripts/ci/verify-p3-services-full-integration.sh" ]]; then
    fail "Verification script not found"
    complete_step "VERIFICATION" "SKIPPED"
    return 0
  fi
  
  log "Running integration verification tests..."
  
  if [[ "$DRY_RUN" == "true" ]]; then
    info "DRY RUN: Would run verification tests"
    complete_step "VERIFICATION" "PLANNED"
    return 0
  fi
  
  if bash "$REPO_ROOT/scripts/ci/verify-p3-services-full-integration.sh" >> "$DEPLOYMENT_LOG" 2>&1; then
    pass "Integration verification passed"
    complete_step "VERIFICATION" "SUCCESS"
  else
    fail "Integration verification failed"
    complete_step "VERIFICATION" "FAILED"
    return 1
  fi
}

################################################################################
# FINAL REPORTING
################################################################################

generate_deployment_report() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "DEPLOYMENT REPORT"
  log "════════════════════════════════════════════════════════"
  
  mkdir -p artifacts
  
  # Count successes and failures
  local success_count=0
  local failure_count=0
  local skipped_count=0
  
  for step in "${DEPLOYMENT_STEPS[@]}"; do
    case "${STEP_STATUS[$step]}" in
      SUCCESS) ((success_count++)) ;;
      FAILED) ((failure_count++)) ;;
      *) ((skipped_count++)) ;;
    esac
  done
  
  # Generate JSON report
  cat > "$DEPLOYMENT_REPORT" << EOF
{
  "deployment_id": "$DEPLOYMENT_ID",
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "environment": "$ENVIRONMENT",
  "dry_run": $([[ "$DRY_RUN" == "true" ]] && echo "true" || echo "false"),
  "total_steps": ${#DEPLOYMENT_STEPS[@]},
  "successful": $success_count,
  "failed": $failure_count,
  "skipped": $skipped_count,
  "status": "$(if [[ $failure_count -eq 0 ]]; then echo "SUCCESS"; else echo "FAILED"; fi)",
  "steps": [
EOF

  local first=true
  for step in "${DEPLOYMENT_STEPS[@]}"; do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      echo "," >> "$DEPLOYMENT_REPORT"
    fi
    
    cat >> "$DEPLOYMENT_REPORT" << EOF
    {
      "name": "$step",
      "status": "${STEP_STATUS[$step]}"
    }
EOF
  done
  
  echo "" >> "$DEPLOYMENT_REPORT"
  echo "  ]" >> "$DEPLOYMENT_REPORT"
  echo "}" >> "$DEPLOYMENT_REPORT"
  
  # Print report
  log ""
  info "Deployment Summary:"
  info "  ID: $DEPLOYMENT_ID"
  info "  Environment: $ENVIRONMENT"
  info "  Dry Run: $DRY_RUN"
  info "  Total Steps: ${#DEPLOYMENT_STEPS[@]}"
  info "  Successful: $success_count"
  info "  Failed: $failure_count"
  info "  Skipped: $skipped_count"
  info ""
  info "Detailed Report: $DEPLOYMENT_REPORT"
  info "Deployment Log: $DEPLOYMENT_LOG"
  
  if [[ $failure_count -eq 0 ]]; then
    pass "Deployment completed successfully"
    return 0
  else
    fail "Deployment completed with failures"
    return 1
  fi
}

################################################################################
# MAIN ORCHESTRATION
################################################################################

main() {
  mkdir -p artifacts
  
  log "╔════════════════════════════════════════════════════════╗"
  log "║  P3 SERVICES DEPLOYMENT ORCHESTRATION                 ║"
  log "║  Deployment ID: $DEPLOYMENT_ID"
  log "║  Environment: $ENVIRONMENT"
  log "║  Dry Run: $DRY_RUN"
  log "╚════════════════════════════════════════════════════════╝"
  
  # Check prerequisites
  track_step "PREREQUISITES"
  start_step "PREREQUISITES"
  if check_prerequisites; then
    complete_step "PREREQUISITES" "SUCCESS"
  else
    fail "Prerequisites check failed"
    complete_step "PREREQUISITES" "FAILED"
    generate_deployment_report
    return 1
  fi
  
  # Deploy DNS infrastructure
  if [[ "$SKIP_DNS" != "true" ]]; then
    track_step "DNS_INFRASTRUCTURE"
    deploy_dns_infrastructure || warn "DNS infrastructure deployment failed or skipped"
  fi
  
  # Deploy P3 services
  if [[ "$SKIP_SERVICES" != "true" ]]; then
    track_step "P3_SERVICES"
    deploy_p3_services || warn "P3 services deployment failed or skipped"
  fi
  
  # Verify deployment
  if [[ "$SKIP_VERIFICATION" != "true" ]]; then
    track_step "VERIFICATION"
    verify_deployment || warn "Verification failed or skipped"
  fi
  
  # Generate report
  generate_deployment_report
}

# Execute main
main "$@"
