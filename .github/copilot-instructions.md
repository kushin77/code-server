# Comprehensive Copilot Instructions
# P2 #446: Consolidated Agent Configuration - Single Source of Truth
# Last Updated: April 23, 2026

<!-- SCOPE SENTINEL: This workspace is kushin77/code-server ONLY -->

---

## 1. REPOSITORY SCOPE

### ✅ ONLY kushin77/code-server
- Terraform IaC for on-premises infrastructure (192.168.168.31, 192.168.168.42)
- Docker Compose services (code-server, postgres, redis, prometheus, grafana, etc.)
- Kubernetes manifests (monitoring, networking, security, failover)
- GitHub Actions workflows (CI/CD, quality gates, security scanning)
- Shell scripts and automation (bootstrap, health checks, deployment)

### ❌ NEVER
- eiq-linkedin (separate org)
- GCP landing zone (cloud-specific)
- code-server-enterprise (sister repo)

---

## 2. PRIORITY SYSTEM

- **P0** 🔴 Critical (outage, data loss, security breach) — fix immediately
- **P1** 🟠 High (major degradation, core broken) — this sprint (1-2 days)
- **P2** 🟡 Medium (enhancement, non-critical) — next sprint (3-7 days)
- **P3** 🟢 Low (nice-to-have, docs, tech debt) — backlog (≥2 weeks)

---

## 3. EXECUTION WORKFLOW

1. **Assess state** → Check memory files + git history
2. **Identify critical path** → What must be done first?
3. **Execute work** → Create/update files, validate, commit
4. **Update GitHub** → Comment with progress
5. **Close issues** → Mark completed, push to branch
6. **Preserve knowledge** → Update /memories/repo/ for next session

---

## 4. INFRASTRUCTURE AS CODE MANDATES

### Four Pillars (Non-Negotiable)
- **Immutable**: All versions pinned, no "latest" tags
- **Idempotent**: Safe to apply 100x, no side effects
- **Duplicate-Free**: No overlapping definitions, clear ownership
- **No Overlap**: Independent modules, composed at root

### On-Premises First
- Primary: `ssh akushnir@192.168.168.31` (Docker + K8s)
- Secondary: `192.168.168.42` (failover/replica)
- No cloud-specific APIs (GCP, AWS, Azure)

### Elite Standards
- ✅ Resource limits (CPU, memory, storage)
- ✅ High availability (multi-replica, failover, backups)
- ✅ Security hardening (SELinux, auditd, least-privilege)
- ✅ Compliance (GDPR, SOC2, ISO27001)
- ✅ Observability (metrics, logs, traces, audit)

---

## 5. DEPLOYMENT PROCEDURES

### CRITICAL: Deploy from Remote Host ONLY
✅ **CORRECT**:
```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise/terraform
terraform apply -var-file=on-prem.tfvars -auto-approve
```

❌ **WRONG**: Never run `terraform apply` locally (Docker daemon unavailable on Windows)

---

## 6. SESSION AWARENESS

### Before Starting Any Work
1. Check `/memories/repo/` for previous session decisions
2. Query `git log` (last 10 commits) to see what's done
3. Review `gh issue comments` for recent progress

### Avoid These Mistakes
- ❌ Re-implementing work another session did
- ❌ Creating conflicting files/modules
- ❌ Opening duplicate issues
- ❌ Modifying files another session is working on

---

## 7. GITHUB ISSUE EXECUTION

### Assessment
1. Read title + body → understand problem
2. Check labels → P0-P3, component, status
3. Review comments → context from other sessions
4. Identify blockers → dependencies, PRs, approvals

### Execution
- Branch: `git checkout -b feature/<issue>-<description>`
- Commits: Follow conventional format (feat|fix|refactor|docs|chore)
- Linking: Include `Fixes #NNN` in commit message
- PR: Create if protected branch, else merge to feature branch

### Closure
- Update issue with completion summary
- Add metrics (LoC, resources, time)
- Close with summary comment

---

## 8. QUICK REFERENCE

