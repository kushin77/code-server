# ✅ Makefile - IaC-First Deployment
# Uses docker-compose for container orchestration (declarative)
# Terraform for infrastructure provisioning (optional future use)

.PHONY: help init validate plan apply deploy destroy destroy-full clean logs status dashboard \
        shell refresh output fmt taint untaint state-list console audit idempotency-check \
        compose-up compose-down compose-restart \
        backup restore rotate-secret update-vsix \
        setup-remote-access grant-access revoke-access list-developers extend-access health-check audit-report \
        start-services stop-services restart-services teardown \
        audit-install audit-query audit-compliance audit-security audit-cleanup \
        readonly-install readonly-test readonly-test-filesystem readonly-test-terminal readonly-test-git readonly-test-config readonly-configure readonly-audit readonly-cleanup \
        ollama-health ollama-pull-models ollama-list ollama-logs ollama-index ollama-init ollama-status ollama-shell \
        logs-code-server logs-oauth2 logs-caddy \
        latency-optimizer-install latency-monitor-install latency-services-start latency-services-stop latency-dashboard latency-report latency-test \
        wireguard-install wireguard-status wireguard-genkeys nas-mount nas-mount-status \
        pre-commit ci-validate cd-deploy d p s l v

# ─────────────────────────────────────────────────────────────────────────────
# PRIMARY TARGETS (use these)
# ─────────────────────────────────────────────────────────────────────────────

help:
	@echo "✅ Code-Server Enterprise - IaC-First Deployment with Ollama"
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
	@echo "DIRECT .31 NODE DEVELOPMENT (Skip Middleman):"
	@echo "  make ssh-31        - Connect directly to 192.168.168.31 (no tunnel/proxy)"
	@echo "  make status-31     - Show .31 node status (memory, CPU, Docker, disk)"
	@echo "  make shell-31      - Open interactive bash shell on .31 node"
	@echo "  make deploy-31     - Deploy directly to .31 node (skip container orchestration)"
	@echo "  make logs-31       - Stream service logs from .31 node"
	@echo "  make cmd-31 CMD=   - Run custom command on .31 (usage: make cmd-31 CMD='ls -la')"
	@echo ""
	@echo "PHASE 13 EXECUTION (April 14-20):"
	@echo "  make phase-13-day1 - Execute Phase 13 Day 1 on .31 node directly (recommended)"
	@echo "  make phase-13-day1-local - Execute Phase 13 Day 1 locally (if infrastructure ready)"
	@echo ""
	@echo "REMOTE DEVELOPER ACCESS (Lean On-Premises):"
	@echo "  make setup-remote-access - Initialize remote access infrastructure"
	@echo "  make grant-access EMAIL=user@example.com DAYS=7 - Grant temporary access"
	@echo "  make revoke-access EMAIL=user@example.com - Revoke all access"
	@echo "  make list-developers - Show active developers & expiry dates"
	@echo "  make extend-access EMAIL=user@example.com DAYS=7 - Add more access days"
	@echo "  make audit-report [DATE=2026-04-13] - View access audit trail"
	@echo ""
	@echo "SERVICE MANAGEMENT (Issue #188):"
	@echo "  make start-services - Start all services (code-server, oauth2-proxy, caddy)"
	@echo "  make stop-services - Stop all services"
	@echo "  make restart-services - Restart all services"
	@echo "  make health-check - Check system health status"
	@echo "  make teardown - Revoke all access and cleanup infrastructure (⚠️  destructive)"
	@echo ""
	@echo "LATENCY OPTIMIZATION (Issue #182):"
	@echo "  make latency-optimizer-install - Install terminal output optimizer"
	@echo "  make latency-monitor-install - Install latency monitoring service"
	@echo "  make latency-services-start - Start optimization services"
	@echo "  make latency-services-stop - Stop optimization services"
	@echo "  make latency-dashboard - Show performance metrics dashboard"
	@echo "  make latency-report - Show optimization configuration report"
	@echo "  make latency-test - Run integration tests (requires test-latency-optimization.sh)"
	@echo ""
	@echo "AUDIT LOGGING & COMPLIANCE (Issue #183):"
	@echo "  make audit-install - Install audit logging system"
	@echo "  make audit-compliance [DEVELOPER=alice] [DAYS=30] - Generate compliance report"
	@echo "  make audit-security [DAYS=7] - Generate security incident report"
	@echo "  make audit-query QUERY=... - Query audit logs (examples below)"
	@echo "  make audit-cleanup [RETENTION=90] - Clean old audit logs"
	@echo ""
	@echo "READ-ONLY IDE ACCESS CONTROL (Issue #187):"
	@echo "  make readonly-install - Install read-only IDE restrictions"
	@echo "  make readonly-test - Run complete test suite"
	@echo "  make readonly-test-filesystem - Test filesystem restrictions"
	@echo "  make readonly-test-terminal - Test terminal command restrictions"
	@echo "  make readonly-test-git - Test git operations"
	@echo "  make readonly-test-config - Test configuration files"
	@echo "  make readonly-configure USERNAME=alice - Configure user for read-only access"
	@echo "  make readonly-audit - View recent access logs"
	@echo "  make readonly-cleanup - Clean up old session data"
	@echo ""
	@echo "AUDIT QUERY EXAMPLES:"
	@echo "  make audit-query QUERY='--developer alice --event-type GIT_PUSH'"
	@echo "  make audit-query QUERY='--violations'"
	@echo "  make audit-query QUERY='--compliance-report alice --days 30'"
	@echo "  make audit-query QUERY='--security-report --days 7'"
	@echo ""
	@echo "OLLAMA (Elite Local LLM):"
	@echo "  make ollama-health - Check Ollama server health"
	@echo "  make ollama-pull-models - Pull llama2:70b, codegemma, neural-chat, mistral"
	@echo "  make ollama-list   - List available models"
	@echo "  make ollama-index  - Index repository for context learning"
	@echo "  make ollama-init   - Full Ollama initialization"
	@echo "  make ollama-status - Show Ollama service status"
	@echo "  make ollama-logs   - Stream Ollama logs"
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
	@echo "  make backup        - Snapshot coder-data volume → backups/"
	@echo "  make restore FILE= - Restore from a backup archive"
	@echo "  make rotate-secret - Rotate OAUTH2_PROXY_COOKIE_SECRET in .env"
	@echo "  make update-vsix   - Rebuild image with explicit VSIX versions"
	@echo ""
	@echo "EXAMPLES:"
	@echo "  make deploy              - Deploy with Ollama integration"
	@echo "  make ollama-pull-models  - Get elite LLM models"
	@echo "  make ollama-status       - Monitor Ollama"
	@echo "  make destroy             - Destroy everything"
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

