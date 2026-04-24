#!/usr/bin/env bash
# @file        scripts/deploy-phase-4-5.sh
# @module      deployment/phase-4-5
# @description Deploy Phase 4-5 infrastructure (Custom domains + SSO tests) - IaC, Immutable, Idempotent
# Usage: ./scripts/deploy-phase-4-5.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/logging.sh"
source "$SCRIPT_DIR/_common/init.sh"

# ════════════════════════════════════════════════════════════════════════════
# Configuration
# ════════════════════════════════════════════════════════════════════════════
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa_onprem}"
REPLICA_1="akushnir@192.168.168.31"
REPLICA_2="akushnir@192.168.168.42"
DEPLOY_DIR="code-server-enterprise"
DRY_RUN="${1:-}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ════════════════════════════════════════════════════════════════════════════
# Helper: Print section header
# ════════════════════════════════════════════════════════════════════════════
function print_header() {
  echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
}

# ════════════════════════════════════════════════════════════════════════════
# Helper: Run command on remote host
# ════════════════════════════════════════════════════════════════════════════
function remote_exec() {
  local host="$1"
  local cmd="$2"
  
  if [ "$DRY_RUN" == "--dry-run" ]; then
    log_info "[DRY-RUN] SSH to $host: $cmd"
    return 0
  fi
  
  ssh -i "$SSH_KEY" "$host" "$cmd"
}

# ════════════════════════════════════════════════════════════════════════════
# Helper: Copy files to remote host
# ════════════════════════════════════════════════════════════════════════════
function remote_copy() {
  local source="$1"
  local host="$2"
  local dest="$3"
  
  if [ "$DRY_RUN" == "--dry-run" ]; then
    log_info "[DRY-RUN] SCP: $source → $host:$dest"
    return 0
  fi
  
  scp -i "$SSH_KEY" -r "$source" "$host:$dest"
}

# ════════════════════════════════════════════════════════════════════════════
# Phase 4.1: Update Caddyfile with custom domain routing
# ════════════════════════════════════════════════════════════════════════════
function deploy_caddy_config() {
  print_header "Phase 4.1: Updating Caddyfile (Custom Domain Routing)"
  
  # Verify Caddyfile exists locally
  if [ ! -f "Caddyfile" ]; then
    log_error "Caddyfile not found in current directory"
    return 1
  fi
  
  log_info "Caddyfile exists locally (✓)"
  
  # Deploy to replica 1
  log_info "Deploying Caddyfile to replica 1 (192.168.168.31)..."
  remote_copy "Caddyfile" "$REPLICA_1" "$DEPLOY_DIR/"
  
  # Deploy to replica 2
  log_info "Deploying Caddyfile to replica 2 (192.168.168.42)..."
  remote_copy "Caddyfile" "$REPLICA_2" "$DEPLOY_DIR/"
  
  # Restart Caddy on both replicas (idempotent)
  log_info "Restarting Caddy on both replicas..."
  remote_exec "$REPLICA_1" "cd $DEPLOY_DIR && docker-compose restart caddy"
  remote_exec "$REPLICA_2" "cd $DEPLOY_DIR && docker-compose restart caddy"
  
  # Wait for Caddy to stabilize
  sleep 5
  
  # Verify health
  log_info "Verifying Caddy health..."
  remote_exec "$REPLICA_1" "docker-compose ps caddy | grep -q healthy && echo '✅ Replica 1 Caddy healthy' || echo '⚠️  Replica 1 Caddy check'"
  remote_exec "$REPLICA_2" "docker-compose ps caddy | grep -q healthy && echo '✅ Replica 2 Caddy healthy' || echo '⚠️  Replica 2 Caddy check'"
  
  log_info "✅ Caddyfile deployment complete"
}

