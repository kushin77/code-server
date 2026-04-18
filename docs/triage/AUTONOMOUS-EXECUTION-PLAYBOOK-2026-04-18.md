# Autonomous Execution Playbook (2026-04-18)

## Scope
This playbook is the canonical handoff for parallel agents working from branch `feat/671-issue-671`.

## Canonical Active Issues
- Program: #659
- Epic: #660
- Branch feature: #671
- CI stabilization blocker: #687
- Production OAuth redeploy blocker: #688

## Closed Duplicate
- #689 (duplicate of #687)

## Dependency Order
1. Resolve #687 first (branch CI determinism).
2. Resolve #688 second (production callback redeploy execution path + runtime verification).
3. Resume completion/closure flow for #671 once #687 and #688 are closed.

## Issue #687 Execution Checklist
- Reproduce failing workflows listed in issue body.
- Fix root causes in workflows/scripts for monorepo path migration (`apps/*` + compatibility symlinks).
- Ensure all checks are deterministic and idempotent.
- Re-run failed workflows and attach run URLs proving green state.

## Issue #688 Execution Checklist
- Provision an executable path to prod host:
  - preferred: register self-hosted Actions runner for repo
  - fallback: non-interactive SSH access to `192.168.168.31`
- Execute idempotent script:
  - `bash scripts/deploy/redeploy-portal-oauth-routing.sh`
- Verify live redirects:
  - `curl -skI 'https://kushnir.cloud/oauth2/start?rd=%2F' | tr -d '\r' | grep -i '^location:'`
  - `curl -skI 'https://ide.kushnir.cloud/oauth2/start?rd=%2F' | tr -d '\r' | grep -i '^location:'`
- Confirm apex callback points to `https://kushnir.cloud/oauth2/callback`
- Post evidence in issue comments and close issue.

## Governance Rules
- No manual in-container edits.
- Compose-driven, immutable, idempotent changes only.
- If not committed, it does not exist.
- Use `Fixes #N` in PRs to close issues automatically on merge.

## Current Runtime Facts
- Local script validation passes; deploy execution fails due missing auth path to prod host.
- Self-hosted runner count observed as zero for this repo during triage.
- Live apex redirect still points to IDE callback until #688 is executed.
