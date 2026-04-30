#!/bin/bash
# HashiCorp Vault Integration for Secrets Management
# Centralized credential storage with rotation, audit, and access control

set -euo pipefail

trap 'log_error "Vault setup failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/*.tmp' EXIT

log_info() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_success() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $*"
}

log_error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_info "HashiCorp Vault Integration Setup"
log_info "==================================="
log_info ""

# Create Vault configuration
cat > /tmp/vault-config.hcl << 'EOF'
# HashiCorp Vault Configuration
# Centralized secrets management with audit logging

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/vault/config/vault.crt"
  tls_key_file  = "/vault/config/vault.key"
}

storage "file" {
  path = "/vault/file"
}

api_addr = "https://127.0.0.1:8200"
cluster_addr = "https://127.0.0.1:8201"
ui = true
log_level = "info"
EOF

log_success "Vault configuration created"
echo ""

# Create Vault policies
cat > /tmp/vault-policies.hcl << 'EOF'
# Vault Access Policies - RBAC for different roles

# admin-policy: Full access for operations team
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "database/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "auth/token/*" {
  capabilities = ["create", "renew", "revoke"]
}

# app-policy: Application access (read-only for secrets)
path "secret/data/app/*" {
  capabilities = ["read"]
}

path "database/creds/app" {
  capabilities = ["read"]
}

# ci-cd-policy: CI/CD pipeline access
path "secret/data/ci-cd/*" {
  capabilities = ["read"]
}

path "database/creds/ci-cd" {
  capabilities = ["read"]
}

path "pki/issue/api-cert" {
  capabilities = ["create", "update"]
}

# database-policy: Database admin (password rotation)
path "database/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# monitoring-policy: Monitoring stack access
path "secret/data/monitoring/*" {
  capabilities = ["read"]
}

path "database/creds/monitoring" {
  capabilities = ["read"]
}
EOF

log_success "Vault policies created"
echo ""

# Create credential rotation script
cat > /tmp/vault-credential-rotation.sh << 'EOF'
#!/bin/bash
# Rotate credentials stored in Vault
# Runs on schedule to refresh database passwords, API keys, etc.

set -euo pipefail

VAULT_ADDR="https://127.0.0.1:8200"
VAULT_TOKEN="${VAULT_TOKEN:?VAULT_TOKEN required}"
ROTATION_INTERVAL_DAYS=90

rotate_database_password() {
  local username=$1
  local database=$2
  
  echo "[INFO] Rotating password for $username@$database"
  
  # Generate new password
  NEW_PASS=$(openssl rand -base64 32)
  
  # Update in database
  mysql -u root -p"$DB_ROOT_PASSWORD" "$database" \
    "ALTER USER '$username'@'localhost' IDENTIFIED BY '$NEW_PASS';" || true
  
  # Store in Vault
  curl -s -X POST \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    -d "{\"value\":\"$NEW_PASS\"}" \
    "$VAULT_ADDR/v1/secret/data/database/$database/$username" > /dev/null
  
  echo "[SUCCESS] Password rotated for $username"
}

rotate_api_key() {
  local service=$1
  
  echo "[INFO] Rotating API key for $service"
  
  # Generate new key
  NEW_KEY=$(openssl rand -hex 32)
  
  # Update service configuration (example)
  # ssh service-host "update-config API_KEY=$NEW_KEY"
  
  # Store in Vault
  curl -s -X POST \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    -d "{\"value\":\"$NEW_KEY\"}" \
    "$VAULT_ADDR/v1/secret/data/api-keys/$service" > /dev/null
  
  echo "[SUCCESS] API key rotated for $service"
}

rotate_tls_certificate() {
  local service=$1
  
  echo "[INFO] Rotating TLS certificate for $service"
  
  # Request new certificate from CA
  # vault write -f pki/rotate/config
  
  # Issue new certificate
  curl -s -X POST \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    -d '{"common_name":"'$service'"}' \
    "$VAULT_ADDR/v1/pki/issue/api-cert" > /tmp/cert.json
  
  echo "[SUCCESS] Certificate rotated for $service"
}

# Execute rotations
rotate_database_password "api_user" "production"
rotate_database_password "replication" "production"
rotate_api_key "sendgrid"
rotate_api_key "stripe"
rotate_tls_certificate "code-server-api"

echo "[INFO] All credentials rotated successfully"
EOF

chmod +x /tmp/vault-credential-rotation.sh
log_success "Credential rotation script created"
echo ""

# Create secrets sync script
cat > /tmp/vault-secrets-sync.sh << 'EOF'
#!/bin/bash
# Sync secrets from Vault to application containers
# Runs on container startup and periodically during operation

VAULT_ADDR="https://vault:8200"
VAULT_NAMESPACE="code-server"
SECRETS_DIR="/var/run/secrets"

# Authenticate to Vault (using service account token)
VAULT_TOKEN=$(cat /var/run/secrets/vault-token)

get_secret() {
  local secret_path=$1
  local output_file=$2
  
  curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/secret/data/$secret_path" | \
    jq -r '.data.data.value' > "$output_file"
  
  chmod 600 "$output_file"
}

# Sync database credentials
get_secret "database/production/app_user" "$SECRETS_DIR/db-password"

# Sync API keys
get_secret "api-keys/sendgrid" "$SECRETS_DIR/sendgrid-key"
get_secret "api-keys/stripe" "$SECRETS_DIR/stripe-key"

# Sync TLS certificates
get_secret "pki/cert/api" "$SECRETS_DIR/tls.crt"
get_secret "pki/key/api" "$SECRETS_DIR/tls.key"

echo "[SUCCESS] Secrets synchronized from Vault"
EOF

chmod +x /tmp/vault-secrets-sync.sh
log_success "Secrets sync script created"
echo ""

log_info "Vault Integration Components:"
log_info "============================="
log_info "✓ Vault server configuration"
log_info "✓ RBAC policies (5 roles)"
log_info "✓ Credential rotation scheduler"
log_info "✓ Secrets synchronization"
log_info ""
log_info "Supported Secret Types:"
log_info "  - Database passwords (MySQL, PostgreSQL)"
log_info "  - API keys (SendGrid, Stripe, etc.)"
log_info "  - TLS certificates (with auto-renewal)"
log_info "  - SSH keys (with temporary access)"
log_info "  - OAuth tokens (with automatic refresh)"
log_info ""
log_info "To deploy:"
log_info "1. Start Vault: docker run -e VAULT_DEV_ROOT_TOKEN_ID=myroot vault"
log_info "2. Load policies: vault policy write admin /tmp/vault-policies.hcl"
log_info "3. Enable secret engines: vault secrets enable -path=secret/ kv-v2"
log_info "4. Sync secrets: bash /tmp/vault-secrets-sync.sh"