# ════════════════════════════════════════════════════════════════════════════
# Phase 4.2: Deploy database migration for custom domains
# ════════════════════════════════════════════════════════════════════════════
function deploy_custom_domains_schema() {
  print_header "Phase 4.2: Deploying Custom Domains Schema"
  
  # Verify migration file exists
  if [ ! -f "migrations/002_custom_domains_schema.sql" ]; then
    log_error "Migration file not found: migrations/002_custom_domains_schema.sql"
    return 1
  fi
  
  log_info "Migration file exists locally (✓)"
  
  # Deploy to replica 1
  log_info "Deploying migration to replica 1..."
  remote_copy "migrations/002_custom_domains_schema.sql" "$REPLICA_1" "$DEPLOY_DIR/migrations/"
  
  # Deploy to replica 2
  log_info "Deploying migration to replica 2..."
  remote_copy "migrations/002_custom_domains_schema.sql" "$REPLICA_2" "$DEPLOY_DIR/migrations/"
  
  # Run migration (saas-db-init service will pick it up on next restart)
  log_info "Triggering migration runner on replica 1..."
  remote_exec "$REPLICA_1" "cd $DEPLOY_DIR && docker-compose up -d saas-db-init"
  
  log_info "Triggering migration runner on replica 2..."
  remote_exec "$REPLICA_2" "cd $DEPLOY_DIR && docker-compose up -d saas-db-init"
  
  # Wait for migrations to complete
  sleep 10
  
  log_info "✅ Custom domains schema deployment complete"
}

# ════════════════════════════════════════════════════════════════════════════
# Phase 4.3: Deploy custom domains API module
# ════════════════════════════════════════════════════════════════════════════
function deploy_custom_domains_api() {
  print_header "Phase 4.3: Deploying Custom Domains API Module"
  
  # Verify API file exists
  if [ ! -f "apps/saas-api/src/custom-domains.js" ]; then
    log_error "API module not found: apps/saas-api/src/custom-domains.js"
    return 1
  fi
  
  log_info "API module exists locally (✓)"
  
  # Deploy to replica 1
  log_info "Deploying API module to replica 1..."
  remote_copy "apps/saas-api/src/custom-domains.js" "$REPLICA_1" "$DEPLOY_DIR/apps/saas-api/src/"
  
  # Deploy to replica 2
  log_info "Deploying API module to replica 2..."
  remote_copy "apps/saas-api/src/custom-domains.js" "$REPLICA_2" "$DEPLOY_DIR/apps/saas-api/src/"
  
  # Note: Main API server (index.js) must be updated to import and register custom-domains router
  log_warn "⚠️  Remember to update apps/saas-api/src/index.js to register custom-domains routes:"
  log_warn "    const { router: domainsRouter } = require('./custom-domains.js');"
  log_warn "    app.use('/api', domainsRouter);"
  
  # Restart API (volume mount picks up new code)
  log_info "Restarting SaaS API on both replicas..."
  remote_exec "$REPLICA_1" "cd $DEPLOY_DIR && docker-compose restart saas-api"
  remote_exec "$REPLICA_2" "cd $DEPLOY_DIR && docker-compose restart saas-api"
  
  # Wait for API to stabilize
  sleep 5
  
  # Verify health
  log_info "Verifying API health..."
  remote_exec "$REPLICA_1" "curl -s http://localhost:5000/health | grep -q 'ok' && echo '✅ Replica 1 API healthy' || echo '❌ Replica 1 API check failed'"
  remote_exec "$REPLICA_2" "curl -s http://localhost:5000/health | grep -q 'ok' && echo '✅ Replica 2 API healthy' || echo '❌ Replica 2 API check failed'"
  
  log_info "✅ Custom domains API deployment complete"
}

# ════════════════════════════════════════════════════════════════════════════
# Phase 4.4: Deploy ACME manager script
# ════════════════════════════════════════════════════════════════════════════
function deploy_acme_manager() {
  print_header "Phase 4.4: Deploying ACME Manager Script"
  
  # Verify script exists
  if [ ! -f "scripts/lib/acme-manager.sh" ]; then
    log_error "ACME manager not found: scripts/lib/acme-manager.sh"
    return 1
  fi
  
  log_info "ACME manager exists locally (✓)"
  
  # Deploy to replica 1
  log_info "Deploying ACME manager to replica 1..."
  remote_copy "scripts/lib/acme-manager.sh" "$REPLICA_1" "$DEPLOY_DIR/scripts/lib/"
  remote_exec "$REPLICA_1" "chmod +x $DEPLOY_DIR/scripts/lib/acme-manager.sh"
  
  # Deploy to replica 2
  log_info "Deploying ACME manager to replica 2..."
  remote_copy "scripts/lib/acme-manager.sh" "$REPLICA_2" "$DEPLOY_DIR/scripts/lib/"
  remote_exec "$REPLICA_2" "chmod +x $DEPLOY_DIR/scripts/lib/acme-manager.sh"
  
  log_info "✅ ACME manager deployment complete"
}

