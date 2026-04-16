# Copilot Instructions for kushin77/code-server

<!-- SCOPE SENTINEL: This workspace is kushin77/code-server ONLY -->

## Scope

✅ **ONLY**: kushin77/code-server — on-prem VSCode server + infrastructure at 192.168.168.31/.42  
❌ **NEVER**: eiq-linkedin, GCP-landing-zone, code-server-enterprise, or any other repo

## Priority Order (execute in this order)

- **P0** 🔴 Critical (outage, data loss, security breach) — fix immediately
- **P1** 🟠 High (major degradation, core broken) — this sprint
- **P2** 🟡 Medium (enhancement, non-critical) — next sprint
- **P3** 🟢 Low (nice-to-have, docs, tech debt) — backlog

## Non-Negotiables

- Every branch → open issue → PR with `Fixes #N` → merge → auto-close issue
- Conventional commits: `feat|fix|refactor|docs|chore|ci(scope): message`
- All changes tested, no CVEs, no secrets in git
- IaC: immutable versions pinned, idempotent, duplicate-free, on-prem first
- GitHub Issues = SSOT (single source of truth). Memory files = working notes only
- Never PATCH closed issues — add comments only
- Session-aware execution: check `/memories/repo/` before starting work
- No duplicate work: review git log to see what previous sessions did
- Elite standards: HA-ready, compliance-checked, observability-integrated

## Production Host

- **Primary**: `ssh akushnir@192.168.168.31` — deploy from here (Docker runs here)
- **Replica**: `192.168.168.42`
- Deploy: `docker compose up -d` or `terraform apply` on remote host

## Quick Reference

```bash
# Core services only (no AI, no tracing overhead)
docker compose up -d

# With AI (Ollama LLM)
COMPOSE_PROFILES=ai docker compose up -d

# With distributed tracing
COMPOSE_PROFILES=tracing docker compose up -d

# Full stack
COMPOSE_PROFILES=ai,tracing docker compose up -d
```

## Execution Workflow (Session-Aware Pattern)

1. **Assess State** (2 min)
   - Check memory files: `/memories/repo/current-production-state.md`
   - Review git history: `git log --oneline -10`
   - Query open issues: `gh issue list --state=open --limit=50`
   - Identify blocking dependencies

2. **Plan Execution** (2 min)
   - Identify critical path (P0 → P1 → P2 → P3)
   - Avoid duplicate work (check what sessions completed)
   - Break into independent tasks (parallelize where possible)

3. **Execute Work** (varies)
   - Create feature branch: `git checkout -b feature/<issue>-<description>`
   - Implement code/docs with IaC standards
   - Test locally before committing
   - Use conventional commit format

4. **Validate Quality** (2 min)
   - Run: `terraform validate && terraform fmt -check .`
   - Check: `docker-compose config` (syntax)
   - Verify: no hardcoded secrets, no CVEs
   - Confirm: backward compatible, idempotent

5. **Update GitHub** (2 min)
   - Push feature branch: `git push origin feature/<issue>...`
   - Create PR with issue link in body
   - Add labels (P0-P3, component, status)
   - Request code review if needed

6. **Close & Document** (2 min)
   - Merge PR to main (if not protected branch)
   - Update issue: add comment with completion summary
   - Close issue: `gh issue close <N>`
   - Update memory files: `/memories/repo/` for next session

## Session Awareness Guidelines

### Before Starting Any Task

```bash
# 1. Check what previous sessions completed
cat /memories/repo/current-production-state.md

# 2. Review recent commits
git log --oneline -20 | head -20

# 3. Check open PRs
gh pr list --state=open --limit=10

# 4. Identify what you should do
# - If P1 #388 merged → you can work on P1 #385, #468, etc.
# - If P2 #418 done → focus on remaining P2 items (#447, #446, #432, #426)
# - If another session is on feature branch → don't duplicate work
```

### Avoid These Mistakes

❌ **Don't**: Re-implement work another session finished  
❌ **Don't**: Create overlapping PRs for same issue  
❌ **Don't**: Modify files another session is working on  
❌ **Don't**: Push to main directly (always use feature branch + PR)  
❌ **Don't**: Leave unmerged PRs stale (close or merge immediately)  

✅ **Do**: Use git history to see what's been done  
✅ **Do**: Check memory files for architectural decisions  
✅ **Do**: Consolidate work into single commits per issue  
✅ **Do**: Update memory files so next session knows what you did

## IaC Standards (Elite Grade)

### Four Pillars (Required for All Infrastructure Code)

| Pillar | Meaning | Example |
|--------|---------|---------|
| **Immutable** | All versions pinned (no "latest" tags) | `codercom/code-server:4.115.0` not `latest` |
| **Idempotent** | Safe to apply 100x, no side effects | `terraform apply` twice = same result |
| **Duplicate-Free** | No overlapping definitions or configs | One `docker-compose.yml`, not 7 variants |
| **On-Prem First** | No cloud-specific APIs (GCP, AWS, Azure) | Fallback to Docker if K8s unavailable |

### Verification Checklist

- [ ] All image versions pinned (semver, not `latest`)
- [ ] All resource limits defined (CPU, memory, storage)
- [ ] Terraform: `terraform validate` passes
- [ ] Terraform: `terraform fmt -check .` passes (no formatting issues)
- [ ] Docker: `docker-compose config` validates syntax
- [ ] No hardcoded secrets or credentials
- [ ] No security issues (exposed ports, default passwords)
- [ ] Immutable: reapply multiple times, same result
- [ ] Idempotent: handles existing resources gracefully
- [ ] On-prem ready: no mandatory cloud dependencies

## Deployment: On-Prem First

### ✅ CORRECT Approach

Deploy from remote host (where Docker/K8s actually run):

```bash
# SSH to production host
ssh akushnir@192.168.168.31

# Deploy infrastructure
cd code-server-enterprise/terraform
terraform apply -var-file=on-prem.tfvars -auto-approve

# Deploy services
docker-compose up -d
```

### ❌ WRONG Approach

Never run deployment commands locally (Docker daemon not available on Windows):

```bash
# DON'T DO THIS - will fail
terraform apply  # ← No Docker daemon available
docker-compose up -d  # ← Docker not running
```

---
**Last updated: April 16, 2026** | [All Issues](https://github.com/kushin77/code-server/issues)

## Session Continuation Pattern

After each session:
1. Commit work: `git commit -m "feat(P# #NNN): description"` 
2. Push: `git push origin feature/...`
3. Create PR or merge to main
4. Close GitHub issues
5. **Update memory files** (critical for next session):
   - `/memories/repo/current-production-state.md` - what's deployed
   - `/memories/repo/active-open-issues.md` - what still needs work
   - `/memories/session/` - in-progress notes

## Next Session Quickstart

```bash
# 1. Check memory files
cat /memories/repo/current-production-state.md
cat /memories/repo/active-open-issues.md

# 2. See what's been merged
git log --oneline main -20

# 3. Identify next P0/P1/P2 items
gh issue list --state=open --search="is:issue" --limit=30

# 4. Pick an issue
gh issue view 450  # Example

# 5. Create feature branch and start work
git checkout -b feature/p1-450-network-policies
```
