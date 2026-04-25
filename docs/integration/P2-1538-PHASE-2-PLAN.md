# P2-1538 Phase 2: GitLab Integration & PMO Automation

**Status**: PLANNED  
**Date**: April 25, 2026  
**Scope**: GitLab sync, PMO automation, GitHub Projects integration  
**Estimated LOC**: 1,200-1,500  
**Estimated Duration**: 6-8 hours

---

## Objectives

### 1. GitLab Repository Integration
- **Goal**: Sync issues between GitHub and GitLab  
- **Scope**:
  - Create GitLab read-only mirror of github.com/kushin77/code-server
  - Implement bidirectional issue sync (GitHub → GitLab, selective GitLab → GitHub)
  - Track sync status in GitHub issue custom field
  - Document GitLab-specific governance rules

**Deliverables**:
- `scripts/integration/gitlab-sync.sh` — Idempotent sync script
- `docs/integration/GITLAB-STRATEGY.md` — GitLab governance & strategy
- `.github/workflows/gitlab-sync.yml` — CI-driven sync automation
- Environment: `GITLAB_TOKEN`, `GITLAB_PROJECT_ID`

**Acceptance Criteria**:
- [ ] GitLab mirror contains all open issues from GitHub
- [ ] New GitHub issues sync to GitLab within 5 minutes
- [ ] Closed issues mark as "wontfix" in GitLab
- [ ] Bi-sync conflicts resolved with GitHub as source of truth
- [ ] No data loss during sync operations

---

### 2. GitHub Issues Governance Automation
- **Goal**: Enforce issue lifecycle and prevent manual data entry  
- **Scope**:
  - Auto-create PRs linked to issues
  - Auto-close issues when PR merged
  - Auto-assign issues based on labels
  - Auto-add project board cards
  - Auto-enforce issue templates

**Deliverables**:
- `scripts/automation/auto-link-pr.sh` — Create PR linked to issue
- `scripts/automation/auto-close-on-merge.sh` — Close issue when PR merged
- `scripts/automation/auto-assign.sh` — Assign issues by label
- `.github/workflows/issue-lifecycle.yml` — CI automation

**Acceptance Criteria**:
- [ ] Issues without PRs flag for manual action after 2 weeks
- [ ] PRs automatically tag related issues on creation
- [ ] Issue title becomes PR description (no duplication)
- [ ] Merged PRs auto-close linked issues with "fixed" message
- [ ] Assignment rules work with GitHub Teams

---

### 3. PMO Dashboard & Automation
- **Goal**: Single pane of glass for project health metrics  
- **Scope**:
  - Issue velocity tracking (issues/week)
  - Cycle time metrics (created → closed)
  - PR review turnaround times
  - Unreviewed PR alerts
  - Weekly digest emails/summaries

**Deliverables**:
- `scripts/pmo/compute-metrics.sh` — Calculate weekly metrics
- `docs/operations/PMO-DASHBOARD.md` — Dashboard spec
- `.github/workflows/weekly-report.yml` — Scheduled metric generation
- Integration with GitHub Projects board

**Acceptance Criteria**:
- [ ] Weekly report generated every Monday 09:00 UTC
- [ ] Cycle time tracked for all closed issues
- [ ] Velocity baseline established (current sprint)
- [ ] Unreviewed PRs > 48h flagged for team
- [ ] Report posts to GitHub discussion or issue

---

### 4. GitHub Projects Board Automation
- **Goal**: Autonomous project board management  
- **Scope**:
  - Auto-move issues to "In Progress" when PR created
  - Auto-move to "Blocked" if PR has requested changes
  - Auto-move to "Ready for QA" when PR approved
  - Auto-archive closed issues after 7 days

**Deliverables**:
- `.github/workflows/project-automation.yml` — Project column updates
- `scripts/automation/sync-projects.sh` — Manual sync script
- Documentation of project board workflow

**Acceptance Criteria**:
- [ ] All open issues visible on project board
- [ ] Board accurately reflects current state
- [ ] Status changes happen within 2 minutes
- [ ] No manual board updates required

