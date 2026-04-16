#!/bin/bash
################################################################################
# Vault Production Setup Script — Issue #413
# File: scripts/vault-production-setup.sh
# Purpose: Automate transition from Vault dev mode to production
# 
# Prerequisites:
#   - Docker and docker-compose installed
#   - PostgreSQL 15+ running (docker-compose exec postgres psql works)
#   - TLS certificates in config/vault/tls/ (self-signed or managed)
#
# Usage:
#   bash scripts/vault-production-setup.sh [--init-only|--unseal-only|--full]
#
# Stages:
#   1. Verify prerequisites (Docker, PostgreSQL, TLS)
#   2. Create PostgreSQL schema for Vault
#   3. Update docker-compose with Vault production service
#   4. Start Vault in production mode
#   5. Initialize Vault (create unseal keys, root token)
#   6. Store initialization data securely
#   7. Enable auth methods and secret engines
#
################################################################################

set -euo pipefail

# ════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

VAULT_ADDR="${VAULT_ADDR:-https://vault.kushnir.cloud:8200}"
VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-true}"
VAULT_CONFIG_DIR="${REPO_ROOT}/config/vault"
VAULT_TLS_DIR="${VAULT_CONFIG_DIR}/tls"
VAULT_LOG_DIR="${REPO_ROOT}/vault/logs"

POSTGRES_HOST="postgres"
POSTGRES_PORT="5432"
POSTGRES_USER="postgres"
POSTGRES_DB="vault"

UNSEAL_KEYS_FILE="/tmp/vault-init-keys.json"
UNSEAL_KEYS_ENCRYPTED="${REPO_ROOT}/.vault-init-keys.enc"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ════════════════════════════════════════════════════════════════════════════
# LOGGING FUNCTIONS
# ════════════════════════════════════════════════════════════════════════════

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

# ════════════════════════════════════════════════════════════════════════════
# VERIFY PREREQUISITES
# ════════════════════════════════════════════════════════════════════════════

verify_prerequisites() {
  log_info "Verifying prerequisites..."
  
  # Check Docker
  if ! command -v docker &> /dev/null; then
    log_error "Docker not found. Please install Docker."
    exit 1
  fi
  log_success "Docker installed"
  
  # Check docker-compose
  if ! command -v docker-compose &> /dev/null; then
    log_error "docker-compose not found. Please install Docker Compose."
    exit 1
  fi
  log_success "docker-compose installed"
  
  # Check PostgreSQL connectivity
  log_info "Checking PostgreSQL connectivity..."
  if ! docker-compose -f "${REPO_ROOT}/docker-compose.yml" exec -T postgres pg_isready > /dev/null 2>&1; then
    log_error "PostgreSQL not accessible via docker-compose"
    exit 1
  fi
  log_success "PostgreSQL accessible"
  
  # Check TLS certificates exist
  if [[ ! -f "${VAULT_TLS_DIR}/vault.crt" ]] || [[ ! -f "${VAULT_TLS_DIR}/vault.key" ]]; then
    log_warn "TLS certificates not found in ${VAULT_TLS_DIR}"
    log_info "Generating self-signed certificates..."
    generate_self_signed_certs
  fi
  log_success "TLS certificates present"
}

# ════════════════════════════════════════════════════════════════════════════
# GENERATE SELF-SIGNED TLS CERTIFICATES
# ════════════════════════════════════════════════════════════════════════════

generate_self_signed_certs() {
  mkdir -p "${VAULT_TLS_DIR}"
  
  log_info "Generating self-signed certificate for vault.kushnir.cloud..."
  
  openssl req -x509 -newkey rsa:4096 -nodes \
    -keyout "${VAULT_TLS_DIR}/vault.key" \
    -out "${VAULT_TLS_DIR}/vault.crt" \
    -days 730 \
    -subj "/CN=vault.kushnir.cloud/O=kushnir.cloud/ST=Virtual/C=US"
  
  # Set proper permissions
  chmod 600 "${VAULT_TLS_DIR}/vault.key"
  chmod 644 "${VAULT_TLS_DIR}/vault.crt"
  
  log_success "Self-signed certificates generated"
  log_warn "These certificates are self-signed. In production, use managed certificates."
  log_info "Certificate expiry: $(openssl x509 -in "${VAULT_TLS_DIR}/vault.crt" -noout -enddate)"
}

# ════════════════════════════════════════════════════════════════════════════
# CREATE POSTGRESQL SCHEMA FOR VAULT
# ════════════════════════════════════════════════════════════════════════════

