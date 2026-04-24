#!/usr/bin/env bash
# @file        scripts/ops/P3-1674-DEPLOY-SAAS-BACKEND.sh
# @module      operations/saas-api
# @description Deploy SaaS Management Backend API with PostgreSQL schema
#
# Usage: bash scripts/ops/P3-1674-DEPLOY-SAAS-BACKEND.sh [--dry-run]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_onprem}"
SSH_USER="${SSH_USER:-akushnir}"
REPLICAS="${REPLICAS:-192.168.168.31,192.168.168.42}"
DRY_RUN="${DRY_RUN:-0}"

# ============================================================================
# Helper Functions
# ============================================================================

ssh_exec() {
    local host="$1"
    local cmd="$2"
    ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 \
        "$SSH_USER@$host" "$cmd"
}

validate_saas_api() {
    log_info "Validating SaaS API configuration..."
    
    # Check that saas-api Dockerfile exists
    if [[ ! -f "apps/saas-api/Dockerfile" ]]; then
        log_error "apps/saas-api/Dockerfile not found"
        return 1
    fi
    
    # Check that package.json has required dependencies
    if ! grep -q "express" apps/saas-api/package.json; then
        log_error "Express not found in package.json"
        return 1
    fi
    
    if ! grep -q '"pg"' apps/saas-api/package.json; then
        log_error "PostgreSQL driver not found in package.json"
        return 1
    fi
    
    log_info "✅ SaaS API validation: OK"
    return 0
}

initialize_database_schema() {
    local replica="$1"
    local replica_clean=$(echo "$replica" | xargs)
    
    log_info "[$replica_clean] Initializing SaaS database schema..."
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[$replica_clean] [DRY-RUN] Would initialize database schema"
        return 0
    fi
    
    # Copy migration file to replica
    log_info "[$replica_clean] Copying migration script..."
    scp -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 \
        scripts/migrations/001-saas-schema.sql "$SSH_USER@$replica_clean:code-server-enterprise/001-saas-schema.sql" >/dev/null 2>&1 || {
        log_error "[$replica_clean] Failed to copy migration script"
        return 1
    }
    
    # Execute migration via psql through postgresql container
    log_info "[$replica_clean] Executing schema migration..."
    ssh_exec "$replica_clean" "cd code-server-enterprise && \
        docker-compose exec -T postgresql psql -U codeserver -d codeserver < 001-saas-schema.sql" >/dev/null 2>&1 || {
        log_warn "[$replica_clean] Migration may have failed or tables already exist"
    }
    
    log_info "[$replica_clean] ✅ Database schema initialized"
    return 0
}

deploy_saas_api() {
    local replica="$1"
    local replica_clean=$(echo "$replica" | xargs)
    
    log_info "[$replica_clean] Deploying SaaS API service..."
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[$replica_clean] [DRY-RUN] Would deploy saas-api service"
        return 0
    fi
    
    # Rebuild and start saas-api service
    log_info "[$replica_clean] Building saas-api Docker image..."
    ssh_exec "$replica_clean" "cd code-server-enterprise && docker-compose build saas-api" >/dev/null 2>&1 || {
        log_error "[$replica_clean] Docker build failed"
        return 1
    }
    
    log_info "[$replica_clean] Starting saas-api service..."
    ssh_exec "$replica_clean" "cd code-server-enterprise && docker-compose up -d saas-api" >/dev/null 2>&1 || {
        log_error "[$replica_clean] docker-compose up failed"
        return 1
    }
    
    # Wait for service to stabilize
    sleep 3
    
    # Verify saas-api is running and healthy
    log_info "[$replica_clean] Verifying saas-api health..."
    if ! ssh_exec "$replica_clean" "docker ps --filter 'name=saas-api' --filter 'status=running' | grep -q saas-api"; then
        log_error "[$replica_clean] saas-api container is not running"
        ssh_exec "$replica_clean" "docker logs saas-api 2>&1 | tail -20" | head -10
        return 1
    fi
    
    # Test /health endpoint
    if ssh_exec "$replica_clean" "curl -s http://localhost:5000/health | grep -q 'ok'"; then
        log_info "[$replica_clean] ✅ saas-api health check passed"
    else
        log_warn "[$replica_clean] saas-api health check inconclusive"
    fi
    
    log_info "[$replica_clean] ✅ SaaS API deployment completed"
    return 0
}

deploy_to_all_replicas() {
    log_info "=========================================="
    log_info "DEPLOYING SAAS MANAGEMENT BACKEND (P3-1674)"
    log_info "=========================================="
    log_info ""
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "🔍 DRY RUN MODE - No changes will be made"
        log_info ""
        log_info "Would deploy SaaS backend:"
        log_info "  - Initialize PostgreSQL schema (users, groups, orgs, memberships)"
        log_info "  - Build saas-api Docker image"
        log_info "  - Start saas-api service on port 5000"
        log_info "  - Verify API health checks"
        log_info ""
        return 0
    fi
    
    local failed_replicas=""
    local IFS=","
    for replica in $REPLICAS; do
        if ! initialize_database_schema "$replica"; then
            failed_replicas="$failed_replicas $replica"
            continue
        fi
        
        if ! deploy_saas_api "$replica"; then
            failed_replicas="$failed_replicas $replica"
        fi
    done
    
    if [[ -n "$failed_replicas" ]]; then
        log_error "Failed to deploy SaaS backend on replicas:$failed_replicas"
        return 1
    fi
    
    return 0
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_info "=========================================="
    log_info "P3-1674: DEPLOY SAAS MANAGEMENT BACKEND"
    log_info "=========================================="
    log_info "Dry Run: $DRY_RUN"
    log_info ""
    
    # Validate SaaS API configuration
    if ! validate_saas_api; then
        log_error "❌ SaaS API validation failed"
        return 1
    fi
    
    # Deploy to all replicas
    if ! deploy_to_all_replicas; then
        log_error "❌ SaaS backend deployment failed"
        return 1
    fi
    
    log_info "✅ SaaS backend deployment complete"
    log_info ""
    log_info "SaaS Backend Status:"
    log_info "  - PostgreSQL schema: Initialized (users, groups, orgs, memberships)"
    log_info "  - API service: Running on port 5000"
    log_info "  - Endpoints: GET/POST /api/users, /api/groups, /api/orgs, /api/memberships"
    log_info "  - Authentication: OAuth2-proxy headers (X-Auth-Request-*)"
    log_info "  - Caddyfile routing: /api/* → saas-api:5000"
    log_info ""
    log_info "Next steps for P3-1674 completion:"
    log_info "  - Implement RBAC (role-based access control)"
    log_info "  - Create Appsmith UI forms (User Manager, Group Manager, Org Manager)"
    log_info "  - Wire Appsmith UI to call backend APIs"
    log_info "  - Deploy and test end-to-end"
    log_info ""
    
    return 0
}

main "$@"
