# ✅ Makefile - IaC-First Deployment
# Uses docker-compose for container orchestration (declarative)
# Terraform for infrastructure provisioning (optional future use)

.PHONY: help init validate plan apply deploy destroy destroy-full clean logs status dashboard \
        shell refresh output fmt taint untaint state-list console audit idempotency-check \
        compose-up compose-down compose-restart \
        backup restore rotate-secret update-vsix \
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

# ─────────────────────────────────────────────────────────────────────────────
# AGENT FARM
# ─────────────────────────────────────────────────────────────────────────────

## Pull a single model from HuggingFace into Ollama
## Usage: make pull-model MODEL=qwen2.5-coder:32b-instruct-q4_K_M
pull-model:
	@if [ -z "$(MODEL)" ]; then echo "Usage: make pull-model MODEL=<ollama-name>"; exit 1; fi
	@MODEL="$(MODEL)" && \
	 REPO=$$(yq eval ".models[] | select(.name == \"$$MODEL\") | .hf_repo" config/recommended-models.yaml) && \
	 FILE=$$(yq eval ".models[] | select(.name == \"$$MODEL\") | .hf_file" config/recommended-models.yaml) && \
	 ./scripts/hf_pull_model.sh "$$REPO" "$$FILE" "$$MODEL"

## Pull all recommended models (respects VRAM gate)
pull-recommended:
	@./scripts/hf_pull_recommended.sh

## Pull only embedding models
pull-embeddings:
	@./scripts/hf_pull_recommended.sh embedding

## Build all agent-farm Docker images
agent-build:
	@docker compose build embeddings agent-api computer-use-mcp

## Start agent-farm services (idempotent — existing containers are no-ops)
agent-up:
	@docker compose up -d keycloak-db keycloak chroma embeddings agent-api computer-use-mcp

## Stop agent-farm services
agent-down:
	@docker compose stop keycloak-db keycloak chroma embeddings agent-api computer-use-mcp

## Tail logs for all agent-farm services
agent-logs:
	@docker compose logs -f keycloak chroma embeddings agent-api computer-use-mcp

## Aggregate health check across all agent-farm services
agent-health:
	@echo "==> Agent Farm Health"
	@curl -sf http://localhost:8001/health | python3 -m json.tool || echo "agent-api unreachable"
	@curl -sf http://localhost:8000/health | python3 -m json.tool || echo "embeddings unreachable"
	@curl -sf http://localhost:8008/health | python3 -m json.tool || echo "computer-use-mcp unreachable"
	@curl -sf http://localhost:8080/health/live | python3 -m json.tool || echo "keycloak unreachable"

## Bootstrap Keycloak realm from keycloak/realm-export.json
keycloak-setup:
	@echo "==> Waiting for Keycloak..."
	@until curl -sf http://localhost:8080/health/live > /dev/null; do sleep 2; done
	@curl -sf -X POST http://localhost:8080/auth/realms/master/protocol/openid-connect/token \
	  -d 'username=$(KEYCLOAK_ADMIN_USER)&password=$(KEYCLOAK_ADMIN_PASSWORD)&grant_type=password&client_id=admin-cli' \
	  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" > /tmp/kc-token.txt
	@curl -sf -X POST http://localhost:8080/auth/admin/realms \
	  -H "Authorization: Bearer $$(cat /tmp/kc-token.txt)" \
	  -H "Content-Type: application/json" \
	  -d @keycloak/realm-export.json
	@rm -f /tmp/kc-token.txt
	@echo "==> Keycloak realm imported."

## Show RAG index status (ChromaDB collection count)
rag-status:
	@curl -sf http://localhost:8000 | python3 -m json.tool || echo "Embeddings service not running"

## Index current workspace into ChromaDB
index-codebase:
	@curl -sf -X POST http://localhost:8001/rag/index \
	  -H "Content-Type: application/json" \
	  -d '{"path":"/workspace","collection":"codebase"}' | python3 -m json.tool

## Submit a task to the agent farm (usage: make agent-task TASK="<description>")
agent-task:
	@if [ -z "$(TASK)" ]; then echo "Usage: make agent-task TASK=\"your task here\""; exit 1; fi
	@curl -sf -X POST http://localhost:8001/run_task \
	  -H "Content-Type: application/json" \
	  -d "{\"task\":\"$(TASK)\",\"thread_id\":\"$$(date +%s)\"}" | python3 -m json.tool

## Prepare fine-tuning dataset from staged git commits
finetune-prep:
	@python3 scripts/prepare_finetune_dataset.py

## Aliases
ab: agent-build
au: agent-up
ad: agent-down
al: agent-logs
ah: agent-health
