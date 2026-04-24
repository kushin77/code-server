# Policy Update & Rollout Runbook
## Issue #650: Org-Wide Auth & Policy Baseline

**Objective**: Safely update code-server RBAC policies across all instances with rollback capability

**Prerequisites**:
- Access to GitHub repository (kushin77/code-server)
- GCP project access (gcp-eiq)
- Slack webhook configured (alerts channel)
- Terraform understanding
- ~30 minutes execution time

---

## Overview: Policy Update Flow

```
1. Create feature branch
2. Update policies/code-server.yaml
3. Run drift detection (verify → no issues)
4. Tag all affected services (for restart)
5. Open PR, let CI validate
6. Merge PR (auto-deploys to main)
7. Monitor drift detection (15m intervals)
8. Validate user feedback (2 hours)
9. Declare success or trigger rollback
```

---

## Step 1: Create Feature Branch

```bash
cd /home/coder/code-server

# Pull latest
git checkout main && git pull origin main

# Create policy update branch
git checkout -b chore/650-policy-update-$(date +%Y%m%d)

# Verify you're on the new branch
git branch -vv
```

**Expected Output**:
```
* chore/650-policy-update-20260418   ...
  main                                  ...
```

---

## Step 2: Update Policy File

Edit `policies/code-server.yaml`:

```bash
# Open policy in your editor
code policies/code-server.yaml
```

**Sections you can modify safely**:
- `spec.authorization.roles[]` — Add/remove roles or update permissions
- `spec.authorization.assignments[]` — Change user/group assignments
- `spec.authorization.defaultRole` — Change default access level
- `spec.auditLogging.retentionDays` — Adjust retention (min 30 days)
- `spec.driftDetection.alerting` — Update alert channels
- `spec.compliance` — Add new compliance mappings

**NEVER modify**:
- `spec.authentication.provider` — Changing identity provider requires migration
- `spec.enforcement.onDeny` — Should always be `reject` for production

### Example: Add a new developer role assignment

```yaml
spec:
  authorization:
    roles:
      developer:
        assignments:
          - new-developer@company.com  # <- Add here
          - existing-dev@company.com
```

**Save the file** (Ctrl+S)

---

## Step 3: Run Drift Detection (Verify Mode)

Before committing, verify the changes don't cause drift:

```bash
# Run drift detection in verify mode (no alerts sent)
bash scripts/auth/auth-policy-drift-detection.sh verify

# Check the generated report
cat /tmp/policy-drift-report-*.json | jq .
```

**Expected Output**:
```json
{
  "status": "OK",
  "drift_score_percent": 0,
  "checks": {
    "auth_flow_integrity": "PASS",
    "policy_config_drift": "PASS",
    "audit_log_health": "PASS",
    "identity_provider_health": "PASS"
  }
}
```

**If ANY check fails**:
1. Read the drift report carefully
2. Run individual checks to identify root cause: `bash scripts/auth/policy-drift-detection.sh | grep FAIL`
3. Fix the issue before proceeding
4. Do NOT commit until all checks pass

---

## Step 4: Commit Your Changes

```bash
# Stage policy file
git add policies/code-server.yaml

# Commit with issue reference
git commit -m "chore(policy): update RBAC assignments and audit retention - Fixes #650"

# Verify commit looks good
git log -1 --stat
```

**Commit message format**:
- `chore(policy): ` — Type
- Describe what changed
- End with " - Fixes #650"

---

## Step 5: Validate Changes Locally

```bash
# Show what we're pushing
git show HEAD:policies/code-server.yaml | diff - policies/code-server.yaml

# Verify git history is clean
git log main..HEAD  # Should show your 1 commit
```

---

## Step 6: Push & Open PR

```bash
# Push to origin
git push origin chore/650-policy-update-$(date +%Y%m%d)

# Open PR via GitHub CLI
gh pr create --title "chore(policy): update RBAC - Fixes #650" \
  --body "## Changes
- Updated role assignments
- Adjusted audit retention

## Validation
- Drift detection: PASS
- Policy validation: PASS

## Rollback plan
See (RUNBOOK-POLICY-ROLLBACK.md) if issues detected"
```

**PR auto-opens in browser**. Verify:
- Title includes issue #650
- Body has validation results
- CI checks are running

---

## Step 7: Review CI/CD Results

The PR will trigger these checks:

| Check | Time | Purpose |
|-------|------|---------|
| `validate-policies` | 2m | YAML schema validation |
| `drift-detection` | 3m | Ensure no manual drift |
| `unit-tests` | 5m | Auth system tests |
| `doc-checks` | 1m | README/runbook updates |

**If any check fails**:
1. Click "Details" to see error
2. Fix locally in the branch
3. Re-commit and re-push: `git commit --amend` (no new branch)

