#!/usr/bin/env bash
################################################################################
# Vault Production Initialization
# File: scripts/vault-init-production.sh
# Purpose: Initialize Vault in production mode with Shamir keys
# Usage: ./scripts/vault-init-production.sh
# Output: vault-unseal-keys.json (MUST be secured in 1Password/Bitwarden)
# Owner: Infrastructure Team
################################################################################

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
VAULT_ADDR="https://vault:8200"
UNSEAL_SHARES=5
UNSEAL_THRESHOLD=3
OUTPUT_FILE="vault-unseal-keys.json"

echo "════════════════════════════════════════════════════════════════════════════"
echo "  VAULT PRODUCTION INITIALIZATION"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "⚠️  WARNING: This script generates unseal keys that MUST be secured immediately"
echo ""
echo "Configuration:"
echo "  • Vault Address: ${VAULT_ADDR}"
echo "  • Shamir key shares: ${UNSEAL_SHARES}"
echo "  • Threshold to unseal: ${UNSEAL_THRESHOLD}"
echo "  • Output file: ${OUTPUT_FILE}"
echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo ""

# Check if Vault is running
if ! vault status >/dev/null 2>&1; then
  echo -e "${RED}✗ Vault is not accessible at ${VAULT_ADDR}${NC}"
  echo "  Start Vault with: docker-compose up -d vault"
  exit 1
fi

# Check if already initialized
if vault status 2>/dev/null | grep -q "Initialized.*true"; then
  echo -e "${YELLOW}⚠ Vault is already initialized${NC}"
  echo "  To reinitialize, unseal first: vault operator unseal"
  exit 0
fi

# Initialize Vault
echo "▸ Initializing Vault..."
vault operator init \
  -key-shares=${UNSEAL_SHARES} \
  -key-threshold=${UNSEAL_THRESHOLD} \
  -format=json > "${OUTPUT_FILE}"

echo -e "${GREEN}✓ Vault initialized successfully${NC}"
echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo "  CRITICAL: UNSEAL KEYS GENERATED"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "File: ${OUTPUT_FILE}"
jq .keys "${OUTPUT_FILE}" | head -5
echo "  ... (${UNSEAL_SHARES} keys total)"
echo ""
echo "Initial root token (save to 1Password):"
ROOT_TOKEN=$(jq -r '.root_token' "${OUTPUT_FILE}")
echo "  Token: ${ROOT_TOKEN:0:20}... (hidden for security)"
echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "NEXT STEPS (DO THIS IMMEDIATELY):"
echo ""
echo "1. BACKUP THIS FILE SECURELY"
echo "   cp ${OUTPUT_FILE} /secure/backup/location/"
echo ""
echo "2. DISTRIBUTE UNSEAL KEYS (via secure channel)"
echo "   • Save in 1Password/Bitwarden (enterprise secret management)"
echo "   • Give 3 of 5 keys to different team members"
echo "   • Each person stores their key securely (encrypted)"
echo "   • Document: who has which key number"
echo ""
echo "3. UNSEAL VAULT (after all 3+ keys are available)"
echo "   vault operator unseal <key1>"
echo "   vault operator unseal <key2>"
echo "   vault operator unseal <key3>"
echo ""
echo "4. AUTHENTICATE WITH ROOT TOKEN"
echo "   vault login <root-token>"
echo "   # Then create admin/operator users (revoke root token after)"
echo ""
echo "5. DELETE THIS FILE AFTER SECURING (DO NOT LEAVE IN REPO)"
echo "   rm ${OUTPUT_FILE}"
echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "${GREEN}✓ Vault initialization complete${NC}"
echo ""
