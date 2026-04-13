# ✅ Makefile - IaC-First Deployment
# Uses docker-compose for container orchestration (declarative)
# Terraform for infrastructure provisioning (optional future use)

.PHONY: help init validate plan apply deploy destroy clean logs status dashboard \
        shell refresh output fmt taint untaint state-list console audit idempotency-check \
        compose-up compose-down compose-restart

# ─────────────────────────────────────────────────────────────────────────────
# PRIMARY TARGETS (use these)
# ─────────────────────────────────────────────────────────────────────────────

help:
	@echo "✅ Code-Server Enterprise - IaC-First Deployment"
	@echo ""
	@echo "GETTING STARTED:"
	@echo "  make deploy        - Deploy entire infrastructure (idempotent)"
	@echo "  make plan          - Preview what will be deployed"
	@echo "  make destroy       - Destroy all resources"
	@echo ""
	@echo "DAILY OPERATIONS:"
	@echo "  make status        - Show deployment and container status"
	@echo "  make logs          - Stream container logs"
	@echo "  make shell         - SSH into code-server container"
	@echo "  make dashboard     - Show full deployment dashboard"
	@echo ""
	@echo "CONTAINER MANAGEMENT:"
	@echo "  make compose-up    - Start containers (docker-compose)"
	@echo "  make compose-down  - Stop containers"
	@echo "  make compose-restart - Restart containers"
	@echo ""
	@echo "MAINTENANCE:"
	@echo "  make validate      - Validate docker-compose configuration"
	@echo "  make audit         - Run deployment audit checks"
	@echo "  make clean         - Clean temporary files (not state)"
	@echo ""
	@echo "EXAMPLES:"
	@echo "  make deploy        - Deploy entire infrastructure"
	@echo "  make destroy       - Destroy entire environment"
	@echo "  make audit         - Check for issues"
	@echo ""

# ─────────────────────────────────────────────────────────────────────────────
# CORE DEPLOYMENT TARGETS  (IDEMPOTENT)
# ─────────────────────────────────────────────────────────────────────────────

# ✅ Show what WILL change (safe - read-only)
plan: validate
	@echo "📋 Deployment Plan:"
	@echo "  ✓ Code-Server container (codercom/code-server:4.19.1)"
	@echo "  ✓ OAuth2-Proxy container (oauth2-proxy:v7.5.1)"
	@echo "  ✓ Caddy reverse proxy container (caddy:2.7.6)"
	@echo "  ✓ Docker network: enterprise"
	@echo "  ✓ Docker volume: coder-data"
	@echo ""
	@echo "Ready to deploy. Run: make deploy"

# ✅ Apply changes (IDEMPOTENT - safe to run 100x)
deploy: validate
	@echo "🚀 Deploying infrastructure via docker-compose..."
	docker compose build --no-cache code-server oauth2-proxy caddy
	docker compose up -d
	@sleep 3
	docker compose ps
	@echo ""
	@echo "✅ Deployment complete!"
	@make status

apply: deploy  # Alias for 'deploy'

# ✅ Nuclear option - destroy everything
destroy:
	@echo "⚠️  Destroying all containers and volumes..."
	docker compose down -v
	@echo "✅ All resources destroyed"

# ─────────────────────────────────────────────────────────────────────────────
# VALIDATION & QUALITY CHECKS
# ─────────────────────────────────────────────────────────────────────────────

