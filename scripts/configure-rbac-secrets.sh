#!/bin/bash

################################################################################
# Phase 6.2: RBAC & Secrets Management with Vault
# Purpose: Implement Role-Based Access Control and secrets rotation
# Usage: ./scripts/configure-rbac-secrets.sh [--apply]
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup: Removing temporary RBAC files..."; rm -f /tmp/rbac-*.tmp /tmp/role-*.tmp 2>/dev/null || true' EXIT

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true

SECURITY_DIR="${PROJECT_ROOT}/security"
VAULT_ADDR="http://code-server-vault:8200"

################################################################################
# 1. VAULT RBAC CONFIGURATION
################################################################################

create_vault_rbac() {
    log_info "Creating Vault RBAC configuration..."

    mkdir -p "$SECURITY_DIR"

    cat > "${SECURITY_DIR}/vault-rbac.hcl" << 'VAULT_RBAC'
# Vault RBAC Policies

# Admin policy - full access
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF

# Control Plane policy - limited access
path "secret/data/control-plane/*" {
  capabilities = ["read", "list"]
}

path "secret/data/database/*" {
  capabilities = ["read"]
}

path "secret/data/redis/*" {
  capabilities = ["read"]
}

path "secret/data/api-keys/*" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Agent Runtime policy
path "secret/data/agent-runtime/*" {
  capabilities = ["read", "list"]
}

path "secret/data/model-store/*" {
  capabilities = ["read"]
}

# Database admin policy
path "database/config/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "database/roles/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "database/creds/*" {
  capabilities = ["read"]
}

# Audit policy - read-only access to logs
path "sys/audit" {
  capabilities = ["read"]
}

path "sys/audit/*" {
  capabilities = ["read"]
}

# Monitoring policy
path "secret/data/monitoring/*" {
  capabilities = ["read"]
}

path "secret/data/alerting/*" {
  capabilities = ["read"]
}
VAULT_RBAC

    log_success "Vault RBAC configuration created"
}

################################################################################
# 2. SECRETS MANAGEMENT CONFIGURATION
################################################################################

create_secrets_config() {
    log_info "Creating secrets management configuration..."

    cat > "${SECURITY_DIR}/secrets.yaml" << 'SECRETS_CONF'
---
# Secrets Management Configuration

secrets:
  vault:
    enabled: true
    address: "http://code-server-vault:8200"
    token_path: "/run/secrets/vault_token"
    
    # Secret engines
    engines:
      - type: kv
        path: secret/
        description: "Key-value secrets storage"
      
      - type: database
        path: database/
        description: "Database dynamic credentials"
      
      - type: transit
        path: transit/
        description: "Encryption as a service"
      
      - type: ssh
        path: ssh/
        description: "SSH certificate generation"
    
    # Secret rotation policies
    rotation:
      tls_certificates:
        enabled: true
        interval: 2592000    # 30 days
        before_expiry: 604800  # Renew 7 days before expiry
      
      api_keys:
        enabled: true
        interval: 7776000    # 90 days
      
      database_passwords:
        enabled: true
        interval: 2592000    # 30 days
      
      encryption_keys:
        enabled: true
        interval: 31536000   # 1 year

  # Secrets storage hierarchy
  storage:
    database:
      postgres:
        path: "secret/data/database/postgres"
        fields: [username, password, connection_string]
      
      redis:
        path: "secret/data/cache/redis"
        fields: [password, auth_token]
    
    api_keys:
      github:
        path: "secret/data/api-keys/github"
        fields: [token, webhook_secret]
      
      vault:
        path: "secret/data/api-keys/vault"
        fields: [token, role_id, secret_id]
      
      docker_registry:
        path: "secret/data/api-keys/docker"
        fields: [username, password, registry_url]
    
    encryption:
      master_keys:
        path: "secret/data/encryption/master-keys"
        fields: [key_v1, key_v2, key_active]
      
      data_encryption:
        path: "secret/data/encryption/data-keys"
        fields: [user_data_key, logs_key, metrics_key]
    
    oauth:
      google:
        path: "secret/data/oauth/google"
        fields: [client_id, client_secret, redirect_uri]
      
      github:
        path: "secret/data/oauth/github"
        fields: [client_id, client_secret, webhook_url]

  # Access policies per service
  access:
    control_plane:
      policy: "control-plane-policy"
      read: ["secret/data/database/*", "secret/data/api-keys/*"]
      write: []
      admin: []
    
    agent_runtime:
      policy: "agent-runtime-policy"
      read: ["secret/data/agent-runtime/*", "secret/data/model-store/*"]
      write: []
      admin: []
    
    activity_feed:
      policy: "activity-feed-policy"
      read: ["secret/data/database/*", "secret/data/cache/redis"]
      write: []
      admin: []
    
    vault:
      policy: "vault-admin-policy"
      read: ["*"]
      write: ["*"]
      admin: ["*"]

  # Secret versioning
  versioning:
    enabled: true
    max_versions: 10
    delete_old_versions: true
    retention_days: 90
SECRETS_CONF

    log_success "Secrets management configuration created"
}

################################################################################
# 3. DOCKER SECRETS INTEGRATION
################################################################################

