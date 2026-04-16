# Copilot Instructions for kushin77/code-server
## Code Governance Rules (Copilot Enforcement)

### Rule 1 — No Duplication
Before writing any helper function or utility, check these canonical locations:
- `scripts/_common/utils.sh` — generic utilities (retry, confirm, die, log_*)
- `scripts/_common/logging.sh` — log_info, log_warn, log_error, log_fatal, log_debug
- `scripts/_common/config.sh` — config loading (load_env, export_vars)
- `scripts/lib/secrets.sh` — secret fetching (GSM + .env fallback)
- `scripts/lib/nas.sh` — NAS mount helpers
- `scripts/lib/` — other shared libraries

**Never create a new helper if the functionality exists in these files.** Refactor into shared libraries instead.

### Rule 2 — Metadata Headers (mandatory on every new file)
Every bash script must start with metadata headers per GOV-002:
```bash
#!/usr/bin/env bash
# @file        scripts/<path>/<filename>.sh
# @module      <category/subcategory>
# @description <one-line purpose of the script>
#
```

Every Python script must start with:
```python
#!/usr/bin/env python3
# @file        scripts/<path>/<filename>.py
# @module      <category/subcategory>
# @description <one-line purpose of the script>
#
```

Use `./scripts/fix-metadata-headers.sh` to auto-fix missing headers.

### Rule 3 — Configuration Separation
- **Infrastructure config** (environment-specific): Use env vars from `scripts/_common/_base-config.env`
	- Example: `$DEPLOY_HOST`, `$REGISTRY_URL`, `$API_KEY`
	- Loaded globally via `source scripts/_common/config.sh`
- **Logic config** (function-specific): Use function parameters or local variables
	- Example: function argument `$1`, local var `retry_count=3`

Never embed hardcoded IPs, URLs, or credentials in scripts. Always use env vars or parameters.

### Rule 4 — Shared Library Adoption
Always use shared libraries; never duplicate. Canonical APIs:

**scripts/_common/init.sh**
- `init_repo()` — initialize repo context
- `ensure_root()` or `ensure_not_root()` — permission checks

**scripts/_common/logging.sh**
- `log_info "message"`, `log_warn`, `log_error`, `log_fatal`, `log_debug`

**scripts/_common/config.sh**
- `load_env <file>` — load env vars from file
- `export_vars <var1> <var2>` — export to subshells

**scripts/lib/secrets.sh**
- `get_secret <key> [fallback_env]` — fetch secret from GSM or .env

**scripts/lib/nas.sh**
- `mount_nas <host> <export>` — mount NAS volume
- `unmount_nas <mount_point>` — unmount volume

### Rule 5 — Copilot Trigger Pattern
When you need Copilot to apply governance standards to your code, use:
```
@workspace, apply governance standards: deduplication (check _common/), headers (metadata block), config separation (env vars), shared libs
```

---
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
