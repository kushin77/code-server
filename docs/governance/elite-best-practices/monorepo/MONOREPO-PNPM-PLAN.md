# Monorepo pnpm Plan

Purpose: standardize JS/TS package management across backend, frontend, and extensions using pnpm workspaces.

Status: ACTIVE
Lifecycle: active-production
Last Updated: 2026-04-18

Implementation Mode: staged. Root workspace files are introduced only in dedicated PRs that satisfy root-budget governance.

## Workspace Packages

- `backend`
- `frontend`
- `session-broker`
- `extensions/*`
- `tests/e2e`

## Rules

- Use single lockfile at repo root (`pnpm-lock.yaml`)
- Use `workspace:^` for internal package version links
- Put shared external versions in `catalog:` entries in `pnpm-workspace.yaml`
- Keep shared scripts in root workspace and reuse from package scripts

## Bootstrapping

```bash
pnpm install -r
pnpm -r test
pnpm -r lint
```

## Governance Checks

- no `npm install` in child packages for CI jobs
- no duplicate dependency versions unless justified
- shared lint/test config centralized where feasible