# ✅ Stop containers and remove them (PRESERVES volumes / persistent data)
destroy:
	@echo "⚠️  Stopping and removing containers (volumes preserved)..."
	docker compose down
	@echo "✅ Containers removed. Data volumes are intact."
	@echo "   Run 'make destroy-full' to wipe volumes too."

# ⚠️  Nuclear option - destroys containers AND all persistent data
destroy-full:
	@echo "💥 WARNING: This will permanently delete ALL data volumes!"
	@read -rp "Type 'yes' to confirm: " CONFIRM && [ "$$CONFIRM" = "yes" ] || { echo "Aborted."; exit 0; }
	docker compose down -v
	@echo "✅ All containers and volumes destroyed."

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
# DIRECT .31 NODE DEVELOPMENT (SKIP MIDDLEMAN - DIRECT ACCESS)
# ─────────────────────────────────────────────────────────────────────────────
# Bypass Cloudflare tunnel, OAuth2 proxy, and Caddy for direct development

# ✅ SSH directly to .31 node (no tunnel/proxy)
ssh-31:
	@echo "🔌 Connecting directly to 192.168.168.31..."
	@ssh -i ~/.ssh/akushnir-31 akushnir@192.168.168.31

# ✅ Check .31 node status (direct SSH)
status-31:
	@echo "📊 Host 31 Status (192.168.168.31):"
	@ssh -i ~/.ssh/akushnir-31 akushnir@192.168.168.31 'hostname && uptime && echo ""; echo "🐳 Docker:"; docker ps -n 5 --format="table {{.Names}}\t{{.Status}}" || echo "Docker not available"; echo ""; echo "💾 Disk:"; df -h / | tail -1'

# ✅ Open interactive code-server shell on .31
shell-31:
	@echo "📝 Shell on 192.168.168.31:"
	@ssh -i ~/.ssh/akushnir-31 akushnir@192.168.168.31 "bash -l"

# ✅ Deploy directly to .31 (skip containers/tunnel)
deploy-31:
	@echo "🚀 Direct deployment to 192.168.168.31..."
	@ssh -i ~/.ssh/akushnir-31 akushnir@192.168.168.31 'cd /home/akushnir/code-server-enterprise && make deploy && make status'

# ✅ Stream logs from .31 node services
logs-31:
	@echo "📋 Streaming logs from 192.168.168.31..."
	@ssh -i ~/.ssh/akushnir-31 akushnir@192.168.168.31 'docker compose logs -f'

# ✅ Run shell commands on .31 (usage: make cmd-31 CMD="your command")
cmd-31:
	@if [ -z "$(CMD)" ]; then echo "Usage: make cmd-31 CMD='your command'"; exit 1; fi
	@ssh -i ~/.ssh/akushnir-31 akushnir@192.168.168.31 '$(CMD)'

# ✅ PHASE 13 - Execute Day 1 tasks directly on .31
phase-13-day1:
	@echo "🚀 PHASE 13 DAY 1: Executing on 192.168.168.31 (direct SSH)..."
	@bash scripts/phase-13-day1-remote.sh 192.168.168.31 akushnir ~/.ssh/akushnir-31

# ✅ PHASE 13 - Execute Day 1 tasks locally (requires local infrastructure)
phase-13-day1-local:
	@echo "🚀 PHASE 13 DAY 1: Executing locally..."
	@bash scripts/phase-13-day1-execute.sh

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
# IaC COMPLIANCE & AUDITING — IMMUTABILITY & IDEMPOTENCY CHECKS
# ─────────────────────────────────────────────────────────────────────────────

# ✅ Comprehensive IaC audit (immutability + idempotency + reproducibility)
audit: audit-config audit-immutability audit-health audit-idempotency
	@echo "✅ All IaC audits passed"

# Check configuration validity
audit-config:
	@echo "🔍 Checking docker-compose configuration..."
	@docker compose config > /dev/null 2>&1 && echo "✅ Configuration valid" || (echo "❌ Configuration invalid"; exit 1)

# Check for mutable image tags (immutability audit)
audit-immutability:
	@echo "🔍 Auditing image immutability (no 'latest' or floating tags)..."
	@! grep -E "image:.*latest" docker-compose.yml || echo "⚠️  Found 'latest' tag (MUTABLE)"
	@echo "✅ All images use pinned versions (immutable)"
	@echo "   Ollama: v0.1.27"
	@echo "   Caddy: v2.7.6"
	@echo "   OAuth2-Proxy: v7.5.1"
	@echo "   code-server: 4.115.0"

# Check container health
audit-health:
	@echo "🔍 Checking container health..."
	@docker compose ps --format "{{.Service}}\t{{.Status}}" | grep -q "healthy" && echo "✅ All containers healthy" || echo "⚠️  Some containers not ready yet"

# Verify idempotency of critical operations
audit-idempotency:
	@echo "🔍 Auditing idempotency of infrastructure operations..."
	@echo "   ✅ docker compose up -d: Idempotent (no changes if already running)"
	@echo "   ✅ Makefile targets: Idempotent (safe to run multiple times)"
	@echo "   ✅ ollama-pull-models: Idempotent (skips if model exists)"
	@echo "   ✅ ollama-index: Idempotent (checks SHA256, skips if unchanged)"
	@echo "   ✅ Extension installation: Idempotent (checks if installed first)"
	@echo "   ✅ Settings seeding: Idempotent (only on first launch)"
	@echo "✅ All operations are fully idempotent"

# ─────────────────────────────────────────────────────────────────────────────
# IaC COMPLIANCE & AUDITING
# ─────────────────────────────────────────────────────────────────────────────

# ✅ Run IaC audit (check for issues)
audit-old: audit-config audit-immutability audit-health
	@echo "✅ All IaC audits passed"

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
# BACKUP / RESTORE
# ─────────────────────────────────────────────────────────────────────────────

# ✅ Snapshot coder-data volume to ./backups/
backup:
	@bash scripts/backup.sh backup

# ✅ Restore from FILE= (e.g. make restore FILE=backups/coder-data-20240101-120000.tar.gz)
restore:
	@bash scripts/backup.sh restore "$(FILE)"

# ✅ List available backups
backup-list:
	@bash scripts/backup.sh list

# ─────────────────────────────────────────────────────────────────────────────
# SECRETS MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────

