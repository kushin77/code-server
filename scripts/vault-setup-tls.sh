#!/usr/bin/env bash
################################################################################
# Vault TLS Certificate Generation
# File: scripts/vault-setup-tls.sh
# Purpose: Generate self-signed TLS certificates for Vault production mode
# Usage: ./scripts/vault-setup-tls.sh [days=365]
# Owner: Infrastructure Team
################################################################################

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
VAULT_TLS_DIR="config/vault-tls"
DAYS="${1:-365}"
DOMAIN="vault"
IP_ADDRESS="127.0.0.1"  # On-prem: localhost for tests

echo "🔐 Generating Vault TLS Certificates..."
echo "   Certificate validity: ${DAYS} days"
echo "   Directory: ${VAULT_TLS_DIR}"

# Create TLS directory
mkdir -p "${VAULT_TLS_DIR}"

# Generate private key
echo "▸ Generating private key..."
openssl genrsa -out "${VAULT_TLS_DIR}/key.pem" 4096

# Generate self-signed certificate
echo "▸ Generating self-signed certificate..."
openssl req -new -x509 -key "${VAULT_TLS_DIR}/key.pem" \
  -out "${VAULT_TLS_DIR}/cert.pem" \
  -days "${DAYS}" \
  -subj "/C=US/ST=Local/L=OnPrem/O=Vault/CN=${DOMAIN}/subjectAltName=IP:${IP_ADDRESS},IP:192.168.168.31,DNS:vault,DNS:vault.local"

# Set restrictive permissions
chmod 600 "${VAULT_TLS_DIR}/key.pem"
chmod 644 "${VAULT_TLS_DIR}/cert.pem"

# Verify certificate
echo "▸ Verifying certificate..."
EXPIRES=$(openssl x509 -in "${VAULT_TLS_DIR}/cert.pem" -noout -enddate | cut -d= -f2)
echo "   Certificate expires: ${EXPIRES}"

echo -e "${GREEN}✓ Vault TLS certificates generated successfully${NC}"
echo ""
echo "Next steps:"
echo "  1. Update docker-compose.yml to mount: ${VAULT_TLS_DIR}:/vault/tls:ro"
echo "  2. Initialize Vault: vault operator init -key-shares=5 -key-threshold=3"
echo "  3. Distribute unseal keys securely to team members (1Password/Bitwarden)"
echo "  4. Create recovery keys backup (separate from unseal keys)"
echo ""