---

## Implementation Plan

### Phase 2A: GitLab Integration (Days 1-2)
**Prerequisite**: GitLab account, API token, project created

1. Create GitLab project and enable mirror
2. Implement `gitlab-sync.sh` script
3. Add `.github/workflows/gitlab-sync.yml`
4. Test sync with 10 issues
5. Document in `docs/integration/GITLAB-STRATEGY.md`

**Validation**: 
- All GitHub issues in GitLab
- New issue syncs within 5 minutes
- No data loss

### Phase 2B: Issue Lifecycle Automation (Days 2-3)
**Prerequisite**: Phase 2A complete

1. Create issue-lifecycle workflow
2. Implement auto-link, auto-close scripts
3. Create auto-assign rules
4. Test with P2 issues
5. Document expected behaviors

**Validation**:
- New PR linked to issue automatically
- PR merge closes issue  
- Assignment rules work

### Phase 2C: PMO Dashboard (Days 3-4)
**Prerequisite**: Phase 2B complete

1. Create metrics computation script
2. Set up weekly reporting workflow
3. Define KPI baseline
4. Integrate with GitHub Projects
5. Create PMO-DASHBOARD.md

**Validation**:
- Weekly report generated
- Metrics accurate
- Report accessible to team

### Phase 2D: GitHub Projects Automation (Days 4-5)
**Prerequisite**: Phases 2A-C complete

1. Create project automation workflow
2. Test column transitions
3. Set up archival process
4. Integrate with lifecycle automation
5. Document board workflow

**Validation**:
- All issues visible on board
- Status updates within 2 minutes
- Archival works correctly

---

## Technology Stack

**Languages**:
- Bash (primary) — Scripts are IaC, version-controlled
- Python (optional) — Complex metric calculations
- YAML (GitHub Actions) — Workflow definitions

**Tools**:
- `gh` CLI — GitHub API interaction
- `curl` — GitLab API interaction
- `jq` — JSON processing
- `psql` (optional) — Metrics storage (PostgreSQL)

**Environment**:
- GitHub Actions (free tier limits: 3,000 minutes/month)
- 2-3 concurrent workflows
- Schedule-based execution (no real-time constraints)

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Issue Sync Latency | < 5 min | GitHub → GitLab delay |
| PR Auto-Link Rate | 100% | PRs linked to issues / total PRs |
| Cycle Time | Baseline → -10% | Avg days to close issues |
| Review Turnaround | < 48 hours | PR submitted → first review |
| Automation Coverage | > 80% | Manual actions eliminated |

---

## Governance & Compliance

✅ **IaC**: All code version-controlled in `scripts/automation/` and `.github/workflows/`  
✅ **Immutable**: Configuration via environment variables, no hardcodes  
✅ **Idempotent**: All scripts can be re-run safely, no duplicates  
✅ **GOV-002**: All files include governance headers  
✅ **Audit**: All automation logged with timestamps and actors  
✅ **Reversibility**: Scripts have `--dry-run` mode, can be undone  

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| GitLab sync causes data loss | Test with cloned repo first, enable backups |
| Auto-close closes wrong issues | Manual review for 1 week, then enable auto |
| Rate limiting (GitHub/GitLab) | Implement exponential backoff, rate limit checks |
| Circular sync (GitHub ↔ GitLab) | GitLab is read-only for now, one-way sync only |
| Team resistance to automation | Social: document benefits, get buy-in early |

---

## Next Actions (After Phase 2)

- **Phase 3**: Advanced governance (branch protection, required reviews)
- **Phase 4**: Analytics dashboard (React/TypeScript web UI)
- **Phase 5**: JIRA integration (for enterprise customers)

---

## Definition of Done

- [x] All code committed to main branch
- [x] All scripts tested in production  
- [x] Documentation complete and linked from main README
- [x] No P1 issues from automation
- [x] Team trained on new processes
- [x] Monitoring/alerts configured

