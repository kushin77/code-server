# Workflow Failures: Runbook & Troubleshooting Guide

**Date**: April 15, 2026  
**Purpose**: Diagnose and remediate GitHub Actions workflow failures  
**Audience**: DevOps, Platform Engineers, Release Managers  

---

## Quick Reference

| Failure Type | Cause | Resolution | SLA |
|-------------|-------|-----------|-----|
| Secret Validation Failed | Missing/invalid GitHub secret | Update secret in Settings > Secrets | 15 min |
| VPN Scan Timeout | Network unreachable | Check VPN config + route verification | 30 min |
| Artifact Upload Failed | Insufficient disk space | Check runner logs + increase retention | 1 hour |
| SAST/Dependency Scan Failed | Security vulnerability detected | Fix vulnerability + re-run | 2 hours |
| Status Check Failed | CI job didn't complete | Check job logs + retry | 30 min |

---

## Workflow Failure Scenarios

### Scenario 1: Secret Validation Failed

**Error Message**:
```
::error::WIREGUARD_CONFIG secret not found
Error: Workflow failed with exit code 1
```

**Root Cause**:
- Required GitHub secret `WIREGUARD_CONFIG` is missing
- Secret was deleted or misconfigured
- Secret is not accessible to workflow

**Diagnosis**:
```bash
# On local machine:
gh secret list --repo kushin77/code-server

# Check if WIREGUARD_CONFIG is listed
# If missing: gh secret set WIREGUARD_CONFIG < wg-config.conf
```

**Resolution**:
1. Navigate to: `GitHub > kushin77/code-server > Settings > Secrets and variables > Actions`
2. Click "New repository secret"
3. Name: `WIREGUARD_CONFIG`
4. Value: Paste WireGuard config (base64-encoded or raw)
5. Click "Add secret"
6. Re-run workflow: `Actions > VPN Enterprise Endpoint Scan > Run workflow`

**Verification**:
```bash
# Workflow should now pass secret validation
# Check: Actions > VPN Enterprise Endpoint Scan > Latest run
```

**Prevention**:
- Document all required secrets in `docs/SECRETS-MANAGEMENT.md`
- Enable branch protection rule: "Require status checks before merge"
- Add secret validation as first step in all workflows

---

### Scenario 2: VPN Scan Timeout (Connection Failed)

**Error Message**:
```
[ERROR] VPN interface setup timed out after 300 seconds
[ERROR] Unable to establish connection to 192.168.168.31:443
```

**Root Cause**:
- WireGuard interface failed to come up
- Network routing not configured
- Target host unreachable
- Firewall blocking WireGuard traffic (port 51820/udp)

**Diagnosis**:
```bash
# SSH to host:
ssh akushnir@192.168.168.31

# Check WireGuard status:
sudo ip link show wgci || echo "Interface not found"
sudo wg show || echo "WireGuard not installed"

# Check routing:
ip route show | grep "192.168.168"

# Test connectivity:
ping -c 3 192.168.168.31
curl -v https://ide.kushnir.cloud:8443 --max-time 5
```

**Resolution**:
1. Verify WireGuard config syntax:
   ```bash
   sudo wg-quick down wgci 2>/dev/null || true
   wg-quick strip /etc/wireguard/wgci.conf | sudo tee /etc/wireguard/wgci-valid.conf
   ```

2. Bring up interface:
   ```bash
   sudo wg-quick up wgci
   ```

3. Verify routes:
   ```bash
   sudo ip route show
   # Should show: 192.168.168.0/24 via wgci
   ```

4. Test DNS:
   ```bash
   nslookup ide.kushnir.cloud
   ```

5. Re-run workflow from GitHub

**Prevention**:
- Add network connectivity checks as preflight job
- Document WireGuard config requirements
- Add timeout flexibility (currently 300s, consider 600s for slow networks)

---

### Scenario 3: Artifact Upload Failed (Disk Space)

**Error Message**:
```
[ERROR] Failed to upload artifact: No space left on device
runner: No space left on device (os error 28)
```

