# Agent Development Triage and Orchestration - Current Program

Date: April 18, 2026
Status: Active

This document is the live triage plan for autonomous implementation.

## Open Issue Set

Program:
- #659 Program: Production transition (monorepo + code-server co-dev + active-active reliability)

Epics:
- #660 EPIC: True monorepo and pnpm migration
- #661 EPIC: code-server core plus enhancement co-development model
- #662 EPIC: Active-active autoscale and zero-downtime service continuity (.31/.42)
- #663 EPIC: Release engineering and operational hardening for production mode

Sprint gates:
- #664 Sprint Gate: Monorepo foundation approved
- #665 Sprint Gate: Monorepo migration execution complete
- #666 Sprint Gate: code-server co-development pipeline proven
- #667 Sprint Gate: Active-active autoscale and failover drills passed
- #668 Sprint Gate: Production cutover and SLO sign-off complete

Implementation lane:
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

Persistent tracker:
- #291 VSCode Crash RCA and stability tracking (never close)

## Priority and Execution Order

Execution order:
1. #664 and #660
2. #665 and #661
3. #666 and #662
4. #667, #663, and #668
5. #669 -> #676 architecture and CI implementation lane
6. #677 -> #683 resilience/release/verification lane
7. Close #659 after all child epics/gates meet acceptance criteria

The persistent tracker #291 remains open and is updated with evidence weekly.

## Triage Quality Requirements

Every open issue must have:
- priority label
- `agent-ready` label
- autonomous execution brief comment
- clear acceptance criteria in body

Triage command:

```bash
GITHUB_TOKEN="<token>" bash scripts/ops/triage-issues-autonomous.sh
```

Live verification command:

```bash
gh issue list --state open --limit 50
```

## Delivery Rules

- Code and IaC only; no ephemeral-only completion claims.
- Immutable and idempotent changes.
- Canonical shared libraries only.
- Commit and PR must reference issue linkage.
- Keep scope minimal and verifiable.

## Definition of Done

For implementation issues:
- merged to main
- tests and validation passing
- rollout/rollback notes documented in PR
- issue contains merge evidence and verification output

For meta/epic issues:
- all child acceptance criteria met
- evidence linked from merged PRs
- issue summary includes operational verification