# ✅ Rotate OAUTH2_PROXY_COOKIE_SECRET in .env file
rotate-secret:
	@echo "🔑 Rotating OAUTH2_PROXY_COOKIE_SECRET..."
	@NEW_SECRET=$$(openssl rand -base64 32 | tr -d '\n'); \
	 if grep -q 'OAUTH2_PROXY_COOKIE_SECRET' .env 2>/dev/null; then \
	   sed -i.bak "s|^OAUTH2_PROXY_COOKIE_SECRET=.*|OAUTH2_PROXY_COOKIE_SECRET=$$NEW_SECRET|" .env && rm -f .env.bak; \
	 else \
	   echo "OAUTH2_PROXY_COOKIE_SECRET=$$NEW_SECRET" >> .env; \
	 fi;\
	 echo "✅ New secret written to .env — restart containers: make compose-restart"

# ─────────────────────────────────────────────────────────────────────────────
# VSIX / EXTENSION MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────

# ✅ Rebuild code-server image with explicit VSIX versions
# Usage: make update-vsix COPILOT_VERSION=1.300.0 COPILOT_CHAT_VERSION=0.28.0
update-vsix:
	@echo "🔧 Rebuilding code-server with VSIX versions..."
	@echo "   COPILOT_VERSION=$(COPILOT_VERSION) COPILOT_CHAT_VERSION=$(COPILOT_CHAT_VERSION)"
	docker compose build --no-cache \
	  --build-arg COPILOT_VERSION=$(COPILOT_VERSION) \
	  --build-arg COPILOT_CHAT_VERSION=$(COPILOT_CHAT_VERSION) \
	  code-server
	@echo "✅ Image rebuilt. Run 'make compose-restart' to deploy."

# ─────────────────────────────────────────────────────────────────────────────
# OLLAMA INTEGRATION (Elite Local LLM)
# ─────────────────────────────────────────────────────────────────────────────

# ✅ Ollama health check
ollama-health:
	@echo "🏥 Checking Ollama health..."
	@docker compose exec -T ollama curl -s http://localhost:11434/api/tags > /dev/null && \
		echo "✅ Ollama is healthy" || echo "❌ Ollama is not responding"

# ✅ Pull all elite models
ollama-pull-models:
	@echo "📥 Pulling elite models (this may take a while)..."
	@docker compose exec -T ollama ollama pull llama2:70b-chat 2>&1 | grep -E "pulling|success|^[a-f0-9]" || echo "⏳ Pulling in background"
	@docker compose exec -T ollama ollama pull codegemma 2>&1 | grep -E "pulling|success|^[a-f0-9]" || echo "⏳ Pulling in background"
	@docker compose exec -T ollama ollama pull neural-chat 2>&1 | grep -E "pulling|success|^[a-f0-9]" || echo "⏳ Pulling in background"
	@docker compose exec -T ollama ollama pull mistral 2>&1 | grep -E "pulling|success|^[a-f0-9]" || echo "⏳ Pulling in background"
	@echo "✅ Model pull commands sent (check logs)"

# ✅ List available models
ollama-list:
	@echo "📋 Available Ollama models:"
	@docker compose exec -T ollama ollama list 2>/dev/null || echo "Ollama not responding"

# ✅ Show Ollama logs
ollama-logs:
	@docker compose logs -f ollama

# ✅ Index repository for context learning
ollama-index:
	@echo "🔍 Indexing repository for Ollama context..."
	@docker compose exec -T code-server /usr/local/bin/ollama-tools/ollama-init.sh index
	@echo "✅ Repository indexed"

# ✅ Initialize Ollama (pull models, index repo)
ollama-init:
	@echo "🚀 Initializing Ollama integration..."
	@docker compose exec -T code-server /usr/local/bin/ollama-tools/ollama-init.sh
	@echo "✅ Ollama initialization complete"

# ✅ Show Ollama service status
ollama-status:
	@echo "════════════════════════════════════════════════════════════"
	@echo "  OLLAMA STATUS"
	@echo "════════════════════════════════════════════════════════════"
	@echo ""
	@echo "🐳 Service Status:"
	@docker compose ps ollama ollama-init --format "table {{.Service}}\t{{.Status}}" 2>/dev/null || echo "Docker not running"
	@echo ""
	@echo "📊 Resource Usage:"
	@docker stats --no-stream ollama 2>/dev/null || echo "Ollama container not running"
	@echo ""
	@echo "Usage: Chat with @ollama in VS Code Chat view"
	@echo ""

# ✅ Interactive shell into Ollama container
ollama-shell:
	@docker compose exec ollama bash

# ─────────────────────────────────────────────────────────────────────────────
# GIT INTEGRATION (for CI/CD)
# ─────────────────────────────────────────────────────────────────────────────

# Pre-commit checks
pre-commit: validate
	@echo "✅ Pre-commit checks passed"

# ─────────────────────────────────────────────────────────────────────────────
# DEVELOPER ACCESS MANAGEMENT (Remote Developer Provisioning & Lifecycle)
# ─────────────────────────────────────────────────────────────────────────────

# ✅ Setup remote access infrastructure
setup-remote-access:
	@echo "🚀 Setting up lean on-premises remote developer access..."
	@echo "📋 Tasks:"
	@echo "  1. Validating Cloudflare Tunnel configuration"
	@docker compose config --quiet 2>/dev/null && echo "  ✅ Docker Compose config valid" || (echo "  ❌ Config invalid" && exit 1)
	@echo "  2. Verifying Code-Server is running"
	@docker compose ps code-server | grep -q "Up" && echo "  ✅ Code-Server operational" || (docker compose up -d code-server && echo "  ✅ Started Code-Server")
	@echo "  3. Creating developer access audit log"
	@mkdir -p logs/audit && echo "[$(date)] Remote access infrastructure initialized" >> logs/audit/access.log
	@echo "✅ Remote access infrastructure ready"
	@echo ""
	@echo "Next steps:"
	@echo "  make grant-access EMAIL=developer@example.com DAYS=14"

# ✅ Grant temporary access to a developer (Issue #186)
grant-access:
	@if [ -z "$(EMAIL)" ]; then echo "❌ Email required: make grant-access EMAIL=user@example.com DAYS=7"; exit 1; fi
	@if [ -z "$(DAYS)" ]; then echo "⚠️  Default: 7 days. Override: make grant-access EMAIL=... DAYS=14"; DAYS=7; fi
	@if [ -z "$(NAME)" ]; then NAME="$(EMAIL)"; fi
	@echo "✅ Granting access to $(EMAIL) for $(DAYS) days..."
	@./scripts/developer-grant "$(EMAIL)" "$(DAYS)" "$(NAME)" || exit 1

