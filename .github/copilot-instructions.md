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

### Rule 5 — Script Template & Writing Guide (mandatory for new scripts)
All new bash scripts MUST use the canonical template to ensure consistency:
```bash
cp scripts/_template.sh scripts/my-new-script.sh
```

The template pre-configures:
- ✅ GOV-002 metadata headers (`@file`, `@module`, `@description`, `@owner`, `@status`)
- ✅ Canonical initialization via `source "$SCRIPT_DIR/_common/init.sh"`
- ✅ Structured logging with `log_info`, `log_error`, `log_fatal`
- ✅ Automatic error handling (set -euo pipefail, ERR trap, stack traces)
- ✅ Configuration separation (env vars only, no hardcoded values)
- ✅ Input validation patterns (require_var, require_command, require_file)
- ✅ Cleanup hooks (trap cleanup EXIT)

**Complete Reference**: [docs/SCRIPT-WRITING-GUIDE.md](docs/SCRIPT-WRITING-GUIDE.md) — covers all patterns, examples, checklist, common mistakes.

### Rule 6 — Deduplication Enforcement (April 17, 2026 analysis)
Repository underwent comprehensive deduplication audit (see [DEDUPLICATION-AND-EFFICIENCY-ANALYSIS.md](DEDUPLICATION-AND-EFFICIENCY-ANALYSIS.md)):

**Logging System**: Use ONLY `log_*` from `scripts/_common/logging.sh`
- ❌ Avoid: `echo`, `echo "ERROR:"`, `write_error`, `die`, custom functions
- ✅ Use: `log_info`, `log_warn`, `log_error`, `log_fatal`, `log_debug`

**Script Initialization**: Use ONLY `source "$SCRIPT_DIR/_common/init.sh"`
- ❌ Avoid: Sourcing config.sh, logging.sh, utils.sh separately (27 scripts did this)
- ✅ Use: Single init.sh which loads all dependencies in correct order

**Configuration Sources**: NEVER hardcode values
- ❌ Avoid: `DEPLOY_HOST="192.168.168.31"`, `DOMAIN="kushnir.cloud"` in scripts
- ✅ Use: `DEPLOY_HOST="${DEPLOY_HOST}"` (loads from .env via init.sh → config.sh)
- Master config SSOT: `.env.template` (deployment config), `terraform/variables.tf` (IaC config)

**Workflow Deduplication**: Use `TEMPLATE-*.yml` as base for all workflows
- ❌ Avoid: Duplicating validation jobs across 3+ workflows
- ✅ Use: Centralized `TEMPLATE-validate-iac.yml` (docker-compose, terraform validation)
- New workflows inherit security jobs, cache setup, and validation checks

**Known Deduplication Debt** (archived for reference):
- `scripts/common-functions.sh` — deprecated, use `_common/` instead
- Inline `echo` logging in 12+ scripts — migrate to `log_*` in next Phase
- 27-copy `SCRIPT_DIR` pattern — now obsolete (init.sh handles this)

### Rule 7 — Copilot Trigger Pattern
When you need Copilot to apply governance standards to your code, use:
```
@workspace, apply governance standards: deduplication (check _common/), headers (metadata block), config separation (env vars), shared libs, use _template.sh for new scripts
```

For deduplication review across entire codebase:
```
@workspace, review governance compliance: logging systems, initialization patterns, config duplication, library adoption
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

**Last updated: April 17, 2026** | [All Issues](https://github.com/kushin77/code-server/issues) | [Deduplication Analysis](DEDUPLICATION-AND-EFFICIENCY-ANALYSIS.md) | [Script Writing Guide](docs/SCRIPT-WRITING-GUIDE.md)
