# Agent Execution Quick Start Guide

Status: Active as of April 18, 2026

Canonical machine-readable execution source:
- `config/issues/agent-execution-manifest.json`

This guide is the current source of truth for autonomous issue execution in this repository.

## What To Do First

1. Pull latest main.
2. Read `AGENT-TRIAGE-APRIL-18-2026.md`.
3. Start with issue #659 (program umbrella).
4. Execute sprint gates in order: #664 -> #665 -> #666 -> #667 -> #668.
5. Execute implementation lane #669 -> #683 in sequence grouped by dependency.
6. Maintain #291 as persistent tracker (never close).

## Current Open Program

- #659 Program: Production transition (monorepo + code-server co-dev + active-active reliability)
- #660 EPIC: True monorepo and pnpm migration
- #661 EPIC: code-server core plus enhancement co-development model
- #662 EPIC: Active-active autoscale and zero-downtime service continuity (.31/.42)
- #663 EPIC: Release engineering and operational hardening for production mode
- #664 Sprint Gate: Monorepo foundation approved
- #665 Sprint Gate: Monorepo migration execution complete
- #666 Sprint Gate: code-server co-development pipeline proven
- #667 Sprint Gate: Active-active autoscale and failover drills passed
- #668 Sprint Gate: Production cutover and SLO sign-off complete
- #669 Define monorepo target architecture and package boundaries
- #670 Bootstrap pnpm workspace and lockfile governance
- #671 Refactor repository layout into apps/packages/infra structure
- #672 Migrate CI to pnpm workspace-aware pipelines
- #673 Define upstream fork/sync operating model for code-server
- #674 Build dual-track CI: upstream validation and enhancement regression
- #675 Create compatibility contract tests for core workstation workflows
- #676 Document enhancement module boundaries and extension points
- #677 Implement traffic policy for .31/.42 active-active routing
- #678 Externalize and replicate runtime state for seamless failover
- #679 Build zero-downtime deploy orchestration with health gates
- #680 Run resilience drills and publish active-active production runbook
- #681 Define production release train and promotion policies
- #682 Implement automated pre/post deploy verification gates
- #683 Create rollback validation suite and game-day checklist
- #291 Persistent crash RCA tracker (never close)

Live source of truth:
- `gh issue list --state open --limit 50`
- `python3 scripts/ops/issue_execution_manifest.py queue`
- If issue titles change, prefer GitHub state over static text.

## Execution Rules

- Use conventional commits: `feat|fix|refactor|docs(scope): message`.
- Include issue references in commit/PR body (`Fixes #NNN` for implementation issues).
- One workstream per branch.
- Prefer immutable and idempotent changes.
- Keep all operational state in code and IaC.
- Use canonical shared libraries (`scripts/_common/`, `scripts/lib/`) and avoid duplication.
- Never hardcode credentials, hosts, or secrets.
- Do not manually close persistent issue #291.

## Branch and PR Pattern

```bash
git checkout main && git pull origin main
git checkout -b feat/issue-665-foundation-contract

# implement
# test

git add .
git commit -m "feat(platform): implement foundation contract gate (Fixes #665)"
git push origin feat/issue-665-foundation-contract

gh pr create --title "feat(platform): implement foundation contract gate" --body "Fixes #665"
```

## Triage and Readiness Command

```bash
GITHUB_TOKEN="<token>" bash scripts/ops/triage-issues-autonomous.sh
python3 scripts/ops/issue_execution_manifest.py validate
```

Expected result:
- Open issues have priority label
- Open issues have `agent-ready`
- Autonomous execution brief comment exists

## Completion Definition

A work item is complete only when all are true:
- Code and IaC merged to `main`
- Tests and validation checks pass
- Issue reflects merged evidence
- No local-only artifacts remain

## Historical Note

Earlier guidance that starts from #650 is obsolete and superseded by this document.
