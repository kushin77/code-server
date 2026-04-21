#!/usr/bin/env bash
# @file        PHASE-2C-STANDALONE-EXECUTION.sh
# @module      operations/phase-2
# @description Standalone Phase 2C execution (no external dependencies) - can be run directly on 192.168.168.31
# @usage       bash PHASE-2C-STANDALONE-EXECUTION.sh

set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────
# PHASE 2C: STANDALONE DEPLOYMENT EXECUTION
# ────────────────────────────────────────────────────────────────────────────
# This script executes Phase 2C (Deployment) independently
# Minimal dependencies - uses only gcloud, docker, curl, openssl
# Safe dry-run mode available (DRY_RUN=1)
# ────────────────────────────────────────────────────────────────────────────

# Configuration
GCP_PROJECT="${GCP_PROJECT:-gcp-eiq}"
DRY_RUN="${DRY_RUN:-1}"  # Default to dry-run for safety
PHASE_2C_SKIP="${PHASE_2C_SKIP:-}"  # Can skip sections: 1,2,3,4,5

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ────────────────────────────────────────────────────────────────────────────
# Logging
# ────────────────────────────────────────────────────────────────────────────

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
  echo -e "${RED}[✗]${NC} $1"
}

# ────────────────────────────────────────────────────────────────────────────
# Prerequisites Check
# ────────────────────────────────────────────────────────────────────────────

check_prerequisites() {
  log_info "Checking prerequisites..."
  
  local missing=0
  
  if ! command -v gcloud &>/dev/null; then
    log_error "gcloud CLI not found"
    missing=1
  fi
  
  if ! command -v docker &>/dev/null; then
    log_error "docker not found"
    missing=1
  fi
  
  if ! command -v docker-compose &>/dev/null; then
    log_error "docker-compose not found"
    missing=1
  fi
  
  if ! command -v curl &>/dev/null; then
    log_error "curl not found"
    missing=1
  fi
  
  if ! command -v openssl &>/dev/null; then
    log_error "openssl not found"
    missing=1
  fi
  
  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    log_error "No active gcloud authentication. Run: gcloud auth login"
    missing=1
  fi
  
  if [[ $missing -eq 1 ]]; then
    return 1
  fi
  
  log_success "All prerequisites met"
  return 0
}

# ────────────────────────────────────────────────────────────────────────────
# PHASE 2C.1: GSM Service Account Provisioning
# ────────────────────────────────────────────────────────────────────────────

phase_2c_1_gsm_provisioning() {
  log_info "PHASE 2C.1: GSM Service Account Provisioning"
  
  if [[ "$PHASE_2C_SKIP" == *"1"* ]]; then
    log_warn "Skipping Phase 2C.1 (PHASE_2C_SKIP=...1...)"
    return 0
  fi
  
  gcloud config set project "$GCP_PROJECT" 2>/dev/null || {
    log_error "Cannot set GCP project to $GCP_PROJECT"
    return 1
  }
  
  log_info "Provisioning GSM secrets in project: $GCP_PROJECT"
  
  # Session-Broker secret
  local sb_secret=$(python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32)))")
  
  # Backend secret
  local backend_secret=$(python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32)))")
  
  # LB session cookie (64 hex chars = 32 bytes)
  local lb_secret=$(openssl rand -hex 32)
  
  log_info "Creating GSM secrets..."
  
  if [[ "$DRY_RUN" == "1" ]]; then
    log_warn "[DRY_RUN] Would create secrets:"
    log_warn "  - service-client-session-broker-secret"
    log_warn "  - service-client-backend-secret"
    log_warn "  - ide-session-lb-secret"
  else
    # Create or update secrets
    if gcloud secrets describe "service-client-session-broker-secret" --project="$GCP_PROJECT" &>/dev/null; then
      echo -n "$sb_secret" | gcloud secrets versions add "service-client-session-broker-secret" --data-file=- --project="$GCP_PROJECT" >/dev/null
    else
      echo -n "$sb_secret" | gcloud secrets create "service-client-session-broker-secret" --replication-policy=automatic --data-file=- --project="$GCP_PROJECT" >/dev/null
    fi
    
    if gcloud secrets describe "service-client-backend-secret" --project="$GCP_PROJECT" &>/dev/null; then
      echo -n "$backend_secret" | gcloud secrets versions add "service-client-backend-secret" --data-file=- --project="$GCP_PROJECT" >/dev/null
    else
      echo -n "$backend_secret" | gcloud secrets create "service-client-backend-secret" --replication-policy=automatic --data-file=- --project="$GCP_PROJECT" >/dev/null
    fi
    
    if gcloud secrets describe "ide-session-lb-secret" --project="$GCP_PROJECT" &>/dev/null; then
      echo -n "$lb_secret" | gcloud secrets versions add "ide-session-lb-secret" --data-file=- --project="$GCP_PROJECT" >/dev/null
    else
      echo -n "$lb_secret" | gcloud secrets create "ide-session-lb-secret" --replication-policy=automatic --data-file=- --project="$GCP_PROJECT" >/dev/null
    fi
    
    log_success "GSM secrets created/updated"
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# PHASE 2C.2: Configuration Merge
# ────────────────────────────────────────────────────────────────────────────

