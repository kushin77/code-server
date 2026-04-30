#!/bin/bash

# Appsmith + Hermes Agent Integration Verification Script
# Validates secure domain integration with OAuth and API connectivity
# Date: April 30, 2026

set -e

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Logging functions
log_info() { echo "[INFO] $1"; }
log_error() { echo "[ERROR] $1" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DOMAIN="${DOMAIN:-kushnir.cloud}"
APPSMITH_URL="https://${DOMAIN}"
API_URL="https://${DOMAIN}/api/hermes"
IDE_URL="https://${DOMAIN}/ide"

# Counters
PASSED=0
FAILED=0
WARNINGS=0

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Hermes Agent + Appsmith Integration Verification${NC}"
echo -e "${BLUE}Domain: ${DOMAIN}${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Function to check command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}✗ FAILED${NC}: $1 not found"
        return 1
    fi
    return 0
}

# Function to check file exists
check_file() {
    if [[ ! -f "$1" ]]; then
        echo -e "${RED}✗ FAILED${NC}: File not found: $1"
        ((FAILED++))
        return 1
    fi
    echo -e "${GREEN}✓ OK${NC}: $1 exists"
    ((PASSED++))
    return 0
}

# Function to check docker service
check_docker_service() {
    local service=$1
    local container="code-server-${service}"
    
    echo -n "Checking $service service... "
    
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo -e "${GREEN}✓ RUNNING${NC}"
        ((PASSED++))
    elif docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
        echo -e "${YELLOW}⚠ STOPPED${NC}"
        ((WARNINGS++))
    else
        echo -e "${RED}✗ NOT FOUND${NC}"
        ((FAILED++))
    fi
}

# Function to check API endpoint
check_api_endpoint() {
    local endpoint=$1
    local method=${2:-GET}
    
    echo -n "Checking ${method} ${endpoint}... "
    
    if response=$(curl -s -o /dev/null -w "%{http_code}" -X "${method}" "${endpoint}" 2>/dev/null); then
        if [[ "$response" =~ ^(200|201|204|301|302|400|401|403)$ ]]; then
            echo -e "${GREEN}✓ HTTP ${response}${NC}"
            ((PASSED++))
        else
            echo -e "${YELLOW}⚠ HTTP ${response}${NC}"
            ((WARNINGS++))
        fi
    else
        echo -e "${RED}✗ CONNECTION FAILED${NC}"
        ((FAILED++))
    fi
}

# Function to validate JSON file
validate_json() {
    local file=$1
    
    echo -n "Validating JSON: $file... "
    
    if command -v jq &> /dev/null; then
        if jq empty < "${file}" 2>/dev/null; then
            echo -e "${GREEN}✓ VALID${NC}"
            ((PASSED++))
        else
            echo -e "${RED}✗ INVALID JSON${NC}"
            ((FAILED++))
        fi
    else
        echo -e "${YELLOW}⚠ jq not available, skipping${NC}"
        ((WARNINGS++))
    fi
}

# Function to check environment variables
check_env_var() {
    local var=$1
    
    echo -n "Checking ${var}... "
    
    if [[ -f .env ]]; then
        if grep -q "^${var}=" .env; then
            echo -e "${GREEN}✓ SET${NC}"
            ((PASSED++))
        else
            echo -e "${YELLOW}⚠ NOT SET (required for OAuth)${NC}"
            ((WARNINGS++))
        fi
    else
        echo -e "${YELLOW}⚠ .env file not found${NC}"
        ((WARNINGS++))
    fi
}

# ============================================================================
# CHECK 1: Configuration Files
# ============================================================================
echo -e "\n${BLUE}[1] Configuration Files${NC}"
echo "─────────────────────────────────────────────────────────────"

check_file "Caddyfile"
check_file "docker-compose.enterprise.yml"
check_file "apps/hermes-integration/main.py"
check_file "apps/hermes-integration/Dockerfile"
check_file "apps/ide-extension/hermes-extension.ts"
check_file "apps/paperclip/appsmith-hermes-dashboard-production.json"

# ============================================================================
# CHECK 2: Caddyfile Configuration
# ============================================================================
echo -e "\n${BLUE}[2] Caddyfile Configuration${NC}"
echo "─────────────────────────────────────────────────────────────"

echo -n "Checking Caddyfile for Appsmith route... "
if grep -q "reverse_proxy http://appsmith:80" Caddyfile; then
    echo -e "${GREEN}✓ FOUND${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ MISSING${NC}"
    ((FAILED++))
fi

echo -n "Checking Caddyfile for hermes-integration route... "
if grep -q "reverse_proxy http://hermes-integration:8000" Caddyfile; then
    echo -e "${GREEN}✓ FOUND${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ MISSING${NC}"
    ((FAILED++))
fi

echo -n "Checking Caddyfile for TLS hardening... "
if grep -q "min_version tls1_2" Caddyfile; then
    echo -e "${GREEN}✓ ENABLED${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ NOT CONFIGURED${NC}"
    ((FAILED++))
fi