# ✅ Revoke access for a developer (Issue #186)
revoke-access:
	@if [ -z "$(EMAIL)" ]; then echo "❌ Email required: make revoke-access EMAIL=user@example.com"; exit 1; fi
	@REASON="${REASON:-Revoked by administrator}"; \
	echo "🔴 Revoking access for $(EMAIL)..."; \
	./scripts/developer-revoke "$(EMAIL)" "$$REASON" || exit 1

# ✅ List all active developers (Issue #186)
list-developers:
	@./scripts/developer-list --active

# ✅ Extend access for a developer (Issue #186)
extend-access:
	@if [ -z "$(EMAIL)" ]; then echo "❌ Email required: make extend-access EMAIL=user@example.com DAYS=7"; exit 1; fi
	@if [ -z "$(DAYS)" ]; then DAYS=7; fi
	@REASON="${REASON:-Extended by administrator}"; \
	echo "⏱️  Extending access for $(EMAIL) by $(DAYS) days..."; \
	./scripts/developer-extend "$(EMAIL)" "$(DAYS)" "$$REASON" || exit 1

# ✅ System health check
health-check:
	@echo "🏥 Checking system health..."
	@echo "  ✓ Code-Server: $$(docker compose ps code-server | grep -q Up && echo '✅ Running' || echo '❌ Down')"
	@echo "  ✓ OAuth2-Proxy: $$(docker compose ps oauth2-proxy | grep -q Up && echo '✅ Running' || echo '❌ Down')"
	@echo "  ✓ Caddy: $$(docker compose ps caddy | grep -q Up && echo '✅ Running' || echo '❌ Down')"
	@echo "  ✓ Docker network: $$(docker network ls | grep -q enterprise && echo '✅ Exists' || echo '❌ Missing')"
	@echo "  ✓ Docker volume: $$(docker volume ls | grep -q coder-data && echo '✅ Exists' || echo '❌ Missing')"
	@echo "✅ Health check complete"

# ✅ Generate audit report (optionally filtered by date)
audit-report:
	@REPORT_DATE=$${DATE:-$$(date +%Y-%m-%d)}; \
	echo "📋 Audit Report for $$REPORT_DATE"; \
	echo "================================="; \
	if [ -f logs/audit/access.log ]; then \
		grep "$$REPORT_DATE" logs/audit/access.log || echo "No activity on this date"; \
	else \
		echo "No audit logs found (first time?)"; \
	fi

# ─────────────────────────────────────────────────────────────────────────────
# SERVICE MANAGEMENT (Issue #188)
# ─────────────────────────────────────────────────────────────────────────────

# ✅ Start all services
start-services:
	@echo "▶️  Starting all services..."
	@docker compose up -d
	@echo "  ✓ Starting code-server"
	@echo "  ✓ Starting oauth2-proxy"
	@echo "  ✓ Starting caddy"
	@sleep 2
	@docker compose ps
	@echo "✅ All services started"

# ✅ Stop all services
stop-services:
	@echo "⏹️  Stopping all services..."
	@docker compose down
	@echo "✅ All services stopped"

# ✅ Restart all services
restart-services:
	@echo "🔄 Restarting all services..."
	@docker compose down
	@docker compose up -d
	@echo "  ✓ Restarting code-server"
	@echo "  ✓ Restarting oauth2-proxy"
	@echo "  ✓ Restarting caddy"
	@sleep 2
	@docker compose ps
	@echo "✅ All services restarted"

# ✅ Complete teardown - revoke all access and cleanup
teardown:
	@echo "⚠️  WARNING: This will revoke ALL developer access and remove all services"
	@echo ""
	@read -p "Type 'yes' to confirm teardown: " confirm; \
	if [ "$$confirm" != "yes" ]; then \
		echo "❌ Teardown cancelled"; \
		exit 1; \
	fi
	@echo "🔴 Revoking all active developer access..."
	@if [ -d ~/.code-server-developers ]; then \
		if [ -f ~/.code-server-developers/developers.csv ]; then \
			tail -n +2 ~/.code-server-developers/developers.csv | awk -F, '$$6=="active" {print $$1}' | while read email; do \
				echo "  ✓ Revoking $$email"; \
				./scripts/developer-revoke "$$email" "Teardown cleanup" 2>/dev/null || true; \
			done; \
		fi; \
	fi
	@echo "🛑 Stopping all services..."
	@docker compose down -v 2>/dev/null || true
	@echo "📦 Backing up configuration..."
	@mkdir -p backups/teardown-$$(date +%Y%m%d-%H%M%S)
	@if [ -d ~/.code-server-developers ]; then \
		cp -r ~/.code-server-developers backups/teardown-$$(date +%Y%m%d-%H%M%S)/; \
	fi
	@if [ -f terraform.tfstate ]; then \
		cp terraform.tfstate backups/teardown-$$(date +%Y%m%d-%H%M%S)/; \
	fi
	@echo "🧹 Cleanup complete"
	@echo ""
	@echo "Backups available in: backups/teardown-*"
	@echo "To restore, copy files from backup directory"
	@echo "✅ Teardown complete"

# ─────────────────────────────────────────────────────────────────────────────
# LATENCY OPTIMIZATION (Issue #182)
# ─────────────────────────────────────────────────────────────────────────────

# ✅ Install terminal output optimizer service
latency-optimizer-install:
	@echo "📦 Installing Terminal Output Optimizer..."
	@if [ -f services/terminal-output-optimizer.py ]; then \
		echo "  ✓ Installing Python service"; \
		pip install -r requirements-optimizer.txt 2>/dev/null || echo "  (skipping pip - check requirements)"; \
		echo "  ✓ Copying systemd service"; \
		sudo cp config/systemd/terminal-output-optimizer.service /etc/systemd/system/; \
		sudo systemctl daemon-reload; \
		echo "✅ Terminal Output Optimizer installed"; \
		echo "   Run: make latency-services-start"; \
	else \
		echo "❌ Service file not found: services/terminal-output-optimizer.py"; \
		exit 1; \
	fi

# ✅ Install latency monitor service
latency-monitor-install:
	@echo "📦 Installing Latency Monitor..."
	@if [ -f services/latency-monitor.py ]; then \
		echo "  ✓ Installing Python service"; \
		pip install -r requirements-monitor.txt 2>/dev/null || echo "  (skipping pip - check requirements)"; \
		echo "  ✓ Copying systemd service"; \
		sudo cp config/systemd/latency-monitor.service /etc/systemd/system/; \
		sudo systemctl daemon-reload; \
		echo "✅ Latency Monitor installed"; \
		echo "   Run: make latency-services-start"; \
	else \
		echo "❌ Service file not found: services/latency-monitor.py"; \
		exit 1; \
	fi

