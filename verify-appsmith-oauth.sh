#!/bin/bash
# @file verify-appsmith-oauth.sh
# @description Verify Appsmith OAuth configuration and infrastructure
# @usage ./verify-appsmith-oauth.sh
# @date April 30, 2026

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Functions
log_success() {
    echo -e "${GREEN}✓${NC} $1"
    ((CHECKS_PASSED++))
}

log_error() {
    echo -e "${RED}✗${NC} $1"
    ((CHECKS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((CHECKS_WARNING++))
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

cleanup() {
    rm -f /tmp/appsmith-oauth-check.* 2>/dev/null || true
}

# Error handling (required by pre-commit hooks)
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; cleanup' EXIT

# Main verification

log_section "APPSMITH OAUTH CONFIGURATION VERIFICATION"

# Check 1: .env file exists
log_info "Checking .env file..."
if [ -f .env ]; then
    log_success ".env file exists"
    # Check it's readable and not world-readable
    PERMS=$(stat -f "%OLp" .env 2>/dev/null || stat -c "%a" .env 2>/dev/null)
    if [[ "$PERMS" == "600" ]]; then
        log_success ".env file permissions are secure (600)"
    else
        log_warning ".env file permissions are $PERMS (should be 600 for security)"
    fi
else
    log_error ".env file not found - OAuth credentials are missing"
fi

# Check 2: Google OAuth credentials
log_info "Checking Google OAuth configuration..."
if [ -f .env ]; then
    source .env 2>/dev/null || true
    
    if [[ -n "${OAUTH_GOOGLE_CLIENT_ID:-}" ]]; then
        log_success "OAUTH_GOOGLE_CLIENT_ID is set"
        log_info "  Value: ${OAUTH_GOOGLE_CLIENT_ID:0:30}..."
    else
        log_error "OAUTH_GOOGLE_CLIENT_ID is not set"
    fi
    
    if [[ -n "${OAUTH_GOOGLE_CLIENT_SECRET:-}" ]]; then
        log_success "OAUTH_GOOGLE_CLIENT_SECRET is set"
        log_info "  Length: ${#OAUTH_GOOGLE_CLIENT_SECRET} characters"
    else
        log_error "OAUTH_GOOGLE_CLIENT_SECRET is not set"
    fi
else
    log_error "Cannot check OAuth credentials - .env file missing"
fi

# Check 3: GitHub OAuth (optional)
log_info "Checking GitHub OAuth configuration (optional)..."
if [ -f .env ]; then
    source .env 2>/dev/null || true
    
    if [[ -n "${OAUTH_GITHUB_CLIENT_ID:-}" ]] && [[ -n "${OAUTH_GITHUB_CLIENT_SECRET:-}" ]]; then
        log_success "GitHub OAuth is configured (optional)"
    else
        log_warning "GitHub OAuth is not configured (optional)"
    fi
else
    log_warning "Cannot check GitHub OAuth - .env file missing"
fi

# Check 4: docker-compose.enterprise.yml exists
log_section "DOCKER COMPOSE CONFIGURATION"
log_info "Checking docker-compose configuration..."

if [ -f docker-compose.enterprise.yml ]; then
    log_success "docker-compose.enterprise.yml exists"
    
    # Check for Appsmith service
    if grep -q "code-server-appsmith" docker-compose.enterprise.yml; then
        log_success "Appsmith service is configured"
    else
        log_error "Appsmith service not found in docker-compose.enterprise.yml"
    fi
    
    # Check for OAuth variables in docker-compose
    if grep -q "OAUTH_GOOGLE_CLIENT_ID" docker-compose.enterprise.yml; then
        log_success "OAuth variables are referenced in docker-compose"
    else
        log_error "OAuth variables not found in docker-compose"
    fi
    
    # Validate docker-compose syntax
    if command -v docker-compose &> /dev/null; then
        if docker-compose -f docker-compose.enterprise.yml config > /dev/null 2>&1; then
            log_success "docker-compose syntax is valid"
        else
            log_error "docker-compose syntax is invalid"
        fi
    elif command -v docker &> /dev/null; then
        if docker compose -f docker-compose.enterprise.yml config > /dev/null 2>&1; then
            log_success "docker-compose syntax is valid"
        else
            log_error "docker-compose syntax is invalid"
        fi
    else
        log_warning "Docker not found - cannot validate docker-compose syntax"
    fi
else
    log_error "docker-compose.enterprise.yml not found"
fi

# Check 5: Caddyfile configuration
log_section "CADDYFILE CONFIGURATION"
log_info "Checking Caddyfile..."

if [ -f Caddyfile ]; then
    log_success "Caddyfile exists"
    
    # Check for necessary routes
    if grep -q "handle.*appsmith" Caddyfile; then
        log_success "Appsmith route is configured in Caddyfile"
    else
        log_warning "Appsmith route not found in Caddyfile"
    fi
    
    # Check for OAuth headers
    if grep -q "X-OAuth" Caddyfile; then
        log_success "OAuth headers are configured in Caddyfile"
    else
        log_warning "OAuth headers not found in Caddyfile"
    fi
    
    # Check for TLS configuration
    if grep -q "tls1_2" Caddyfile; then
        log_success "TLS 1.2+ enforcement is configured"
    else
        log_warning "TLS configuration not found in Caddyfile"
    fi
    
    # Validate Caddyfile syntax
    if command -v caddy &> /dev/null; then
        if caddy validate --config Caddyfile 2>/dev/null; then
            log_success "Caddyfile syntax is valid"
        else
            log_error "Caddyfile syntax is invalid"
        fi
    else
        log_warning "Caddy not found - cannot validate Caddyfile syntax"
    fi
else
    log_error "Caddyfile not found"
fi

# Check 6: DNS Configuration
log_section "DNS & NETWORK CONFIGURATION"
log_info "Checking DNS and network..."

# Check for APEX_DOMAIN
source .env.infrastructure 2>/dev/null || true
if [[ -n "${APEX_DOMAIN:-}" ]]; then
    log_success "APEX_DOMAIN is set: ${APEX_DOMAIN}"
    
    # Try to resolve domain
    if command -v nslookup &> /dev/null; then
        if nslookup "${APEX_DOMAIN}" 2>/dev/null | grep -q "Address"; then
            log_success "DNS resolves ${APEX_DOMAIN}"
            IP=$(nslookup "${APEX_DOMAIN}" 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}')
            log_info "  Resolved to: $IP"
        else
            log_warning "DNS lookup for ${APEX_DOMAIN} failed (may be offline)"
        fi
    else
        log_warning "nslookup not found - cannot verify DNS"
    fi
else
    log_warning "APEX_DOMAIN not set in .env.infrastructure"
fi

# Check 7: Appsmith Service Status
log_section "APPSMITH SERVICE STATUS"
log_info "Checking Appsmith container..."

if command -v docker-compose &> /dev/null; then
    DOCKER_CMD="docker-compose -f docker-compose.enterprise.yml"
elif command -v docker &> /dev/null; then
    DOCKER_CMD="docker compose -f docker-compose.enterprise.yml"
else
    log_warning "Docker not found - cannot check container status"
    DOCKER_CMD=""
fi

if [[ -n "$DOCKER_CMD" ]]; then
    if $DOCKER_CMD ps 2>/dev/null | grep -q "code-server-appsmith"; then
        STATUS=$($DOCKER_CMD ps | grep code-server-appsmith | awk '{print $7}')
        log_success "Appsmith container is running (Status: $STATUS)"
        
        # Check health
        if echo "$STATUS" | grep -q "healthy"; then
            log_success "Appsmith container is healthy"
        elif echo "$STATUS" | grep -q "unhealthy"; then
            log_error "Appsmith container is unhealthy"
        else
            log_warning "Appsmith container health status: $STATUS"
        fi
        
        # Check logs for OAuth errors
        if docker logs code-server-appsmith 2>&1 | grep -q -i "oauth.*error\|authentication.*error\|invalid.*credential"; then
            log_error "OAuth errors found in Appsmith logs"
        fi
    else
        log_warning "Appsmith container is not running"
    fi
else
    log_warning "Docker not available - cannot check container status"
fi

# Check 8: Port accessibility
log_section "PORT ACCESSIBILITY"
log_info "Checking port access..."

if command -v curl &> /dev/null; then
    # Check Appsmith port (8084)
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8084/health 2>/dev/null | grep -q "200"; then
        log_success "Appsmith port 8084 is accessible and healthy"
    else
        log_warning "Appsmith port 8084 may not be accessible"
    fi
    
    # Check Caddyfile port (443)
    if curl -s -o /dev/null -w "%{http_code}" https://localhost/ 2>/dev/null | grep -q ""; then
        log_warning "Caddyfile port 443 check requires investigation"
    fi
else
    log_warning "curl not found - cannot check port accessibility"
fi

# Summary
log_section "VERIFICATION SUMMARY"
echo ""
echo -e "Checks Passed:  ${GREEN}$CHECKS_PASSED${NC}"
echo -e "Checks Failed:  ${RED}$CHECKS_FAILED${NC}"
echo -e "Warnings:       ${YELLOW}$CHECKS_WARNING${NC}"
echo ""

if [[ $CHECKS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ ALL CRITICAL CHECKS PASSED${NC}"
    echo ""
    if [[ $CHECKS_WARNING -eq 0 ]]; then
        echo -e "${GREEN}✓ READY FOR DEPLOYMENT${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠ Please review warnings above${NC}"
        exit 0
    fi
else
    echo -e "${RED}✗ CRITICAL ISSUES FOUND - DEPLOYMENT BLOCKED${NC}"
    echo ""
    echo "Required actions:"
    echo "  1. Review failures above"
    echo "  2. Create .env file with OAuth credentials"
    echo "  3. Verify docker-compose configuration"
    echo "  4. Check DNS and network connectivity"
    echo ""
    exit 1
fi