**Root Cause**:
- GitHub Actions runner disk full
- Too many artifacts retained (default 90 days)
- Large test result files not cleaned up
- Docker layer cache consuming space

**Diagnosis**:
```bash
# In workflow step:
df -h
du -sh /tmp/*
du -sh ~/.docker/*

# Check artifact storage:
gh run download <RUN_ID> --dir /tmp/artifacts
du -sh /tmp/artifacts
```

**Resolution**:
1. Increase artifact retention policy (GitHub Actions settings):
   - Settings > Artifacts and logs > Artifact retention
   - Set to 5-14 days (default is 90)

2. Add cleanup step before upload:
   ```yaml
   - name: Cleanup before artifact upload
     run: |
       df -h
       rm -rf /tmp/*.log /tmp/*.json /tmp/coverage
       docker system prune -af
       df -h
   ```

3. Compress artifacts:
   ```yaml
   - name: Compress coverage results
     run: tar -czf coverage-results.tar.gz test-results/
   
   - name: Upload compressed artifact
     uses: actions/upload-artifact@v4
     with:
       name: coverage-results
       path: coverage-results.tar.gz
       retention-days: 7
   ```

**Prevention**:
- Set explicit retention days on all `upload-artifact` steps
- Add disk cleanup before artifact operations
- Monitor workflow disk usage trends

---

### Scenario 4: SAST/Security Scan Failed

**Error Message**:
```
[ERROR] Semgrep scan found 5 critical issues:
  - Hardcoded credentials in docker-compose.yml:45
  - SQL injection risk in query builder:121
  - Insecure randomness in session.ts:89
```

**Root Cause**:
- Security vulnerability introduced in code
- Known pattern violation detected
- Hardcoded secrets found
- Third-party dependency with CVE

**Diagnosis**:
```bash
# Run locally first:
semgrep --config p/security-audit .

# Check dependencies:
npm audit

# Run SAST locally:
trufflehog filesystem .
```

**Resolution**:
1. **If hardcoded credential**:
   ```bash
   # Find and remove:
   git log -S "password\|secret\|token" --oneline | head -5
   # Remove from history + rotate credential
   ```

2. **If vulnerability**:
   ```bash
   # Fix code vulnerability
   # Update vulnerable dependency: npm audit fix
   # Re-run scan locally to verify
   ```

3. **If false positive**:
   - Document in `.semgrep-allowlist.yml`
   - Add review approval override
   - File issue for false positive pattern

4. **Re-run**:
   ```bash
   git push  # Triggers workflow automatically
   ```

**Prevention**:
- Enforce SAST scanning on every PR (required check)
- Add pre-commit hook for secret detection
- Document security scanning failures in runbook
- Train developers on secure coding patterns

---

### Scenario 5: Workflow Status Check Failed (CI Never Completes)

**Error Message**:
```
Workflow did not complete within timeout (900 seconds)
Status check timed out
```

**Root Cause**:
- Long-running job exceeded timeout
- Job waiting for external resource (e.g., test server)
- Infinite loop or hang in script
- GitHub runner crashed/disconnected

**Diagnosis**:
```bash
# Check workflow logs:
gh run view <RUN_ID> --log

# Look for:
# - Last log entry (where it hung)
# - Resource usage (CPU/memory maxed out)
# - External dependency timeouts
```

**Resolution**:
1. **Increase timeout**:
   ```yaml
   jobs:
     long_running:
       name: Long Running Task
       timeout-minutes: 120  # Increase from default 360
   ```

2. **Add intermediate checkpoints**:
   ```yaml
   - name: Step 1 - Part A
     run: echo "Progress checkpoint 1"
   
   - name: Step 1 - Part B
     run: echo "Progress checkpoint 2"
   ```

3. **Kill hanging processes**:
   ```yaml
   - name: Cleanup hanging processes
     if: always()
     run: |
       pkill -9 -f "hang-risk-process" || true
       pkill -9 -f "stale-server" || true
   ```

**Prevention**:
- Set explicit timeout-minutes on long jobs
- Add heartbeat/progress logging
- Split jobs into smaller stages
- Document expected duration for each job

---

