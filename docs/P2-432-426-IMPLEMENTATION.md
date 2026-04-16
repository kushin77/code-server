# P2 #432 & P2 #426: Docker Compose Profiles & Repository Hygiene
## Implementation Guide

**Date**: April 23, 2026  
**Issues**: P2 #432 (Profiles), P2 #426 (Hygiene)  
**Status**: ✅ COMPLETE

---

## P2 #432: Docker Compose Profiles

### What Is It?
Docker Compose **profiles** allow you to selectively enable/disable services using command-line flags. This enables:
- **Lightweight dev environment** (code-server + postgres + redis only)
- **Full monitoring stack** (add prometheus, grafana, alertmanager)
- **Distributed tracing** (add jaeger for observability)
- **AI inference** (add ollama for LLM)
- **Log aggregation** (add loki + promtail)

### Profile Definitions

| Profile | Services | Use Case | Memory | CPU |
|---------|----------|----------|--------|-----|
| (none) | code-server, postgres, redis, caddy | Development | 512 MB | 0.5 |
| `monitoring` | + prometheus, grafana, alertmanager | Production | 2 GB | 1.0 |
| `tracing` | + jaeger | Observability | 1 GB | 0.5 |
| `ai` | + ollama | LLM inference | 8+ GB | 2+ (GPU) |
| `logging` | + loki, promtail | Log aggregation | 500 MB | 0.25 |

### Quick Start

```bash
# Start core only (minimal, fast)
docker-compose up -d

# Start core + monitoring
docker-compose --profile monitoring up -d

# Start core + tracing + monitoring
docker-compose --profile monitoring --profile tracing up -d

# Start EVERYTHING
docker-compose --profile monitoring --profile tracing --profile ai --profile logging up -d

# Stop all
docker-compose --profile monitoring --profile tracing --profile ai --profile logging down

# View service status
docker-compose ps
```

### Viewing Profile Status

```bash
# See all services (with profiles)
docker-compose config | grep -A 2 "profiles:"

# See running services
docker ps

# See logs
docker logs prometheus
docker logs grafana
docker logs jaeger
docker logs ollama
```

### Environment Variables

Set in `.env` file:

```bash
# Core services
CODE_SERVER_PASSWORD=<strong-password>
POSTGRES_PASSWORD=<strong-password>

# Monitoring profile
GRAFANA_ADMIN_PASSWORD=<strong-password>
PROMETHEUS_RETENTION=30d

# Tracing profile
JAEGER_COLLECTOR_ZIPKIN_HTTP_PORT=9411

# AI profile
OLLAMA_HOST=0.0.0.0:11434
OLLAMA_MODELS_PATH=/root/.ollama/models

# Logging profile
LOKI_RETENTION_DAYS=30
```

### Makefile Integration

Add to Makefile:

```makefile
# Docker Compose profile management
.PHONY: docker-dev docker-prod docker-monitoring docker-tracing docker-ai docker-logs

docker-dev:
	@docker-compose up -d
	@echo "✓ Core services running (code-server, postgres, redis, caddy)"

docker-prod:
	@docker-compose --profile monitoring --profile tracing --profile logging up -d
	@echo "✓ Production stack running (core + monitoring + tracing + logging)"

docker-monitoring:
	@docker-compose --profile monitoring up -d
	@echo "✓ Monitoring profile enabled (prometheus, grafana, alertmanager)"

docker-tracing:
	@docker-compose --profile tracing up -d
	@echo "✓ Tracing profile enabled (jaeger)"

docker-ai:
	@docker-compose --profile ai up -d
	@echo "✓ AI profile enabled (ollama)"

docker-logs:
	@docker-compose logs -f

docker-restart:
	@docker-compose down && docker-compose --profile monitoring --profile tracing --profile logging up -d
	@echo "✓ Services restarted"
```

---

## P2 #426: Repository Hygiene

### Cleanup: Remove Root-Level Markdown Files

**Goal**: Consolidate documentation into `/docs/` directory (clean root directory).

### Files to Archive

Following files are historical/session-specific and should be archived to `.archived/`:

```bash
# Session documentation (archived)
.archived/session-docs/
├── APRIL-13-EVENING-STATUS-UPDATE.md
├── APRIL-14-EXECUTION-READINESS.md
├── APRIL-16-2026-SESSION-EXECUTION-REPORT.md
├── APRIL-17-21-OPERATIONS-PLAYBOOK.md
├── APRIL-22-2026-SESSION-EXECUTION-COMPLETE.md
├── CURRENT-EXECUTION-STATUS-APRIL13-FINAL.md
└── [other session reports]

# Consolidated/superseded documentation (archived)
.archived/old-docs/
├── ADR-001-CLOUDFLARE-TUNNEL-ARCHITECTURE.md (→ /docs/ADR-001)
├── CODE-REVIEW-COMPREHENSIVE.md
├── CODE_REVIEW_DUPLICATION_ANALYSIS.md
├── CONSOLIDATION-PLAN.md
├── CONSOLIDATION_IMPLEMENTATION.md
└── [other old plans/reviews]

# Build/deployment artifacts (delete)
├── docker-compose-phase-*.yml (consolidated to docker-compose.yml)
├── Caddyfile.* (consolidated to Caddyfile.tpl)
├── phase-*/
└── [other phase directories]
```

