# AI/Ollama Repository Separation

**Issue:** #1546  
**Governance:** GOV-002  
**Status:** In progress — code-server now uses external Ollama endpoint defaults; final cross-repo migration validation pending

---

## Repository Strategy

| Repository | Purpose | URL |
|------------|---------|-----|
| `kushin77/code-server` | Core infrastructure, IDE platform, orchestration | (this repo) |
| `kushin77/ollama` | All AI/Ollama workloads, models, inference | https://github.com/kushin77/ollama |
| `kushin77/source-control` | GitLab/GitHub integration code | https://github.com/kushin77/source-control |

---

## AI Surface in This Repo

| File/Path | Current State |
|-----------|---------------|
| `docker-compose.yml` | No local `ollama` service; callers use `OLLAMA_HOST` |
| `scripts/ops/deploy-ollama-external.sh` | External deployment orchestration for `kushin77/ollama` |
| `.env*` / `.env.schema.json` | Defaults now point to external endpoint semantics |

---

## Migration Steps

### Phase 1 (Done): Externalize runtime dependencies
- Removed local `ollama` runtime dependency from active compose.
- Standardized `OLLAMA_HOST` defaults to external endpoint semantics.
- Updated CLI offline flow to preload model through Ollama HTTP API instead of `docker-compose exec ollama`.

### Phase 2: Validate and complete in `kushin77/ollama`

```bash
# 1. Clone target repo
git clone https://github.com/kushin77/ollama.git /tmp/ollama-repo

# 2. Validate AI workload ownership and deployment pipeline in target repo
cd /tmp/ollama-repo
docker compose --profile ai up -d

# 3. Confirm external endpoint availability from code-server host
curl -f http://192.168.168.31:11434/api/tags
```

### Phase 3: Governance closeout

1. Verify all acceptance criteria in issue #1546 against both repos.
2. Capture CI evidence that code-server works with Ollama as external runtime only.
3. Close issue #1546 once cross-repo validation is complete.

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
      - OLLAMA_HOST=${OLLAMA_HOST:-http://192.168.168.31:11434}
```

---

*GOV-002: Update this doc when migration phases complete.*
