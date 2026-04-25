---
description: "Use when: completing any task or issue to enforce commit-push-main-merge-redeploy-cleanup workflow and prevent branch sprawl"
applyTo: "**"
---

# Branch Lifecycle Mandate

This policy is mandatory after every task or issue is marked complete.

## Completion sequence (must run in order)

1. Validate completion with relevant checks/tests.
2. Commit immediately after validation with a task or issue scoped message.
3. Push commit to remote.
4. Merge into `main` (direct or via PR) as the only integration target.
5. Redeploy from `main`.
6. Delete the task branch locally.
7. Delete the task branch remotely.

## Anti-branch-sprawl controls

- Exactly one active branch per task or issue.
- No stacked feature branches unless explicitly approved.
- No long-lived inactive branches.
- Do not start the next task until local and remote cleanup is complete.
- Contributors must install repository-managed git hooks (`pnpm hooks:install`) to enforce pre-push hygiene checks locally.

## Completion evidence (required in status output)

- Commit SHA
- Push confirmation
- Main merge confirmation
- Redeploy confirmation
- Local branch deletion confirmation
- Remote branch deletion confirmation

## Blocker handling

If any step cannot be completed, report:

- Blocked step
- Concrete reason
- Named owner
- ETA to resolution

Do not defer branch cleanup to a later session.
