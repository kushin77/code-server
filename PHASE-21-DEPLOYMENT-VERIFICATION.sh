#!/bin/bash
# ═════════════════════════════════════════════════════════════════════════════
# Phase 21 Deployment Verification Script
# 
# Purpose: Validate DNS-First Architecture configuration before deployment
# Usage: bash PHASE-21-DEPLOYMENT-VERIFICATION.sh
# ═════════════════════════════════════════════════════════════════════════════

set -euo pipefail

echo "════════════════════════════════════════════════════════════════════════════"
echo "PHASE 21: DNS-First Architecture Verification"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0

# Helper function to check file content
check_file_contains() {
    local file="$1"
    local pattern="$2"
    local description="$3"
    
    if [ ! -f "$file" ]; then
        echo -e "${RED}✗ FAILED${NC} - File not found: $file"
        ((FAILED++))
        return 1
    fi
    
    if grep -q "$pattern" "$file"; then
        echo -e "${GREEN}✓ PASSED${NC} - $description"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAILED${NC} - $description (pattern not found in $file)"
        ((FAILED++))
        return 1
    fi
}

# Check 1: Caddyfile uses DOMAIN variable
echo "[1/8] Verifying Caddyfile configuration..."
check_file_contains "Caddyfile" '{\$DOMAIN:192.168.168.31.nip.io}' "Caddyfile uses DOMAIN environment variable"

# Check 2: Caddyfile has conditional HTTPS
echo "[2/8] Verifying conditional HTTPS..."
check_file_contains "Caddyfile" 'if eq "{\$ACME_EMAIL' "Caddyfile conditional HTTPS for production"

# Check 3: No hardcoded 192.168.168.31 in service routes
echo "[3/8] Verifying no hardcoded IPs in service routes..."
if grep -E 'reverse_proxy [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:' Caddyfile > /dev/null 2>&1; then
    echo -e "${RED}✗ FAILED${NC} - Hardcoded IPs found in Caddyfile proxy routes"
    ((FAILED++))
else
    echo -e "${GREEN}✓ PASSED${NC} - All proxy routes use container DNS names"
    ((PASSED++))
fi

# Check 4: docker-compose.yml has DOMAIN env var for caddy
echo "[4/8] Verifying docker-compose DOMAIN variable..."
check_file_contains "docker-compose.yml" 'DOMAIN=\${DOMAIN:-192.168.168.31.nip.io}' "Caddy service has DOMAIN environment variable"

# Check 5: docker-compose.yml has ACME_EMAIL env var
echo "[5/8] Verifying docker-compose ACME_EMAIL variable..."
check_file_contains "docker-compose.yml" 'ACME_EMAIL=' "Caddy service has ACME_EMAIL environment variable"

# Check 6: variables.tf has external_domain variable
echo "[6/8] Verifying Terraform variables..."
check_file_contains "variables.tf" 'variable "external_domain"' "Terraform has external_domain variable"

# Check 7: main.tf passes variables to docker-compose
echo "[7/8] Verifying Terraform passes variables to template..."
check_file_contains "main.tf" 'external_domain.*=.*var.external_domain' "Terraform main.tf passes external_domain to locals"

# Check 8: code-server-config.yaml has wildcard proxy domains
echo "[8/8] Verifying code-server configuration..."
check_file_contains "code-server-config.yaml" '*.nip.io' "code-server-config includes wildcard nip.io domain"

echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo "VERIFICATION RESULTS"
echo "════════════════════════════════════════════════════════════════════════════"
echo -e "Passed: ${GREEN}${PASSED}/8${NC}"
echo -e "Failed: ${RED}${FAILED}/8${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All verification checks passed!${NC}"
    echo ""
    echo "NEXT STEPS for deployment:"
    echo "  1. SSH to 192.168.168.31:"
    echo "     ssh akushnir@192.168.168.31"
    echo ""
    echo "  2. Set environment variables:"
    echo "     export DOMAIN=192.168.168.31.nip.io"
    echo "     export ACME_EMAIL=\"\"  # Empty for nip.io (no HTTPS)"
    echo ""
    echo "  3. Deploy via Terraform:"
    echo "     terraform apply -auto-approve"
    echo ""
    echo "  4. Verify containers:"
    echo "     docker compose ps"
    echo ""
    echo "  5. Test endpoints:"
    echo "     curl http://192.168.168.31.nip.io/healthz"
    echo "     curl http://code-server.192.168.168.31.nip.io/"
    echo "     curl http://prometheus.192.168.168.31.nip.io/api/v1/targets"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Verification failed! Fix the issues above before deploying.${NC}"
    echo ""
    echo "COMMON ISSUES:"
    echo "  - Caddyfile syntax error: check Caddyfile format"
    echo "  - Missing env vars: ensure docker-compose.yml updated"
    echo "  - Terraform not updated: verify main.tf and variables.tf"
    echo ""
    exit 1
fi
