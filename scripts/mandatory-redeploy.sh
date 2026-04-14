#!/usr/bin/env bash
################################################################################
# mandatory-redeploy.sh - Post-merge deployment orchestration
# Executes after successful CI/CD to rebuild and redeploy code-server
################################################################################

set -euo pipefail

source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"

cd "$REPO_ROOT"

# Source common functions
if [[ -f "$SCRIPT_DIR/common-functions.sh" ]]; then
    source "$SCRIPT_DIR/common-functions.sh"
fi

# Configuration
DOCKER_CONTEXT="${DOCKER_CONTEXT:-default}"
BUILD_TIMEOUT=600  # 10 minutes
HEALTH_CHECK_TIMEOUT=180  # 3 minutes
SERVICES=("code-server" "oauth2-proxy" "caddy")

write_section "MANDATORY REDEPLOY ORCHESTRATION"

# Step 1: Build code-server image
write_info "Building code-server image..."
if ! docker compose build code-server; then
    write_error "Failed to build code-server image"
    exit 1
fi
write_success "code-server image built successfully"

# Step 2: Recreate compose stack
write_info "Recreating compose stack..."
if ! docker compose up -d --force-recreate code-server oauth2-proxy caddy; then
    write_error "Failed to recreate stack"
    exit 1
fi
write_success "Stack recreated"

# Step 3: Wait for services to be healthy
write_info "Waiting for services to become healthy..."
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
        write_success "All services are healthy"
        docker compose ps
        exit 0
    fi

    sleep 5
    elapsed=$((elapsed + 5))
done

write_error "Timeout waiting for services to become healthy"
exit 1