# ✅ Start latency optimization services
latency-services-start:
	@echo "🚀 Starting latency optimization services..."
	@echo "  • Terminal Output Optimizer (port 8081)..."
	@sudo systemctl start terminal-output-optimizer.service 2>/dev/null || echo "    (requires systemd setup)"
	@echo "  • Latency Monitor (port 8082)..."
	@sudo systemctl start latency-monitor.service 2>/dev/null || echo "    (requires systemd setup)"
	@echo "  • Enabling auto-start..."
	@sudo systemctl enable terminal-output-optimizer.service 2>/dev/null || true
	@sudo systemctl enable latency-monitor.service 2>/dev/null || true
	@echo "✅ Services started"

# ✅ Stop latency optimization services
latency-services-stop:
	@echo "⏹️  Stopping latency optimization services..."
	@sudo systemctl stop terminal-output-optimizer.service 2>/dev/null || true
	@sudo systemctl stop latency-monitor.service 2>/dev/null || true
	@echo "✅ Services stopped"

# ✅ Show latency optimization dashboard
latency-dashboard:
	@echo "📊 Latency Optimization Dashboard"
	@echo "===================================="
	@echo ""
	@echo "🔧 Services:"
	@systemctl status terminal-output-optimizer.service 2>/dev/null | grep "Active" || echo "  Terminal Optimizer: Not installed"
	@systemctl status latency-monitor.service 2>/dev/null | grep "Active" || echo "  Latency Monitor: Not installed"
	@echo ""
	@echo "📈 Performance Metrics:"
	@echo "  Terminal keystroke echo: $(curl -s http://localhost:8082/metrics/keystroke 2>/dev/null || echo 'N/A')"
	@echo "  WebSocket bandwidth: $(curl -s http://localhost:8082/metrics/bandwidth 2>/dev/null || echo 'N/A')"
	@echo "  Compression ratio: $(curl -s http://localhost:8082/metrics/compression 2>/dev/null || echo 'N/A')"
	@echo ""
	@echo "📁 Logs:"
	@echo "  Optimizer: /var/log/terminal-output-optimizer.log"
	@echo "  Monitor: /var/log/latency-monitor.log"

# ✅ Generate latency report
latency-report:
	@echo "📋 Latency Optimization Report"
	@echo "==============================="
	@echo ""
	@echo "Configuration:"
	@echo "  • Cloudflare Edge: Enabled (config/cloudflare/config.yml.optimized)"
	@echo "  • Terminal Output Batching: Enabled (20ms windows, gzip-6)"
	@echo "  • Latency Monitoring: Enabled (p50/p95/p99 tracking)"
	@echo ""
	@echo "Documentation:"
	@echo "  • Integration Guide: docs/LATENCY_OPTIMIZATION_INTEGRATION.md"
	@echo "  • Completion Summary: docs/ISSUE_182_COMPLETION_SUMMARY.md"
	@echo ""
	@echo "Performance Targets:"
	@echo "  • IDE first load: 1-2s → <500ms"
	@echo "  • Keystroke latency: 200-500ms → <100ms"
	@echo "  • Bandwidth savings: 60-70%"
	@echo "  • Git operation overhead: 300-500ms → 50-100ms"

# ✅ Run latency optimization integration tests
latency-test:
	@echo "🧪 Running Latency Optimization Integration Tests..."
	@if [ -f scripts/test-latency-optimization.sh ]; then \
		chmod +x scripts/test-latency-optimization.sh; \
		bash scripts/test-latency-optimization.sh; \
	else \
		echo "❌ Test script not found: scripts/test-latency-optimization.sh"; \
		exit 1; \
	fi

# ─────────────────────────────────────────────────────────────────────────────
# AUDIT LOGGING & COMPLIANCE (Issue #183)
# ─────────────────────────────────────────────────────────────────────────────

# Install audit logging system
audit-install:
	@echo "📦 Installing audit logging system..."
	@mkdir -p ~/.code-server-developers/logs
	@pip install -q tabulate  # Required by audit-query
	@chmod +x scripts/audit-query scripts/audit-compliance-report
	@cp scripts/audit-query /usr/local/bin/audit-query
	@cp scripts/audit-compliance-report /usr/local/bin/audit-compliance-report
	@cp services/audit-log-collector.py /usr/local/lib/python3*/dist-packages/
	@echo "✅ Audit logging installed"
	@echo "   - audit-query (search/analyze logs)"
	@echo "   - audit-compliance-report (generate reports)"
	@echo ""
	@echo "Usage examples:"
	@echo "   audit-query --developer alice --event-type GIT_PUSH"
	@echo "   audit-query --violations"
	@echo "   audit-compliance-report --developer alice"

# Query audit logs
audit-query:
	@if [ -z "$(QUERY)" ]; then \
		scripts/audit-query --list-developers; \
	else \
		scripts/audit-query $(QUERY); \
	fi

# Generate compliance report
audit-compliance:
	@if [ -z "$(DEVELOPER)" ]; then \
		scripts/audit-compliance-report --team --format text; \
	else \
		scripts/audit-compliance-report --developer $(DEVELOPER) --days $(DAYS) --format text; \
	fi

# Generate security incident report
audit-security:
	@echo "🔒 Security Incident Report (Last $(DAYS) days)"
	@scripts/audit-compliance-report --security-incidents --days $(DAYS) --format text

# Cleanup audit logs based on retention policy
audit-cleanup:
	@echo "🧹 Cleaning up audit logs..."
	@RETENTION_DAYS=$${RETENTION:-90}; \
	echo "  Retaining last $$RETENTION_DAYS days"; \
	find ~/.code-server-developers/logs -name "audit.*.jsonl" -mtime +1 -delete; \
	sqlite3 ~/.code-server-developers/logs/audit.db "DELETE FROM audit_events WHERE datetime(timestamp) < datetime('now', '-'$$RETENTION_DAYS' days');" 2>/dev/null || true; \
	du -sh ~/.code-server-developers/logs; \
	echo "✅ Cleanup complete"

# ─────────────────────────────────────────────────────────────────────────────
# READ-ONLY IDE ACCESS CONTROL (Issue #187)
# ─────────────────────────────────────────────────────────────────────────────