### Scenario 6: Deployment Blocked by Quality Gate

**Error Message**:
```
PR blocked by required status check: "QA Coverage Gate"
  ✓ Code review
  ✓ Tests passing
  ✗ Coverage below threshold (89% < 95% required)
```

**Root Cause**:
- Code coverage dropped below 95% threshold
- SLO not met (regression > 5%)
- Missing test coverage for new code paths

**Diagnosis**:
```bash
# Run coverage locally:
npm test -- --coverage

# Compare against baseline:
cat .coverage-history/baseline.json | jq '.coverage_percent'

# Generate report:
npm test -- --coverage --json > coverage-report.json
```

**Resolution**:
1. **Add missing tests**:
   ```bash
   # Identify untested lines:
   npm test -- --coverage --coverageReporters=text-lcov | genhtml -o coverage_html -
   # Review coverage_html/index.html
   ```

2. **Update tests**:
   ```bash
   # Example: Test new function
   describe("newFeature", () => {
     it("should return correct value", () => {
       expect(newFeature()).toBe(expected);
     });
   });
   ```

3. **Re-run**:
   ```bash
   git push  # Triggers CI
   # GitHub > PR > Checks > QA Coverage Gate > Re-run
   ```

**Prevention**:
- Require tests for all new code (100% for business logic)
- Add pre-commit hook for coverage check
- Configure pre-push verification
- Document coverage targets in README

---

## Emergency Procedures

### Force Skip Failed Check (Last Resort)

**⚠️ WARNING**: Only use with explicit approval from security team

```bash
# 1. Request override in GitHub (add label: skip-checks)
gh pr edit #<PR_NUMBER> --add-label skip-checks

# 2. Document reason in PR comment:
gh pr comment #<PR_NUMBER> -b "Override reason: [explain]"

# 3. Security review approval required
```

### Rollback Failed Deployment

```bash
# 1. Identify last good commit:
git log --oneline main | head -5

# 2. Revert problematic commit:
git revert <commit-sha>
git push origin main

# 3. Verify rollback:
# GitHub > Actions > Latest run should succeed
```

---

## Monitoring & Alerting

### Daily Workflow Health Report

```bash
#!/bin/bash
# workflows-daily-report.sh

echo "=== Workflow Health Report (Last 24h) ==="
gh run list -R kushin77/code-server \
  --created ">$(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --json status,name,updatedAt \
  --query '.[] | [.name, .status, .updatedAt]' \
  -t 'table {{.name}}\t{{.status}}\t{{.updatedAt}}'

echo ""
echo "Failed workflows (requires action):"
gh run list -R kushin77/code-server --status failure --limit 10
```

### Slack Notifications

Add to workflow for critical failures:
```yaml
- name: Notify Slack on failure
  if: failure()
  uses: slackapi/slack-github-action@v1
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK_URL }}
    payload: |
      {
        "text": "🚨 Workflow Failed",
        "blocks": [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn",
              "text": "*${{ github.workflow }}* failed\n${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
            }
          }
        ]
      }
```

---

## Escalation Path

| Issue | On-Call | Response | Duration |
|-------|---------|----------|----------|
| Secret validation | DevOps Lead | 15 min | 1 hour |
| Network/VPN | Network Ops | 30 min | 2 hours |
| Security scan | Security Lead | 1 hour | 4 hours |
| Performance timeout | Eng Lead | 30 min | 2 hours |
| Systemic failure | VP Eng | 15 min | ASAP |

---

## Success Metrics

- **MTTR** (Mean Time To Repair): < 30 minutes
- **Failure Rate**: < 0.5% (false positives + transient)
- **Recovery Time**: < 5 minutes after fix
- **Coverage**: All workflow failure modes documented

---

**Last Updated**: April 15, 2026  
**Owner**: Platform Engineering  
**Review**: Quarterly or after workflow changes  

See Also:
- [CONTRIBUTING.md](../../CONTRIBUTING.md)
- [SECRETS-MANAGEMENT.md](../SECRETS-MANAGEMENT.md)
- [Production Standards](../../PRODUCTION-STANDARDS.md)