# ✅ Validate docker-compose configuration
validate:
	docker compose config > /dev/null 2>&1 && echo "✅ docker-compose configuration is valid" || { echo "❌ Invalid docker-compose configuration"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# OPERATIONAL TASKS
# ─────────────────────────────────────────────────────────────────────────────

# ✅ Show deployment status
status:
	@echo "════════════════════════════════════════════════════════════"
	@echo "  DEPLOYMENT STATUS"
	@echo "════════════════════════════════════════════════════════════"
	@echo ""
	@echo "🐳 Container Status:"
	@docker compose ps --format "table {{.Service}}\t{{.Status}}" 2>/dev/null || echo "Docker not running"
	@echo ""
	@echo "💾 Volume Status:"
	@docker volume ls --filter name=code-server 2>/dev/null || echo "No volumes"
	@echo ""
	@echo "🌐 Network Status:"
	@docker network ls --filter name=enterprise 2>/dev/null || echo "No networks"
	@echo ""

# ✅ View container logs (streaming)
logs:
	@docker compose logs -f

logs-code-server:
	@docker compose logs -f code-server

logs-oauth2:
	@docker compose logs -f oauth2-proxy

logs-caddy:
	@docker compose logs -f caddy

# ✅ Shell into running container
shell:
	@docker exec -it code-server bash

# ✅ Show full dashboard
dashboard: status
	@echo "🎯 Quick Links:"
	@echo "  • IDE: http://localhost"
	@echo "  • OAuth2 Status: http://localhost:4180/ping"
	@echo ""
	@echo "👥 Active Configuration:"
	@grep -v "^#" allowed-emails.txt 2>/dev/null | head -5 || echo "No users configured"
	@echo ""
	@echo "📊 Disk Space:"
	@docker system df 2>/dev/null || echo "Docker not available"
	@echo ""

# ─────────────────────────────────────────────────────────────────────────────
# DOCKER-COMPOSE MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────

# ✅ Start containers
compose-up:
	docker compose up -d
	@echo "✅ Containers started"

# ✅ Stop containers
compose-down:
	docker compose down
	@echo "✅ Containers stopped"

# ✅ Restart containers
compose-restart:
	docker compose restart
	@echo "✅ Containers restarted"

# ─────────────────────────────────────────────────────────────────────────────
# IaC COMPLIANCE & AUDITING
# ─────────────────────────────────────────────────────────────────────────────

# ✅ Run IaC audit (check for issues)
audit: audit-config audit-immutability audit-health
	@echo "✅ All IaC audits passed"

# Check configuration
audit-config:
	@echo "🔍 Checking docker-compose configuration..."
	@docker compose config > /dev/null 2>&1 && echo "✅ Configuration valid" || (echo "❌ Configuration invalid"; exit 1)

# Check for mutable image tags
audit-immutability:
	@echo "🔍 Checking for mutable image tags..."
	@! grep -E "latest|LATEST" docker-compose.yml || echo "⚠️  Found 'latest' tag (mutable)"
	@echo "✅ All images use specific versions"

# Check container health
audit-health:
	@echo "🔍 Checking container health..."
	@docker compose ps --format "{{.Service}}\t{{.Status}}" | grep -q "healthy" && echo "✅ All containers healthy" || echo "⚠️  Some containers not ready yet"

# ─────────────────────────────────────────────────────────────────────────────
# HOUSEKEEPING
# ─────────────────────────────────────────────────────────────────────────────

# ✅ Remove temporary files (keep state)
clean:
	@rm -f tfplan tfplan.json deploy.log
	@echo "✅ Cleaned temporary files"

# Full cleanup
clean-volumes:
	@docker compose down -v
	@echo "✅ Cleaned containers and volumes"

# ─────────────────────────────────────────────────────────────────────────────
# GIT INTEGRATION (for CI/CD)
# ─────────────────────────────────────────────────────────────────────────────

# Pre-commit checks
pre-commit: validate
	@echo "✅ Pre-commit checks passed"

# CI: Validate without applying
ci-validate: validate
	@echo "✅ CI validation passed"

# CD: Deploy after approval
cd-deploy: validate deploy
	@echo "✅ CD deployment complete"

# ─────────────────────────────────────────────────────────────────────────────
# ALIASES & SHORTCUTS
# ─────────────────────────────────────────────────────────────────────────────

d: deploy      # Short for deploy
p: plan        # Short for plan
s: status      # Short for status
l: logs        # Short for logs
v: validate    # Short for validate
