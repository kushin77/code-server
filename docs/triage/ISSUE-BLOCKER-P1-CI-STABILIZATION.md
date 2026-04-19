## Summary
The active branch feat/671-issue-671 has a repeated CI failure cluster after monorepo refactor work. This blocks autonomous merge and downstream deployment confidence.

Recent failing runs include:
- Workflow Lint
- Validate Configuration Files (startup_failure)
- Enforce Repository Structure
- CI Validate
- CI - Lint & Format
- CI - Unit & Integration Tests
- AI Indexing Quality Gate
- Production Readiness Gate

## Goal
Produce a deterministic CI baseline where required gates pass on feat/671-issue-671 and future agent branches without manual retries.

## Required Work
- [ ] Triage each failing workflow to a concrete root cause (path move, lint config, missing tooling, startup guard)
- [ ] Fix workflows/scripts to support monorepo path migration (apps/* + compatibility symlinks)
- [ ] Ensure validation jobs are idempotent and resilient to read-only/non-prod environments
- [ ] Remove flaky assumptions and pin required toolchain versions
- [ ] Re-run full gate set and capture passing evidence

## Acceptance Criteria
- [ ] No failure or startup_failure conclusions on required checks for the branch head
- [ ] Workflow Lint, Validate Configuration Files, and CI Validate pass consistently
- [ ] Production readiness and AI indexing gates pass or have approved waiver with documented rationale
- [ ] Follow-up PR references this issue with Fixes #<issue>

## Evidence Seed (branch failures)
- 24597129103 Workflow Lint
- 24597129104 Validate Configuration Files (startup_failure)
- 24597129112 Enforce Repository Structure
- 24597129123 CI - Unit & Integration Tests
- 24597129201 CI Validate
