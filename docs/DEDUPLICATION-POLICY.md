**Lifecycle**: active-production

# Deduplication Policy

**Version:** 1.0.0  
**Date:** 2026-04-18  
**Enforced by:** `scripts/ci/detect-duplicate-helpers.sh` and `.github/workflows/global-dedup-guard.yml`

---

## Rule 1: Check Before You Write

Before implementing any helper function or utility, check these canonical locations in order:

1. `scripts/_common/utils.sh` — generic utilities
2. `scripts/_common/logging.sh` — structured logging
3. `scripts/_common/config.sh` — config loading
4. `scripts/_common/docker.sh` — Docker helpers
5. `scripts/_common/ssh.sh` — SSH helpers
6. `scripts/lib/secrets.sh` — secret fetching (GSM + .env fallback)
7. `scripts/lib/nas.sh` — NAS mount helpers
8. `scripts/lib/` — other shared libraries

**If the function exists there, use it. Never re-implement.**

---

## Canonical Helper Registry

### scripts/_common/logging.sh

| Function | Purpose | Use Instead Of |
|----------|---------|----------------|
| `log_info "msg"` | Structured INFO log | `echo "msg"`, `echo "[INFO] msg"` |
| `log_warn "msg"` | Structured WARN log | `echo "WARNING: msg"` |
| `log_error "msg"` | Structured ERROR log (non-fatal) | `echo "ERROR: msg" >&2` |
| `log_fatal "msg"` | Structured FATAL + exit 1 | `echo "FATAL" >&2; exit 1`, `die()` |
| `log_debug "msg"` | Debug log (off in prod) | `echo "[DEBUG]"` |
| `log_section "title"` | Section header separator | `echo "====="` patterns |
| `log_success "msg"` | Green success message | `echo "✅ ..."`|
| `log_failure "msg"` | Red failure message | `echo "❌ ..."` |
| `log_exec cmd` | Log + execute a command | manual `echo cmd && cmd` |

### scripts/_common/utils.sh

| Function | Purpose | Use Instead Of |
|----------|---------|----------------|
| `retry N cmd` | Retry command N times | manual retry loops |
| `require_command CMD` | Assert command exists | manual `which`/`command -v` checks |
| `require_file PATH` | Assert file exists | manual `[[ -f ]]` checks with die |
| `require_dir PATH` | Assert directory exists | manual `[[ -d ]]` checks |
| `require_var NAME` | Assert env var is set | manual `[[ -z "$VAR" ]]` + die |
| `add_cleanup "cmd"` | Register EXIT trap | ad-hoc `trap` declarations |
| `mktemp_dir` | Create temp dir with cleanup | `mktemp -d` without cleanup |
| `docker_ready` | Wait for Docker daemon | manual sleep loops |

### scripts/_common/config.sh

| Function | Purpose | Use Instead Of |
|----------|---------|----------------|
| `load_env FILE` | Load env from file | `source` or `set -a; . FILE` |
| `export_vars VAR1 VAR2` | Export vars to subshells | manual `export` calls |

### scripts/lib/secrets.sh

| Function | Purpose | Use Instead Of |
|----------|---------|----------------|
| `get_secret KEY [fallback]` | Fetch from GSM or .env | inline `gcloud secrets` calls |

### scripts/lib/nas.sh

| Function | Purpose | Use Instead Of |
|----------|---------|----------------|
| `mount_nas HOST EXPORT` | Mount NAS volume | inline `mount -t nfs` calls |
| `unmount_nas MOUNTPOINT` | Unmount with cleanup | inline `umount` calls |

---

## Rule 2: Initialization Pattern

All bash scripts must initialize via:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"
```

**Never** source `logging.sh`, `config.sh`, `utils.sh` individually — `init.sh` loads them all in the correct order.

---

## Rule 3: Compose File Canonical

| Use Case | Canonical File | Never Create |
|----------|---------------|-------------|
| Production deployment | `docker-compose.production.yml` | `docker-compose.prod.yml`, `docker/docker-compose.yml` |
| Local development | `docker-compose.yml` | `docker-compose.dev-v2.yml` |
| Base services only | `docker-compose.base.yml` | `docker-compose.minimal.yml` |

---

## Rule 4: No Inline config

Never hardcode:
- IPs → use `${DEPLOY_HOST:-default}`
- Domains → use `${DOMAIN:-default}`
- Ports in env vars → use `${PORT:-default}`

All defaults must exist in `.env.example`.

---

## Deduplication Debt Tracker

| File | Pattern | Status | Owner |
|------|---------|--------|-------|
| `scripts/common-functions.sh` | Deprecated; use `_common/` | ⚠️ Legacy | Platform |
| 12+ scripts with inline `echo` | Migrate to `log_*` | 🔄 In Progress | Platform |

---

## CI Enforcement

The `dedup-guard` CI check (`scripts/ci/detect-duplicate-helpers.sh`) scans for:
- Function names defined in `scripts/_common/` being re-defined in other scripts
- Inline `echo "ERROR:"` patterns (when `log_error` should be used)
- Inline `exit 1` without `log_fatal` (when `log_fatal` should be used)

See `.github/workflows/global-dedup-guard.yml` for trigger conditions.

---

## Related Issues
- #625 — Deduplication-as-Policy
- DEDUPLICATION-AND-EFFICIENCY-ANALYSIS.md — full audit findings