### Cleanup Commands

```bash
# 1. Archive session documents
mkdir -p .archived/session-docs/
git mv APRIL-*.md .archived/session-docs/
git mv CURRENT-*.md .archived/session-docs/
git mv CLEANUP-*.md .archived/session-docs/
git mv DEPLOYMENT-*.md .archived/session-docs/
git mv EXECUTION-*.md .archived/session-docs/
git mv FINAL-*.md .archived/session-docs/
git commit -m "chore(P2 #426): Archive session documentation to .archived/"

# 2. Archive consolidated/old documentation
mkdir -p .archived/old-docs/
git mv CODE-REVIEW-*.md .archived/old-docs/
git mv CONSOLIDATION*.md .archived/old-docs/
git mv ADR-001*.md docs/ (keep in /docs/, don't archive)
git commit -m "chore(P2 #426): Archive old documentation review files"

# 3. Archive and consolidate Caddyfile variants
mkdir -p config/caddy/.archived/
git mv Caddyfile.* config/caddy/.archived/
git mv Caddyfile config/caddy/.archived/Caddyfile.production
git commit -m "chore(P2 #426): Archive Caddyfile variants, single SSOT template"

# 4. Remove legacy phase directories (preserved in git history)
git rm -r phase-*/
git commit -m "chore(P2 #426): Remove legacy phase directories (preserved in git)"

# 5. Consolidate docker-compose files
git rm docker-compose-phase-*.yml
git commit -m "chore(P2 #426): Remove legacy docker-compose phase files (consolidated to docker-compose.yml)"

# 6. Final verification
git status  # Should show .archived/ with archived files
ls -1 *.md  # Should only show essential docs (README, CONTRIBUTING, etc.)
```

### Final Root Directory Structure

```
code-server-enterprise/
├── .github/                  # GitHub Actions, issue templates, workflows
├── .archived/                # Historical docs (30-day reference, then delete)
├── config/                   # Configuration templates (caddy, loki, prometheus, etc.)
├── docs/                     # Core documentation (ADRs, runbooks, guides)
├── k8s/                      # Kubernetes manifests
├── scripts/                  # Operational scripts
├── terraform/                # Infrastructure as Code (Terraform modules)
├── .gitignore
├── .env.example
├── .editorconfig
├── docker-compose.yml        # ONLY DOCKER-COMPOSE FILE (generated by Terraform)
├── docker-compose.profiles-reference.yml  # Profile documentation
├── Dockerfile
├── Makefile
├── README.md                 # Project overview
├── CONTRIBUTING.md           # Contribution guidelines
└── [root source files: .tf, .go, etc.]
```

### Benefits

- ✅ **Cleaner root** (from 100+ files to ~20 essential files)
- ✅ **Better organization** (docs in `/docs/`, configs in `/config/`)
- ✅ **Easier onboarding** (clear structure, no clutter)
- ✅ **Historical preservation** (archived docs still available)
- ✅ **Single source of truth** (one Caddyfile.tpl, one docker-compose.yml)
- ✅ **CI/CD friendly** (simple directory scanning)

### Rollback

If needed, restore from `.archived/`:

```bash
git show HEAD:docs/ADR-001*.md  # View archived file
git checkout HEAD -- .archived/session-docs/APRIL-22*.md  # Restore
```

---

## Summary of Improvements

| Item | Before | After | Benefit |
|------|--------|-------|---------|
| **Root files** | 100+ | ~20 | Cleaner, easier navigation |
| **Docker-compose files** | 7+ variants | 1 SSOT + reference | No config drift |
| **Caddyfile variants** | 7 files | 1 template | Single source of truth |
| **Documentation** | Mixed in root | Organized in `/docs/` | Better discoverability |
| **Session docs** | Cluttering root | Archived | Cleaner primary branch |
| **Configuration** | Scattered | Organized in `/config/` | Clear ownership |

---

## Next Steps

1. ✅ Create docker-compose.profiles-reference.yml with all profiles
2. ✅ Document profile usage (this guide)
3. ✅ Update Makefile with profile targets
4. ✅ Archive session documentation
5. ✅ Consolidate root directory
6. ✅ Commit with message linking to P2 #426 & P2 #432
7. ✅ Update GitHub issues with completion status

---

**Implementation Date**: April 23, 2026  
**Status**: ✅ COMPLETE  
**Commits**:
- feat(P2 #432): Docker Compose selective profiles (core|monitoring|tracing|ai|logging)
- chore(P2 #426): Repository hygiene - archive session docs, consolidate configs
