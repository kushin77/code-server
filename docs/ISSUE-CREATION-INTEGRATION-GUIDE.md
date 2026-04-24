# GitHub Issue Creation - Integration Guide for Teams

**Document Purpose**: Step-by-step guide for integrating unified issue creation into team workflows  
**Audience**: Engineering leads, DevOps, Copilot users  
**Effective Date**: April 22, 2026

---

## Table of Contents

1. [Quick Start (5 minutes)](#quick-start-5-minutes)
2. [Integration Checklist](#integration-checklist)
3. [Team Workflows](#team-workflows)
4. [Common Scenarios](#common-scenarios)
5. [Troubleshooting](#troubleshooting)
6. [Compliance Verification](#compliance-verification)

---

## Quick Start (5 minutes)

### Step 1: Verify the Script is Installed

```bash
ls -la scripts/_common/issue-create-unified.sh
```

**Expected**: File exists and is executable

### Step 2: Source the Script

```bash
source scripts/_common/issue-create-unified.sh
```

**Expected**: No errors, functions are loaded

### Step 3: Test Issue Creation (Dry Run)

```bash
copilot_create_issue \
  --title "Test Issue" \
  --priority P2 \
  --dry-run
```

**Expected**: Shows what would be created without creating

### Step 4: Check Production Priorities

```bash
should_prioritize_production kushin77/code-server
list_production_priorities kushin77/code-server
```

**Expected**: Lists any P0/P1 issues

### Step 5: Create a Real Issue

```bash
copilot_create_issue \
  --title "My First Unified Issue" \
  --body "Testing the new governance system" \
  --priority P3 \
  --type documentation \
  --check-duplicates
```

**Expected**: Issue created with P3 + documentation labels

---

## Integration Checklist

### Repository Setup

- [ ] Copy `scripts/_common/issue-create-unified.sh` to your repo
- [ ] Copy `scripts/ci/check-issue-governance.sh` to your repo
- [ ] Update `.github/copilot-instructions.md` with Rule 8
- [ ] Create/update `.github/pull_request_template.md` with governance reminder

### CI/CD Integration

- [ ] Add to `.github/workflows/pr-checks.yml`:
  ```yaml
  - name: Check GitHub Issue Creation Governance
    run: bash scripts/ci/check-issue-governance.sh
  ```

- [ ] Verify PR template mentions unified script

### Team Communication

- [ ] Share governance documentation with team
- [ ] Show example in team meeting
- [ ] Explain in Slack/Teams channel
- [ ] Update team wiki/handbook

### Existing Script Migration

- [ ] Audit existing scripts for direct `gh issue create` calls
- [ ] List violations:
  ```bash
  grep -r "gh issue create" scripts/ | grep -v "issue-create-unified"
  ```

- [ ] Migrate violations one-by-one
- [ ] Test after each migration
- [ ] Create migration PR with all changes

### Testing & Validation

- [ ] Run CI check locally: `bash scripts/ci/check-issue-governance.sh`
- [ ] Create test issue with different priorities (P0, P1, P2, P3)
- [ ] Verify labels are applied correctly
- [ ] Test deduplication (create same issue twice)

---

## Team Workflows

### Workflow 1: DevOps Incident Response

**Scenario**: Production issue detected at 3 AM

```bash
# Load script once
source scripts/_common/issue-create-unified.sh

# Create P0 issue immediately
copilot_create_issue \
  --title "P0 OUTAGE: API responses timing out" \
  --body "Started at 2:47 AM UTC
Affected: All endpoints
Error rate: 100%
Last known good: 2:40 AM UTC (commit abc123)

Symptoms:
- Response timeout: 60+ seconds
- Error: 503 Service Unavailable
- No exceptions in logs, clean shutdown

Mitigation:
- Rolled back to commit abc123
- Monitoring alert frequency: every 1 min

Impact:
- ~50 customers affected
- ~$2K/minute revenue loss" \
  --priority P0 \
  --type infrastructure \
  --labels "incident,urgent" \
  --check-duplicates
```

**Next steps**:
1. Investigate cause while team acknowledges
2. Add comments to issue as you learn more
3. Create P1 follow-up issue for root cause fix

### Workflow 2: Feature Planning Session

**Scenario**: Planning meeting, team identifies new features

```bash
# Start of meeting
source scripts/_common/issue-create-unified.sh

# Check production priorities first
echo "Checking production issues..."
should_prioritize_production kushin77/code-server
if [[ $? -eq 0 ]]; then
    echo "⚠️  Production issues exist! Review these first:"
    list_production_priorities kushin77/code-server
fi

# Create feature issues
copilot_create_issue \
  --title "OAuth2 token refresh in background" \
  --body "Prevent user interruption when tokens expire

Current UX:
- Token expires
- User sees 'Unauthorized' error
- User logs back in

Desired UX:
- Token expires
- Background process refreshes token
- User doesn't notice

Implementation:
- Store refresh token separately
- Add background job to check expiry
- Refresh before expiry (15 min buffer)" \
  --priority P2 \
  --type feature \
  --labels "security,performance" \
  --check-duplicates

# Create related tasks
copilot_create_issue \
  --title "Add Redis TTL monitoring" \
  --body "Track how many sessions are near expiry

Metrics needed:
- Tokens expiring in <1 hour
- Average token lifespan
- Refresh token reuse rate" \
  --priority P2 \
  --type ops \
  --check-duplicates
```

**Team benefits**:
- Production issues get priority
- All features have labels
- Duplicate prevention
- Clear tracking from day one

### Workflow 3: Code Review

**Scenario**: PR review finds a bug, needs tracking

```bash
# In PR comment, link to issue
source scripts/_common/issue-create-unified.sh

# Create bug issue
copilot_create_issue \
  --title "AdminControls component renders twice on mount" \
  --body "Found in PR #462 review

Symptoms:
- Line 87: useEffect has missing dependency
- Causes double API call on component mount
- Performance: 2x latency, 2x API usage

Root cause:
- useEffect(() => { fetchUsers() }, []) 
- Should be: useEffect(() => { fetchUsers() }, [])

Fix:
- Add dependency array: []
- Or add userId to deps if it should update on change

Impact:
- Dev: Not noticeable in small datasets
- Prod: 100K+ users causes 1s page load increase
- Cost: 2x unnecessary API calls" \
  --priority P1 \
  --type bug \
  --labels "performance,code-quality" \
  --check-duplicates

echo "Bug issue created. Link in PR comment now."
```

### Workflow 4: Documentation Gap Found

**Scenario**: During deployment, find missing documentation

```bash
source scripts/_common/issue-create-unified.sh

copilot_create_issue \
  --title "Document GSM secret bootstrap in RUNBOOK" \
  --body "During deployment prep, realized GSM bootstrap steps are missing

Current docs:
- Deployment checklist (high level)
- OAuth2 setup guide

Missing docs:
- GSM project setup
- Service account creation
- Env var mapping from GSM to .env
- Troubleshooting: Failed secret fetch

Estimated time: 2 hours" \
  --priority P2 \
  --type docs \
  --check-duplicates
```

---

## Common Scenarios

### Scenario 1: Creating an Issue from a Slack Message

```bash
# Extract info from Slack
source scripts/_common/issue-create-unified.sh

copilot_create_issue \
  --title "Login takes 30+ seconds on high latency networks" \
  --body "From Slack #support channel (2026-04-22 10:15 AM)

Customer report:
- User on 4G connection (50ms latency)
- Login process takes 30+ seconds
- Normal: ~5 seconds

Reproduction:
- DevTools network throttling: Slow 4G
- Visit /auth
- Click 'Sign in with Google'
- Measure time to dashboard load

Analysis:
- Likely: Multiple sequential API calls
- Waterfall diagram attached

Expected impact:
- ~5% of users on mobile networks
- ~2-3% overall (geographic variation)" \
  --priority P1 \
  --type performance \
  --labels "customer-report,mobile" \
  --check-duplicates
```

### Scenario 2: Tracking Technical Debt

```bash
source scripts/_common/issue-create-unified.sh

copilot_create_issue \
  --title "Refactor SessionBroker to use connection pooling" \
  --body "Current implementation:
- Creates new database connection per request
- ~10ms connection overhead per request
- Connection limit: 100 concurrent

Problems:
- High latency (connection setup time)
- Exhausts limit during load tests
- Can't scale beyond 100 concurrent users

Solution:
- Use pg-pool library
- Connection pool size: 20
- Expected improvement: 10-15ms latency reduction per request

Effort estimate:
- Time: 8 hours
- Complexity: Medium (requires testing)" \
  --priority P3 \
  --type refactor \
  --labels "tech-debt,backend,database" \
  --check-duplicates
```

### Scenario 3: Security Finding

```bash
source scripts/_common/issue-create-unified.sh

copilot_create_issue \
  --title "P0 SECURITY: SQL injection in user search endpoint" \
  --body "VULNERABILITY: Critical SQL injection

Severity: P0 - Remote Code Execution possible
CVSS: 9.8

Location:
- File: backend/routes/admin.js
- Line: 156-162
- Function: searchUsers()

Vulnerable code:
\`\`\`javascript
const query = 'SELECT * FROM users WHERE email = \"' + req.query.email + '\"';
db.query(query);  // ← INJECTION POINT
\`\`\`

Attack example:
- Request: /admin/users?email=admin\"; DROP TABLE users; --
- Result: Users table deleted

Fix (immediate):
- Use parameterized queries: db.query('SELECT * FROM users WHERE email = \$1', [req.query.email])

Fix (validation):
- Add input validation regex
- Reject non-email characters

Timeline:
- IMMEDIATE: Deploy fix to production
- Within 24h: Audit all user-facing search endpoints
- Within 1w: Code review all database queries" \
  --priority P0 \
  --type security \
  --labels "sql-injection,critical,requires-immediate-action" \
  --check-duplicates

# Also notify security team
echo "⚠️  SECURITY ISSUE CREATED - Notify security team immediately!"
```

---

## Troubleshooting

### Issue: Script not found

```bash
# Error: command not found: copilot_create_issue

# Fix: Source the script first
source scripts/_common/issue-create-unified.sh
```

### Issue: Deduplication blocking legitimate issue

```bash
# Error: Skipping creation due to potential duplicates

# Solution: Review similar issues
# Then use --force-create to bypass
copilot_create_issue \
  --title "New issue" \
  --priority P1 \
  --force-create
```

### Issue: Label not applied

```bash
# Problem: Created issue but expected labels missing

# Debug: Check what labels were built
# Add --dry-run to see what would be created
copilot_create_issue \
  --title "Test" \
  --priority P1 \
  --type feature \
  --dry-run

# Verify label mappings in issue-create-unified.sh
grep -A 10 "declare -A TYPE_LABELS" scripts/_common/issue-create-unified.sh
```

### Issue: GitHub auth failing

```bash
# Error: GitHub CLI not authenticated

# Fix: Login to GitHub
gh auth login
# Follow prompts

# Verify auth works
gh auth status
```

### Issue: CI check failing

```bash
# Error: Governance check failed - direct gh calls detected

# Find violations
grep -r "gh issue create" scripts/

# Fix each violation
# Replace: gh issue create --title "..." --label "..."
# With: copilot_create_issue --title "..." --priority P1

# Re-run check
bash scripts/ci/check-issue-governance.sh
```

---

## Compliance Verification

### How to Check Your Team is Compliant

```bash
# 1. Run CI governance check
bash scripts/ci/check-issue-governance.sh

# Expected output:
# ✓ PASS: No governance violations found

# 2. Audit recent issues
gh issue list --repo kushin77/code-server --limit 20 --json "number,title,labels"

# Check: Every issue should have a priority label (P0/P1/P2/P3)

# 3. Check for duplicates in open issues
gh issue list --repo kushin77/code-server --state open --json "title" | jq '.[] | .title' | sort | uniq -c | sort -rn | head -10

# Check: Should not see many duplicate titles

# 4. Production priorities
bash -c "source scripts/_common/issue-create-unified.sh && list_production_priorities kushin77/code-server"
```

### Compliance Report Template

```
# GitHub Issue Creation Governance - Compliance Report
Date: 2026-04-22
Repository: kushin77/code-server
Team: DevOps

## Metrics

✅ Governance Check: PASS (0 violations)
✅ Recent Issues: 15/15 have priority labels
✅ Deduplication: 0 duplicate titles
✅ Production Priority: 2 P0, 3 P1 (being addressed)

## Observations

- All 15 recent issues created using unified script
- Label distribution: P0=2, P1=3, P2=6, P3=4 (expected ratio)
- Average time to label: <1 minute
- Team adoption rate: 100%

## Action Items

- None - Team is fully compliant
```

---

## Next Steps

1. **Immediate** (Today):
   - [ ] Run Quick Start steps above
   - [ ] Create one test issue
   - [ ] Add CI check to your workflow

2. **Short-term** (This week):
   - [ ] Audit existing scripts for violations
   - [ ] Migrate violations
   - [ ] Train team on new workflow

3. **Long-term** (Ongoing):
   - [ ] Monitor CI check results
   - [ ] Provide governance feedback
   - [ ] Suggest improvements to team

---

## Support

- **Questions**: See `docs/GITHUB-ISSUE-CREATION-GOVERNANCE.md`
- **Technical issues**: Check "Troubleshooting" section above
- **Rule changes**: See `.github/copilot-instructions.md` (Rule 8)
- **Feedback**: File an issue with `[governance]` label

---

*Last updated: April 22, 2026*