echo -n "Checking Caddyfile for OAuth headers... "
if grep -q "X-OAuth" Caddyfile; then
    echo -e "${GREEN}✓ CONFIGURED${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠ NOT FOUND${NC}"
    ((WARNINGS++))
fi

# ============================================================================
# CHECK 3: Docker Configuration
# ============================================================================
echo -e "\n${BLUE}[3] Docker Services${NC}"
echo "─────────────────────────────────────────────────────────────"

echo -n "Checking Docker availability... "
if docker --version &>/dev/null; then
    echo -e "${GREEN}✓ OK${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ DOCKER NOT AVAILABLE${NC}"
    ((FAILED++))
    exit 1
fi

check_docker_service "appsmith"
check_docker_service "hermes-integration"
check_docker_service "code-server-ide"
check_docker_service "postgres"

# ============================================================================
# CHECK 4: Environment Variables
# ============================================================================
echo -e "\n${BLUE}[4] OAuth Configuration${NC}"
echo "─────────────────────────────────────────────────────────────"

check_env_var "OAUTH_GOOGLE_CLIENT_ID"
check_env_var "OAUTH_GOOGLE_CLIENT_SECRET"
check_env_var "APPSMITH_INSTANCE_NAME"

# ============================================================================
# CHECK 5: JSON Configuration Validation
# ============================================================================
echo -e "\n${BLUE}[5] JSON Configuration Files${NC}"
echo "─────────────────────────────────────────────────────────────"

validate_json "apps/paperclip/appsmith-hermes-dashboard-production.json"

# ============================================================================
# CHECK 6: API Connectivity (if services are running)
# ============================================================================
if docker ps --format '{{.Names}}' | grep -q "code-server-hermes-integration"; then
    echo -e "\n${BLUE}[6] API Connectivity${NC}"
    echo "─────────────────────────────────────────────────────────────"
    
    # Try local API first
    echo -n "Checking hermes-integration service (local)... "
    if response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health 2>/dev/null); then
        if [[ "$response" == "200" ]]; then
            echo -e "${GREEN}✓ HTTP ${response}${NC}"
            ((PASSED++))
        else
            echo -e "${YELLOW}⚠ HTTP ${response}${NC}"
            ((WARNINGS++))
        fi
    else
        echo -e "${YELLOW}⚠ Connection refused (may require port mapping)${NC}"
        ((WARNINGS++))
    fi
fi

# ============================================================================
# CHECK 7: Integration Points
# ============================================================================
echo -e "\n${BLUE}[7] Integration Points${NC}"
echo "─────────────────────────────────────────────────────────────"

echo -n "Checking docker-compose Appsmith config... "
if docker-compose -f docker-compose.enterprise.yml config 2>/dev/null | grep -q "appsmith:"; then
    echo -e "${GREEN}✓ VALID${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ INVALID OR MISSING${NC}"
    ((FAILED++))
fi

echo -n "Checking docker-compose hermes-integration config... "
if docker-compose -f docker-compose.enterprise.yml config 2>/dev/null | grep -q "hermes-integration:"; then
    echo -e "${GREEN}✓ VALID${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠ SERVICE NOT IN DOCKER-COMPOSE${NC}"
    ((WARNINGS++))
fi

echo -n "Checking network configuration... "
if grep -q "networks:" docker-compose.enterprise.yml && grep -q "services:" docker-compose.enterprise.yml; then
    echo -e "${GREEN}✓ CONFIGURED${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ NETWORK CONFIG MISSING${NC}"
    ((FAILED++))
fi

# ============================================================================
# CHECK 8: Security Configuration
# ============================================================================
echo -e "\n${BLUE}[8] Security Configuration${NC}"
echo "─────────────────────────────────────────────────────────────"

echo -n "Checking HTTPS redirect... "
if grep -q "redir http:// https://" Caddyfile; then
    echo -e "${GREEN}✓ ENABLED${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ NOT CONFIGURED${NC}"
    ((FAILED++))
fi

echo -n "Checking security headers... "
if grep -q "Strict-Transport-Security\|X-Content-Type-Options\|X-Frame-Options" Caddyfile; then
    echo -e "${GREEN}✓ CONFIGURED${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ MISSING HEADERS${NC}"
    ((FAILED++))
fi

echo -n "Checking CSP (Content Security Policy)... "
if grep -q "Content-Security-Policy" Caddyfile; then
    echo -e "${GREEN}✓ CONFIGURED${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠ NOT FOUND${NC}"
    ((WARNINGS++))
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Verification Summary${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"

echo -e "${GREEN}Passed:${NC}  $PASSED"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo -e "${RED}Failed:${NC}  $FAILED"

echo ""

if [[ $FAILED -eq 0 ]]; then
    if [[ $WARNINGS -eq 0 ]]; then
        echo -e "${GREEN}✓ ALL CHECKS PASSED - READY FOR DEPLOYMENT${NC}"
        exit 0
    else
        echo -e "${YELLOW}✓ CHECKS PASSED WITH WARNINGS${NC}"
        exit 0
    fi
else
    echo -e "${RED}✗ SOME CHECKS FAILED - REVIEW CONFIGURATION${NC}"
    exit 1
fi
