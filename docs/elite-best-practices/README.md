# Elite Best Practices Index

Purpose:
- Navigation-only landing zone for the repository's best-practices topics.
- Mirrors the canonical documentation SSOT in [../structure/README.md](../structure/README.md) without duplicating it.
- Keeps the repo free of loose best-practices files at the docs root.

## Layout

- `monorepo/` - canonical workspace layout, package boundaries, and migration evidence.
- `pnpm/` - workspace protocol, lockfile immutability, and package manager policy.
- `deep/` - long-form implementation notes and evidence trails.
- `shared/` - shared libraries, deduplication helpers, and reusable contracts.
- `indexed/` - index files and navigation-only entrypoints.
- `meta/` - metadata rules, headers, and document hygiene.
- `structure/` - folder maps and placement rules that point back to the SSOT.
- `repo-rules/` - governance, review, and duplication policy.
- `instructions/` - contributor workflow instructions and handoff guidance.
- `ssot/` - source-of-truth pointers for config, contracts, and indexed governance.
- `standard-naming-convention/` - naming and file-layout conventions.

## Operating Rule

- When a topic has a canonical home, link to it instead of copying the content here.
- When this index changes, update [../structure/README.md](../structure/README.md) and [../README.md](../README.md) together.