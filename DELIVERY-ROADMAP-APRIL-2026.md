# Delivery Roadmap - Current Program (April 18, 2026)

Status: Active
Scope: Current open issue set centered on #659

## Objective

Deliver the current platform program tracked by #659 and its epics/sprint-gates (#660-#668), while maintaining crash stability tracking in #291.

## Active Issue Lanes

Program umbrella:
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

Implementation lane (P1 execution backlog):
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

Persistent:
- #291 VSCode Crash RCA and stability tracking (never close)

## Execution Order

Phase 1:
- #664 monorepo foundation gate
- #660 monorepo and package-management epic

Phase 2:
- #665 migration execution gate
- #661 co-development model epic

Phase 3:
- #666 co-development pipeline gate
- #662 active-active continuity epic
- #667 active-active failover gate

Phase 4:
- #663 release engineering and hardening epic
- #668 production cutover and SLO gate

Phase 5:
- #669-#676 monorepo/co-development architecture and CI implementation

Phase 6:
- #677-#683 active-active reliability, release train, verification, and rollback hardening

Program closure:
- Validate #660-#668 acceptance evidence
- Close #659 after child completion and rollout verification
- Keep #291 open with periodic updates

## Mandatory Delivery Controls

- All changes committed to git (no ephemeral-only updates).
- IaC-first and immutable configuration changes.
- Idempotent scripts and deploy paths.
- Canonical shared libs only, no duplicate helper logic.
- No hardcoded secrets, hosts, or credentials.

## Agent Readiness Checklist

- Issue has priority label and `agent-ready`.
- Autonomous execution brief exists.
- Dependencies and acceptance criteria are explicit in issue body.
- Implementation branch references issue in commit and PR body.

## Historical Note

This file supersedes the earlier 26-issue roadmap tied to now-closed #650-era work.
Current live issue state always takes precedence over static roadmap text.
