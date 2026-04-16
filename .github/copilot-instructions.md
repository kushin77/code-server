# Copilot Instructions for kushin77/code-server

<!-- SCOPE SENTINEL: This workspace is kushin77/code-server ONLY -->

## Scope

✅ **ONLY**: kushin77/code-server — on-prem VSCode server + infrastructure at 192.168.168.31/.42  
❌ **NEVER**: eiq-linkedin, GCP-landing-zone, code-server-enterprise, or any other repo

## Priority Order (execute in this order)

- **P0** 🔴 Critical (outage, data loss, security breach) — fix immediately
- **P1** 🟠 High (major degradation, core broken) — this sprint
- **P2** 🟡 Medium (enhancement, non-critical) — next sprint
- **P3** 🟢 Low (nice-to-have, docs, tech debt) — backlog

## Non-Negotiables

- Every branch → open issue → PR with `Fixes #N` → merge → auto-close issue
- Conventional commits: `feat|fix|refactor|docs|chore|ci(scope): message`
- All changes tested, no CVEs, no secrets in git
- IaC: immutable versions pinned, idempotent, duplicate-free, on-prem first
- GitHub Issues = SSOT. Memory files = ephemeral working notes only
- Never PATCH closed issues — add comments only

## Production Host

- **Primary**: `ssh akushnir@192.168.168.31` — deploy from here (Docker runs here)
- **Replica**: `192.168.168.42`
- Deploy: `docker compose up -d` or `terraform apply` on remote host

## Quick Reference

```bash
# Core services only (no AI, no tracing overhead)
docker compose up -d

# With AI (Ollama LLM)
COMPOSE_PROFILES=ai docker compose up -d

# With distributed tracing
COMPOSE_PROFILES=tracing docker compose up -d

# Full stack
COMPOSE_PROFILES=ai,tracing docker compose up -d
```

---
**Last updated: April 16, 2026** | [All Issues](https://github.com/kushin77/code-server/issues)