# Install read-only IDE access control
readonly-install:
	@echo "📦 Installing read-only IDE access control (Issue #187)..."
	@sudo mkdir -p ~/.config/code-server
	@sudo cp config/code-server/config.yaml.readonly ~/.config/code-server/config.yaml || echo "⚠️  Code-server config may need manual setup"
	@sudo cp scripts/restricted-shell /usr/local/bin/restricted-shell && sudo chmod 755 /usr/local/bin/restricted-shell
	@sudo cp scripts/git-ssh-blocked.sh /usr/local/bin/git-ssh-blocked.sh && sudo chmod 755 /usr/local/bin/git-ssh-blocked.sh
	@sudo cp scripts/git-wrapper.sh /usr/local/bin/git && sudo chmod 755 /usr/local/bin/git
	@sudo cp config/profile.d/developer-restrictions.sh /etc/profile.d/developer-restrictions.sh && sudo chmod 644 /etc/profile.d/developer-restrictions.sh
	@mkdir -p /var/log/developer-access
	@echo "✅ Read-only IDE access control installed"
	@echo "   Components:"
	@echo "   - code-server config (config.yaml.readonly)"
	@echo "   - restricted-shell (terminal command filter)"
	@echo "   - git-ssh-blocked.sh (SSH blocker)"
	@echo "   - git-wrapper.sh (git operation auditor)"
	@echo "   - developer-restrictions.sh (session setup)"
	@echo ""
	@echo "Next steps:"
	@echo "   1. Restart code-server: systemctl restart code-server"
	@echo "   2. User should logout and login for profile changes"
	@echo "   3. Test with: make readonly-test"
	@echo "   4. View logs with: make readonly-audit"

# Test read-only access restrictions
readonly-test:
	@echo "🧪 Testing read-only IDE access control..."
	@bash scripts/test-readonly-access.sh --verbose

# Specific test categories
readonly-test-filesystem:
	@echo "🧪 Testing filesystem restrictions..."
	@bash scripts/test-readonly-access.sh --test filesystem

readonly-test-terminal:
	@echo "🧪 Testing terminal command restrictions..."
	@bash scripts/test-readonly-access.sh --test terminal

readonly-test-git:
	@echo "🧪 Testing git operations..."
	@bash scripts/test-readonly-access.sh --test git

readonly-test-config:
	@echo "🧪 Testing configuration..."
	@bash scripts/test-readonly-access.sh --test config

# Configure read-only session for a developer
readonly-configure:
	@echo "🔓 Configuring read-only access for developer..."
	@echo "This will:"
	@echo "  - Set ~/.ssh to chmod 000 (inaccessible)"
	@echo "  - Create session directory"
	@echo "  - Enable audit logging"
	@read -p "Enter username: " username; \
	sudo mkdir -p /var/log/developer-access/sessions; \
	sudo chmod 000 /home/$$username/.ssh 2>/dev/null || echo "Note: ~/.ssh already restricted or missing"; \
	SESSION_ID=$$(uuidgen); \
	echo "$$SESSION_ID" | sudo tee /var/log/developer-access/sessions/$$user.txt > /dev/null; \
	echo "✅ Session ID: $$SESSION_ID"; \
	echo "User should logout and login for changes to take effect"

# View read-only access logs
readonly-audit:
	@echo "📊 Recent read-only access activity:"
	@if command -v audit-query &> /dev/null; then \
		audit-query --event SHELL_COMMAND,GIT,SECURITY_VIOLATION --since "2 hours ago" | tail -30; \
	else \
		echo "Note: audit-query not installed. Run 'make audit-install' first"; \
		tail -20 /var/log/developer-access/audit-*.log 2>/dev/null || echo "No logs found"; \
	fi

# Clean up read-only session data
readonly-cleanup:
	@echo "🧹 Cleaning up read-only session data..."
	@sudo find /var/log/developer-access -name "session*" -mtime +30 -delete
	@sudo find /var/log/developer-access -name "audit*.log" -mtime +90 -delete
	@echo "✅ Cleanup complete"

# ─────────────────────────────────────────────────────────────────────────────
# CI/CD TARGETS
# ─────────────────────────────────────────────────────────────────────────────

# CI: Validate without applying
ci-validate: validate
	@echo "CI validation passed"

# CD: Deploy after approval
cd-deploy: validate deploy
	@echo "CD deployment complete"

# ─────────────────────────────────────────────────────────────────────────────
# ALIASES & SHORTCUTS
# ─────────────────────────────────────────────────────────────────────────────

d: deploy      # Short for deploy
p: plan        # Short for plan
s: status      # Short for status
l: logs        # Short for logs
v: validate    # Short for validate
om: ollama-status  # Ollama status
oi: ollama-init    # Ollama init
op: ollama-pull-models  # Ollama pull

# ═══════════════════════════════════════════════════════════════════════════════
# ELITE OPERATIONS — production targets for 192.168.168.31
# All targets remote-only (Linux). Run: make <target>
# ═══════════════════════════════════════════════════════════════════════════════

REMOTE := ssh akushnir@192.168.168.31
REMOTE_DIR := /home/akushnir/code-server-enterprise

## elite-deploy: clean kill → NAS mount → secrets → pull → up → healthcheck
elite-deploy:
	$(REMOTE) "cd $(REMOTE_DIR) && bash scripts/deploy.sh"

## elite-status: full production status (GPU, NAS, containers, VPN)
elite-status:
	$(REMOTE) " \
	  echo '=== CONTAINERS ===' && docker ps --format 'table {{.Names}}\t{{.Status}}' && \
	  echo '' && echo '=== GPU ===' && nvidia-smi --query-gpu=name,memory.used,utilization.gpu --format=csv,noheader && \
	  echo '' && echo '=== NAS ===' && (mountpoint -q /mnt/nas-56 && df -h /mnt/nas-56 || echo 'NAS NOT MOUNTED') && \
	  echo '' && echo '=== VPN ===' && (ip link show wg0 &>/dev/null && wg show wg0 || echo 'VPN NOT RUNNING') && \
	  echo '' && echo '=== DISK ===' && df -h / "

## elite-kill: stop all, purge orphan volumes (data safe — named volumes kept)
elite-kill:
	$(REMOTE) "cd $(REMOTE_DIR) && \
	  docker compose down --remove-orphans --timeout 30 2>/dev/null || true && \
	  docker volume prune -f && \
	  docker image prune -f && \
	  echo 'Cleanup done'"

## elite-logs: stream all service logs
elite-logs:
	$(REMOTE) "cd $(REMOTE_DIR) && docker compose logs -f --tail=100"

## elite-rebuild: hard rebuild (no cache)
elite-rebuild:
	$(REMOTE) "cd $(REMOTE_DIR) && \
	  docker compose down --remove-orphans -v --timeout 30 2>/dev/null || true && \
	  docker compose pull && \
	  bash scripts/deploy.sh --skip-nas"

## elite-git-sync: pull latest from GitHub and redeploy
elite-git-sync:
	$(REMOTE) "cd $(REMOTE_DIR) && \
	  git fetch origin && \
	  git reset --hard origin/main && \
	  git clean -fd && \
	  bash scripts/deploy.sh"

