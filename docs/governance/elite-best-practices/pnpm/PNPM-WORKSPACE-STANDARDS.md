# pnpm Workspace Standards

Purpose: canonical rules for pnpm-based workspace package management across all JS/TS packages.

Status: ACTIVE
Lifecycle: active-production
Owner: platform engineering
Last Updated: 2026-04-18

## Core Rules

1. **Single lockfile** — `pnpm-lock.yaml` lives at repo root only. Never per-package lockfiles.
2. **Workspace protocol** — internal packages reference each other with `workspace:^`, never with version ranges.
3. **No npm/yarn** — `npm install` and `yarn` are banned in CI and pre-commit hooks. pnpm only.
4. **Hoisting** — no `shamefully-hoist`. Use explicit dependencies and pnpm catalogs for shared external versions.
5. **Root budget** — root `package.json` changes require a dedicated PR tagged `pnpm-workspace`.

## .npmrc Defaults (repo root)

```ini
shamefully-hoist=false
strict-peer-dependencies=true
auto-install-peers=false
save-workspace-protocol=true
```

## Workspace Package Boundaries

- `backend/` — server-side Node.js services
- `frontend/` — browser SPA/extensions
- `session-broker/` — per-session runtime isolation service
- `extensions/*` — VS Code extension packages
- `tests/e2e/` — Playwright smoke and regression suites
- `scripts/` — tooling (not a pnpm package; shell only)
- `terraform/` — IaC (not a pnpm package)

## Shared Versions

- Repeated external dependency ranges belong in `catalog:` entries in `pnpm-workspace.yaml`.
- Packages should reference shared versions with `catalog:` rather than duplicating version ranges in each manifest.

## Bootstrap

```bash
# From repo root on deployment host
pnpm install -r
pnpm -r run build
pnpm -r run test
pnpm -r run lint
```

## CI Enforcement

- `pnpm install --frozen-lockfile` in all CI jobs (no drift from lockfile)
- `scripts/ci/check-pnpm-lockfile.sh` also validates catalog usage, workspace membership, and internal `workspace:^` references.
- Lockfile change PRs require explicit label `lockfile-update`
- `pnpm audit --audit-level high` blocks merge on HIGH/CRITICAL CVEs

## Related

- Monorepo structure: [../monorepo/MONOREPO-PNPM-PLAN.md](../monorepo/MONOREPO-PNPM-PLAN.md)
- Repo rules enforcement: [../repo-rules/REPO-RULES-SSOT.md](../repo-rules/REPO-RULES-SSOT.md)
