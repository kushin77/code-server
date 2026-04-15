#!/bin/bash

# Vault Setup Script - Using Binary (No Sudo Required)
# Phase 4: Secrets Management
# This script sets up Vault in user home directory

set -e

export VAULT_HOME="$HOME/.vault"
export VAULT_DATA_DIR="$VAULT_HOME/data"
export VAULT_LOG_DIR="$VAULT_HOME/logs"
export VAULT_CONFIG_DIR="$VAULT_HOME/config"
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_SKIP_VERIFY=true

echo "=== Phase 4: Vault Setup (No Sudo) ==="
echo ""
echo "Setting up Vault in: $VAULT_HOME"

# Step 1: Create directories
echo "Step 1: Creating directories..."
mkdir -p "$VAULT_DATA_DIR" "$VAULT_LOG_DIR" "$VAULT_CONFIG_DIR/tls"
echo "✅ Directories created"

# Step 2: Copy TLS certificates
echo "Step 2: Copying TLS certificates..."
if [ -f "vault.crt" ] && [ -f "vault.key" ]; then
  cp vault.crt "$VAULT_CONFIG_DIR/tls/"
  cp vault.key "$VAULT_CONFIG_DIR/tls/"
  chmod 600 "$VAULT_CONFIG_DIR/tls/vault.key"
  chmod 644 "$VAULT_CONFIG_DIR/tls/vault.crt"
  echo "✅ TLS certificates copied"
else
  echo "⚠️  TLS certificates not found in current directory"
  echo "   Looking for: vault.crt and vault.key"
fi

# Step 3: Copy Vault config
echo "Step 3: Creating Vault configuration..."
if [ -f "vault-config.hcl" ]; then
  cp vault-config.hcl "$VAULT_CONFIG_DIR/config.hcl"
  echo "✅ Configuration copied"
else
  # Create default config
  cat > "$VAULT_CONFIG_DIR/config.hcl" <<'EOF'
listener "tcp" {
  address       = "127.0.0.1:8200"
  tls_disable   = 0
  tls_cert_file = "config/tls/vault.crt"
  tls_key_file  = "config/tls/vault.key"
}

storage "file" {
  path = "data"
}

api_addr     = "https://127.0.0.1:8200"
cluster_addr = "https://127.0.0.1:8201"
ui           = true
log_level    = "info"
EOF
  echo "✅ Configuration created"
fi

# Step 4: Create startup script
echo "Step 4: Creating startup script..."
cat > "$VAULT_HOME/start-vault.sh" <<'EOF'
#!/bin/bash
cd "$HOME/.vault"
export VAULT_ADDR="https://127.0.0.1:8200"
exec vault server -config=config/config.hcl >> logs/vault.log 2>&1
EOF

chmod +x "$VAULT_HOME/start-vault.sh"
echo "✅ Startup script created: $VAULT_HOME/start-vault.sh"

# Step 5: Display next steps
echo ""
echo "=== NEXT STEPS ==="
echo ""
echo "To start Vault, run:"
echo "  $VAULT_HOME/start-vault.sh &"
echo ""
echo "Then initialize Vault:"
echo "  export VAULT_ADDR='https://127.0.0.1:8200'"
echo "  export VAULT_SKIP_VERIFY=true"
echo "  vault operator init -key-shares=5 -key-threshold=3"
echo ""
echo "Save the unseal keys and root token securely!"
echo ""
echo "✅ Vault setup complete"