setup_postgres_backend() {
  log_info "Setting up PostgreSQL backend for Vault..."
  
  # Create database
  docker-compose -f "${REPO_ROOT}/docker-compose.yml" exec -T postgres psql -U "${POSTGRES_USER}" -tc "SELECT 1 FROM pg_database WHERE datname = '${POSTGRES_DB}';" | grep -q 1 || \
  docker-compose -f "${REPO_ROOT}/docker-compose.yml" exec -T postgres createdb -U "${POSTGRES_USER}" "${POSTGRES_DB}"
  
  log_success "PostgreSQL database '${POSTGRES_DB}' ready"
  
  # Vault will auto-create tables on startup:
  # - vault_kv (key-value storage)
  # - vault_locks (HA distributed locking)
}

# ════════════════════════════════════════════════════════════════════════════
# START VAULT IN PRODUCTION MODE
# ════════════════════════════════════════════════════════════════════════════

start_vault_production() {
  log_info "Starting Vault in production mode..."
  
  cd "${REPO_ROOT}"
  
  # Ensure vault directories exist and have correct permissions
  mkdir -p "${VAULT_CONFIG_DIR}" "${VAULT_LOG_DIR}"
  
  # Start Vault service
  docker-compose up -d vault
  
  log_info "Waiting for Vault to start (15 seconds)..."
  sleep 15
  
  # Check if Vault started
  if ! docker-compose ps vault 2>&1 | grep -q "running\|Up"; then
    log_error "Vault failed to start. Check logs:"
    docker-compose logs vault
    exit 1
  fi
  
  log_success "Vault started in production mode"
}

# ════════════════════════════════════════════════════════════════════════════
# INITIALIZE VAULT
# ════════════════════════════════════════════════════════════════════════════

init_vault() {
  log_info "Initializing Vault..."
  log_warn "This will create unseal keys and root token. Store safely!"
  
  # Initialize Vault (5 keys, 3 threshold)
  export VAULT_ADDR="${VAULT_ADDR}"
  export VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY}"
  
  vault operator init -key-shares=5 -key-threshold=3 \
    -format=json > "${UNSEAL_KEYS_FILE}"
  
  log_success "Vault initialized"
  
  # Extract and display unseal keys (first 3 needed for unsealing)
  echo ""
  log_warn "════════════════════════════════════════════════════════════════════"
  log_warn "IMPORTANT: Save these unseal keys in a secure location!"
  log_warn "════════════════════════════════════════════════════════════════════"
  echo ""
  
  echo "Unseal Keys (3 of 5 required):"
  jq -r '.unseal_keys_b64[]' "${UNSEAL_KEYS_FILE}" | head -3 | while IFS= read -r key; do
    echo "  - ${key:0:20}...${key: -20}"
  done
  
  echo ""
  log_warn "Root Token:"
  jq -r '.root_token' "${UNSEAL_KEYS_FILE}" | while IFS= read -r token; do
    echo "  ${token:0:25}...${token: -25} (TRUNCATED)"
  done
  
  echo ""
  log_info "Full initialization keys saved to: ${UNSEAL_KEYS_FILE}"
  log_warn "Secure this file immediately (encrypt or store in vault)"
}

# ════════════════════════════════════════════════════════════════════════════
# UNSEAL VAULT
# ════════════════════════════════════════════════════════════════════════════

unseal_vault() {
  log_info "Unsealing Vault..."
  
  export VAULT_ADDR="${VAULT_ADDR}"
  export VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY}"
  
  # Check if initialization file exists
  if [[ ! -f "${UNSEAL_KEYS_FILE}" ]]; then
    log_error "Initialization keys not found at ${UNSEAL_KEYS_FILE}"
    log_info "Run 'init_vault' first or provide unseal keys via environment"
    return 1
  fi
  
  # Unseal with first 3 keys
  jq -r '.unseal_keys_b64[]' "${UNSEAL_KEYS_FILE}" | head -3 | while IFS= read -r key; do
    log_info "Unsealing with key: ${key:0:20}..."
    vault operator unseal "${key}" > /dev/null 2>&1
  done
  
  # Verify unseal status
  if vault status 2>/dev/null | grep -q "Sealed.*false"; then
    log_success "Vault unsealed successfully"
  else
    log_error "Vault still sealed. Check status:"
    vault status
    return 1
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# ENABLE AUTHENTICATION & SECRET ENGINES
# ════════════════════════════════════════════════════════════════════════════

setup_vault_auth() {
  log_info "Setting up Vault authentication and secret engines..."
  
  export VAULT_ADDR="${VAULT_ADDR}"
  export VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY}"
  
  # Get root token from init file
  if [[ ! -f "${UNSEAL_KEYS_FILE}" ]]; then
    log_error "Cannot find initialization file"
    return 1
  fi
  
  export VAULT_TOKEN=$(jq -r '.root_token' "${UNSEAL_KEYS_FILE}")
  
  # Enable AppRole auth
  log_info "Enabling AppRole authentication..."
  vault auth enable approle || log_warn "AppRole already enabled"
  
  # Create policy for code-server
  log_info "Creating code-server policy..."
  vault policy write code-server - <<'POLICY'
