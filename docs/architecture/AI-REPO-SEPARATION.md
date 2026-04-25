# AI/Ollama Repository Separation

**Issue:** #1546  
**Governance:** GOV-002  
**Status:** In progress — `docker-compose.ai.yml` created as migration intermediate

---

## Repository Strategy

| Repository | Purpose | URL |
|------------|---------|-----|
| `kushin77/code-server` | Core infrastructure, IDE platform, orchestration | (this repo) |
| `kushin77/ollama` | All AI/Ollama workloads, models, inference | https://github.com/kushin77/ollama |
| `kushin77/source-control` | GitLab/GitHub integration code | https://github.com/kushin77/source-control |

---

## AI Code in This Repo (to be migrated)

| File/Path | Migration Target |
|-----------|-----------------|
| `apps/multimodal-ai/` | `kushin77/ollama/apps/multimodal-ai/` |
| `docker-compose.ai.yml` | `kushin77/ollama/docker-compose.yml` |
| Ollama service in `docker-compose.yml` | Remove after migration |
| `OLLAMA_*` env vars in `.env` | Move to `kushin77/ollama/.env` |

---

## Migration Steps

### Phase 1 (Done): Create AI Compose Overlay
`docker-compose.ai.yml` has been created as an isolated overlay containing:
- `ollama` service (image-pinned, non-root user)
- `multimodal-ai` service (voice, diagrams, image analysis)

This allows the AI stack to be run independently or in combination.

### Phase 2: Migrate to kushin77/ollama

```bash
# 1. Clone the target repo
git clone https://github.com/kushin77/ollama.git /tmp/ollama-repo

# 2. Copy AI application code
cp -r apps/multimodal-ai /tmp/ollama-repo/apps/
cp docker-compose.ai.yml /tmp/ollama-repo/docker-compose.yml

# 3. Commit and push to ollama repo
cd /tmp/ollama-repo
git add .
git commit -m "feat: migrate multimodal-ai from code-server repo"
git push origin main

# 4. Update code-server docker-compose.yml to reference external service
# (or use docker compose -f docker-compose.yml -f path/to/ollama/docker-compose.yml)
```

### Phase 3: Remove from This Repo

Once `kushin77/ollama` has the AI services running:
1. Remove `ollama` service from `docker-compose.yml`
2. Remove `multimodal-ai` service from `docker-compose.yml`
3. Remove `apps/multimodal-ai/` directory
4. Update environment references to point to external Ollama host

---

## Boundary Rules

After separation, these boundaries must be enforced:

| Concern | Repo | NOT allowed in |
|---------|------|----------------|
| Ollama models, inference | `kushin77/ollama` | `code-server` |
| GPU configuration | `kushin77/ollama` | `code-server` |
| LLM prompt engineering | `kushin77/ollama` | `code-server` |
| Docker Compose orchestration | `code-server` | `ollama` |
| SSL/TLS, DNS, Caddy | `code-server` | `ollama` |
| Auth, OAuth2 | `code-server` | `ollama` |

---

## Connection Pattern (Post-Migration)

```yaml
# In code-server docker-compose.yml (post-migration):
services:
  memory-engine:
    environment:
      # Point to external Ollama host instead of internal service
      - OLLAMA_HOST=${OLLAMA_EXTERNAL_URL:-http://192.168.168.31:11434}
```

---

*GOV-002: Update this doc when migration phases complete.*
