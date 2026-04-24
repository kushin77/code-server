#!/usr/bin/env bash
# @file        scripts/mandatory-redeploy.sh
# @module      operations
# @description mandatory redeploy — on-prem code-server
# @owner       platform
# @status      active
################################################################################
# mandatory-redeploy.sh - Post-merge deployment orchestration
# Executes after successful CI/CD to rebuild and redeploy code-server
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Get script directory
REPO_ROOT="$(git rev-parse --show-toplevel)"

cd "$REPO_ROOT"

# Configuration
DOCKER_CONTEXT="${DOCKER_CONTEXT:-default}"
# shellcheck disable=SC2034
BUILD_TIMEOUT=600  # 10 minutes
HEALTH_CHECK_TIMEOUT=180  # 3 minutes
SERVICES=("code-server" "oauth2-proxy" "caddy")

log_section "MANDATORY REDEPLOY ORCHESTRATION"

# Step 1: Build code-server image
log_info "Building code-server image..."
if ! docker compose build code-server; then
    log_error "Failed to build code-server image" || true
    exit 1
fi
log_success "code-server image built successfully"

# Step 2: Recreate compose stack
log_info "Recreating compose stack..."
if ! docker compose up -d --force-recreate code-server oauth2-proxy caddy; then
    log_error "Failed to recreate stack" || true
    exit 1
fi
log_success "Stack recreated"

# Step 3: Wait for services to be healthy
log_info "Waiting for services to become healthy..."
wait_for_health() {
    local elapsed=0
    while (( elapsed < HEALTH_CHECK_TIMEOUT )); do
        local all_healthy=true
        
        for service in "${SERVICES[@]}"; do
            local health
            health=$(docker inspect --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}" "$service" 2>/dev/null || echo "error")
            
            if [[ "$health" != "healthy" && "$health" != "none" ]]; then
                all_healthy=false
                break
            fi
        done
        
        if $all_healthy; then
            log_success "All services are healthy"
            docker compose ps
            return 0
        fi
        
        sleep 5
        elapsed=$((elapsed + 5))
    done

    log_error "Timeout waiting for services to become healthy" || true
    return 1
}

wait_for_health
