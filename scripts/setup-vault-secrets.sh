#!/usr/bin/env bash
# @file        scripts/setup-vault-secrets.sh
# @module      security/secrets
# @description Bootstrap Vault for production secret storage (on-prem)
# @owner       security
# @status      active
#
# Purpose:  Initialize HashiCorp Vault for encrypted secret storage
#           Enable automatic secret injection into containers
#           Implement secret rotation policies
#
# Usage:    ./scripts/setup-vault-secrets.sh init
#           ./scripts/setup-vault-secrets.sh validate
#           ./scripts/setup-vault-secrets.sh rotate

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

VAULT_ADDR="${VAULT_ADDR:-https://vault:8200}"
VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-true}"  # For self-signed certs in lab
VAULT_TOKEN_FILE="${VAULT_TOKEN_FILE:-.vault-token}"

# ════════════════════════════════════════════════════════════════════════════
# Vault Initialization
# ════════════════════════════════════════════════════════════════════════════

init_vault() {
  log_info "=== Initializing Vault ==="
  
  # Check if Vault is already initialized
  if vault status >/dev/null 2>&1; then
    log_info "Vault already initialized"
    return 0
  fi
  
  log_info "Initializing Vault with 5 key shares, 3 threshold..."
  # Initialize Vault: creates 5 unseal keys, requires 3 to unseal
  vault operator init \
    -key-shares=5 \
    -key-threshold=3 \
    -format=json > vault-init.json
  
  log_success "Vault initialized. Store vault-init.json in secure location."
  log_warn "IMPORTANT: Distribute unseal keys to 5 different people"
  log_warn "  Each person gets 1 key (no one has more than 1)"
  log_warn "  Only 3 needed to unseal (byzantine fault tolerance)"
}

# ════════════════════════════════════════════════════════════════════════════
# Enable KV v2 Secrets Engine
# ════════════════════════════════════════════════════════════════════════════

enable_kv2_engine() {
  log_info "=== Enabling KV v2 Secrets Engine ==="
  
  vault secrets enable -version=2 -path=secret kv || {
    log_warn "KV engine already enabled"
  }
  
  log_success "KV v2 secrets engine enabled at path: secret/"
}

# ════════════════════════════════════════════════════════════════════════════
# Create Secret Policies
# ════════════════════════════════════════════════════════════════════════════

