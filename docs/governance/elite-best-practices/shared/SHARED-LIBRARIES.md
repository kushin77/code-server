# Shared Libraries and Canonical Utilities

Purpose: define ownership, location, and adoption rules for shared code used across scripts, services, and tooling.

Status: ACTIVE
Lifecycle: active-production
Owner: platform engineering
Last Updated: 2026-04-18

## Shell Script Shared Libraries

All shared bash utilities live under `scripts/_common/`. **Do not duplicate.**

| File | Purpose | Key Functions |
|------|---------|---------------|
| `scripts/_common/init.sh` | Bootstrap entry point | `init_repo()`, `ensure_root()` |
| `scripts/_common/logging.sh` | Structured logging | `log_info`, `log_warn`, `log_error`, `log_fatal`, `log_debug` |
| `scripts/_common/config.sh` | Config loading | `load_env()`, `export_vars()` |
| `scripts/_common/utils.sh` | Generic utilities | `retry()`, `confirm()`, `die()` |
| `scripts/lib/nas.sh` | NAS mount helpers | `mount_nas()`, `unmount_nas()` |

## Adoption Rules

1. **Before writing any new helper**: search `scripts/_common/` and `scripts/lib/` first.
2. If the function exists → import it. If it almost fits → extend the shared file.
3. If truly new → add to the appropriate `_common/` or `lib/` file with a comment block.

## Duplicate Detection

Run this to detect shadowing:
```bash
grep -rn "^log_info\|^log_error\|^die\|^retry" scripts/ \
  --include="*.sh" | grep -v "_common/" | grep -v "lib/"
```
Any match is a violation — remove the shadow copy and source the shared library.

## Service-Level Shared Code

- Shared TypeScript types: `packages/shared-types/` (when JS monorepo matures)
- Shared Python utilities: `scripts/_common/` (sh wrappers that call Python)
- Shared configuration schemas: `config/` (YAML/JSON contract files)

## NAS-Backed Volume Ownership

All persistent state paths mount from NAS `192.168.168.56`:

| Volume Name | NFS Export | Notes |
|------------|-----------|-------|
| `code-server-workspace` | `/export/code-server/workspace` | User workspace |
| `code-server-profile` | `/export/code-server/profile` | IDE profile/settings |
| `code-server-profile-backups` | `/export/code-server/profile-backups` | Periodic backups |
| `ollama-data` | `/export/ollama` | LLM model storage |
| `postgres-backup` | `/export/postgres/backups` | DB PITR backups |

DB engines (`postgres-data`, `redis-data`, `prometheus-data`) stay `driver: local` — NFS causes locking issues.

## Related

- Deduplication analysis: [../deep/INDEXING-AND-META.md](../deep/INDEXING-AND-META.md)
- Repo rules: [../repo-rules/REPO-RULES-SSOT.md](../repo-rules/REPO-RULES-SSOT.md)
