#!/usr/bin/env bash
################################################################################
# Vault Production Deployment & Initialization
# File: scripts/vault-deploy-production.sh
# Purpose: Complete Vault setup from TLS generation through initialization
# Usage: ./scripts/vault-deploy-production.sh
# Owner: Infrastructure Team
# Last Updated: April 17, 2026
################################################################################

set -euo pipefail

# ════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

VAULT_TLS_DIR="${PROJECT_ROOT}/config/vault-tls"
VAULT_CONFIG_DIR="${PROJECT_ROOT}/config/vault"
TLS_CERT_DAYS=365

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# ════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ════════════════════════════════════════════════════════════════════════════

log_step() {
  echo ""
  echo -e "${BLUE}▸ $1${NC}"
}

log_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

log_warn() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

log_error() {
  echo -e "${RED}✗ $1${NC}"
}

# ════════════════════════════════════════════════════════════════════════════
# PHASE 1: TLS CERTIFICATE GENERATION
# ════════════════════════════════════════════════════════════════════════════

setup_tls_certificates() {
  log_step "Phase 1: Generating TLS Certificates"
  
  if [[ -f "${VAULT_TLS_DIR}/cert.pem" ]]; then
    log_warn "TLS certificates already exist at ${VAULT_TLS_DIR}"
    read -p "Regenerate? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log_success "Skipping TLS generation"
      return 0
    fi
  fi
  
  mkdir -p "${VAULT_TLS_DIR}"
  
  # Generate private key
  log_step "  Generating private key..."
  openssl genrsa -out "${VAULT_TLS_DIR}/key.pem" 4096
  
  # Generate self-signed certificate with SANs
  log_step "  Generating self-signed certificate..."
  openssl req -new -x509 -key "${VAULT_TLS_DIR}/key.pem" \
    -out "${VAULT_TLS_DIR}/cert.pem" \
    -days "${TLS_CERT_DAYS}" \
    -subj "/C=US/ST=Local/L=OnPrem/O=Enterprise/CN=vault/subjectAltName=IP:127.0.0.1,IP:192.168.168.31,IP:192.168.168.42,DNS:vault,DNS:vault.local"
  
  # Set restrictive permissions
  chmod 600 "${VAULT_TLS_DIR}/key.pem"
  chmod 644 "${VAULT_TLS_DIR}/cert.pem"
  
  # Verify
  EXPIRES=$(openssl x509 -in "${VAULT_TLS_DIR}/cert.pem" -noout -enddate | cut -d= -f2)
  log_success "TLS certificates generated (expires: ${EXPIRES})"
}

# ════════════════════════════════════════════════════════════════════════════
# PHASE 2: DOCKER COMPOSE VALIDATION
# ════════════════════════════════════════════════════════════════════════════

validate_docker_compose() {
  log_step "Phase 2: Validating Docker Compose Configuration"
  
  if ! docker-compose -f "${PROJECT_ROOT}/docker-compose.yml" config > /dev/null 2>&1; then
    log_error "docker-compose.yml validation failed"
    docker-compose -f "${PROJECT_ROOT}/docker-compose.yml" config
    return 1
  fi
  
  log_success "docker-compose.yml is valid"
}

# ════════════════════════════════════════════════════════════════════════════
# PHASE 3: VAULT DEPLOYMENT
# ════════════════════════════════════════════════════════════════════════════

deploy_vault() {
  log_step "Phase 3: Deploying Vault Container"
  
  cd "${PROJECT_ROOT}"
  
  log_step "  Starting Vault container..."
  docker-compose up -d vault
  
  # Wait for Vault to be ready
  log_step "  Waiting for Vault to be ready..."
  local max_attempts=30
  local attempt=0
  
  while [[ $attempt -lt $max_attempts ]]; do
    if docker-compose exec -T vault vault status >/dev/null 2>&1; then
      log_success "Vault is ready"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 1
  done
  
  log_error "Vault failed to start after 30 seconds"
  docker-compose logs vault | tail -20
  return 1
}

# ════════════════════════════════════════════════════════════════════════════
# PHASE 4: VAULT INITIALIZATION
# ════════════════════════════════════════════════════════════════════════════

initialize_vault() {
  log_step "Phase 4: Initializing Vault"
  
  cd "${PROJECT_ROOT}"
  
  # Check if already initialized
  if docker-compose exec -T vault vault status 2>&1 | grep -q "Initialized.*true"; then
    log_warn "Vault is already initialized"
    return 0
  fi
  
  log_step "  Running vault operator init..."
  docker-compose exec -T vault vault operator init \
    -key-shares=5 \
    -key-threshold=3 \
    -format=json > "vault-unseal-keys.json"
  
  log_success "Vault initialized successfully"
  
  log_warn "Unseal keys saved to: vault-unseal-keys.json"
  log_warn "IMPORTANT: Distribute unseal keys securely (1Password/Bitwarden)"
  log_warn "Save this file securely, then delete: rm vault-unseal-keys.json"
  
  # Show initialization summary
  echo ""
  echo "════════════════════════════════════════════════════════════════════════════"
  echo "  VAULT INITIALIZATION COMPLETE"
  echo "════════════════════════════════════════════════════════════════════════════"
  jq '{keys: .keys | length, root_token: (.root_token | .[0:20] + "..."), recovery_keys: (.recovery_keys | length)}' vault-unseal-keys.json
  echo "════════════════════════════════════════════════════════════════════════════"
}

# ════════════════════════════════════════════════════════════════════════════
# PHASE 5: UNSEALING INSTRUCTIONS
# ════════════════════════════════════════════════════════════════════════════

show_unsealing_instructions() {
  log_step "Phase 5: Unsealing Vault"
  
  echo ""
  echo "════════════════════════════════════════════════════════════════════════════"
  echo "  VAULT UNSEALING INSTRUCTIONS"
  echo "════════════════════════════════════════════════════════════════════════════"
  echo ""
  echo "To unseal Vault, run (from 3 different unseal key holders):"
  echo ""
  echo "  docker-compose exec vault vault operator unseal <unseal-key-1>"
  echo "  docker-compose exec vault vault operator unseal <unseal-key-2>"
  echo "  docker-compose exec vault vault operator unseal <unseal-key-3>"
  echo ""
  echo "Verify unsealing:"
  echo "  docker-compose exec vault vault status"
  echo ""
  echo "Authentication (using root token from vault-unseal-keys.json):"
  echo "  docker-compose exec vault vault login <root-token>"
  echo ""
  echo "════════════════════════════════════════════════════════════════════════════"
}

# ════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ════════════════════════════════════════════════════════════════════════════

main() {
  echo "════════════════════════════════════════════════════════════════════════════"
  echo "  VAULT PRODUCTION DEPLOYMENT SCRIPT"
  echo "════════════════════════════════════════════════════════════════════════════"
  echo ""
  echo "This script will:"
  echo "  1. Generate TLS certificates for Vault"
  echo "  2. Validate docker-compose configuration"
  echo "  3. Deploy Vault container"
  echo "  4. Initialize Vault with Shamir key sharing"
  echo "  5. Show unsealing and authentication instructions"
  echo ""
  echo "════════════════════════════════════════════════════════════════════════════"
  echo ""
  
  # Run all phases
  setup_tls_certificates
  validate_docker_compose
  deploy_vault
  initialize_vault
  show_unsealing_instructions
  
  echo ""
  log_success "Vault production deployment complete!"
  echo ""
}

# Execute
main "$@"
