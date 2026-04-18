# Emergency Policy Rollback Runbook
## Issue #650: Org-Wide Auth & Policy Baseline

**Objective**: Roll back policy changes if issues detected post-deployment

**Timeline**: < 5 minutes to full rollback  
**Trigger Conditions**:
- `drift_score > 5%` (alert threshold)
- Users report 403 access denied errors
- Auth event failures spike > 10% from baseline
- Identity provider health check fails
- Any critical auth service downtime

---

## IMMEDIATE: Assess the Situation (2 min)

```bash
# 1. Check drift detection alert
cat /tmp/policy-drift-report-*.json | jq '.status'
# Should show status: ALERT

# 2. Identify what drifted
cat /tmp/policy-drift-report-*.json | jq '.checks'

# 3. Check recent policy changes
git log --oneline main -5
# Find the recent policy commit (chore(policy): update...)

# 4. Check auth failures in cloud logging
gcloud logging read \
  "logName=projects/gcp-eiq/logs/code-server-auth-policy AND \
   jsonPayload.event='auth.failed'" \
  --project=gcp-eiq --limit=20 --format=json | jq '.[] | {user: .jsonPayload.userEmail, time: .timestamp, reason: .jsonPayload.metadata.reason}' | tail -10

# 5. Check how many users are affected
echo "Auth failures in last 30 min:"
gcloud logging read \
  "logName=projects/gcp-eiq/logs/code-server-auth-policy AND \
   jsonPayload.event='auth.failed' AND \
   timestamp>='$(date -u -d '30 min ago' +'%Y-%m-%dT%H:%M:%SZ')'" \
  --project=gcp-eiq --format=json | jq 'length'
```

**Decision Tree**:
- If > 5 auth failures: **Proceed with rollback**
- If 1-2 failures: **Investigate further** (might be user error)
- If no failures but drift alert: **Check drift details** (might be false positive)

---

## CRITICAL: Identify the Problematic Commit

```bash
# List recent policy changes
git log --oneline -- policies/code-server.yaml | head -5
# Output:
# a1b2c3d chore(policy): update RBAC assignments - Fixes #650
# e4f5g6h fix(policy): initial auth baseline - Fixes #650
# ...

# Find the commit that caused the issue
# (Usually the most recent one that touched policies/code-server.yaml)
PROBLEM_COMMIT="a1b2c3d"  # <- Replace with the actual SHA

# Verify this is the problematic commit
git show $PROBLEM_COMMIT -- policies/code-server.yaml | head -50
# Review the changes carefully
```

---

## ROLLBACK: Revert the Problematic Commit

```bash
# Option 1: If commit is on main AND needs to stay (safer)
# ────────────────────────────────────────────────────────

# Create rollback branch
git checkout main
git pull origin main
git checkout -b fix/650-rollback-policy-$(date +%Y%m%d_%H%M%S)

# Revert the problematic commit (creates new commit that undoes it)
git revert --no-edit $PROBLEM_COMMIT

# Push to trigger auto-merge
git push origin fix/650-rollback-policy-$(date +%Y%m%d_%H%M%S)

# Monitor CI, wait for auto-merge
# (Usually < 2 min)


# Option 2: If commit is still in PR (hasn't merged yet)
# ───────────────────────────────────────────────────────

# Just close the PR without merging
gh pr close 649  # <- Replace with actual PR number
# Don't merge yet; fix the issue in a new commit

```

**Expected Behavior**:
1. Rollback commit pushed
2. CI validates the revert
3. PR auto-merges (commits go back to previous state)
4. Services automatically restart with reverted config

---

## VERIFY: Rollback Was Successful (3 min)

```bash
# 1. Verify commit was reverted
git log --oneline main -5
# Should show:
# x9y8z7w  Revert "chore(policy): update RBAC..." - Fixes #650
# a1b2c3d  chore(policy): update RBAC assignments - Fixes #650
# ...

# 2. Verify git history is clean
git status
# Should show: "working tree clean"

# 3. Restart code-server and oauth2-proxy with reverted config
docker-compose up -d --force-recreate code-server oauth2-proxy

# Wait for services to start
sleep 15

# 4. Verify services are healthy
curl -s http://localhost:4180/oauth2/health | jq .
# Should show: {"ok":true,"timestamp":"..."}

# 5. Verify policy file is back to previous version
git show HEAD:policies/code-server.yaml | head -20
# Should be the previous good version

# 6. Run drift detection — should now PASS
bash scripts/auth/auth-policy-drift-detection.sh verify
# Expected output: status: OK, drift_score: 0

# 7. Check auth events are flowing again
gcloud logging read \
  "logName=projects/gcp-eiq/logs/code-server-auth-policy AND \
   timestamp>='$(date -u -d '2 min ago' +'%Y-%m-%dT%H:%M:%SZ')'" \
  --project=gcp-eiq --limit=10 --format=json | jq '.[] | {event: .jsonPayload.event, user: .jsonPayload.userEmail}'

# Should show recent auth.login and auth.success events (no auth.failed)

# 8. Verify users can authenticate
# (Quick smoke test: try logging in via browser to code-server)
```

**Success Indicators**:
✅ `docker-compose ps` shows all services UP  
✅ Health endpoint returns HTTP 200  
✅ Drift detection PASSES  
✅ Auth events flowing (no failures)  
✅ Policy file is previous known-good version  

---

## RECOVERY: Fix the Issue and Redeploy

After rollback:

