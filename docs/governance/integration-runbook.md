# GitHub + GitLab Integration Runbook

**Issue:** #3157 - GitHub + GitLab Integration Hardening and PMO Workflow Automation
**Purpose:** Document the operational path, permission model, and fallback handling for issue automation.
**Status:** Active reference runbook

## Scope

This runbook covers the repo-local automation that links pull requests to issues, enforces issue lifecycle governance, and keeps gap-analysis output aligned with tracked work items.

Primary entry points:

- [.github/workflows/auto-link-pr-to-issue.yml](../../.github/workflows/auto-link-pr-to-issue.yml)
- [scripts/automation/auto-link-pr-to-issue.sh](../../scripts/automation/auto-link-pr-to-issue.sh)
- [scripts/_common/issue-lifecycle-governor.sh](../../scripts/_common/issue-lifecycle-governor.sh)
- [scripts/ops/gap-analysis-audit.sh](../../scripts/ops/gap-analysis-audit.sh)

## Permission Model

The automation is intentionally scoped to the minimum permissions needed for each job:

- PR-to-issue linking requires `pull-requests: read`, `issues: write`, and `contents: read`.
- Policy validation and governance checks use repository read access plus the ability to publish logs and summaries.
- Issue lifecycle checks run through the GitHub API wrapper in `scripts/_common/` and operate against the repository's token source of truth.

This keeps the automation auditable and avoids broad repository mutation rights.

## Standard Flow

1. A pull request is opened, reopened, synchronized, or edited.
2. The workflow extracts issue references from the PR title, branch name, or body.
3. The automation posts a linking comment on each related issue.
4. GitHub's native cross-reference closes the issue when the PR merges and the commit message or PR body contains a closing reference.
5. Governance checks verify that closed issues still have a documented resolution path.

## Gap-Analysis Flow

The gap-analysis path is used when a document or audit reveals a missing control.

1. Run the gap-analysis audit script.
2. Review the generated findings against the existing issue register.
3. Create or update tracked issues for unresolved gaps.
4. Link the resulting issue to the corresponding governance artifact or audit note.

This keeps PMO tracking aligned with the repo's actual state rather than a stale checklist.

## Fallback Paths

If automation fails or a GitHub event does not trigger correctly, use the following manual paths:

- Add a manual issue comment that references the related PR number.
- Use `gh issue comment <issue-number>` to attach evidence and context.
- Close the issue manually only after the evidence comment is present and the fix is merged.
- If the auto-link workflow cannot infer an issue number, add the issue reference explicitly in the PR body as `Fixes #<number>`.
- If the gap-analysis run cannot create a tracked issue automatically, record the finding in the audit output and open the issue manually.

## Validation Checklist

Before marking the integration work complete, confirm:

- The auto-link workflow file exists and is scoped to PR activity.
- The auto-link script can parse issue references from title, branch, and body.
- The lifecycle governor still flags missing priority labels and unresolved closures.
- The gap-analysis audit artifacts point to tracked issues rather than unowned findings.
- The fallback process is documented in this runbook.

## Operational Notes

- Prefer repo-local evidence over ad hoc manual updates.
- Keep automation logs under `artifacts/automation-logs/` when running locally.
- Treat the runbook as the authoritative fallback reference for PMO and integration incidents.

---

**Last Updated:** May 1, 2026
**Owner:** Governance / PMO Automation