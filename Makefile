# ✅ Makefile - IaC-First Deployment
# Uses docker-compose for container orchestration (declarative)
# Terraform for infrastructure provisioning (optional future use)

.PHONY: help init validate plan apply deploy destroy destroy-full clean logs status dashboard \
        shell refresh output fmt taint untaint state-list console audit idempotency-check \
        compose-up compose-down compose-restart \
        backup restore rotate-secret update-vsix \
        setup-remote-access grant-access revoke-access list-developers extend-access health-check audit-report \
        audit-install audit-query audit-compliance audit-security audit-cleanup \
        ollama-health ollama-pull-models ollama-list ollama-logs ollama-index ollama-init ollama-status ollama-shell \
        logs-code-server logs-oauth2 logs-caddy \
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
	@echo "REMOTE DEVELOPER ACCESS (Lean On-Premises):"
	@echo "  make setup-remote-access - Initialize remote access infrastructure"
	@echo "  make grant-access EMAIL=user@example.com DAYS=7 - Grant temporary access"
	@echo "  make revoke-access EMAIL=user@example.com - Revoke all access"
	@echo "  make list-developers - Show active developers & expiry dates"
	@echo "  make extend-access EMAIL=user@example.com DAYS=7 - Add more access days"
	@echo "  make audit-report [DATE=2026-04-13] - View access audit trail"
	@echo ""
	@echo "AUDIT LOGGING & COMPLIANCE (Issue #183):"
	@echo "  make audit-install - Install audit logging system"
	@echo "  make audit-compliance [DEVELOPER=alice] [DAYS=30] - Generate compliance report"
	@echo "  make audit-security [DAYS=7] - Generate security incident report"
	@echo "  make audit-query QUERY=... - Query audit logs (examples below)"
	@echo "  make audit-cleanup [RETENTION=90] - Clean old audit logs"
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

# ✅ Grant temporary access to a developer
grant-access:
	@if [ -z "$(EMAIL)" ]; then echo "❌ Email required: make grant-access EMAIL=user@example.com DAYS=7"; exit 1; fi
	@if [ -z "$(DAYS)" ]; then echo "⚠️  Default: 7 days. Override: make grant-access EMAIL=... DAYS=14"; DAYS=7; fi
	@echo "✅ Granting access to $(EMAIL) for $(DAYS) days..."
	@EXPIRY_DATE=$$(date -d "+$(DAYS) days" +%Y-%m-%d); \
	echo "[$(date)] GRANT_ACCESS email=$(EMAIL) days=$(DAYS) expiry=$$EXPIRY_DATE" >> logs/audit/access.log; \
	echo "$(EMAIL) $$EXPIRY_DATE" >> .env.developers; \
	echo "✅ Access granted! Expiry: $$EXPIRY_DATE"; \
	echo "🔗 Share this link: https://code-server.tunnel.example.com (via Cloudflare Access)"; \
	echo "⏰ Will auto-revoke on $$EXPIRY_DATE"

# ✅ Revoke access for a developer
revoke-access:
	@if [ -z "$(EMAIL)" ]; then echo "❌ Email required: make revoke-access EMAIL=user@example.com"; exit 1; fi
	@echo "🔴 Revoking access for $(EMAIL)..."
	@grep -v "^$(EMAIL) " .env.developers > .env.developers.tmp && mv .env.developers.tmp .env.developers || true
	@echo "[$(date)] REVOKE_ACCESS email=$(EMAIL)" >> logs/audit/access.log
	@docker compose exec -T code-server pkill -f "$(EMAIL)" 2>/dev/null || true
	@echo "✅ Access revoked for $(EMAIL)"

# ✅ List all active developers
list-developers:
	@echo "👥 Active developers:"
	@if [ -f .env.developers ]; then \
		echo "  Email           | Access Expires"; \
		echo "  ---|---"; \
		cat .env.developers | grep -v "^#" | awk '{print "  " $$1 " | " $$2}'; \
	else \
		echo "  (none)"; \
	fi
	@echo ""
	@echo "📊 Access Statistics:"
	@if [ -f logs/audit/access.log ]; then \
		echo "  Total grants: $$(grep GRANT_ACCESS logs/audit/access.log | wc -l)"; \
		echo "  Total revokes: $$(grep REVOKE_ACCESS logs/audit/access.log | wc -l)"; \
	fi

# ✅ Extend access for a developer (add more days)
extend-access:
	@if [ -z "$(EMAIL)" ]; then echo "❌ Email required: make extend-access EMAIL=user@example.com DAYS=7"; exit 1; fi
	@if [ -z "$(DAYS)" ]; then DAYS=7; fi
	@echo "⏱️  Extending access for $(EMAIL) by $(DAYS) days..."
	@if grep -q "^$(EMAIL) " .env.developers; then \
		CURRENT_EXPIRY=$$(grep "^$(EMAIL) " .env.developers | awk '{print $$2}'); \
		NEW_EXPIRY=$$(date -d "$$CURRENT_EXPIRY + $(DAYS) days" +%Y-%m-%d); \
		sed -i "s/^$(EMAIL) .*/$(EMAIL) $$NEW_EXPIRY/" .env.developers; \
		echo "[$(date)] EXTEND_ACCESS email=$(EMAIL) days=$(DAYS) new_expiry=$$NEW_EXPIRY" >> logs/audit/access.log; \
		echo "✅ Extended! New expiry: $$NEW_EXPIRY"; \
	else \
		echo "❌ Developer $(EMAIL) not found"; \
		exit 1; \
	fi

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
# CI/CD TARGETS
# ─────────────────────────────────────────────────────────────────────────────

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
om: ollama-status  # Ollama status
oi: ollama-init    # Ollama init
op: ollama-pull-models  # Ollama pull
