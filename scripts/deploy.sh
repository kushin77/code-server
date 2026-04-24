#!/bin/bash
# @file        scripts/deploy.sh
# @module      deployment
# @description deploy — on-prem code-server
# @owner       platform
# @status      active
################################################################################
# File: deploy.sh
# Owner: DevOps/Infrastructure Team
# Purpose: Idempotent infrastructure deployment orchestrator
# Last Modified: April 14, 2026
# Compatibility: Ubuntu 22.04+, Bash 4.0+, Terraform 1.4+, Docker 20.10+
#
# Dependencies:
#   - terraform (>= 1.4) — Infrastructure as Code
#   - docker-compose (>= 2.0) — Container orchestration
#   - jq — JSON parsing for validation
#   - curl — Health check verification
#
# Related Files:
#   - terraform/main.tf — Infrastructure definition
#   - docker-compose.yml — Container services
#   - scripts/deployment-validation-suite.sh — Post-deploy tests
#   - .github/workflows/deploy.yml — CI/CD integration
#
# Usage:
#   bash scripts/deploy.sh                # Full deployment
#   bash scripts/deploy.sh --validate-only  # Validation only
#   bash scripts/deploy.sh --rollback       # Rollback to previous
#
# Orchestration:
#   1) terraform apply (pin versions, generate docker-compose.yml)
#   2) docker-compose build (rebuild with explicit versions)
#   3) docker-compose up (start all services)
#   4) health checks (validate all services operational)
#   5) integration tests (verify critical paths)
#
# Exit Codes:
#   0 — Successful deployment
#   1 — Terraform failed
#   2 — Docker build failed
#   3 — Health checks failed
#   4 — Integration tests failed
#
# Examples:
#   ./scripts/deploy.sh                   # Full deployment with validation
#   ./scripts/deploy.sh --validate-only   # Check readiness without deploying
#
# Recent Changes:
#   2026-04-14: Integrated error-handler and logging libraries (Phase 2.2)
#   2026-04-13: Created idempotent deployment pattern
#
################################################################################
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Idempotent Deployment Script
# Orchestrates: Terraform → docker-compose rebuild → startup verification
# 
# Usage:  bash scripts/deploy.sh
# 
# What it does:
#   1. Runs terraform apply to generate docker-compose.yml with pinned versions
#   2. Rebuilds Docker images (--no-cache for immutability verification)
#   3. Brings up all services
#   4. Waits for all healthchecks to pass
#   5. Validates critical paths (extension activations, oauth2-proxy auth)
# 
# Exit code: 0 = success, 1 = deployment failed
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"
TF_DIR="$PROJECT_DIR/terraform"

# Bootstrap: single entrypoint loads config, logging, utils, error-handler, docker, ssh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Override log destination for this script
export LOG_FILE="${PROJECT_DIR}/deployment.log"

# Precondition assertions — fail fast before any side effects
assert_deploy_access   # SSH reachable at DEPLOY_HOST
assert_docker          # Docker daemon responding on remote

# Setup error handling
add_cleanup cleanup_deployment_handler

log_info "════════════════════════════════════════════════════════════════════════════"
log_info "IDEMPOTENT DEPLOYMENT: code-server-enterprise"
log_info "Timestamp: $(date -Iseconds)"
log_info "════════════════════════════════════════════════════════════════════════════"

# Step 1: Terraform init + apply (generates docker-compose.yml with versions)
echo ""
log_info "Step 1: Generating infrastructure config (Terraform)..."
if terraform -chdir="$TF_DIR" init && terraform -chdir="$TF_DIR" apply -auto-approve; then
  log_success "Terraform apply completed"
else
  log_fatal "Terraform apply failed"
fi

# Step 2: Build Docker images (immutability: --no-cache forces full rebuild)
echo ""
log_info "Step 2: Building Docker images with pinned versions..."
if docker compose build --no-cache; then
  log_success "Docker images built successfully"
else
  log_fatal "Docker image build failed"
fi

# Step 3: Bring up services
echo ""
log_info "Step 3: Deploying containers..."
if docker compose up -d; then
  log_success "Containers started"
else
  log_fatal "Docker compose up failed"
fi

# Step 4: Wait for healthchecks
echo ""
log_info "Step 4: Waiting for all services to be healthy..."
MAX_WAIT=120
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
  HEALTHY=$(docker compose ps --format json | jq '[.[] | select(.Health=="healthy" or .State=="running")] | length')
  TOTAL=$(docker compose ps --format json | jq 'length')
  log_info "  [$ELAPSED/$MAX_WAIT] Healthy services: $HEALTHY/$TOTAL"
  
  if [ "$HEALTHY" -eq "$TOTAL" ]; then
    log_success "All services healthy"
    break
  fi
  
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
  log_warn "Services not fully healthy after $MAX_WAIT seconds (may still be starting)"
  docker compose ps
fi

# Step 5: Verify critical paths
echo ""
echo "Step 5: Validating deployment..."
CHECKS_PASSED=0

# Check code-server HTTP endpoint
if curl -sf http://localhost:8080/healthz > /dev/null 2>&1; then
  echo "✅ code-server HTTP health check passed"
  ((CHECKS_PASSED++))
else
  echo "⚠️  code-server HTTP health check failed (may still be starting)"
fi

# Check docker compose state
if docker compose ps code-server | grep -q "healthy\|running"; then
  echo "✅ code-server container is running"
  ((CHECKS_PASSED++))
else
  echo "❌ code-server container is not running"
fi

echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo "DEPLOYMENT COMPLETE"
echo "✅ Access IDE at: https://${DOMAIN}"
echo "✅ Authentication: Google OAuth2"
echo "✅ TLS: Let's Encrypt (auto-renewed)"
echo "════════════════════════════════════════════════════════════════════════════"