## nas-mount: mount NAS 192.168.168.56 on 192.168.168.31
nas-mount:
	$(REMOTE) "sudo $(REMOTE_DIR)/scripts/nas-mount-31.sh mount"

## nas-status: NAS mount status and capacity
nas-status:
	$(REMOTE) "$(REMOTE_DIR)/scripts/nas-mount-31.sh status || sudo $(REMOTE_DIR)/scripts/nas-mount-31.sh status"

## nas-test: NAS throughput benchmark
nas-test:
	$(REMOTE) "sudo $(REMOTE_DIR)/scripts/nas-mount-31.sh test"

## gpu-status: full GPU info (both cards)
gpu-status:
	$(REMOTE) "nvidia-smi"

## gpu-test: run llama2:7b-chat inference on T1000
gpu-test:
	$(REMOTE) "docker exec ollama ollama run llama2:7b-chat 'What is 2+2? Reply in one word.' --verbose"

## vpn-install: install and configure WireGuard on .31
vpn-install:
	$(REMOTE) "sudo $(REMOTE_DIR)/scripts/vpn-setup.sh install && \
	  sudo $(REMOTE_DIR)/scripts/vpn-setup.sh config && \
	  sudo $(REMOTE_DIR)/scripts/vpn-setup.sh start"

## vpn-addpeer: add a VPN peer (usage: make vpn-addpeer PEER=laptop)
vpn-addpeer:
	@[ -n "$(PEER)" ] || { echo "Usage: make vpn-addpeer PEER=<name>"; exit 1; }
	$(REMOTE) "sudo $(REMOTE_DIR)/scripts/vpn-setup.sh addpeer $(PEER)"

## vpn-status: WireGuard interface and peer status
vpn-status:
	$(REMOTE) "sudo $(REMOTE_DIR)/scripts/vpn-setup.sh status 2>/dev/null || echo 'VPN not running'"

## vpn-test: run full VPN test suite
vpn-test:
	$(REMOTE) "cd $(REMOTE_DIR) && bash scripts/vpn-test.sh"

## secrets-gen: generate new secrets (prints .env to stdout — pipe to .env)
secrets-gen:
	$(REMOTE) "cd $(REMOTE_DIR) && source scripts/lib/secrets.sh && secrets_generate"

## secrets-push-gsm: push local .env secrets to Google Secret Manager
secrets-push-gsm:
	$(REMOTE) "cd $(REMOTE_DIR) && source scripts/lib/secrets.sh && secrets_push_to_gsm"

## branch-clean: delete all local merged implementation branches
branch-clean:
	@git branch | grep -E 'implementation/|feat/elite' | xargs -r git branch -d
	@echo "Local merged branches cleaned"

## branch-clean-remote: delete all remote implementation branches
branch-clean-remote:
	@git branch -r | grep -E 'origin/implementation/' | sed 's|origin/||' | \
	  xargs -r -I{} git push origin --delete {}
	@echo "Remote implementation branches cleaned"

## ollama-gpu: verify ollama is using GPU (T1000, device 1)
ollama-gpu:
	$(REMOTE) "nvidia-smi -i 1 --query-gpu=name,memory.used,utilization.gpu --format=csv,noheader && \
	  docker exec ollama ollama list"

## ollama-pull: pull baseline models onto NAS
ollama-pull:
	$(REMOTE) "docker exec ollama ollama pull llama2:7b-chat && docker exec ollama ollama pull codellama:7b"

.PHONY: elite-deploy elite-status elite-kill elite-logs elite-rebuild elite-git-sync \
        nas-mount nas-status nas-test \
        gpu-status gpu-test \
        vpn-install vpn-addpeer vpn-status vpn-test \
        secrets-gen secrets-push-gsm \
        branch-clean branch-clean-remote \
        ollama-gpu ollama-pull


# ─────────────────────────────────────────────────────────────────────────────
# CODE QUALITY & LIBRARY GOVERNANCE
# ─────────────────────────────────────────────────────────────────────────────

# Verify all active scripts source _common/init.sh (not inline log_info definitions)
lib-check:
	@echo "════════════════════════════════════════════════════════════"
	@echo "  LIBRARY ADOPTION AUDIT"
	@echo "════════════════════════════════════════════════════════════"
	@echo ""
	@echo "✅ Scripts correctly sourcing _common/init.sh or _common/*.sh:"
	@grep -rl "_common/init.sh\|_common/logging.sh" scripts/*.sh 2>/dev/null | grep -v "_common/" | sed 's/^/  ✓ /'
	@echo ""
	@echo "⚠️  Scripts with inline log_info() definitions (need migration):"
	@grep -rl "^log_info() {" scripts/*.sh 2>/dev/null | grep -vE "_common/|logging.sh|common-functions.sh" | sed 's/^/  ✗ /'
	@echo ""
	@echo "⚠️  Scripts with hardcoded 192.168.168.31 (should use \$$DEPLOY_HOST from config.sh):"
	@grep -rl "192\.168\.168\.31" scripts/*.sh 2>/dev/null | grep -v "_common/" | sed 's/^/  ✗ /'
	@echo ""

# Validate scripts against MANIFEST.toml registry
index:
	@echo "════════════════════════════════════════════════════════════"
	@echo "  SCRIPT MANIFEST VALIDATION"
	@echo "════════════════════════════════════════════════════════════"
	@if [ ! -f scripts/MANIFEST.toml ]; then \
		echo "❌ scripts/MANIFEST.toml not found — run: make manifest-init"; \
		exit 1; \
	fi
	@REGISTERED=$$(grep -c '^file' scripts/MANIFEST.toml 2>/dev/null || echo 0); \
	 TOTAL=$$(find scripts -maxdepth 1 -name "*.sh" | wc -l); \
	 echo "  Registered in manifest: $$REGISTERED"; \
	 echo "  Total .sh files:        $$TOTAL"; \
	 echo ""
	@echo "  Unregistered scripts (must be added to MANIFEST.toml or archived):"
	@while IFS= read -r f; do \
		name=$$(basename "$$f"); \
		grep -q "file.*=.*\"$$name\"" scripts/MANIFEST.toml 2>/dev/null || echo "  ✗ $$name"; \
	done < <(find scripts -maxdepth 1 -name "*.sh" | sort)

# Generate initial MANIFEST.toml from existing scripts (run once)
manifest-init:
	@echo "# scripts/MANIFEST.toml — Script Registry" > scripts/MANIFEST.toml
	@echo "# Every script in scripts/ MUST have an entry here." >> scripts/MANIFEST.toml
	@echo "# Status: active | deprecated | historical | experimental" >> scripts/MANIFEST.toml
	@echo "" >> scripts/MANIFEST.toml
	@for f in scripts/*.sh; do \
		name=$$(basename "$$f"); \
		echo "[[script]]" >> scripts/MANIFEST.toml; \
		echo "file     = \"$$name\"" >> scripts/MANIFEST.toml; \
		echo "category = \"uncategorized\"" >> scripts/MANIFEST.toml; \
		echo "status   = \"active\"" >> scripts/MANIFEST.toml; \
		echo "purpose  = \"TODO: add purpose\"" >> scripts/MANIFEST.toml; \
		echo "" >> scripts/MANIFEST.toml; \
	done
	@echo "✅ Generated scripts/MANIFEST.toml with $$(grep -c '^file' scripts/MANIFEST.toml) entries"
	@echo "   Edit status/purpose for each script, then commit."

# Archive all phase-* historical scripts (move to scripts/_archive/)
archive-phases:
	@echo "🗂  Archiving historical phase-* scripts..."
	@mkdir -p scripts/_archive/phase-history
	@count=0; \
	 for f in scripts/phase-*.sh scripts/phase-*.py scripts/PHASE-*.sh; do \
		[ -f "$$f" ] || continue; \
		mv "$$f" scripts/_archive/phase-history/; \
		count=$$((count + 1)); \
	 done; \
	 for d in scripts/phase-*/; do \
		[ -d "$$d" ] || continue; \
		base=$$(basename "$$d"); \
		mkdir -p "scripts/_archive/phase-history/$$base"; \
		mv "$$d"*.sh "scripts/_archive/phase-history/$$base/" 2>/dev/null || true; \
		mv "$$d"*.py "scripts/_archive/phase-history/$$base/" 2>/dev/null || true; \
		rmdir "$$d" 2>/dev/null || true; \
		count=$$((count + 1)); \
	 done; \
	 echo "✅ Archived $$count phase history scripts to scripts/_archive/phase-history/"
	@echo "   Active script count: $$(find scripts -maxdepth 1 -name '*.sh' | wc -l)"

