# Contributing Guidelines — Branch Management

**Purpose:** Establish clear branch naming, lifecycle, and cleanup policies to prevent branch sprawl  
**Last Updated:** April 19, 2026  
**Status:** Active policy

---

## Branch Naming Conventions

All branches must follow this pattern:
```
<type>/<jira-or-issue-number>-<short-description>
```

### Valid Types

| Type | Purpose | Example | Lifetime |
|------|---------|---------|----------|
| **feat/** | New feature implementation | `feat/376-root-zero-sprawl` | Until PR merged + 7 days |
| **fix/** | Bug fix | `fix/p1-519-ip-to-dns-compliance` | Until PR merged + 7 days |
| **refactor/** | Code refactoring (no behavior change) | `refactor/401-dedup-helpers` | Until PR merged + 7 days |
| **docs/** | Documentation only | `docs/404-monorepo-guide` | Until PR merged + 7 days |
| **chore/** | Maintenance (deps, config, scripts) | `chore/450-upgrade-terraform` | Until PR merged + 7 days |
| **perf/** | Performance optimization | `perf/425-redis-latency` | Until PR merged + 7 days |
| **deploy/** | Infrastructure/deployment | `deploy/tier2-3-hardening` | DELETE after Phase complete |
| **ops/** | Operations/runbooks | `ops/failover-orchestration` | Until PR merged + 7 days |
| **test/** | Testing-only changes | `test/600-e2e-suite` | Until PR merged + 7 days |

### Examples

✅ **GOOD:**
- `feat/388-iam-phase-1-implementation`
- `fix/p1-519-ip-to-dns-compliance`
- `docs/governance-framework-guide`

❌ **BAD:**
- `new-feature` (missing issue number)
- `fix_password_validation` (using underscore)
- `Feature-388` (wrong case)
- `WIP-stuff` (non-standard type)

---

## Issue Tracking

GitHub Issues are the source of truth for active work.

- Check [docs/status/ISSUE-TRACKER-APRIL-19-2026.md](docs/status/ISSUE-TRACKER-APRIL-19-2026.md) before creating new work items.
- Do not create a second issue for a gap that is already tracked.
- Each issue should describe one workstream, include acceptance criteria, and reference the relevant audit or runbook evidence.
- When a task is done, update the linked issue with validation evidence, then close it after the change is merged and deployed.
- Audit reports are evidence artifacts only; they must not become competing canonical tracking docs.

---

## Branch Lifecycle

### 1. **Creation**
- Branch from `main` or designated base branch
- Follow naming convention above
- Link to GitHub issue (issue number in branch name)
- Push to origin immediately (enables CI/CD)

### 2. **Active Development**
- Keep branch synced with main: `git rebase origin/main`
- Squash commits before PR (1 commit = 1 feature)
- Keep branch < 30 days old
- Rebase onto main (not merge) if main has updates

### 3. **Pull Request**
- PR title: Copy branch name or use issue title
- PR description: Link issue with `Fixes #XXX`
- Require 1 approval before merge
- Enable auto-delete on merge (GitHub Settings → Branches)

### 4. **Merge**
- Squash merge to main (clean history)
- Delete branch on GitHub (automatic if auto-delete enabled)
- Delete local branch: `git branch -d <branch>`

### 5. **Post-Merge Cleanup**
- **Local:** Git automatically cleans stale tracking branches
- **Remote:** GitHub auto-delete or manual `git push origin --delete <branch>`
- **Stale Detection:** > 30 days without activity → delete candidate

---

## Branch Cleanup Rules

### Keep Permanently (Protected Branches)
```
✅ main
✅ develop
✅ staging (if used)
```

### Keep While Active
- **Active Feature:** `feat/XXX` with open PR or active work
- **Active Release:** `release/v*.*.x` with merge commits pending
- **Active Fix:** `hotfix/XXX` with open PR

### Delete Immediately
- ❌ Merged to main (auto-deleted via PR)
- ❌ Stale (> 30 days, no commits, no active PR)
- ❌ Phase-complete (e.g., `deploy/tier2-3-infrastructure-hardening` after Phase 14 complete)
- ❌ Duplicate (multiple branches for same feature; consolidate)

### Delete Process

**Identify Stale Branches:**
```bash
# Show all branches not updated in 30 days
for branch in $(git branch -r | grep -v HEAD); do
  age=$(git log -1 --format=%ai "$branch" | cut -d- -f1 | tr -d -);
  if [[ $(($(date +%s) - age)) -gt 2592000 ]]; then
    echo "Stale: $branch"
  fi
done
```

**Delete Locally (Merged):**
```bash
# Safe delete (only merged branches)
git branch --merged main | grep -v "main\|develop" | xargs git branch -d
```

**Delete Remotely:**
```bash
# Delete specific branch
git push origin --delete feat/332-session-schema-versioning

# Delete multiple
git push origin --delete feat/XXX fix/YYY docs/ZZZ
```

---

## Current Branch Status (April 19, 2026)

### Cleanup Completed
✅ **12 merged local branches deleted:**
- feat/332-session-schema-versioning
- feat/334-broadcast-multitab-sync
- feat/issue-duplicate-sentry
- feat/phase-1-production
- feature/phase-1-minimal
- fix/304-docker-governance-final
- fix/314-chaos-crlf-exit-code
- fix/ci-quality-gate-unblock-apr16
- fix/p1-519-ip-to-dns-compliance
- fix/p2-319-coverage-threshold-gates
- fix/p2-319-qa-gates-minimal
- fix/p3-304-docker-build-governance

**Result:** 70 local → 50 local branches

### Recommended Remote Deletions (~15 branches)
```
deploy/tier2-3-infrastructure-hardening       (Phase 14 complete)
docs/failover-runbook                          (merged)
feature/comprehensive-p1-p2-execution-april-16 (stale)
feature/final-session-completion-april-22      (stale)
feature/gov-002-metadata-headers               (superseded by main)
feature/copilot-consolidation-446              (old)
feature/p2-spring-completion                   (old)
feature/p2-sprint-clean                        (old)
feat/remove-ollama-code-migrate-to-separate-repo (incomplete)
feat/readiness-gates-main                      (Phase 14 complete)
feat/phase-8-performance-tuning-slo            (old)
feat/code-server-dev-env-final                 (old)
feat/code-server-dev-env                       (old)
feat/deploy-phases-177-178-168                 (old)
```

**Execution (when approved):**
```bash
git push origin --delete \
  deploy/tier2-3-infrastructure-hardening \
  docs/failover-runbook \
  feature/comprehensive-p1-p2-execution-april-16 \
  feature/final-session-completion-april-22 \
  # ... (11 more)
```

---

## Active Branches To Keep

### Core Development
- `feat/376-root-zero-sprawl-guardrails` (active governance)
- `feat/618-enterprise-policy-pack` (in progress)
- `feature/p1-388-iam-implementation` (Phase 1 underway)
- `feature/p1-388-phase1-implementation` (related)
- `feature/p2-service-to-service-auth` (Phase 2 planned)

### Phase Branches
- `feature/p1-388-phase2-service-to-service`
- `feature/p1-p2-alert-coverage`
- `feature/p1-architecture-decisions`
- `feature/p2-*` (next sprint planning)

### Governance & Infrastructure
- `feature/governance-framework`
- `feature/issue-duplicate-sentry`
- `feature/readiness-gates-main`

---

## Automation: Pre-Push Hook

**Optional:** Add to `.git/hooks/pre-push` to prevent pushing to main without PR:

```bash
#!/bin/bash
# Prevent force-push to protected branches
protected_branches="^(main|develop|staging|production)$"
current_branch=$(git symbolic-ref --short HEAD)

if [[ $current_branch =~ $protected_branches ]]; then
  echo "❌ Cannot push directly to protected branch: $current_branch"
  echo "   Create a PR instead: git push origin $current_branch"
  exit 1
fi
```

---

## Governance Metrics

| Metric | Target | Current (Apr 19) | Status |
|--------|--------|------------------|--------|
| **Local branches** | < 60 | 50 | ✅ |
| **Remote branches** | < 80 | ~110 | 🔶 (cleanup pending) |
| **Stale branches** | < 5 | ~40 | ❌ (cleanup required) |
| **Avg branch age** | < 20 days | ~45 days | ❌ (old branches present) |
| **Merged but not deleted** | 0 | 0 | ✅ (after cleanup) |

---

## Policy Enforcement

### Automated (via GitHub)
- ✅ Auto-delete on merge (GitHub Settings → Branches)
- ✅ Require PR before merge (branch protection rules)
- ✅ Require CI/CD pass before merge

### Manual Reviews
- ⏳ **Monthly:** Audit old branches; create cleanup PR if needed
- ⏳ **After Phase complete:** Delete deploy/ branches
- ⏳ **After release:** Delete release/ and hotfix/ branches

### Team Accountability
- Assign branch ownership (author responsible for cleanup after merge)
- Link to JIRA/GitHub issue (auto-close on merge)
- Mention in sprint planning (old branches = incomplete work)

---

## FAQ

**Q: Can I push to a branch without a PR?**  
A: Yes, but it's discouraged. Best practice: create PR immediately after first push (enables early review + CI/CD).

**Q: How long should a branch live?**  
A: Target 1-2 weeks (1 sprint). If > 30 days, either:
  - Split work into smaller PRs
  - Or rebase onto main to keep up-to-date
  - Or close branch if work is abandoned

**Q: What if I need to keep a branch for reference?**  
A: Tag the commit before deleting: `git tag archival/branch-name && git branch -D branch-name`

**Q: Can I delete main by accident?**  
A: No, main is protected via GitHub (requires admin override).

---

## References

- [GitHub Branch Protection](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches)
- [Git Branching Model](https://nvie.com/posts/a-successful-git-branching-model/)
- [Code Review Governance Rules](CODE-REVIEW-REMEDIATION-PLAN-APRIL-19-2026.md#branch-sprawl)

---

**Last Cleanup:** April 19, 2026 (12 local branches removed, 50 remaining)  
**Next Review:** April 26, 2026  
**Approval:** Required from @kushin77 before enforcement