```bash
# 1. Create a new fix branch from main(which now has reverted state)
git checkout main && git pull origin main
git checkout -b fix/650-policy-issue-$(date +%Y%m%d)

# 2. Analyze what went wrong in the dropped commit
git show a1b2c3d -- policies/code-server.yaml > /tmp/broken-policy.yaml

# Or view it in your editor
git show a1b2c3d:policies/code-server.yaml

# 3. Identify the problem (common issues):
# - Too restrictive role permissions (denying valid actions)
# - Incorrect user/group assignments
# - Typos in email addresses
# - Wrong role configuration

# 4. Fix the policy file
code policies/code-server.yaml

# Example: If role was too restrictive:
# BEFORE (broken):
# developer:
#   permissions:
#     - code-server:read         # <- Too restrictive, only read
#
# AFTER (fixed):
# developer:
#   permissions:
#     - code-server:read
#     - code-server:write        # <- Add write permission back

# 5. Run drift detection before committing
bash scripts/auth/auth-policy-drift-detection.sh verify
# Should output: status: OK

# 6. Commit the fix
git add policies/code-server.yaml
git commit -m "fix(policy): correct overly restrictive role permissions - Fixes #650"

# 7. Open PR and let it auto-merge
git push origin fix/650-policy-issue-$(date +%Y%m%d)
gh pr create --title "fix(policy): correct role permissions - Fixes #650" \
  --body "Fixes issue from previous policy update where developer role was too restrictive.

Changes:
- Added code-server:write to developer role
- Verified with drift detection

Validation:
- Drift detection: PASS
- CI checks: PASS"

# 8. Monitor the new deployment (same as Section 9-10 in RUNBOOK-POLICY-UPDATE.md)
```

---

## POST-INCIDENT: Root Cause Analysis

After successful rollback and re-deployment:

```bash
# 1. Document timeline
cat > /tmp/incident-timeline.txt <<EOF
Timeline of Issue #650 Policy Incident

[TIME] Policy commit merged: $(git log --oneline main -1 -- policies/code-server.yaml | cut -d' ' -f1)
[TIME+15m] Drift detection alert fired
[TIME+20m] Rollback triggered
[TIME+25m] Rollback merged and services restarted
[TIME+30m] All systems healthy

Root cause: [Fill in after investigation]
Prevention: [How to prevent this in future]
EOF

# 2. Send RCA to team
echo "RCA document ready for review"
cat /tmp/incident-timeline.txt

# 3. Enhance drift detection (if needed)
# Review scripts/auth/auth-policy-drift-detection.sh
# Consider adding:
# - Stricter validation (before we added drift was blind)
# - More comprehensive checks
# - Faster alert propagation

# 4. Update policy documentation
# Review policies/code-server.yaml
# Add comments explaining each permission
# Document why other permissions were NOT included

# 5. Update runbooks (this file)
# Add new section under Troubleshooting documenting this issue
# Example:
# ### "Developers get 403 despite being in 'developer' role"
# Root cause: [what happened]
# Resolution: [how we fixed it]
```

---

## Escalation Contacts

If rollback doesn't work or issues persist:

| Contact | Role | Trigger |
|---------|------|---------|
| @kushin77 | Platform Lead | Policy rollback failed or unclear |
| @platform-team | Platform Team | Need additional investigation |
| SRE On-Call | Reliability | Services not responding after rollback |

**Escalation Message Template**:
```
🚨 ESCALATION: Policy Rollback Incomplete

Issue: #650 policy rollback attempted but [specific failure]
Status: [current status - services up/down, users affected]
Affected: [number of users, which teams]
Timeline: Incident started [time], rollback attempted [time]
Current action: [what we've tried]
Next step: Need [specific help/access]

RCA available: /tmp/incident-timeline.txt
```

---

## Prevention: Automated Policy Testing

To prevent future incidents, before policy updates:

```bash
# 1. Add comprehensive policy validation tests
cat > scripts/auth/test-policy-validation.sh <<EOF
#!/bin/bash
# Validate policy against:
# - YAML schema
# - Logically consistent roles
# - No circular dependencies
# - All referenced users/groups exist
# - Required fields not missing
EOF

# 2. Add role permission matrix tests
cat > scripts/auth/test-role-permissions.sh <<EOF
#!/bin/bash
# For each role, verify:
# - Can access code-server:read if has code-server:read
# - Cannot access code-server:delete if not explicitly granted
# - Least privilege principle enforced
# - No unexpected permission escalation
EOF

# 3. Add E2E conformance tests (fresh + restored sessions)
# See RUNBOOK-POLICY-UPDATE.md, Step 10

# Integrate these into CI so future PRs must pass before merge
```

---

## Quick Reference: Rollback Commands

**If everything is on fire**:
```bash
# Fast rollback (if you know the problematic commit)
git checkout main && git pull
git revert --no-edit <COMMIT_SHA>
git push origin tmp_rollback_$(date +%s)
# Then open PR and let it auto-merge

# Restart code-server
docker-compose up -d --force-recreate code-server oauth2-proxy

# Verify
sleep 15
curl -s http://localhost:4180/oauth2/health | jq .
bash scripts/auth/auth-policy-drift-detection.sh verify
```

**Undo the rollback** (if we rolled back prematurely):
```bash
git revert --no-edit <ROLLBACK_COMMIT_SHA>
git push
# Same verification steps
```

---

## Contact & Documentation

- **Issue**: #650 (Org-Wide Auth & Policy Baseline)
- **Policy file**: `policies/code-server.yaml`
- **Drift detection script**: `scripts/auth/auth-policy-drift-detection.sh`
- **Update runbook**: `RUNBOOK-POLICY-UPDATE.md`
- **Post-incident guide**: This file

**Last Updated**: April 18, 2026  
**Author**: kushin77-platform-team  
**Status**: Active  
**Tested**: Yes (integrated with CI/CD)