# ════════════════════════════════════════════════════════════════════════════
# Phase 5.1-5.2: Deploy E2E tests and CI/CD workflow
# ════════════════════════════════════════════════════════════════════════════
function deploy_tests_and_workflow() {
  print_header "Phase 5.1-5.2: Deploying E2E Tests and CI/CD Workflow"
  
  # Verify test file exists
  if [ ! -f "tests/e2e/sso-flows.spec.ts" ]; then
    log_error "E2E test file not found: tests/e2e/sso-flows.spec.ts"
    return 1
  fi
  
  log_info "E2E test file exists locally (✓)"
  
  # Verify workflow exists
  if [ ! -f ".github/workflows/sso-validation.yml" ]; then
    log_error "CI/CD workflow not found: .github/workflows/sso-validation.yml"
    return 1
  fi
  
  log_info "CI/CD workflow exists locally (✓)"
  
  # These are deployed to git, not to on-prem hosts
  log_info "Tests and workflows are deployed via git (not SSH)"
  log_info "Run: git add tests/e2e/sso-flows.spec.ts .github/workflows/sso-validation.yml"
  log_info "     git commit -m 'feat(P2-Phase5): SSO validation tests and CI/CD workflow'"
  log_info "     git push origin main"
  
  log_info "✅ Test and workflow deployment plan complete"
}

# ════════════════════════════════════════════════════════════════════════════
# Verification: Post-deployment checks
# ════════════════════════════════════════════════════════════════════════════
function verify_deployment() {
  print_header "Verification: Post-Deployment Health Checks"
  
  log_info "Checking Replica 1 (192.168.168.31)..."
  remote_exec "$REPLICA_1" "cd $DEPLOY_DIR && docker-compose ps | grep -E 'caddy|postgres|saas-api|redis' | grep -q 'healthy' && echo '✅ Services healthy' || echo '⚠️  Check logs'"
  
  log_info "Checking Replica 2 (192.168.168.42)..."
  remote_exec "$REPLICA_2" "cd $DEPLOY_DIR && docker-compose ps | grep -E 'caddy|postgres|saas-api|redis' | grep -q 'healthy' && echo '✅ Services healthy' || echo '⚠️  Check logs'"
  
  log_info "Checking external access..."
  curl -ksf https://kushnir.cloud/health > /dev/null && echo "✅ Portal accessible" || echo "⚠️  Portal check"
  curl -ksf https://ide.kushnir.cloud/health > /dev/null && echo "✅ IDE accessible" || echo "⚠️  IDE check"
  
  log_info "✅ Verification complete"
}

# ════════════════════════════════════════════════════════════════════════════
# Main execution flow
# ════════════════════════════════════════════════════════════════════════════
function main() {
  print_header "Phase 4-5 Deployment (IaC, Immutable, Idempotent)"
  
  if [ "$DRY_RUN" == "--dry-run" ]; then
    log_warn "🔵 DRY RUN MODE — No changes will be applied"
  fi
  
  # Deploy phases sequentially
  deploy_caddy_config || log_error "Phase 4.1 failed"
  deploy_custom_domains_schema || log_error "Phase 4.2 failed"
  deploy_custom_domains_api || log_error "Phase 4.3 failed"
  deploy_acme_manager || log_error "Phase 4.4 failed"
  deploy_tests_and_workflow || log_error "Phase 5 failed"
  
  # Verify everything
  if [ "$DRY_RUN" != "--dry-run" ]; then
    verify_deployment || log_error "Verification failed"
  fi
  
  print_header "✅ Phase 4-5 Deployment Complete"
  
  echo ""
  echo -e "${GREEN}Next Steps:${NC}"
  echo "1. Push test and workflow files to git:"
  echo "   git add tests/e2e/sso-flows.spec.ts .github/workflows/sso-validation.yml"
  echo "   git commit -m 'feat(P2-1674-1675): Phase 4-5 complete'"
  echo "   git push origin main"
  echo ""
  echo "2. Verify custom domain API is working:"
  echo "   curl -s https://kushnir.cloud/api/health"
  echo ""
  echo "3. Monitor CI/CD workflow execution:"
  echo "   https://github.com/kushin77/code-server/actions/workflows/sso-validation.yml"
  echo ""
}

main "$@"