path "secret/data/code-server/*" {
  capabilities = ["read", "list"]
}
path "database/static-creds/code-server" {
  capabilities = ["read"]
}
path "auth/approle/login" {
  capabilities = ["create", "read"]
}
POLICY
  
  # Enable KV v2 secrets engine
  log_info "Enabling KV v2 secrets engine..."
  vault secrets enable -version=2 kv || log_warn "KV v2 already enabled"
  
  # Enable database secrets engine
  log_info "Enabling database secrets engine..."
  vault secrets enable database || log_warn "Database engine already enabled"
  
  log_success "Vault authentication and secret engines configured"
}

# ════════════════════════════════════════════════════════════════════════════
# SETUP DATABASE DYNAMIC CREDENTIALS (Issue #356)
# ════════════════════════════════════════════════════════════════════════════

setup_database_credentials() {
  log_info "Configuring PostgreSQL dynamic credentials..."
  
  export VAULT_ADDR="${VAULT_ADDR}"
  export VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY}"
  export VAULT_TOKEN=$(jq -r '.root_token' "${UNSEAL_KEYS_FILE}")
  
  # Generate password for vault-admin user
  VAULT_ADMIN_PASS=$(openssl rand -base64 32)
  
  # Configure PostgreSQL connection
  vault write database/config/postgresql \
    plugin_name=postgresql-database-plugin \
    allowed_roles="code-server,readonly" \
    connection_url="postgresql://{{username}}:{{password}}@postgres:5432/code_server?sslmode=disable" \
    username="vault-admin" \
    password="${VAULT_ADMIN_PASS}" || log_warn "PostgreSQL config might already exist"
  
  # Create code-server role
  vault write database/roles/code-server \
    db_name=postgresql \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
      GRANT USAGE ON SCHEMA public TO \"{{name}}\"; \
      GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h" || log_warn "code-server role might already exist"
  
  log_success "PostgreSQL dynamic credentials configured"
}

# ════════════════════════════════════════════════════════════════════════════
# VERIFY VAULT STATUS
# ════════════════════════════════════════════════════════════════════════════

verify_vault_status() {
  log_info "Verifying Vault production setup..."
  
  export VAULT_ADDR="${VAULT_ADDR}"
  export VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY}"
  
  # Check sealed status
  STATUS=$(vault status -format=json 2>/dev/null)
  
  echo ""
  echo "Vault Status:"
  echo "  Sealed:     $(echo "$STATUS" | jq -r '.sealed')"
  echo "  Version:    $(echo "$STATUS" | jq -r '.version')"
  echo "  Storage:    $(echo "$STATUS" | jq -r '.storage_type')"
  echo "  HA Enabled: $(echo "$STATUS" | jq -r '.ha_enabled')"
  echo ""
  
  # Check audit logs
  if [[ -f "${VAULT_LOG_DIR}/audit.log" ]]; then
    log_success "Audit logging active ($(wc -l < "${VAULT_LOG_DIR}/audit.log") entries)"
  else
    log_warn "Audit log not found"
  fi
  
  # Check metrics export
  log_info "Checking Prometheus metrics export..."
  if vault read sys/metrics -format=json 2>/dev/null | jq . > /dev/null; then
    log_success "Prometheus metrics accessible"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ════════════════════════════════════════════════════════════════════════════

main() {
  MODE="${1:-full}"
  
  log_info "════════════════════════════════════════════════════════════════════════════"
  log_info "Vault Production Setup (Issue #413)"
  log_info "Mode: ${MODE}"
  log_info "════════════════════════════════════════════════════════════════════════════"
  echo ""
  
  case "${MODE}" in
    init-only)
      verify_prerequisites
      setup_postgres_backend
      start_vault_production
      init_vault
      ;;
    unseal-only)
      unseal_vault
      setup_vault_auth
      setup_database_credentials
      ;;
    full)
      verify_prerequisites
      setup_postgres_backend
      start_vault_production
      init_vault
      unseal_vault
      setup_vault_auth
      setup_database_credentials
      verify_vault_status
      ;;
    *)
      log_error "Unknown mode: ${MODE}"
      log_info "Usage: $0 [init-only|unseal-only|full]"
      exit 1
      ;;
  esac
  
  echo ""
  log_success "════════════════════════════════════════════════════════════════════════════"
  log_success "Vault production setup complete!"
  log_success "════════════════════════════════════════════════════════════════════════════"
}

main "$@"
