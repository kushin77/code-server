# Branch Policy

Purpose: canonical branch naming and cleanup policy for this repository.

## Branch Types

- `main` - protected production branch
- `develop` - integration branch when used for longer-lived coordination
- `feature/<issue>-<slug>` - feature work tied to a GitHub issue
- `bugfix/<issue>-<slug>` - corrective fixes
- `hotfix/<issue>-<slug>` - emergency production fixes
- `release/<version>` - release preparation branches

## Naming Rules

- Keep branch names short and descriptive.
- Include the GitHub issue number when the work is issue-backed.
- Avoid generic branch names such as `temp`, `test`, or `work`.
- Prefer one branch per issue or per logical slice of work.

## Cleanup Rules

- Delete merged local branches after the PR is merged.
- Delete stale remote branches once the work is merged or superseded.
- Keep only active branches that still have a live issue, PR, or deployment dependency.
- Use the cleanup workflow before release or after large merge bursts.

## Automation

- Cleanup workflows already exist in `.github/workflows/cleanup-stale-branches.yml` and `.github/workflows/branch-cleanup.yml`.
- Use those workflows as the default path for stale-branch pruning.

## Operational Checklist

- [ ] Branch name follows the naming rules above
- [ ] Issue or PR link exists for the branch
- [ ] Branch has a clear delete condition
- [ ] Cleanup workflow has been run or scheduled
- [ ] No stale remote refs remain after the release train

## References

- [README.md](README.md)
- [OPERATIONS-INDEX.md](OPERATIONS-INDEX.md)
- [DEPLOYMENT-CHECKLIST.md](DEPLOYMENT-CHECKLIST.md)

<!-- Runbook tracking: #1674 -->
