# Agent Execution Quick Start Guide

**Who This Is For**: Autonomous agents implementing GitHub issues 

**What To Do Now**:
1. Read this file (you are here) — 5 min
2. Read [AGENT-TRIAGE-APRIL-18-2026.md](AGENT-TRIAGE-APRIL-18-2026.md) — 15 min
3. Start with issue #650 (P1, foundation) — 17 hours
4. Follow dependency chain from there

**Keys to Success**:
- ✅ Follow conventional commits: `feat|fix(scope): description - Fixes #NNN`
- ✅ All code in git (if not committed, it doesn't exist)
- ✅ Use `_common/` libraries (no duplication)
- ✅ IaC everything (terraform, helm, k8s, docker-compose)
- ✅ Tests passing before pushing
- ✅ Let PR auto-merge (no human approval)
- ✅ Never manually close issues (let PR merge close them)

---

## Execution Commands Cheat Sheet

### Start a New Issue

```bash
# Create branch from latest main
git checkout main && git pull origin main
git checkout -b feat/issue-650-auth-baseline

# Make your changes
# Write code, tests, docs, IaC

# Commit with issue reference
git add .
git commit -m "feat(auth): deploy org-wide baseline - Fixes #650"

# Verify tests pass
npm test 2>&1 | tail -5
# or
pytest tests/ -v

# Governance checks
shellcheck scripts/*.sh
markdownlint *.md
terraform validate -json

# Push
git push origin feat/issue-650-auth-baseline
```

### Open a PR (Auto-Merge)

```bash
# GitHub CLI auto-opens PR when you push branch
# PR title will be your commit message
# PR description auto-includes: "Fixes #650"
# CI runs automatically
# PR auto-merges when tests pass ✅

# Verify auto-merge worked
gh pr view --web  # Opens PR in browser
gh pr status      # Shows merge status
```

### Check Issue Dependencies

```bash
# Before starting issue, verify blockers are done
# Example: #657 depends on #650, #622, #653

# Check if #650 is merged
git log main --oneline | grep "Fixes #650"

# If not merged yet, don't start #657 yet
# Start with #650 instead
```

### Update Issue Description (If Needed)

```bash
# If issue description is incomplete, add acceptance criteria
# Use GitHub UI or API:

export GITHUB_TOKEN=$(gcloud secrets versions access latest --secret="github-token")
curl -X PATCH -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/kushin77/code-server/issues/650 \
  -d '{"body": "## Acceptance Criteria\n- [ ] Auth deployed\n..."}'
```

### Monitor Dashboard

```bash
# Open issue #650 in GitHub
gh issue view 650 -R kushin77/code-server -w

# Or: https://github.com/kushin77/code-server/issues/650
```

---

## Prioritized Issue Sequence (Start Here)

### 🔴 P1 Critical (Complete in order):

1. **#650** (17h) — Org-wide auth baseline [FOUNDATION]
   - Start immediately
   - Blocks all other P1

2. **#643** (5h) — Fix org_internal 403
   - Depends on: #650 ✅
   - Start once #650 merged

3. **#622** (8h) — Workspace-level secrets
   - Depends on: #650 ✅
   - Can run parallel to #643

4. **#653** (12h) — Auth keepalive service
   - Depends on: #650, #643, #622 ✅
   - Start once prev 3 merged

5. **#657** (20h) — Thin client refactor
   - Depends on: #650, #622, #653 ✅
   - Largest change, allow full time

6. **#655** (16h) — Conformance test suite
   - Depends on: #657 ✅
   - Depends on: #634 (E2E framework)
   - Can start #634 in parallel

### 🟠 P2 High (Can run parallel to P1 Days 5+):

7. **#654** (12h) — Cross-repo policy gate
   - Depends on: #650 ✅

8. **#638** (8h) — Persistence hardening
   - Depends on: #612 (closed, done)

9. **#613** (8h) — Folder taxonomy
   - Depends on: #649 (open PR, check status first)

10. **#291** (2h/week) — Crash tracking [PERSISTENT]
    - Update weekly, never close

### 🟡 P3 Low (Can run anytime):

11. **#634-637** (57h) — E2E Testing Program
    - Gates other P3 work
    - Can start Day 7

12. **#628-632** (64h) — AI/Ollama Integration
    - Can start Day 10
    - Scales with #634 completion

13. **#627, #626** (28h) — Enterprise Policy
    - Can start Day 13

14. **#639-641** (29h) — Autopilot State Fix
    - Can start Day 13

---

## Critical Rules (Non-Negotiable)

### Code Organization
- **No hardcoded values**: Use env vars from `scripts/_common/config.sh`
- **No duplication**: Check `scripts/_common/` and `scripts/lib/` first
- **All scripts**: Must have metadata header (GOV-002)
- **All scripts**: Must `source "$SCRIPT_DIR/_common/init.sh"`
- **No local logging**: Use `log_info`, `log_error`, `log_fatal` only

### Git Discipline
- **Branch naming**: `feat|fix|refactor|docs/issue-#NNN-short-desc`
- **Commit messages**: `type(scope): message - Fixes #NNN`
- **Every commit**: MUST reference issue (`Fixes #NNN`)
- **One issue per PR**: Never mix unrelated work
- **All changes in git**: No local-only changes, no README-only docs

### IaC Requirements
- **All configs**: terraform/ (primary), helm/ (k8s), k8s/ (manifests)
- **All versions**: Pinned to immutable SHAs (not `latest`)
- **All secrets**: GSM (Google Secret Manager), never in git
- **Idempotency**: Apply 2x → same result
- **No manual steps**: Everything scriptable

### Testing
- **Unit tests**: >80% coverage
- **Integration tests**: All major flows
- **E2E tests**: Production endpoints (if applicable)
- **Governance tests**: shellcheck, markdownlint, terraform validate
- **Security tests**: Trivy scan, no credentials in code

### Documentation
- **README update**: If public API changes
- **SOP**: Deployment, troubleshooting, recovery
- **IaC comments**: Complex logic documented
- **Runbook**: How to debug + recover

---

## Common Gotchas & Solutions

### Gotcha 1: I pushed a branch but no PR opened

**Solution**: GitHub CLI doesn't auto-open PRs. Use:
```bash
gh pr create --title "feat(...): - Fixes #650" --body "Fixes #650"
# Or open manually: gh pr create -w (opens browser)
```

### Gotcha 2: PR didn't auto-merge

**Check**:
- Tests failing? Fix in same branch, re-commit, push.
- Governance check failed? Check error msg, fix, re-commit.
- Still not merging? Add comment: "@workspace help"

**Action**:
```bash
# View PR checks
gh pr checks 650  # or gh pr view 650

# Re-run failed checks
gh pr checks 650 --watch
```

### Gotcha 3: I want to revert a merged PR

**Solution**: Create a new fix PR:
```bash
git log main --oneline | grep "Fixes #650"
git revert SHA  # Use the commit SHA
git push origin feat/fix-revert-650
gh pr create --title "fix: revert issue 650 - #651"
```

**Note**: Never force-push to main. Always do reverts as new PRs.

### Gotcha 4: Dependency issue (#657) isn't merging, blocking my work

**Solution**: 
- Check #657 status: `gh pr view 657`
- Add comment: "@workspace #657 is blocked, can I start #655 with mocks?"
- Create fallback: Mock the dependency, replace when real one merges

### Gotcha 5: I need to update IaC and it's complex

**Solution**: Break into multiple commits:
```bash
# Commit 1: terraform changes
git add terraform/
git commit -m "chore(iac): update auth baseline terraform - Fixes #650"

# Commit 2: helm changes
git add helm/
git commit -m "chore(iac): update helm auth chart - Fixes #650"

# Both will close #650 (first one has "Fixes #650")
```

---

## When You Get Stuck

### "I don't know where to start"
→ Read [AGENT-TRIAGE-APRIL-18-2026.md](AGENT-TRIAGE-APRIL-18-2026.md) section for #650  
→ Look at [ACCEPTANCE-CRITERIA-BY-ISSUE.md](ACCEPTANCE-CRITERIA-BY-ISSUE.md) for detailed AC

### "Tests are failing"
→ Run locally: `npm test` or `pytest -v`  
→ Fix in same branch  
→ Re-commit and push  
→ CI will retry automatically

### "I can't access GSM secrets"
→ Run: `gcloud auth login`  
→ Verify: `gcloud secrets versions access latest --secret="github-token"`  
→ If error: credentials not configured, ask human for help

### "An issue I depend on is stuck"
→ Create blocker issue: `P0 BLOCKED: Issue #NNN waiting on #DEP`  
→ Continue with non-blocked issues  
→ Return to blocked issue when dependency clears

### "Changes fail governance checks"
→ Check error message carefully  
→ Common fixes:
  - Missing metadata header? Add per GOV-002
  - Hardcoded value? Use env var from config.sh
  - `echo` instead of `log_*`? Replace with proper logging
  - Duplicate code? Move to `_common/` library
→ Run local checks: `shellcheck *.sh` `markdownlint *.md`

---

## Reference Documents

| Document | Purpose | Time |
|----------|---------|------|
| [AGENT-TRIAGE-APRIL-18-2026.md](AGENT-TRIAGE-APRIL-18-2026.md) | Full issue breakdown, dependencies, execution plan | 15 min |
| [ACCEPTANCE-CRITERIA-BY-ISSUE.md](ACCEPTANCE-CRITERIA-BY-ISSUE.md) | Detailed AC for every issue | 20 min |
| [DELIVERY-ROADMAP-APRIL-2026.md](DELIVERY-ROADMAP-APRIL-2026.md) | Timeline, phases, weekly checkpoints | 10 min |
| [copilot-instructions.md](.github/copilot-instructions.md) | Governance rules (metadata, dedup, logging, IaC) | 10 min |
| [DEDUPLICATION-AND-EFFICIENCY-ANALYSIS.md](DEDUPLICATION-AND-EFFICIENCY-ANALYSIS.md) | What not to duplicate, canonical libraries | 5 min |
| [docs/SCRIPT-WRITING-GUIDE.md](docs/SCRIPT-WRITING-GUIDE.md) | How to write bash scripts correctly | 10 min |

---

## Success Metrics

Track these daily:

- **PRs merged**: # of issues closed (target: 1-2 PRs/day)
- **Tests passing**: % of governance + unit + integration tests (target: >95%)
- **Code review time**: Minutes from push to merge (target: <30 min via CI)
- **Blockers**: # of agents stuck waiting (target: 0)
- **Regressions**: # of post-merge failures (target: 0)

---

## Final Checklist Before Starting

- [ ] Read this 5-minute guide (you're here ✅)
- [ ] Opened [AGENT-TRIAGE-APRIL-18-2026.md](AGENT-TRIAGE-APRIL-18-2026.md)
- [ ] Bookmarked [ACCEPTANCE-CRITERIA-BY-ISSUE.md](ACCEPTANCE-CRITERIA-BY-ISSUE.md)
- [ ] Have `gh` CLI installed: `which gh`
- [ ] GitHub authenticated: `gh auth status`
- [ ] Git can access GSM: `gcloud secrets versions access latest --secret="github-token"`
- [ ] Can run tests locally: `npm test` or `pytest -v`

**Ready to start?** → Begin with issue #650

---

**Last Updated**: April 18, 2026, 02:00 UTC  
**Status**: All systems ready for autonomous agent execution  
**Next Step**: Start issue #650 (P1 Auth Baseline)  
**Expected Start Time**: Now  
**Expected P1 Completion**: May 6, 2026  
**Expected Full Completion**: May 12, 2026 (24/7) or May 21, 2026 (business hours)
