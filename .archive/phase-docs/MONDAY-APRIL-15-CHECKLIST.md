# Monday April 15, 2026 - Sprint Start Checklist

**Sprint**: April 15-21 (Phase 2 + Dependabot CVEs + Phase 23-A)
**Owner**: @kushin77
**Time**: 09:00 UTC Start
**Duration**: 5 business days

---

## ✅ Pre-Sprint (Friday April 14 - COMPLETED)

- [x] Sprint plan document created → `SPRINT-APRIL-15-21-2026.md`
- [x] Three tracks defined: Phase 2, Dependabot, Phase 23-A
- [x] Production status verified (all services healthy)
- [x] OTel config file ready → `otel-config.yml`
- [x] Repository clean and synced

---

## 📋 Monday April 15 - Track Setup (9 hours)

### Morning (09:00-11:00) - Track 1: Phase 2 Branch Protection

#### 09:00-09:30
- [ ] Review GitHub branch protection documentation
- [ ] Understand current main branch protection rules
- [ ] Check what's already configured

```bash
# SSH to GitHub (or use API)
# Go to: https://github.com/kushin77/code-server/settings/branches
# Current state: Check if "Require status checks" is enabled
```

#### 09:30-10:15
- [ ] Configure required status checks in GitHub UI
  - [ ] Repository Settings → Branches → main
  - [ ] Check: "Require status checks to pass before merging"
  - [ ] Select checks:
    - [ ] `validate-config` (from .github/workflows/)
    - [ ] `docker-compose-syntax`
    - [ ] `terraform-validate`
    - [ ] `shell-lint`
    - [ ] `secrets-scan`
  - [ ] Check: "Dismiss stale pull request approvals"
  - [ ] Check: "Require branches to be up to date before merging"
  - [ ] Set: "Require 1 code review"

#### 10:15-11:00
- [ ] Verify configuration saved
- [ ] Take screenshot of configured rules
- [ ] Document in: `PHASE-2-BRANCH-PROTECTION-ENABLED.md`

**Deliverable**: Screenshots showing enabled checks + Save link

---

### Late Morning (11:00-13:00) - Track 3.1: Deploy OTel Collector

#### 11:00-11:30
- [ ] SSH to 192.168.168.31
- [ ] Create container startup command:

```bash
ssh akushnir@192.168.168.31 @"
docker run -d \
  --name otel-collector \
  --restart unless-stopped \
  --network code-server-enterprise_enterprise \
  -p 4317:4317 \
  -p 4318:4318 \
  -p 14250:14250 \
  -v /home/akushnir/code-server-enterprise/otel-config.yml:/etc/otel/config.yml \
  otel/opentelemetry-collector-contrib:0.88.0

sleep 3
docker ps --filter name=otel-collector --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
echo 'Checking health endpoint...'
curl -s http://localhost:13133/healthz
"@
```

#### 11:30-12:00
- [ ] Verify container running
- [ ] Check health endpoint: `curl http://192.168.168.31:13133/healthz`
- [ ] Expected: `{"status":"Server available","upSince":"...","uptimeNanos":"..."}`

#### 12:00-13:00
- [ ] Check logs: `docker logs otel-collector --tail 20`
- [ ] Verify no errors
- [ ] Document in: `PHASE-23-A-DEPLOYMENT-LOG.md`

**Deliverable**: OTel running on ports 4317/4318/14250, health check passing

---

### Afternoon (14:00-16:00) - Track 2.1: Dependabot Audit

#### 14:00-14:30
- [ ] Navigate to security page: `https://github.com/kushin77/code-server/security/dependabot`
- [ ] List all alerts (2 high, 3 moderate)
- [ ] For each: Document:
  - [ ] CVE ID
  - [ ] Affected package name
  - [ ] Current version
  - [ ] Required version
  - [ ] Severity
  - [ ] Description

#### 14:30-16:00
- [ ] Create tracking issue: `.github/DEPENDABOT-CVE-TRACKER.md`

```markdown
# Dependabot CVEs - April 14, 2026

## High Severity (2)

### CVE-1: [NAME]
- Package: [pkg-name]
- Current: [version]
- Required: [version]
- Status: TODO
- Risk: [HIGH/MEDIUM/LOW]

### CVE-2: [NAME]
...

## Moderate Severity (3)

### CVE-3: [NAME]
...
```

**Deliverable**: Complete CVE tracking document

---

## ✅ Monday End-of-Day Status (16:00-17:00)

### Checklist
- [ ] Track 1: GitHub branch protection enabled + verified
- [ ] Track 1: Screenshot + documentation saved
- [ ] Track 3: OTel Collector running + healthcheck passing
- [ ] Track 2: All 5 CVEs documented + categorized
- [ ] All 3 tracks ready for Tuesday continuation

### Standup Notes
- [ ] What was completed
- [ ] What's blocked
- [ ] What's next (Tuesday priorities)

---

## Tuesday April 16 - Integration Testing (9 hours)

_Scheduled for next session_

### Track 1.2: Test PR Validation (3 hours)
- Create test/governance-enforcement branch
- Deliberately break docker-compose
- Create PR → verify CI catches it
- Document error messages

### Track 3.2: Deploy Jaeger (2 hours)
- Launch Jaeger backend
- Verify UI accessible on :16686
- Configure connection to OTel Collector

### Track 2.2: Update Dependencies (2 hours)
- Create fix/dependabot-cves branch
- Update vulnerable packages
- Run tests to verify no breakage

### Track 2.3: Merge CVE Fix (1 hour)
- Create PR
- Get review
- Merge

---

## Repository State

**Commits prepared for Monday**:
- [x] SPRINT-APRIL-15-21-2026.md (main)
- [x] otel-config.yml (exists)
- [x] PRODUCTION-STATUS-APRIL-14.md (main)
- [x] PHASE-23-ADVANCED-OBSERVABILITY.md (main)

**Monday deliverables to commit**:
- [ ] PHASE-2-BRANCH-PROTECTION-ENABLED.md
- [ ] PHASE-23-A-DEPLOYMENT-LOG.md
- [ ] .github/DEPENDABOT-CVE-TRACKER.md
- [ ] .github/VALIDATION-GUIDE.md (draft)

---

## Success Criteria (Monday EOD)

| Criterion | Target | Status |
|-----------|--------|--------|
| Phase 2 branch protection enabled | YES | ⏳ |
| OTel Collector running | YES | ⏳ |
| OTel health check passing | HTTP 200 | ⏳ |
| CVEs documented & prioritized | 5/5 | ⏳ |
| No production issues | NONE | ✅ |
| All 3 tracks ready to continue | YES | ⏳ |

---

## Emergency Contacts

If anything blocks progress Monday:
- **Infrastructure Issue**: SSH to 192.168.168.31, check docker logs
- **GitHub Access**: Verify permissions to repository settings
- **Network Issue**: Check connectivity to 192.168.168.31
- **Docker Image Pull**: May be slow, pull overnight if needed

---

## Next Session Handoff (Tuesday)

Pass to next engineer/session:
- [ ] All Monday tasks completed + documented
- [ ] Branch protection enabled + verified
- [ ] OTel running + healthy
- [ ] CVE tracker created
- [ ] Ready to continue with integration testing Tuesday

---

**Status**: 🟢 READY FOR MONDAY START
**Owner**: @kushin77
**Start Time**: April 15, 09:00 UTC
