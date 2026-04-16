#!/bin/bash
# Vault RBAC Policies Setup — P0 #413 Phase 1
# Implements least-privilege access control
# Run after Vault is unsealed and authenticated

set -euo pipefail

VAULT_ADDR=${VAULT_ADDR:-"https://localhost:8200"}
VAULT_TOKEN=${VAULT_TOKEN:-""}
VAULT_CACERT="${VAULT_CACERT:-/etc/vault/tls/ca.crt}"

if [ -z "$VAULT_TOKEN" ]; then
  echo "ERROR: VAULT_TOKEN must be set (root token for initial setup)"
  exit 1
fi

echo "═══════════════════════════════════════════════════════════════"
echo "Vault RBAC Setup — P0 #413 Phase 1"
echo "═══════════════════════════════════════════════════════════════"

# Function to create policy
create_policy() {
  local policy_name="$1"
  local policy_file="$2"
  
  echo "Creating policy: $policy_name"
  vault policy write "$policy_name" "$policy_file"
}

export VAULT_ADDR VAULT_TOKEN VAULT_CACERT

# 1. Default deny-all policy (security baseline)
cat > /tmp/vault-policy-deny-all.hcl << 'EOF'
# Default deny-all policy (no permissions)
# All other policies extend this with specific grants
path "*" {
  capabilities = ["deny"]
}
EOF

create_policy "deny-all" "/tmp/vault-policy-deny-all.hcl"

# 2. Code-Server policy (read-only database credentials)
cat > /tmp/vault-policy-code-server.hcl << 'EOF'
# code-server service: read-only access to DB credentials
path "secret/data/code-server/*" {
  capabilities = ["read", "list"]
}

path "database/static-creds/code-server" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF

create_policy "code-server" "/tmp/vault-policy-code-server.hcl"

# 3. Monitoring policy (health + metrics read)
cat > /tmp/vault-policy-monitoring.hcl << 'EOF'
# Monitoring services (Prometheus, Loki): health + config read
path "sys/health" {
  capabilities = ["read"]
}

path "sys/metrics" {
  capabilities = ["read"]
}

path "secret/data/monitoring/*" {
  capabilities = ["read", "list"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF

create_policy "monitoring" "/tmp/vault-policy-monitoring.hcl"

# 4. Terraform policy (IaC provisioning - limited)
cat > /tmp/vault-policy-terraform.hcl << 'EOF'
# Terraform: generate DB credentials, manage secrets (limited scope)
path "secret/data/terraform/*" {
  capabilities = ["create", "read", "update", "list"]
}

path "database/static-creds/terraform" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF

create_policy "terraform" "/tmp/vault-policy-terraform.hcl"

# 5. Admin policy (full access - restricted to root token use)
cat > /tmp/vault-policy-admin.hcl << 'EOF'
# Admin: full Vault control (for operators only)
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF

create_policy "admin" "/tmp/vault-policy-admin.hcl"

# 6. Create service tokens (with policies)
echo ""
echo "✓ Creating service tokens with limited policies..."

# Code-server token
echo "  → code-server token"
CODE_SERVER_TOKEN=$(vault token create \
  -policy=code-server \
  -ttl=24h \
  -display-name="code-server-service" \
  -format=json | jq -r '.auth.client_token')

echo "    Token: $CODE_SERVER_TOKEN"
echo "    Store in: .env VAULT_TOKEN_CODE_SERVER=$CODE_SERVER_TOKEN"

# Monitoring token
echo "  → monitoring token"
MONITORING_TOKEN=$(vault token create \
  -policy=monitoring \
  -ttl=24h \
  -display-name="monitoring-service" \
  -format=json | jq -r '.auth.client_token')

echo "    Token: $MONITORING_TOKEN"
echo "    Store in: .env VAULT_TOKEN_MONITORING=$MONITORING_TOKEN"

# Terraform token
echo "  → terraform token"
TERRAFORM_TOKEN=$(vault token create \
  -policy=terraform \
  -ttl=24h \
  -display-name="terraform-provisioning" \
  -format=json | jq -r '.auth.client_token')

echo "    Token: $TERRAFORM_TOKEN"
echo "    Store in: terraform/vars/.env VAULT_TOKEN=$TERRAFORM_TOKEN"

# 7. Verify policies
echo ""
echo "✓ Listing all policies:"
vault policy list

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✓ RBAC Setup Complete"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "⚠️  CRITICAL: Store these tokens securely!"
echo "    code-server:   $CODE_SERVER_TOKEN"
echo "    monitoring:    $MONITORING_TOKEN"
echo "    terraform:     $TERRAFORM_TOKEN"
echo ""
echo "Next Steps:"
echo "1. Add tokens to .env files (do NOT commit to git)"
echo "2. Enable audit logging (P0 #413 Phase 1 Step 3)"
echo "3. Test policies with service applications"
echo "4. Monitor token usage in audit logs"