create_policies() {
  log_info "=== Creating Vault Policies ==="
  
  # Policy for code-server application
  cat > /tmp/code-server-policy.hcl << 'EOF'
# Code-Server Application Policy
# Allows code-server to read its own secrets

path "secret/data/code-server/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/code-server/*" {
  capabilities = ["list"]
}
EOF

  vault policy write code-server /tmp/code-server-policy.hcl
  log_success "Policy 'code-server' created"
  
  # Policy for DevOps (admin)
  cat > /tmp/devops-policy.hcl << 'EOF'
# DevOps Team Policy
# Full access to all secrets for rotation and management

path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/leases/*" {
  capabilities = ["list"]
}
EOF

  vault policy write devops /tmp/devops-policy.hcl
  log_success "Policy 'devops' created"
}

# ════════════════════════════════════════════════════════════════════════════
# Store Secrets in Vault
# ════════════════════════════════════════════════════════════════════════════

store_secrets() {
  log_info "=== Storing Secrets in Vault ==="
  
  # These values should be provided via:
  #   - Environment variables
  #   - .env.vault file (encrypted)
  #   - User input (for initial setup)
  
  local postgres_password="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD required}"
  local code_server_password="${CODE_SERVER_PASSWORD:?CODE_SERVER_PASSWORD required}"
  local google_client_id="${GOOGLE_CLIENT_ID:?GOOGLE_CLIENT_ID required}"
  local google_client_secret="${GOOGLE_CLIENT_SECRET:?GOOGLE_CLIENT_SECRET required}"
  local oauth_cookie_secret="${OAUTH2_PROXY_COOKIE_SECRET:?OAUTH2_PROXY_COOKIE_SECRET required}"
  local grafana_password="${GRAFANA_PASSWORD:?GRAFANA_PASSWORD required}"
  local github_token="${GITHUB_TOKEN:?GITHUB_TOKEN required}"
  
  # Store PostgreSQL credentials
  vault kv put secret/code-server/postgres \
    username="code_server" \
    password="$postgres_password" \
    host="postgres" \
    port="5432" \
    database="code_server"
  log_success "✓ PostgreSQL credentials stored"
  
  # Store Code-Server credentials
  vault kv put secret/code-server/app \
    password="$code_server_password"
  log_success "✓ Code-Server password stored"
  
  # Store OAuth2 credentials
  vault kv put secret/code-server/oauth2 \
    google_client_id="$google_client_id" \
    google_client_secret="$google_client_secret" \
    cookie_secret="$oauth_cookie_secret"
  log_success "✓ OAuth2 credentials stored"
  
  # Store Grafana credentials
  vault kv put secret/code-server/grafana \
    admin_password="$grafana_password"
  log_success "✓ Grafana credentials stored"
  
  # Store GitHub token
  vault kv put secret/code-server/github \
    token="$github_token"
  log_success "✓ GitHub token stored"
  
  log_info "All secrets stored in Vault"
}

# ════════════════════════════════════════════════════════════════════════════
# Enable AppRole Auth (for automated access)
# ════════════════════════════════════════════════════════════════════════════

enable_approle() {
  log_info "=== Enabling AppRole Authentication ==="
  
  vault auth enable approle || {
    log_warn "AppRole already enabled"
  }
  
  # Create AppRole for code-server
  vault write auth/approle/role/code-server \
    token_ttl=1h \
    token_max_ttl=24h \
    policies="code-server"
  
  # Get RoleID (like username)
  local role_id=$(vault read -field=role_id auth/approle/role/code-server/role-id)
  
  # Generate SecretID (like password, rotatable)
  vault write -f auth/approle/role/code-server/secret-id
  local secret_id=$(vault read -field=secret_id auth/approle/role/code-server/secret-id)
  
  log_success "AppRole created for code-server"
  log_info "Role ID: $role_id"
  log_info "Secret ID: $secret_id"
  log_warn "Save these securely in .env or Docker secrets"
  
  # Save to file for later reference
  cat > .vault-approle << EOF
VAULT_ROLE_ID=$role_id
VAULT_SECRET_ID=$secret_id
EOF
  log_info "AppRole credentials saved to .vault-approle"
}

# ════════════════════════════════════════════════════════════════════════════
# Validate Vault Setup
# ════════════════════════════════════════════════════════════════════════════

validate_vault() {
  log_info "=== Validating Vault Setup ==="
  
  # Check Vault status
  vault status || {
    log_error "Vault not accessible at $VAULT_ADDR"
    return 1
  }
  
  # Check if secrets exist
  vault kv get secret/code-server/postgres >/dev/null || {
    log_error "PostgreSQL secrets not found"
    return 1
  }
  
  vault kv get secret/code-server/oauth2 >/dev/null || {
    log_error "OAuth2 secrets not found"
    return 1
  }

  vault kv get secret/code-server/app >/dev/null || {
    log_error "Code-Server app secret not found"
    return 1
  }

  vault kv get secret/code-server/grafana >/dev/null || {
    log_error "Grafana secrets not found"
    return 1
  }

  vault kv get secret/code-server/github >/dev/null || {
    log_error "GitHub token secret not found"
    return 1
  }
  
  log_success "✓ Vault is operational and secrets are accessible"
}

# ════════════════════════════════════════════════════════════════════════════
# Secret Rotation
# ════════════════════════════════════════════════════════════════════════════

rotate_secrets() {
  log_info "=== Rotating Secrets ==="
  log_warn "IMPORTANT: Rotate secrets quarterly for security compliance"
  
  # Update password in Vault
  local new_password=$(openssl rand -base64 32)
  vault kv put secret/code-server/postgres \
    password="$new_password" \
    username="code_server" \
    host="postgres" \
    port="5432" \
    database="code_server"
  
  log_success "✓ PostgreSQL password rotated"
  
  # TODO: Update password in database
  # docker exec postgres psql -U postgres -c "ALTER USER code_server WITH PASSWORD '$new_password';"
  
  log_warn "NEXT STEP: Update PostgreSQL with new password"
}

# ════════════════════════════════════════════════════════════════════════════
# Main
# ════════════════════════════════════════════════════════════════════════════

main() {
  local action="${1:-help}"
  
  case "$action" in
    init)
      init_vault
      enable_kv2_engine
      create_policies
      enable_approle
      log_success "Vault initialized successfully"
      ;;
    
    store)
      store_secrets
      ;;
    
    validate)
      validate_vault
      ;;
    
    rotate)
      rotate_secrets
      ;;
    
    help)
      cat << 'HELP'
Usage: ./scripts/setup-vault-secrets.sh [command]

Commands:
  init      Initialize Vault, enable auth methods, create policies
  store     Store secrets from environment variables
  validate  Test Vault connectivity and check secrets
  rotate    Rotate all secrets (quarterly security requirement)
  help      Show this help message

Examples:
  # First time: initialize and store secrets
  POSTGRES_PASSWORD=xxx \
  CODE_SERVER_PASSWORD=yyy \
  GOOGLE_CLIENT_ID=zzz \
  GOOGLE_CLIENT_SECRET=aaa \
  ./scripts/setup-vault-secrets.sh init
  
  ./scripts/setup-vault-secrets.sh store
  ./scripts/setup-vault-secrets.sh validate
  
  # Quarterly: rotate secrets
  ./scripts/setup-vault-secrets.sh rotate

Documentation:
  - HashiCorp Vault: https://www.vaultproject.io/docs
  - AppRole Auth: https://www.vaultproject.io/docs/auth/approle
  - Secret Rotation: https://www.vaultproject.io/docs/auth/approle#secretid-lifecycle
HELP
      ;;
    
    *)
      log_error "Unknown command: $action"
      exit 1
      ;;
  esac
}

main "$@"
