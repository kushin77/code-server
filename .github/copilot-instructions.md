# Copilot Instructions for kushin77/code-server

## ✅ Kushnir.cloud / KC Branding (April 21, 2026)
**Active public brand**: Kushnir.cloud (KC)  
**Domain**: kushnir.cloud (apex), ide.kushnir.cloud (IDE subdomain)  
**Internal shorthand**: KC (example: KC IDE, KC infrastructure)  
**Upstream exception**: Keep "code-server" only for codercom/code-server image references and third-party protocol names.  
**Issue tracker**: See #1187 (rebrand parent) for rollout details.

---

## Code Governance Rules (Copilot Enforcement)

### Rule 1 — No Duplication
Before writing any helper function or utility, check these canonical locations:
- `scripts/_common/utils.sh` — generic utilities (retry, confirm, die, log_*)
- `scripts/_common/logging.sh` — log_info, log_warn, log_error, log_fatal, log_debug
- `scripts/_common/config.sh` — config loading (load_env, export_vars)
- `scripts/fetch-gsm-secrets.sh` — GSM secret bootstrap (GSM first; `.env` fallback only for local dev)
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

Default secret source is Google Secret Manager. Use the GSM bootstrap script for secret material, service accounts for workload identity and automated API access, and SSH keys only for host transport/authentication.

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

**scripts/fetch-gsm-secrets.sh**
- `source scripts/fetch-gsm-secrets.sh` — populate GSM-backed secret env vars for the current shell

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
- Master config SSOT: `.env.schema.json` (env var schema), `CONFIG-SSOT-MASTER.md` (precedence map), `terraform/variables.tf` (IaC config)

**Credential Defaults**: GSM is the default secret source; service accounts own machine-to-machine API access; SSH keys are limited to remote host login and transport.

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

### Rule 8 — GitHub Issue Creation Governance (MANDATED)

**CRITICAL MANDATE: All GitHub issue creation MUST use the unified script.**

#### ✅ DO: Use unified issue creation
```bash
# Always use this:
source scripts/_common/issue-create-unified.sh
copilot_create_issue \
  --title "Issue title" \
  --body "Description" \
  --priority P1 \
  --type feature \
  --repo kushin77/code-server \
  --check-duplicates  # Prevents duplicates
```

#### ❌ DON'T: Direct gh CLI calls
```bash
# NEVER do this:
gh issue create --title "..." --body "..." --label "..."  # ← FORBIDDEN
```

#### Why This Matters
- **Deduplication**: Prevents duplicate issues (common problem)
- **Label Enforcement**: Every issue MUST have priority (P0/P1/P2/P3)
- **Consistency**: Unified label format across all repos
- **Copilot Integration**: Seamless issue creation in every session
- **Production Priority**: Forces P0/P1 triage before new features

#### Copilot Behavior
1. **Every Copilot session** loads `scripts/_common/issue-create-unified.sh`
2. **Before creating ANY issue**, Copilot MUST:
   - Check for duplicates (--check-duplicates flag)
   - Assign priority (P0/P1/P2/P3)
   - Apply type-based label (feature/bug/infrastructure/etc.)
   - Verify production P0/P1 issues exist (suggest fixing those first)
3. **Production Rule**: If P0 or P1 issues exist → focus on them before new features

#### Enforcement
- ✅ CI guard: `scripts/ci/check-issue-governance.sh` blocks commits with direct gh calls
- ✅ Pull Request Template: Reminds about using unified script
- ✅ Copilot Instructions: This rule (Rule 8) is canonical source of truth

#### Common Patterns

**Creating a P0 production issue:**
```bash
copilot_create_issue \
  --title "P0 SECURITY: Hardcoded password in config" \
  --body "Found hardcoded password in Caddyfile line 42..." \
  --priority P0 \
  --type security \
  --check-duplicates
```

**Creating a feature request:**
```bash
copilot_create_issue \
  --title "Add new feature XYZ" \
  --body "Feature description..." \
  --priority P2 \
  --type feature \
  --check-duplicates
```

**Checking production priorities before work:**
```bash
source scripts/_common/issue-create-unified.sh
should_prioritize_production kushin77/code-server  # Returns 0 if P0/P1 exist
list_production_priorities kushin77/code-server    # Show top issues
```

**Dry run (safe preview):**
```bash
copilot_create_issue \
  --title "..." \
  --priority P1 \
  --dry-run  # Shows what would be created without actually creating
```

#### Labels Applied Automatically
- **Priority**: P0, P1, P2, P3 (required)
- **Type**: enhancement, bug, refactor, documentation, infrastructure, security, ops, testing, performance, accessibility (when specified)
- **Custom**: Any additional labels via --labels "label1,label2"

#### Cross-Repository Support
This script works across ANY organization repo:
```bash
copilot_create_issue \
  --title "..." \
  --priority P1 \
  --repo owner/other-repo  # Override default repo
```

### Rule 9 — Copilot Session Initialization (ALWAYS ON - IaC, Immutable, Idempotent)

**CRITICAL MANDATE: Every Copilot task MUST search existing work BEFORE starting execution.**

This rule makes Copilot **search-aware and duplicate-preventing** as an always-on mechanism.

#### ✅ DO: Always search before executing

