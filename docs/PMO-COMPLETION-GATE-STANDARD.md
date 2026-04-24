# PMO Universal Completion Gate Standard

**Definition**: Every GitHub issue must pass through a 4-gate completion standard before closure, ensuring quality, traceability, and operational hygiene.

## The 4 Gates

```
┌──────────────┐       ┌──────────────┐       ┌──────────────┐       ┌──────────────┐
│ GATE 1:      │  →    │ GATE 2:      │  →    │ GATE 3:      │  →    │ GATE 4:      │
│ COMMITTED    │       │ MERGED       │       │ DEPLOYED     │       │ CLEANED      │
│ Code on      │       │ PR merged    │       │ Running on   │       │ Branches     │
│ branch       │       │ to main      │       │192.168.168.31       │ deleted      │
└──────────────┘       └──────────────┘       └──────────────┘       └──────────────┘
         ↓                    ↓                     ↓                      ↓
    branch: N/A         main: PR#N            ssh+docker-compose      local+remote
       (label)          (gate:merged)         (gate:deployed)         (gate:cleaned)
```

## Gate 1: Committed

**What**: Code is committed to a feature branch following PMO naming convention.

**Verification**:
```bash
# Check commit exists on feature branch
git log feat/epic-id-1234-slug --oneline | head -5

# Should show: "feat: description (#1234)"
```

**Automated**:
- CI check validates commit message format (Conventional Commits)
- CI check validates branch name matches pattern: `<type>/<epic-id>-<issue-number>-<slug>`
- PR opened with "Closes #1234" in body

**Manual Sign-Off**: Copilot/Human confirms code review passed

**Label Applied**: `gate:committed` (auto-applied when PR opens)

