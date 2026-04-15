#!/bin/bash

# Vault TLS Certificate Generation Script
# Phase 4: Secrets Management - TLS Setup
# Usage: bash scripts/vault-tls-setup.sh

set -e

VAULT_TLS_DIR="./vault-tls"
CERT_FILE="$VAULT_TLS_DIR/vault.crt"
KEY_FILE="$VAULT_TLS_DIR/vault.key"

echo "=== Vault TLS Certificate Generation ==="
echo "Creating directory: $VAULT_TLS_DIR"

# Create TLS directory
mkdir -p "$VAULT_TLS_DIR"

# Generate self-signed certificate (365 days, 4096-bit RSA)
echo "Generating self-signed certificate..."
openssl req -x509 -newkey rsa:4096 \
  -keyout "$KEY_FILE" \
  -out "$CERT_FILE" \
  -days 365 \
  -nodes \
  -subj "/CN=vault.kushnir.local/O=Code-Server/C=US" \
  2>/dev/null

# Verify certificate generation
if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
  echo "✅ TLS certificates generated successfully"
  echo "   Certificate: $CERT_FILE"
  echo "   Private Key: $KEY_FILE"
  
  # Display certificate info
  echo ""
  echo "Certificate Details:"
  openssl x509 -in "$CERT_FILE" -noout -dates
  openssl x509 -in "$CERT_FILE" -noout -subject
else
  echo "❌ Failed to generate TLS certificates"
  exit 1
fi

# Set proper permissions (readable by docker)
chmod 644 "$CERT_FILE"
chmod 600 "$KEY_FILE"

echo ""
echo "✅ Vault TLS setup complete"