Every Copilot session **MUST** source the session initialization script and run the pre-execution check:

```bash
# 1. ALWAYS load session init at start of every task
source scripts/_common/copilot-session-init.sh

# 2. RUN PRE-EXECUTION CHECK before starting any work
copilot_pre_execute_check \
  --task "description of work to perform" \
  --repo kushin77/code-server \
  --issue 1234  # optional: if working on specific issue

# 3. EXAMINE OUTPUT
#    - If returns 0: green light, proceed with work
#    - If returns 1: blocking issues found, review findings and update plan
```

#### What Pre-Execution Check Does

1. **Validates Idempotency** (✅ immutable pattern)
   - Rejects non-idempotent operations (DELETE, DROP, force-push, etc.)
   - Ensures task is safe to run multiple times without side effects
   - BLOCKS execution if task contains dangerous operations

2. **Checks if Work Already Complete** (✅ prevents rework)
   - Searches GitHub issues for closed/completed work
   - Returns status if issue is already resolved
   - Prevents duplicate effort on solved problems

3. **Detects Duplicate Issues** (✅ deduplication)
   - Searches for related open issues with similar keywords
   - Lists found issues with links
   - Recommends linking or updating existing work

4. **Checks Work in Progress** (✅ prevents conflicts)
   - Scans open PRs for related implementations
   - Identifies if someone else is working on same task
   - Suggests collaboration or priority coordination

5. **Searches Existing Code** (✅ reuse prevention)
   - Scans repository for existing implementations
   - Finds similar components or utilities
   - Recommends refactoring instead of reimplementing

6. **Provides Execution Recommendation** (✅ guided workflow)
   - Green light: no blocking issues → proceed
   - Caution: review found issues → update plan
   - Go/No-Go decision before starting

#### IaC, Immutable, Idempotent Principles

**IaC (Infrastructure as Code)**:
- Session initialization is code (`scripts/_common/copilot-session-init.sh`)
- Searches are deterministic and repeatable
- All decisions are logged and traceable
- Can be version-controlled and audited

**Immutable**:
- Session state is read-only (no modifications to GitHub during check)
- Findings are reported but not applied automatically
- Human makes final decision before proceeding
- Check results cannot be overwritten or changed

**Idempotent**:
- Can run pre-execution check multiple times with same result
- Doesn't mutate repo state or GitHub state
- Safe to re-run check before each attempt
- No side effects from check itself

#### Always-On Activation

The pre-execution check is activated in two ways:

1. **Explicit** (manual):
   ```bash
   source scripts/_common/copilot-session-init.sh
   copilot_pre_execute_check --task "..." --repo kushin77/code-server
   ```

2. **Implicit** (via session hooks - future):
   - Integrate into Copilot session initialization
   - Auto-run on every Copilot prompt
   - Prompt user to confirm before proceeding

#### Usage Examples

**Before Creating Feature**:
```bash
source scripts/_common/copilot-session-init.sh
copilot_pre_execute_check \
  --task "Add JWT token refresh caching to Redis" \
  --repo kushin77/code-server

# Output will show:
# - Whether related JWT issues exist
# - Whether JWT caching is already implemented
# - Whether someone else is working on this
# - Recommendation: proceed or update existing work
```

**Before Starting Bug Fix**:
```bash
copilot_pre_execute_check \
  --task "Fix AdminControlsPage rendering loop" \
  --issue 1023 \
  --repo kushin77/code-server

# Output will show:
# - Issue #1023 status (open/closed)
# - Related rendering issues
# - Existing code in AdminControlsPage
# - Recommendation: green light or research first
```

**Before Infrastructure Work**:
```bash
copilot_pre_execute_check \
  --task "Add Redis HA with Sentinel for session store" \
  --repo kushin77/code-server

# Output will show:
# - Whether Redis HA issues exist
# - Whether Sentinel is already configured
# - Related database HA work
# - Recommendation: start fresh or extend existing
```

#### Enforcement & CI Integration

- **CI Check**: `scripts/ci/check-copilot-session-compliance.sh` validates that major tasks have pre-execution checks logged
- **PR Template**: Reminds to document pre-execution check findings
- **Copilot Logs**: Session init output is captured for audit trail
- **Governance**: Rule 9 violations flagged in code review (pre-execution check not run)

#### Related Files

- **Script**: `scripts/_common/copilot-session-init.sh` (main implementation)
- **CI Guard**: `scripts/ci/check-copilot-session-compliance.sh` (enforcement)
- **Documentation**: `docs/COPILOT-SESSION-INITIALIZATION.md` (guide)

#### Non-Negotiable Principles

1. **Every task begins with search** — No exceptions
2. **Idempotency is non-negotiable** — Reject operations that cannot run twice
3. **Findings must be reviewed** — Not just checked, but acted upon
4. **Workflow is human-guided** — Script recommends, human decides
5. **All searches are logged** — Audit trail for decisions

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
- Every merge to `main` or direct push to `main` MUST trigger production redeploy immediately (no manual deferral)
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

**Last updated: April 18, 2026** | [All Issues](https://github.com/kushin77/code-server/issues) | [Deduplication Analysis](DEDUPLICATION-AND-EFFICIENCY-ANALYSIS.md) | [Script Writing Guide](docs/SCRIPT-WRITING-GUIDE.md)
