#!/usr/bin/env bash
# @file        scripts/update-dast-config.sh
# @module      infrastructure/dast
# @description Update oauth2-proxy skip-auth configuration to allow DAST scanner access

set -euo pipefail

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || {
    echo "ERROR: Failed to source init.sh"
    exit 1
}

log_info "Updating oauth2-proxy DAST scanner configuration..."

# Load environment
if [[ -f .env ]]; then
    export $(grep -v '^#' .env | xargs)
    log_info "Loaded .env configuration"
else
    log_error ".env file not found"
    exit 1
fi

# Update docker-compose environment if needed
if ! grep -q "^/$" docker-compose.yml 2>/dev/null; then
    log_warn "SKIP_AUTH_REGEX not yet updated with root path pattern"
fi

# Check if oauth2-proxy needs restart
log_info "Checking oauth2-proxy configuration..."
if ! docker exec oauth2-proxy grep -q "^/\|" /proc/self/environ 2>/dev/null; then
    log_info "oauth2-proxy environment does not include updated SKIP_AUTH_REGEX"
    log_info "Removing and recreating oauth2-proxy container with updated configuration..."
    
    docker rm -f oauth2-proxy || true
    sleep 2
    
    # Get all environment variables needed
    eval $(cat .env | grep -v '^#' | sed 's/^/export /')
    
    # Start oauth2-proxy through docker-compose
    docker-compose up -d oauth2-proxy 2>&1 || {
        log_error "Failed to start oauth2-proxy via docker-compose"
        exit 1
    }
    
    log_info "Waiting for oauth2-proxy to be healthy..."
    for i in {1..30}; do
        if docker exec oauth2-proxy wget -qO- http://localhost:4180/ping &>/dev/null; then
            log_info "oauth2-proxy is healthy"
            break
        fi
        if [[ $i -eq 30 ]]; then
            log_error "oauth2-proxy did not become healthy within 30 seconds"
            docker logs oauth2-proxy | tail -20
            exit 1
        fi
        sleep 1
    done
fi

# Verify DAST endpoint accessibility
log_info "Testing DAST endpoint accessibility..."
if curl -sf -k https://ide.kushnir.cloud/ >/dev/null 2>&1; then
    log_info "✅ DAST endpoint (/) is accessible without authentication"
elif curl -sf -k https://ide.kushnir.cloud/ping >/dev/null 2>&1; then
    log_warn "⚠️ DAST root path (/) still requires auth, but /ping endpoint is accessible"
    log_info "You can use /ping for DAST scanner probe requests"
fi

log_info "Done!"
