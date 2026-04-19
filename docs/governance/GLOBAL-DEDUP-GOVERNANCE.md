# Global Dedup Governance

Version: 1.0  
Effective: 2026-04-17  
Owner: Platform Engineering

## Purpose

This policy eliminates overlap drift by enforcing single source of truth (SSOT) for critical infrastructure paths and blocking new duplicate variants in CI.

## Canonical Sources

1. Compose runtime: docker-compose.yml
2. Caddy runtime config: Caddyfile
3. Terraform entrypoint: terraform/main.tf

## Blocked Overlap Paths

These are legacy paths under freeze. They are listed for enforcement and migration tracking, not for active runtime edits.

Changes to these files are blocked by default in CI unless a documented waiver is used:

1. docker/docker-compose.yml
2. scripts/docker-compose.yml
3. docker-compose.production.yml
4. docker-compose.prod.yml
5. docker-compose.base.yml
6. docker-compose.dev.yml
7. Caddyfile.production
8. Caddyfile.tpl

Waiver control:

1. Set ALLOW_LEGACY_OVERLAP_EDIT=true in CI only when required.
2. Link waiver rationale in PR body and governance waiver issue.
3. Include rollback and migration plan back to canonical paths.

## Global Rules

1. No new top-level compose variants beyond docker-compose.yml.
2. No new Caddyfile variants beyond Caddyfile.
3. Keep main.tf and terraform/main.tf synchronized whenever either mirror is changed.
4. OAuth callback settings must use surface-specific variables in docker-compose.yml:
	OAUTH2_PROXY_IDE_REDIRECT_URL for ide.kushnir.cloud and OAUTH2_PROXY_PORTAL_REDIRECT_URL for kushnir.cloud.
5. New documentation files under docs/ must not create normalized filename collisions with existing docs.

## Enforcement

CI workflow:

1. .github/workflows/global-dedup-guard.yml

Guard script:

1. scripts/ci/enforce-global-dedup.sh

## Local Validation

Run before opening a PR:

```bash
bash scripts/ci/enforce-global-dedup.sh
```

## Migration Roadmap

1. Freeze overlap-prone legacy files (current phase).
2. Move all active changes to canonical files only.
3. Retire duplicated mirrors once no workflows/scripts depend on them.
4. Remove waiver path after legacy removal is complete.