create_docker_secrets() {
    log_info "Creating Docker secrets integration..."

    cat > "${SECURITY_DIR}/init-docker-secrets.sh" << 'DOCKER_SECRETS'
#!/bin/bash

# Initialize Docker Secrets for use with services

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"

# Create secrets from Vault
create_secret() {
    local secret_name="$1"
    local secret_path="$2"
    
    # Retrieve from Vault
    value=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/$secret_path" | jq -r '.data.data.value')
    
    # Create Docker secret
    if echo "$value" | docker secret create "$secret_name" - 2>/dev/null; then
        echo "Created secret: $secret_name"
    else
        docker secret rm "$secret_name" 2>/dev/null || true
        echo "$value" | docker secret create "$secret_name" -
        echo "Updated secret: $secret_name"
    fi
}

# Initialize all secrets
echo "Initializing Docker secrets from Vault..."

# Database secrets
create_secret "db_postgres_password" "secret/data/database/postgres/password"
create_secret "db_postgres_connection" "secret/data/database/postgres/connection_string"

# Cache secrets
create_secret "redis_password" "secret/data/cache/redis/password"
create_secret "redis_auth_token" "secret/data/cache/redis/auth_token"

# API keys
create_secret "vault_token" "secret/data/api-keys/vault/token"
create_secret "github_token" "secret/data/api-keys/github/token"
create_secret "docker_registry_password" "secret/data/api-keys/docker/password"

# Encryption keys
create_secret "encryption_master_key" "secret/data/encryption/master-keys/key_active"

# TLS certificates
create_secret "tls_cert" "secret/data/tls/certificate"
create_secret "tls_key" "secret/data/tls/private_key"
create_secret "tls_ca" "secret/data/tls/ca_cert"

echo "Docker secrets initialization complete"
DOCKER_SECRETS

    chmod +x "${SECURITY_DIR}/init-docker-secrets.sh"
    log_success "Docker secrets integration created"
}

################################################################################
# 4. RBAC ROLES AND POLICIES
################################################################################

create_rbac_roles() {
    log_info "Creating RBAC roles and policies..."

    cat > "${SECURITY_DIR}/rbac-roles.yaml" << 'RBAC_ROLES'
---
# RBAC Roles and Policies

roles:
  # Admin role - full access to all resources
  admin:
    description: "Full administrator access"
    permissions:
      - resource: "*"
        verbs: ["*"]
      - resource: "secrets"
        verbs: ["get", "create", "update", "delete", "list"]
      - resource: "services"
        verbs: ["get", "create", "update", "delete", "list", "scale"]
      - resource: "config"
        verbs: ["get", "create", "update", "delete", "list"]
      - resource: "audit"
        verbs: ["get", "list"]

  # Operator role - manage services and view logs
  operator:
    description: "Service operations and monitoring"
    permissions:
      - resource: "services"
        verbs: ["get", "list", "update", "scale"]
      - resource: "logs"
        verbs: ["get", "list"]
      - resource: "metrics"
        verbs: ["get", "list"]
      - resource: "events"
        verbs: ["get", "list"]
      - resource: "config"
        verbs: ["get", "list"]

  # Developer role - deploy and view logs
  developer:
    description: "Application development and deployment"
    permissions:
      - resource: "services"
        verbs: ["get", "list", "create", "update"]
      - resource: "logs"
        verbs: ["get", "list"]
      - resource: "metrics"
        verbs: ["get", "list"]
      - resource: "secrets"
        verbs: ["get"]
      - resource: "api_keys"
        verbs: ["get"]

  # Viewer role - read-only access
  viewer:
    description: "View-only access to resources"
    permissions:
      - resource: "services"
        verbs: ["get", "list"]
      - resource: "logs"
        verbs: ["get", "list"]
      - resource: "metrics"
        verbs: ["get", "list"]
      - resource: "events"
        verbs: ["get", "list"]

  # Security role - manage security policies
  security_admin:
    description: "Security policy management"
    permissions:
      - resource: "rbac"
        verbs: ["get", "create", "update", "delete", "list"]
      - resource: "secrets"
        verbs: ["get", "create", "update", "delete", "list"]
      - resource: "audit"
        verbs: ["get", "list", "configure"]
      - resource: "tls"
        verbs: ["get", "create", "update", "rotate"]
      - resource: "policies"
        verbs: ["get", "create", "update", "delete", "list"]

  # Service account role - limited service access
  service_account:
    description: "Service-to-service authentication"
    permissions:
      - resource: "api"
        verbs: ["call"]
      - resource: "secrets"
        verbs: ["get"]
      - resource: "logs"
        verbs: ["create"]

# Service-to-role bindings
bindings:
  control_plane: [developer, service_account]
  agent_runtime: [developer, service_account]
  activity_feed: [developer, service_account]
  monitoring: [operator, viewer]
  vault: [security_admin]
  api_gateway: [operator]

# User-to-role bindings (example)
user_bindings:
  admin@example.com: [admin]
  operator@example.com: [operator]
  dev@example.com: [developer]
  viewer@example.com: [viewer]
  security@example.com: [security_admin]
RBAC_ROLES

    log_success "RBAC roles and policies created"
}

################################################################################
# 5. APPLY CONFIGURATIONS
################################################################################

apply_rbac_config() {
    if $APPLY; then
        log_info "Applying RBAC configuration to Vault..."

        ssh akushnir@192.168.168.31 "
            export VAULT_ADDR='$VAULT_ADDR'
            
            # Apply policies
            docker exec vault vault policy write control-plane-policy -<<EOF
            $(cat ${SECURITY_DIR}/vault-rbac.hcl)
EOF

            # Enable auth methods
            docker exec vault vault auth enable approle 2>/dev/null || true
            
            log_success 'RBAC applied to Vault'
        " || log_warn "Could not apply RBAC to Vault"
    fi
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "Phase 6.2: RBAC & Secrets Management"
    log_info "===================================="

    create_vault_rbac
    create_secrets_config
    create_docker_secrets
    create_rbac_roles

    if $APPLY; then
        apply_rbac_config
        log_success "Phase 6.2 Complete - RBAC & Secrets Configured"
    else
        log_info "Configurations created at: $SECURITY_DIR"
        log_info "Run with --apply flag to deploy"
    fi
}

main "$@"
