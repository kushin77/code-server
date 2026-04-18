# Document Metadata Standards

Purpose: enforce consistent metadata headers, lifecycle status, and hygiene rules across all repo documentation.

Status: ACTIVE
Lifecycle: active-production
Owner: platform engineering
Last Updated: 2026-04-18

## Required Metadata Block (every new doc)

Every new `.md` file under `docs/` must open with:

```markdown
# <Title>

Purpose: <one sentence>
Status: ACTIVE | ARCHIVED | DRAFT
Lifecycle: active-production | archived | draft
Owner: platform engineering | <team>
Last Updated: YYYY-MM-DD
```

Every new bash script must open with:

```bash
#!/usr/bin/env bash
# @file        scripts/<path>/<filename>.sh
# @module      <category/subcategory>
# @description <one-line purpose>
```

Run `./scripts/fix-metadata-headers.sh` to auto-fix missing headers.

## Lifecycle States

| Status | Meaning | Action |
|--------|---------|--------|
| `ACTIVE` | Current, authoritative | Maintain |
| `DRAFT` | In-progress, not authoritative | Complete or discard |
| `ARCHIVED` | Superseded, kept for history | Do not update content; add redirect header |

## Naming Conventions

See [../standard-naming-convention/SNC.md](../standard-naming-convention/SNC.md) for the full SNC.

### Key Rules

- Files: `UPPER-KEBAB-CASE.md` for docs, `lower-kebab-case.sh` for scripts
- Branches: `<type>/<scope>-<description>` (e.g., `feat/storage-nfs-volumes`)
- Issues: `P<0-3>: <Verb> <noun>` prefix (e.g., `P0: Fix oauth2-proxy crash`)
- Commits: Conventional commits — `feat|fix|refactor|docs|chore|ci(scope): message`

## Document Hygiene Rules

1. **No loose files at repo root** — only `README.md` lives there. Everything else goes under `docs/`.
2. **No duplicate docs** — before creating a file, search for an existing canonical home.
3. **No orphan docs** — every doc must be linked from a parent index (this file or `indexed/INDEX.md`).
4. **Redirect before delete** — deprecated docs get a redirect header before removal (1 sprint grace period).
5. **Archive, don't delete history** — superseded docs move to `docs/archives/` with date suffix.

## Anti-Patterns

- ❌ Creating `PHASE-N-SOMETHING.md` at docs root for every new phase
- ❌ Copying content across files instead of linking
- ❌ Using TODO/WIP in ACTIVE docs (move to GitHub issues instead)
- ❌ Status = ACTIVE on a doc that hasn't been updated in 3+ months (auto-flag for review)

## Enforcement

The hardening guard (`scripts/ci/check-compose-hardening-guard.sh`) catches compose-level violations.
A pre-commit hook (`.husky/pre-commit`) blocks commits of files missing the required metadata block.