### Terraform
```bash
terraform init -backend=false
terraform validate
terraform fmt .
terraform plan -var-file=on-prem.tfvars
terraform apply -var-file=on-prem.tfvars -auto-approve
```

### Docker
```bash
docker-compose up -d
docker-compose ps
docker logs <service>
docker-compose exec <svc> sh
docker-compose down && docker-compose up -d
```

### Git
```bash
git checkout -b feature/p2-xxx
git commit -m "feat(P2 #xxx): Description"
git push origin feature/p2-xxx
gh pr create --base=main --title "Title"
```

### GitHub CLI
```bash
gh issue list --state=open --limit=50
gh issue view 418
gh issue comment 418 --body "message"
gh issue close 418
gh run list -w ci-validate.yml --limit=5
```

---

## 9. TESTING & VALIDATION

### Pre-Commit
- `terraform validate`
- `terraform fmt -check .`
- `tfsec .`
- `docker-compose config`
- `kubectl apply --dry-run=client`

### Pre-Deploy
- `terraform plan -out=tfplan`
- `docker-compose up --no-start`
- Service health checks

---

## 10. KNOWLEDGE PRESERVATION

After each session, update:
- `/memories/repo/current-production-state.md` (what's deployed)
- `/memories/repo/active-open-issues.md` (issue status)
- `/memories/session/` (in-progress work)

Record:
- Architecture decisions (ADRs, trade-offs)
- Infrastructure changes (what was deployed)
- Issue status (completed, merged, closed)
- Blocking issues (dependencies)
- Known issues (bugs, workarounds)

---

## 11. COMPLIANCE CHECKLIST

Before submitting work:
- [ ] IaC mandates met (immutable, idempotent, duplicate-free)
- [ ] No secrets hardcoded
- [ ] No security issues (open ports, default passwords)
- [ ] Conventional commit format
- [ ] Issue linked (`Fixes #NNN`)
- [ ] Terraform validated & formatted
- [ ] Documentation updated
- [ ] Memory files updated
- [ ] No conflicts with other sessions
- [ ] On-prem first approach

---

## 12. NON-NEGOTIABLES

- Every branch → open issue → PR with `Fixes #N` → merge → auto-close
- Conventional commits: `feat|fix|refactor|docs|chore|ci(scope): message`
- All changes tested, no CVEs, no secrets in git
- IaC: immutable, idempotent, duplicate-free, on-prem first
- GitHub Issues = SSOT (single source of truth)
- Never PATCH closed issues — add comments only

---

## 13. PRODUCTION HOST INFO

- **Primary**: `ssh akushnir@192.168.168.31` — deploy from here
- **Replica**: `192.168.168.42`
- **Deploy**: `docker compose up -d` or `terraform apply` on remote

---

**Last updated: April 23, 2026**  
**Scope**: kushin77/code-server ONLY  
**Type**: Consolidated, single-source-of-truth for all Copilot sessions  
x, no side effects
- **Duplicate-Free**: No overlapping definitions, clear ownership
- **No Overlap**: Independent modules, composed at root

### On-Premises First
- Primary: `ssh akushnir@192.168.168.31` (Docker + K8s)
- Secondary: `192.168.168.42` (failover/replica)
- No cloud-specific APIs (GCP, AWS, Azure)

### Elite Standards
- ✅ Resource limits (CPU, memory, storage)
- ✅ High availability (multi-replica, failover, backups)
- ✅ Security hardening (SELinux, auditd, least-privilege)
- ✅ Compliance (GDPR, SOC2, ISO27001)
- ✅ Observability (metrics, logs, traces, audit)

---

## 5. DEPLOYMENT PROCEDURES

### CRITICAL: Deploy from Remote Host ONLY
✅ **CORRECT**:
```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise/terraform
terraform apply -var-file=on-prem.tfvars -auto-approve
```

❌ **WRONG**: Never run `terraform apply` locally (Docker daemon unavailable on Windows)

---

## 6. SESSION AWARENESS

### Before Starting Any Work
1. Check `/memories/repo/` for previous session decisions
2. Query `git log` (last 10 commits) to see what's done
3. Review `gh issue comments` for recent progress

### Avoid These Mistakes
- ❌ Re-implementing work another session did
- ❌ Creating conflicting files/modules
- ❌ Opening duplicate issues
- ❌ Modifying files another session is working on

---

## 7. GITHUB ISSUE EXECUTION

### Assessment
1. Read title + body → understand problem
2. Check labels → P0-P3, component, status
3. Review comments → context from other sessions
4. Identify blockers → dependencies, PRs, approvals

### Execution
- Branch: `git checkout -b feature/<issue>-<description>`
- Commits: Follow conventional format (feat|fix|refactor|docs|chore)
- Linking: Include `Fixes #NNN` in commit message
- PR: Create if protected branch, else merge to feature branch

### Closure
- Update issue with completion summary
- Add metrics (LoC, resources, time)
- Close with summary comment

---

## 8. QUICK REFERENCE

### Terraform
```bash
terraform init -backend=false
terraform validate
terraform fmt .
terraform plan -var-file=on-prem.tfvars
terraform apply -var-file=on-prem.tfvars -auto-approve
```

### Docker
```bash
docker-compose up -d
docker-compose ps
docker logs <service>
docker-compose exec <svc> sh
docker-compose down && docker-compose up -d
```

### Git
```bash
git checkout -b feature/p2-xxx
git commit -m "feat(P2 #xxx): Description"
git push origin feature/p2-xxx
gh pr create --base=main --title "Title"
```

### GitHub CLI
```bash
gh issue list --state=open --limit=50
gh issue view 418
gh issue comment 418 --body "message"
gh issue close 418
gh run list -w ci-validate.yml --limit=5
```

---

## 9. TESTING & VALIDATION

### Pre-Commit
- `terraform validate`
- `terraform fmt -check .`
- `tfsec .`
- `docker-compose config`
- `kubectl apply --dry-run=client`

### Pre-Deploy
- `terraform plan -out=tfplan`
- `docker-compose up --no-start`
- Service health checks

---

## 10. KNOWLEDGE PRESERVATION

After each session, update:
- `/memories/repo/current-production-state.md` (what's deployed)
- `/memories/repo/active-open-issues.md` (issue status)
- `/memories/session/` (in-progress work)

Record:
- Architecture decisions (ADRs, trade-offs)
- Infrastructure changes (what was deployed)
- Issue status (completed, merged, closed)
- Blocking issues (dependencies)
- Known issues (bugs, workarounds)

---

## 11. COMPLIANCE CHECKLIST

Before submitting work:
- [ ] IaC mandates met (immutable, idempotent, duplicate-free)
- [ ] No secrets hardcoded
- [ ] No security issues (open ports, default passwords)
- [ ] Conventional commit format
- [ ] Issue linked (`Fixes #NNN`)
- [ ] Terraform validated & formatted
- [ ] Documentation updated
- [ ] Memory files updated
- [ ] No conflicts with other sessions
- [ ] On-prem first approach

---

## 12. NON-NEGOTIABLES

- Every branch → open issue → PR with `Fixes #N` → merge → auto-close
- Conventional commits: `feat|fix|refactor|docs|chore|ci(scope): message`
- All changes tested, no CVEs, no secrets in git
- IaC: immutable, idempotent, duplicate-free, on-prem first
- GitHub Issues = SSOT (single source of truth)
- Never PATCH closed issues — add comments only

---

## 13. PRODUCTION HOST INFO

- **Primary**: `ssh akushnir@192.168.168.31` — deploy from here
- **Replica**: `192.168.168.42`
- **Deploy**: `docker compose up -d` or `terraform apply` on remote

---

**Last updated: April 23, 2026**  
**Scope**: kushin77/code-server ONLY  
**Type**: Consolidated, single-source-of-truth for all Copilot sessions  
[All Issues](https://github.com/kushin77/code-server/issues)