**When all checks pass**:
PR auto-merges to main (policy #656 — no manual approval required)

---

## Step 8: Post-Merge: Restart Services

After PR merges, redeploy to ensure new policies are live:

```bash
# Option A: Blue-green deployment (recommended)
docker-compose up -d --force-recreate oauth2-proxy code-server

# Option B: Pod restart (if using Kubernetes)
kubectl rollout restart deployment/code-server -n code-server

# Verify deployment
sleep 10
curl -s http://localhost:4180/oauth2/health | jq .

# Check logs for auth events
gcloud logging read "logName=projects/gcp-eiq/logs/code-server-auth-policy" \
  --project=gcp-eiq --limit=5 --format=json | jq '.[] | .jsonPayload'
```

**Expected**: No errors in logs; auth events flowing to Cloud Logging

---

## Step 9: Monitor Drift Detection (2 hours)

Policy updates trigger drift detection every 15 minutes. Watch for alerts:

```bash
# Check drift status every 15 min (or wait for Slack alert)
watch -n 300 'bash scripts/auth/auth-policy-drift-detection.sh verify'

# Or view reports
ls -lh /tmp/policy-drift-report-*.json | tail -5
cat /tmp/policy-drift-report-*.json | jq '.status'
```

**Expected**: Status = `OK` for all checks

**If Status = `ALERT`**:
- Check drift score
- Review which check failed
- Determine if it's a real policy issue or false positive
- If real issue: trigger rollback (see RUNBOOK-POLICY-ROLLBACK.md)

---

## Step 10: Validate User Impact (2 hours)

Test that users can still authenticate and access workspaces:

```bash
# Use E2E conformance tests if available
bash scripts/ci/test-auth-conformance.sh

# Manual test: Try logging in as a test user
# (or ask team to report any access issues in Slack)

# Check audit logs for auth failures
gcloud logging read \
  "logName=projects/gcp-eiq/logs/code-server-auth-policy AND \
   jsonPayload.event='auth.failed'" \
  --project=gcp-eiq --limit=10 --format=json | jq '.[] | {user: .jsonPayload.userEmail, reason: .jsonPayload.metadata.reason}'
```

**Expected**: 
- All conformance tests pass
- No recent auth.failed events
- Happy team in Slack chatting, not complaining

**If issues found**: See Step 11 (Emergency Rollback)

---

## Step 11: Declare Success

If all validations pass (Section 10), policies are live:

```bash
# Add completion comment to issue #650
gh issue comment 650 \
  --body "✅ Policy update [$(git rev-parse HEAD | cut -c1-7)] deployed successfully

Policy changes:
- [Summary of changes]

Validation:
- Drift detection: PASS
- CI checks: PASS
- Auth events: flowing correctly
- User feedback: no issues reported

The org-wide auth baseline is now live."

# Update PR with success note
gh pr comment 649 --body "✅ Deployment successful. All validations passed."
```

---

## Rollback: See RUNBOOK-POLICY-ROLLBACK.md

If issues detected during the 2-hour monitoring window:

```bash
cat RUNBOOK-POLICY-ROLLBACK.md
# Then follow step-by-step to revert policy
```

---

## Troubleshooting

### "Drift detection shows ALERT but policies look correct"

**Possible causes**:
- Policy YAML was edited manually (not via git)
- Kubernetes/Docker restarted with stale config
- gcloud credentials expired

**Resolution**:
```bash
# Force re-read of committed policy
git checkout HEAD -- policies/code-server.yaml

# Verify hash matches
sha256sum policies/code-server.yaml
git show HEAD:policies/code-server.yaml | sha256sum

# Restart services
docker-compose up -d --force-recreate

# Re-run drift detection
bash scripts/auth/auth-policy-drift-detection.sh verify
```

### "CI check fails: validate-policies"

**Most common**: YAML syntax error

**Resolution**:
```bash
# Validate YAML syntax locally
python3 -c "import yaml; yaml.safe_load(open('policies/code-server.yaml'))"

# If error shown, fix the YAML
# Common mistakes:
# - Misaligned indentation (must be 2-space)
# - Unquoted special characters
# - Missing quotes on boolean true/false

# After fix:
git add policies/code-server.yaml
git commit -m "fix: correct YAML syntax - Fixes #650"
git push
```

### "Users report 403 Forbidden after policy update"

The new policy might be too restrictive.

**Immediate action**:
```bash
# Trigger rollback NOW (don't wait)
bash RUNBOOK-POLICY-ROLLBACK.md
```

Then investigate:
```bash
# Check what the new role permissions are
grep -A 5 "developer:" policies/code-server.yaml | grep permissions

# Check which users were affected
gcloud logging read \
  "jsonPayload.event='policy.denied'" \
  --project=gcp-eiq --limit=20 --format=json | jq '.[] | {user: .jsonPayload.userEmail, denied_at: .timestamp}'
```

---

## Success Criteria

Policy update is successful when:

✅ PR merged to main  
✅ Drift detection: PASS for all checks  
✅ CI workflow: all green  
✅ Auth logs: no `auth.failed` events in last 2h  
✅ User feedback: no Slack complaints about access  
✅ Conformance tests: all pass (if available)  

---

## Communication Template

**If updating during business hours**, post to Slack:

```
🔧 Policy Update in Progress

Branch: chore/650-policy-update-20260418
PR: #XXX
Changes: [Summary]
Timeline: 
  - Deploy: now
  - Monitor: 2 hours
  - Rollback: if issues detected

Expected impact: None (internal policy changes)
Action required: none
Questions: Reply in thread
```

**Post-deployment**:

```
✅ Policy Update Complete

Version: [git SHA]
Changes: [what changed]
Status: All systems green
Next update: [date if planned]
```

---

**Last Updated**: April 18, 2026  
**Author**: kushin77-platform-team  
**Status**: Approved  
**Related**: Issue #650, Runbook: RUNBOOK-POLICY-ROLLBACK.md
