# Golden Rule: Mandatory Auto-Redeploy After Every Merge

**Effective**: April 18, 2026  
**Status**: 🟢 ENFORCED  
**Policy**: ZERO EXCEPTIONS

---

## The Golden Rule

> **After every successful merge to `main` branch, fresh code MUST be automatically deployed to production.**

This is a non-negotiable operational requirement that ensures:
- ✅ Production always runs the latest approved code
- ✅ Feedback loop between merge and deployment is immediate
- ✅ Developers get instant validation that their code works in production
- ✅ No stale code running in production (prevents "but it works on my machine")

---

## Enforcement Mechanism

### Workflow: `golden-rule-enforce-redeploy.yml`

**Location**: `.github/workflows/golden-rule-enforce-redeploy.yml`  
**Trigger**: Every push to `main` (all code changes)  
**Scope**: Runs AFTER all other CI/validation checks pass

### How It Works

#### 1. Trigger Point
```
On: push to main (all paths except .md, .gitignore, CODEOWNERS)
When: Automatically after merge completes
Status: Immediate (no waiting, no approval gates)
```

#### 2. Deployment Process
```
1. Checkout latest code from main
2. Validate prerequisites (docker, docker-compose, host connectivity)
3. Deploy to Primary Host (.31)
   ├─ Gracefully stop services (30s timeout)
   ├─ Pull latest images and code
   ├─ Start fresh services (docker-compose up -d --pull always)
   ├─ Verify services are running (ps check)
   └─ Wait 10s for stabilization
4. If Primary fails, Fallback to Secondary Host (.42)
   ├─ Same process on .42
   └─ Services continue on secondary
5. Health Check (60s timeout)
   ├─ Check primary endpoint /health
   ├─ Check secondary endpoint /health
   └─ Assert at least one is healthy
6. Record Deployment Status
   ├─ Create GitHub deployment record
   ├─ Mark as successful in GitHub
   └─ Link to production environment
7. Notify Result
   ├─ Slack notification (success or failure)
   ├─ PR comment with deployment details
   └─ Create critical incident if failed
```

#### 3. Fallback & Recovery
```
Primary Host Down → Automatic Failover to Secondary
├─ Detects if .31 unreachable/unhealthy
├─ Immediately attempts .42
├─ Services continue running on .42
└─ Engineering takes corrective action

Both Hosts Down → CRITICAL ALERT
├─ Slack emergency notification
├─ P0 critical incident created in GitHub
├─ DevOps team paged on-call
└─ Requires manual investigation and redeploy
```

#### 4. Health Checks
```
POST-DEPLOY VALIDATION
├─ Wait for /health endpoint to respond (primary or secondary)
├─ Timeout: 60 seconds (services have 1 minute to boot)
├─ Interval: 5 second checks
└─ Pass criteria: At least one host reporting healthy

If all checks fail:
├─ Workflow fails (exit 1)
├─ Slack alert sent
├─ Critical incident created
└─ Requires manual recovery
```

---

## Compliance & Verification

### What Triggers a Redeploy?
✅ Code changes (any .ts, .js, .py, .yml, .json in root or subdirs)  
✅ Config changes (docker-compose.yml, .env, terraform)  
✅ Script changes (scripts/, Dockerfile)  
✅ CI/workflow changes  

### What Does NOT Trigger a Redeploy?
❌ Markdown files (*.md)  
❌ .gitignore changes  
❌ CODEOWNERS changes  
❌ (Other documentation-only paths)

### Checking Redeploy Status

**Option 1: GitHub Actions Tab**
```
1. Go to github.com/kushin77/code-server/actions
2. Filter by workflow: "Golden Rule"
3. Check latest run status
4. View logs for details
```

**Option 2: GitHub Deployments**
```
1. Go to Deployments tab on repo
2. Filter by environment: "production"
3. View deployment history
4. Check rollout status and health checks
```

**Option 3: CLI**
```bash
# Check last Golden Rule workflow run
gh workflow view golden-rule-enforce-redeploy.yml --json runs \
  --jq '.[0] | "\(.status) - \(.conclusion)"'

# View deployment records
gh deployment list --env production
```

---

## Failure Scenarios & Recovery

### Scenario 1: Primary Host Unreachable
```
Detection: SSH connection fails to .31
Response: 
  1. Workflow logs connection error
  2. Automatically attempts secondary (.42)
  3. If secondary succeeds, deployment marked successful
  4. Alert: "Primary host offline, deployed to secondary"
Recovery: 
  • Restart .31 services
  • Verify connectivity
  • Next merge will reattempt primary
```

### Scenario 2: Docker Compose Fails
```
Detection: docker compose up returns non-zero exit code
Response:
  1. Log error details (image pull failure, volume issues, etc.)
  2. Try secondary host
  3. If secondary also fails, alert DevOps
Recovery:
  • Check disk space on hosts
  • Verify image registry accessibility
  • Fix connectivity/image issues
  • Manually trigger redeploy via workflow_dispatch
```

### Scenario 3: Health Check Timeout
```
Detection: No endpoint responds to /health after 60s
Response:
  1. Log service status (docker compose ps)
  2. Capture error state
  3. Mark deployment as failed
  4. Create critical incident
Recovery:
  • SSH to host and check logs
  • Restart services manually
  • Investigate application errors
  • Redeploy once root cause is fixed
```