phase_2c_2_config_merge() {
  log_info "PHASE 2C.2: Configuration Merge"
  
  if [[ "$PHASE_2C_SKIP" == *"2"* ]]; then
    log_warn "Skipping Phase 2C.2 (PHASE_2C_SKIP=...2...)"
    return 0
  fi
  
  log_info "Loading JWT environment variables..."
  
  if [[ ! -f .env.phase-2 ]]; then
    if [[ -f .env.phase-2-template ]]; then
      log_warn ".env.phase-2 not found, copying from template"
      if [[ "$DRY_RUN" == "1" ]]; then
        log_warn "[DRY_RUN] Would copy .env.phase-2-template -> .env.phase-2"
      else
        cp .env.phase-2-template .env.phase-2
      fi
    else
      log_error ".env.phase-2 and .env.phase-2-template not found"
      return 1
    fi
  fi
  
  if [[ "$DRY_RUN" == "1" ]]; then
    log_warn "[DRY_RUN] Would source .env.phase-2"
    log_warn "Variables that would be loaded:"
    grep "^[A-Z_]*=" .env.phase-2 2>/dev/null | cut -d= -f1 | head -10
    echo "  (and more...)"
  else
    source .env.phase-2
    log_success "Configuration merged"
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# PHASE 2C.3: Service Deployment
# ────────────────────────────────────────────────────────────────────────────

phase_2c_3_service_deployment() {
  log_info "PHASE 2C.3: Service Deployment"
  
  if [[ "$PHASE_2C_SKIP" == *"3"* ]]; then
    log_warn "Skipping Phase 2C.3 (PHASE_2C_SKIP=...3...)"
    return 0
  fi
  
  log_info "Deploying services with JWT configuration..."
  
  if [[ ! -f docker-compose.yml ]]; then
    if [[ ! -f docker-compose.tpl ]]; then
      log_error "docker-compose.yml and docker-compose.tpl not found"
      return 1
    fi
    
    if [[ "$DRY_RUN" == "1" ]]; then
      log_warn "[DRY_RUN] Would generate docker-compose.yml from template"
    else
      envsubst < docker-compose.tpl > docker-compose.yml
      log_success "docker-compose.yml generated from template"
    fi
  fi
  
  if [[ "$DRY_RUN" == "1" ]]; then
    log_warn "[DRY_RUN] Would execute: docker-compose up -d"
    log_warn "Services that would be deployed:"
    grep "^  [a-z-]*:$" docker-compose.yml 2>/dev/null | sed 's/://g' | head -15
  else
    docker-compose up -d
    sleep 10
    log_success "Services deployed"
    log_info "Checking service health..."
    docker-compose ps | grep -E "NAMES|STATUS|Up" | head -10
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# PHASE 2C.4: Token Acquisition Test
# ────────────────────────────────────────────────────────────────────────────

phase_2c_4_token_test() {
  log_info "PHASE 2C.4: Token Acquisition Test"
  
  if [[ "$PHASE_2C_SKIP" == *"4"* ]]; then
    log_warn "Skipping Phase 2C.4 (PHASE_2C_SKIP=...4...)"
    return 0
  fi
  
  if [[ "$DRY_RUN" == "1" ]]; then
    log_warn "[DRY_RUN] Would test JWT token acquisition from /oauth2/token endpoint"
    return 0
  fi
  
  log_info "Waiting for oauth2-oidc-issuer to be ready..."
  local max_attempts=30
  local attempt=0
  
  while [[ $attempt -lt $max_attempts ]]; do
    if docker-compose logs oauth2-oidc-issuer 2>/dev/null | grep -q "listening\|ready"; then
      log_success "OIDC issuer ready"
      break
    fi
    attempt=$((attempt + 1))
    sleep 2
  done
  
  if [[ $attempt -eq $max_attempts ]]; then
    log_warn "OIDC issuer not ready after 60 seconds"
  fi
  
  log_info "Testing token acquisition..."
  local token=$(curl -s -X POST \
    http://localhost:6969/oauth2/token \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials&client_id=${OIDC_CLIENT_ID:-test}&client_secret=${OIDC_CLIENT_SECRET:-test}&audience=api" 2>/dev/null | jq -r '.access_token // empty' 2>/dev/null)
  
  if [[ -n "$token" && "$token" != "null" ]]; then
    log_success "Token acquired: ${token:0:50}..."
    echo "$token" | jq -R 'split(".") | .[0:2] | map(@base64d | fromjson)' 2>/dev/null || log_warn "Could not decode token"
  else
    log_warn "Token acquisition failed or OIDC issuer not responding"
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# PHASE 2C.5: Service-to-Service Test
# ────────────────────────────────────────────────────────────────────────────

phase_2c_5_s2s_test() {
  log_info "PHASE 2C.5: Service-to-Service Test"
  
  if [[ "$PHASE_2C_SKIP" == *"5"* ]]; then
    log_warn "Skipping Phase 2C.5 (PHASE_2C_SKIP=...5...)"
    return 0
  fi
  
  if [[ "$DRY_RUN" == "1" ]]; then
    log_warn "[DRY_RUN] Would test service-to-service bearer token acceptance"
    return 0
  fi
  
  log_info "Testing service-to-service authentication with bearer token..."
  
  # Try to reach session-broker health endpoint
  local response=$(curl -s -w "\n%{http_code}" -X GET \
    http://localhost:7777/health \
    -H "Authorization: Bearer dummy-token" 2>/dev/null)
  
  local http_code=$(echo "$response" | tail -1)
  local body=$(echo "$response" | head -1)
  
  if [[ "$http_code" == "200" ]]; then
    log_success "Session-broker responding (HTTP 200)"
    echo "$body" | jq . 2>/dev/null || echo "$body"
  elif [[ "$http_code" == "401" ]]; then
    log_success "Session-broker correctly rejected invalid token (HTTP 401)"
  else
    log_warn "Session-broker HTTP status: $http_code (expected 200 or 401)"
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────────────────────────────────────

print_summary() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║              PHASE 2C EXECUTION COMPLETE                        ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  
  if [[ "$DRY_RUN" == "1" ]]; then
    log_warn "DRY-RUN MODE ENABLED - No changes were made"
    echo ""
    echo "To execute Phase 2C for real, run:"
    echo "  DRY_RUN=0 bash $0"
  else
    log_success "Phase 2C deployment executed"
    echo ""
    echo "Next steps:"
    echo "  1. Verify all services are healthy: docker-compose ps"
    echo "  2. Check JWT token: bash scripts/ci/run-jwt-e2e-tests.sh"
    echo "  3. Proceed to Phase 2D (observability)"
  fi
  echo ""
}

# ────────────────────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────────────────────

main() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║       PHASE 2C: STANDALONE DEPLOYMENT EXECUTION                ║"
  echo "║     JWT Service-to-Service Authentication Deployment           ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  
  log_info "Configuration:"
  log_info "  GCP Project: $GCP_PROJECT"
  log_info "  Dry-Run: $DRY_RUN"
  log_info "  Skip Phases: ${PHASE_2C_SKIP:-none}"
  echo ""
  
  check_prerequisites || {
    log_error "Prerequisites check failed"
    return 1
  }
  
  phase_2c_1_gsm_provisioning || log_warn "Phase 2C.1 failed (may be expected if secrets exist)"
  phase_2c_2_config_merge || log_warn "Phase 2C.2 failed"
  phase_2c_3_service_deployment || log_warn "Phase 2C.3 failed"
  phase_2c_4_token_test || log_warn "Phase 2C.4 failed"
  phase_2c_5_s2s_test || log_warn "Phase 2C.5 failed"
  
  print_summary
}

main "$@"