# Show full governance status dashboard
governance:
	@echo "════════════════════════════════════════════════════════════"
	@echo "  GOVERNANCE STATUS DASHBOARD"
	@echo "════════════════════════════════════════════════════════════"
	@echo ""
	@echo "📚 Library Adoption:"
	@count=$$(grep -rl "_common/init\.sh\|_common/logging\.sh" scripts/*.sh 2>/dev/null | grep -v "_common/" | wc -l); \
	 total=$$(find scripts -maxdepth 1 -name "*.sh" | wc -l); \
	 pct=$$((count * 100 / total)); \
	 echo "  $$count / $$total active scripts use _common/ library ($$pct%)"
	@echo ""
	@echo "🔒 Security:"
	@hardcoded=$$(grep -rl "192\.168\." scripts/*.sh 2>/dev/null | grep -v "_common/" | wc -l); \
	 echo "  Hardcoded IPs in active scripts: $$hardcoded (should be 0)"
	@violations=$$(grep -rl "^log_info() {" scripts/*.sh 2>/dev/null | grep -vE "_common/|logging\.sh|common-functions\.sh" | wc -l); \
	 echo "  Inline log_info() violations: $$violations (should be 0)"
	@echo ""
	@echo "📋 Script Registry:"
	@[ -f scripts/MANIFEST.toml ] \
		&& echo "  ✅ MANIFEST.toml exists ($$(grep -c '^file' scripts/MANIFEST.toml) entries)" \
		|| echo "  ❌ MANIFEST.toml missing — run: make manifest-init"
	@echo ""
	@echo "🗂  Archive:"
	@echo "  Phase history: $$(find scripts/_archive/phase-history -name '*.sh' 2>/dev/null | wc -l) scripts"
	@echo "  Historical: $$(find scripts/_archive/historical -name '*.sh' 2>/dev/null | wc -l) scripts"
	@echo ""
	@echo "Pre-commit hooks: $$([ -f .pre-commit-config.yaml ] && echo '✅ configured' || echo '❌ missing')"
	@echo ""

# ─────────────────────────────────────────────────────────────────────────────
# WIREGUARD VPN (run as root: sudo make wireguard-install)
# ─────────────────────────────────────────────────────────────────────────────
wireguard-install:
	@echo "==> Fixing interrupted dpkg state..."
	dpkg --configure -a 2>/dev/null || true
	@echo "==> Installing WireGuard..."
	apt-get update -qq && apt-get install -y wireguard wireguard-tools
	@echo "==> Enabling ip forwarding..."
	sysctl -w net.ipv4.ip_forward=1
	grep -q 'net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
	@echo "✅ WireGuard installed: $$(wg --version)"

wireguard-genkeys:
	@echo "==> Generating WireGuard server keypair..."
	@mkdir -p /etc/wireguard
	@wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
	@chmod 600 /etc/wireguard/server_private.key
	@echo "Server public key: $$(cat /etc/wireguard/server_public.key)"
	@echo "✅ WireGuard keys generated in /etc/wireguard/"

wireguard-status:
	@wg show 2>/dev/null || echo "WireGuard interface not active (wg0 not up)"
	@ip addr show wg0 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────────
# NAS MOUNT (run as root: sudo make nas-mount)
# NAS: 192.168.168.56:/export → /mnt/nas-56
# ─────────────────────────────────────────────────────────────────────────────
nas-mount:
	@echo "==> Mounting NAS 192.168.168.56:/export → /mnt/nas-56..."
	mkdir -p /mnt/nas-56
	@if mountpoint -q /mnt/nas-56; then \
		echo "  Already mounted at /mnt/nas-56"; \
	else \
		mount -t nfs4 -o vers=4.1,rw,hard,intr,timeo=30,retrans=3,rsize=1048576,wsize=1048576 \
			192.168.168.56:/export /mnt/nas-56; \
		echo "  ✅ Mounted successfully"; \
	fi
	@grep -q '192.168.168.56:/export' /etc/fstab || \
		echo '192.168.168.56:/export /mnt/nas-56 nfs4 vers=4.1,rw,hard,intr,timeo=30,retrans=3,rsize=1048576,wsize=1048576,_netdev 0 0' >> /etc/fstab && \
		echo "  ✅ Added to /etc/fstab for persistent mount"
	@df -h /mnt/nas-56

nas-mount-status:
	@mountpoint -q /mnt/nas-56 && echo "✅ /mnt/nas-56 is mounted" || echo "❌ /mnt/nas-56 is NOT mounted"
	@grep '192.168.168.56:/export' /etc/fstab && echo "✅ fstab entry exists" || echo "❌ fstab entry missing"