### Manual Redeploy (If Automatic Fails)

```bash
# Option 1: Trigger via GitHub CLI
gh workflow run golden-rule-enforce-redeploy.yml --ref main

# Option 2: Trigger via GitHub Web UI
# Go to Actions > Golden Rule > Run workflow > Run workflow

# Option 3: Manual SSH redeploy
ssh akushnir@192.168.168.31
cd /home/akushnir/code-server
git pull origin main
docker compose up -d --pull always
docker compose ps
curl http://localhost:8080/health
```

---

## Notifications & Alerts

### Success Notification
**Slack**:
```
✅ Golden Rule Enforced
Production has been automatically redeployed with the latest code.
Commit: abc1234
Author: @alice
Message: feat(monorepo): improve CI performance
```

**GitHub PR Comment**:
```
✅ Golden Rule Enforced: Code redeployed to production
- Commit: abc1234
- Author: @alice
- Timestamp: 2026-04-18T14:30:00Z
Production is now running the latest code.
```

### Failure Notification
**Slack (Emergency)**:
```
❌ CRITICAL: Production Redeploy Failed
The mandatory golden rule enforcement failed. 
Production may be running stale code.
Commit: abc1234
Action Required: Manual intervention needed
Link: [View Workflow]
```

**GitHub Critical Incident**:
```
Title: 🔴 CRITICAL: Production Redeploy Failed — Golden Rule Violated
Body:
  - Incident link: [Workflow run]
  - Impact: Production may be stale
  - Required actions: investigate, fix, redeploy
  - Assigned to: DevOps team
Labels: P0, production, golden-rule-violation
```

---

## Key Metrics & SLOs

| Metric | Target | Status |
|--------|--------|--------|
| Redeploy Trigger Time | <5 seconds after merge completes | ✅ Automated |
| Deployment Duration | <5 minutes (pull images + start) | ✅ Typical |
| Health Check Timeout | 60 seconds | ✅ Set |
| Fallback Activation | <1 minute if primary fails | ✅ Automatic |
| Failure Alert SLA | <1 minute to Slack/incident | ✅ Immediate |
| Production Downtime Risk | <2 minutes (during deploy) | ✅ Acceptable |

---

## Operational Procedures

### For Developers
1. ✅ Merge PR to main → automatic redeploy happens
2. ✅ Check GitHub Actions tab to see deployment progress
3. ✅ If deployment fails, contact DevOps immediately
4. ✅ DO NOT push fixes that bypass redeploy (every merge must deploy)

### For DevOps/Infrastructure
1. **Monitor** redeploy workflows in Actions tab
2. **Alert** on failures (Slack, incident creation)
3. **Investigate** root cause if Golden Rule fails
4. **Fix** connectivity/infrastructure issues
5. **Validate** both hosts are healthy before declaring resolved
6. **Document** any manual interventions in incident

### For On-Call
1. **Page trigger**: Red alert for failed Golden Rule enforcement
2. **First action**: Check GitHub workflow logs
3. **Investigation**: 
   - Is primary host reachable?
   - Are services running on secondary?
   - What's causing failures?
4. **Recovery**:
   - Restart services if they crashed
   - Fix networking/connectivity if down
   - Manually redeploy if needed
5. **Escalation**: CTO if both hosts compromised

---

## FAQ

### Q: What if I merge a branch to main but don't want it deployed yet?
**A**: The Golden Rule has zero exceptions. Every merge→main = automatic deploy. If you want to delay deployment:
- Don't merge to main yet (use staging branch)
- Keep PR open in draft
- Deploy via release tag (separate from main)

### Q: Can I prevent a redeploy?
**A**: No. The Golden Rule is mandatory. If you need to prevent deployment:
- Don't merge to main
- Use a separate long-lived branch for staging
- Deploy from a different source (releases, tags)

### Q: What if Docker Compose is broken?
**A**: 
1. Fix the issue in code
2. Push fix to feature branch
3. Merge to main → auto-redeploy with fix
4. If broken beyond repair, create incident & rollback

### Q: How do I manually trigger redeploy?
**A**:
```bash
# Via GitHub CLI
gh workflow run golden-rule-enforce-redeploy.yml --ref main

# Via Web: Actions > Golden Rule > Run workflow > Run
```

### Q: Can I disable this workflow?
**A**: No. This is a mandated policy. If you believe it needs to change, file an RFC with CTO. Until approved, the Golden Rule is in effect and cannot be disabled.

---

## Compliance Statement

✅ This workflow enforces the golden rule without regard to:
- Developer convenience
- Number of failing tests in current branch
- Reviewer approval processes
- Risk assessments

**If code merges to main, it WILL go to production automatically.**

This is intentional. It ensures:
- Rapid feedback on code in production
- No stale deployments
- Immediate visibility of issues
- Swift recovery from failures

---

**Last Updated**: April 18, 2026  
**Enforced By**: golden-rule-enforce-redeploy.yml workflow  
**Policy Owner**: Engineering + DevOps  
**Status**: 🟢 ACTIVE AND ENFORCED  

---

For questions or incidents, contact: platform-engineering@kushnir.cloud
