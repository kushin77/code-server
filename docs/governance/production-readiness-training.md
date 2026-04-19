# Production Readiness Gate Training

## Purpose

This document is the training artifact for issue #381 and the production-readiness gate process.

## Audience

- PR authors for non-trivial changes
- Non-author peer reviewers
- On-call and operations reviewers

## Required Outcomes

After this walkthrough, the reviewer and author should be able to:

1. Classify a PR as trivial or non-trivial.
2. Complete the Phase 1-4 readiness sections in the PR template.
3. Provide rollout evidence, rollback evidence, and waiver traceability.
4. Attach load-test and post-deploy certification evidence.

## Walkthrough Agenda

1. Review the PR template readiness sections.
2. Review the runbook: docs/runbooks/production-readiness-gate.md.
3. Run the baseline load-test harness: scripts/loadtest/k6-baseline.js.
4. Validate rollback command and incident drill path.
5. Record approval comment link in the PR `Training evidence` field.

## Evidence Template

- Reviewer:
- Date:
- PR:
- Approval comment or note link:
- Follow-up actions:

## Owner

- Primary owner: Platform Engineering
- Canonical tracking issue: #381