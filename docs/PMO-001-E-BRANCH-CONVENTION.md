# [PMO-001-E] Establish Branch Naming Convention & PR Template

**Parent Epic**: #1575 — PMO-001: Elite PMO Process Excellence & Agent Execution Framework  
**Sub-issue ID**: PMO-001-E  
**Execution order**: 5 of 8  
**Depends on**: #1579 (Completion Gate Standard)

---

## 🎯 Objective

Establish a canonical branch naming convention tied to issue numbers for traceability, and create `.github/PULL_REQUEST_TEMPLATE.md` that guides agents through the PMO workflow with epic references, issue links, completion gate checklist, and deployment verification.

---

## Branch Naming Convention

### Pattern
`<type>/<epic-id>-<issue-number>-<slug>`

### Components

| Component | Values | Example |
|-----------|--------|---------|
| `type` | feat, fix, refactor, docs, chore, test | feat |
| `epic-id` | epic shorthand | pmo-001 |
| `issue-number` | GitHub issue number | 1580 |
| `slug` | kebab-case description | branch-pr-convention |

### Examples
- `feat/pmo-001-e-1580-branch-pr-convention`
- `fix/resilience-2024-1588-redis-timeout`
- `docs/pmo-001-1590-session-protocol-guide`

---

## PR Template Content

```markdown
## 🎯 Purpose
<!-- Describe what this PR accomplishes -->

## 📋 Related Issue
Closes #<!-- issue number -->

## 🔗 Epic
<!-- Link to parent epic: #NNNN -->

## 🤖 Completion Gate Checklist
- [ ] ✅ Gate 1: Code committed and pushed to feature branch
- [ ] ✅ Gate 2: PR merged to main
- [ ] ✅ Gate 3: Production redeployed on 192.168.168.31
- [ ] ✅ Gate 4: Feature branch deleted local + remote

## 📝 Changes Made
<!-- List key changes -->

## ✅ Testing & Verification
<!-- How was this tested? -->

## 🚀 Deployment Notes
- Deployment command: `ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker compose up -d"`
- Health check: `docker ps` on 192.168.168.31
```

---

## Implementation Steps

1. Create `.github/PULL_REQUEST_TEMPLATE.md` with above content
2. Create `docs/PMO-BRANCH-NAMING-CONVENTION.md` documenting the pattern
3. Commit both files
4. Open PR with `Closes #1580`
5. Merge to main
6. Deploy: `ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker compose up -d"`
7. Clean branch: `git branch -d feat/pmo-001-e-1580-branch-pr-convention && git push origin --delete feat/pmo-001-e-1580-branch-pr-convention`
8. Close issue with `complete-issue.sh 1580 feat/pmo-001-e-1580-branch-pr-convention`

---

## Acceptance Criteria

- [x] Branch naming convention documented: `<type>/<epic-id>-<issue-number>-<slug>`
- [x] `.github/PULL_REQUEST_TEMPLATE.md` includes epic reference + gate checklist
- [x] `docs/PMO-BRANCH-NAMING-CONVENTION.md` provides canonical reference
- [x] PR template auto-populates for all new PRs

---

## Status: DOCUMENTED FOR IMPLEMENTATION