**Examples**:
- ✅ Branch `feat/pmo-001-1576-labels` has commits with "feat: add label provisioning (#1576)"
- ✅ PR opened against main with "Closes #1576" in body
- ❌ Branch name is `my-feature-branch` (doesn't match pattern)
- ❌ Commit message is "fixed stuff" (not Conventional Commits)

---

## Gate 2: Merged

**What**: PR is approved and merged to main branch.

**Verification**:
```bash
# Check PR merged and commit is on main
gh pr view <PR_NUMBER> --json state,mergedAt
# Should show: state: MERGED, mergedAt: [timestamp]

# Verify commit on main
git log main --grep="#1234" --oneline | head -1
```

**Automated**:
- GitHub Actions validates PR passes all CI checks before merge approval
- PMO compliance job validates commit message and branch name
- Auto-merge can be triggered after Phase 1 + Phase 2 review gates pass

**Manual Sign-Off**: 
- Reviewer approves PR (GitHub workflow)
- Merge (via GitHub UI or `gh pr merge <PR_NUMBER>`)

**Label Applied**: `gate:merged` (auto-applied when PR merges)

**Examples**:
- ✅ PR #1576 merged to main with commit hash abc123def456
- ✅ `git log main` shows merged commit with issue #1576 reference
- ❌ PR is still open (not yet merged)
- ❌ PR was closed without merging (abandoned)

---

## Gate 3: Deployed

**What**: Code is running on production host (192.168.168.31).

**Verification**:
```bash
# SSH deploy
ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker compose up -d"

# Check deployment succeeded
ssh akushnir@192.168.168.31 "docker ps -a | grep -E 'code-server|oauth|oidc' | head -10"

# Verify container status: should all show "Up X seconds"
```

**Automated**:
- Complete-issue.sh script handles SSH deployment
- Docker compose brings up all services defined in docker-compose.yml
- Health checks verify services are healthy (exit code 0)

**Manual Sign-Off**:
- Copilot or human executes: `bash scripts/pmo/complete-issue.sh kushin77/code-server 1234`
- Verifies SSH connection and docker compose output

**Label Applied**: `gate:deployed` (auto-applied after successful deployment)

**Examples**:
- ✅ SSH succeeds, docker compose up completes with all containers running
- ✅ Health check endpoint returns 200 OK
- ❌ SSH fails (host unreachable, auth failed)
- ❌ Docker compose fails (service exits, config error)

---

## Gate 4: Cleaned

**What**: Feature branch deleted locally and on remote; repository is clean.

**Verification**:
```bash
# Verify branch deleted
git branch -a | grep -i "feat/pmo-001-1576" || echo "✓ Branch deleted"

# Verify remote branch deleted
git branch -r | grep -i "origin/feat/pmo-001-1576" || echo "✓ Remote deleted"

# Stale branch audit
bash scripts/pmo/cleanup-stale-branches.sh --dry-run
```

**Automated**:
- Complete-issue.sh runs cleanup-stale-branches.sh
- Deletes local branch: `git branch -d feat/...`
- Deletes remote branch: `git push origin --delete feat/...`
- Verifies branch no longer exists locally or remotely

**Manual Sign-Off**:
- Copilot executes cleanup via complete-issue.sh
- Human verifies git branch -a shows no stale branches

**Label Applied**: `gate:cleaned` (auto-applied after cleanup)

**Examples**:
- ✅ `git branch -a` shows no branches matching feat/pmo-001-1576-*
- ✅ Remote has no dangling branches for closed issues
- ❌ Stale branch still exists locally: `feat/pmo-001-1576-labels`
- ❌ Remote branch not deleted: `origin/feat/pmo-001-1576-labels`

---

## Completion Sequence

### Fast Path (Typical Scenario)

```bash
# Session 1: Create and implement
git checkout -b feat/pmo-001-1576-labels
# ... make changes ...
git commit -m "feat: add label provisioning (#1576)"
git push -u origin HEAD
# → PR opens, Gate 1 applied

# PR Review + Merge
# → Gate 2 applied

# Session 2: Deploy and cleanup
bash scripts/pmo/complete-issue.sh kushin77/code-server 1576
  # ↓ Gate 1: Verified ✓
  # ↓ Gate 2: Verified ✓
  # ↓ Gate 3: SSH deploy + docker compose
  # ↓ Gate 4: Delete branches
  # → Gates 3 & 4 applied, issue closes
```

### Blocked Gate (Remediation)

```bash
# If Gate 3 deployment fails:
bash scripts/pmo/complete-issue.sh kushin77/code-server 1576 --skip-deploy

# OR diagnose + fix:
ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker compose logs"
# Fix the issue, commit, merge PR, then try again
```

---

## Gate Labels & Tracking

Each gate applies a label for visibility:

| Label | Applied When | Meaning |
|-------|------------|---------|
| `gate:committed` | PR opens with correct format | Code exists on branch |
| `gate:merged` | PR merges to main | Code is on main |
| `gate:deployed` | docker compose succeeds | Code is running on 192.168.168.31 |
| `gate:cleaned` | Branches deleted | Repository is clean |

**Viewing gate status**:
```bash
# Check all gates applied
gh issue view 1576 --repo kushin77/code-server --json labels

# Should show: gate:committed, gate:merged, gate:deployed, gate:cleaned, status:done
```

---

## Enforcement via CI

**File**: `.github/workflows/pmo-compliance.yml`

Validation steps:
1. **Branch name validation** — Must match `<type>/<epic-id>-<issue-number>-<slug>`
2. **Commit message validation** — Must be Conventional Commits format
3. **PR body validation** — Must include `Closes #N` or `Fixes #N`
4. **Secrets scan** — No hardcoded credentials
5. **Governance headers** — New scripts must have GOV-002 metadata headers

**If CI fails**:
```
❌ PR cannot merge until CI passes
   → Fix branch name / commit message / secrets
   → Rebase onto main
   → Push again
```

---

## Q&A

**Q: What if deployment fails on Gate 3?**  
A: Run with `--skip-deploy` flag to bypass, then manually fix and re-deploy.  
```bash
bash scripts/pmo/complete-issue.sh kushin77/code-server 1576 --skip-deploy
```

**Q: Can I close an issue manually without these gates?**  
A: No — issues must close via complete-issue.sh which enforces all 4 gates.

**Q: What if I'm only making documentation changes?**  
A: Use `--skip-deploy` for docs-only PRs (no docker compose needed).

**Q: How long does a typical cycle take?**  
A: Gate 1-2: 5-30 min (review + merge). Gate 3: 2-5 min (deploy). Gate 4: <1 min (cleanup).  
Total: ~15-45 minutes from commit to closure.

**Q: Can gates be skipped?**  
A: No — all 4 must pass. But there are flags for special cases (--skip-deploy, etc.)

---

**Version**: 1.0  
**Last Updated**: April 23, 2026  
**References**:  
- Rule 5: Script Writing Guide  
- Rule 8: GitHub Issue Creation Governance  
- Rule 9: Copilot Session Lock Protocol  
- PMO-001-D: Sub-Issue #1579
