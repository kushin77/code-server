# VPN Enterprise Endpoint Scan - Manual Runbook

**Issue**: VPN-OPS-011  
**Purpose**: Hardened operational guide for VPN endpoint scanning in both scheduled and manual execution modes  
**Audience**: On-call operators, SREs, DevOps team

## Quick Reference

### Scheduled Execution
- **Frequency**: Every hour (0 * * * *)
- **Duration**: ~10 minutes
- **Status**: Check GitHub Actions > VPN Enterprise Endpoint Scan
- **Artifacts**: Retained for 30 days

### Manual Execution (Immediate)
```bash
# Via GitHub UI: Actions > VPN Enterprise Endpoint Scan > Run workflow > Configure
# Select action: scan | scan-verbose | manual-verify

# Via CLI:
gh workflow run vpn-enterprise-endpoint-scan-enhanced.yml \
  -f action=scan \
  -f base_url=https://ide.kushnir.cloud \
  -f vpn_interface=wgci
```

---

## Prerequisites

### Required Secrets
**Location**: GitHub > Settings > Secrets and variables > Actions

1. **WIREGUARD_CONFIG** (REQUIRED)
   - **What**: Base64-encoded or plain WireGuard configuration
   - **Format**:
     ```
     [Interface]
     Address = 10.x.x.x/32
     PrivateKey = <key>
     DNS = <dns>
     
     [Peer]
     PublicKey = <key>
     AllowedIPs = <ips>
     Endpoint = <endpoint>
     ```
   - **How to set**: 
     - Copy WireGuard config file contents
     - Settings > Secrets > New repository secret
     - Name: `WIREGUARD_CONFIG`
     - Paste contents (no encoding needed)
   - **Validation**: Syntax checked at runtime

2. **VPN_SCAN_BASE_URL** (OPTIONAL)
   - **What**: Override default base URL
   - **Default**: https://ide.kushnir.cloud
   - **How to set**: Same as WIREGUARD_CONFIG

3. **SLACK_NOTIFICATIONS_WEBHOOK** (OPTIONAL)
   - **What**: Slack webhook for failure notifications
   - **How to set**: Create Incoming Webhook in Slack workspace
   - **Value**: `https://hooks.slack.com/services/T.../B.../XXX`

### Local Environment (For Manual Host Execution)

```bash
# Install WireGuard
apt-get install -y wireguard-tools iproute2 jq curl dnsutils

# Install Node.js
node --version  # Require v20+

# Install dependencies
cd tests/vpn-enterprise-endpoint-scan
npm install
npx playwright install --with-deps chromium
```

---

## Execution Modes

### Mode 1: Scheduled Scan (Automatic)
**Trigger**: Every hour  
**Environment**: GitHub Actions runner  
**User Input**: None  
**Actions Taken**:
1. Validate WireGuard config secret exists
2. Bring up VPN interface
3. Verify routing to target
4. Execute endpoint scan
5. Upload results to artifacts
6. Notify on failure (if Slack webhook configured)

**Troubleshooting**: Check GitHub Actions logs

---

### Mode 2: Manual Scan via GitHub UI (Recommended)

**Steps**:

1. **Navigate to workflow**
   ```
   GitHub > Code Server repo > Actions > VPN Enterprise Endpoint Scan
   ```

2. **Trigger workflow_dispatch**
   ```
   Click "Run workflow" button (right side)
   ```

3. **Configure inputs**
   ```
   Action: scan | scan-verbose | manual-verify
   Base URL: https://ide.kushnir.cloud (or custom)
   VPN Interface: wgci (usually no change needed)
   Retention Days: 30 (artifact retention)
   ```

4. **Confirm and execute**
   ```
   Click "Run workflow"
   ```

5. **Monitor execution**
   ```
   Wait for "Deep VPN Endpoint Scan" job to complete
   Check "Annotations" section for any errors
   ```

6. **Review results**
   ```
   Download "vpn-endpoint-scan-results" artifact
   Review: summary.json, debug-errors.log, screenshots/
   ```

---

### Mode 3: Manual Execution on Host

**When to use**: Immediate diagnostics, emergency validation, local testing

**Steps**:

1. **SSH to host**
   ```bash
   ssh akushnir@192.168.168.31
   cd code-server-enterprise
   ```

2. **Configure WireGuard**
   ```bash
   # Copy config to /etc/wireguard/wgci.conf
   # Must be readable only by root:
   sudo chmod 600 /etc/wireguard/wgci.conf
   ```

3. **Bring up VPN**
   ```bash
   sudo wg-quick up wgci
   ip link show wgci  # Verify UP status
   ```

4. **Run scan**
   ```bash
   export VPN_INTERFACE=wgci
   export VPN_SCAN_BASE_URL=https://ide.kushnir.cloud
   cd tests/vpn-enterprise-endpoint-scan
   npm install
   node run-vpn-enterprise-scan.mjs
   ```

5. **Review results**
   ```bash
   ls -la test-results/vpn-endpoint-scan/
   cat test-results/vpn-endpoint-scan/*/summary.json | jq .
   ```

6. **Cleanup**
   ```bash
   sudo wg-quick down wgci
   ```

---

## Troubleshooting Matrix

### Problem: Secret Validation Failed

**Error Message**: `Missing required secret: WIREGUARD_CONFIG`

**Root Cause**: WireGuard configuration not configured in GitHub secrets

**Resolution**:
1. Get WireGuard config file
2. Go to GitHub > Settings > Secrets and variables > Actions
3. Create new secret: `WIREGUARD_CONFIG`
4. Paste entire WireGuard config
5. Re-run workflow

**Verification**:
```bash
# Local: Test WireGuard syntax
wg-quick strip /etc/wireguard/wgci.conf
```

---

### Problem: VPN Interface Did Not Come Up

**Error Message**: `Failed to bring up VPN interface` or `VPN interface did not come up`

**Root Cause**: 
- Invalid WireGuard configuration
- Port already in use
- Missing kernel module

**Resolution**:
1. Check WireGuard config syntax:
   ```bash
   sudo wg-quick strip /etc/wireguard/wgci.conf
   ```

2. If already running, bring down first:
   ```bash
   sudo wg-quick down wgci
   ```

3. Try bringing up manually:
   ```bash
   sudo wg-quick up wgci
   sudo wg show wgci
   ```

4. Check logs:
   ```bash
   sudo journalctl -u wg-quick@wgci -n 50
   ```

---

### Problem: Target Host Not Routed Through VPN

**Error Message**: `Target may not be routed through VPN: ide.kushnir.cloud`

**Root Cause**:
- Incorrect WireGuard AllowedIPs configuration
- DNS resolution pointing to non-VPN interface
- Network split

**Resolution**:
1. Check routing:
   ```bash
   ip route get ide.kushnir.cloud
   # Output should include: via <vpn-peer> dev wgci
   ```

2. Test DNS through VPN:
   ```bash
   nslookup ide.kushnir.cloud
   # Should resolve to private IP (10.x.x.x)
   ```

3. Check WireGuard config:
   ```bash
   # AllowedIPs must include target network
   # Example: AllowedIPs = 10.0.0.0/8, 192.168.168.0/24
   ```

4. Force reconnect:
   ```bash
   sudo wg-quick down wgci
   sudo wg-quick up wgci
   ```

---

### Problem: Endpoint Scan Timeout

**Error Message**: `Timeout waiting for response` or `ETIMEDOUT`

**Root Cause**:
- Target service not responding
- Network latency high
- Firewall blocking traffic

**Resolution**:
1. Test connectivity manually:
   ```bash
   curl -v https://ide.kushnir.cloud/healthz
   # Should return 200 or 401, not timeout
   ```

2. Check service status:
   ```bash
   # SSH to 192.168.168.31
   docker-compose ps  # All containers should be UP
   ```

3. Increase timeout (if needed):
   ```bash
   # In workflow or local execution:
   export VPN_SCAN_TIMEOUT=120000  # milliseconds
   ```

4. Run with verbose mode:
   ```bash
   # GitHub UI: action = scan-verbose
   # Local: Add debug logging (node --inspect-brk)
   ```

---

### Problem: Scan Passed But GitHub Shows Status As "Blocked"

**Error Message**: `deployment blocked` or check mark not appearing

**Root Cause**: Quality gate not passing due to pre-scan failures

**Resolution**:
1. Check preflight job:
   ```
   GitHub > Actions > Run details > Preflight Validation
   ```

2. Check for config errors:
   - base_url format validation
   - Secret presence check
   - Input parameter validation

3. Re-run entire workflow

---

## Success Criteria

### Scheduled Execution Success
```json
{
  "preflight": "✅ PASS",
  "vpn_scan": "✅ PASS",
  "quality_gates": "✅ PASS",
  "artifacts_uploaded": true,
  "all_endpoints_responding": true
}
```

### Manual Execution Success
- Workflow completes without errors
- Artifact "vpn-endpoint-scan-results" generated
- summary.json shows "status": "pass"
- No blocked deployments from this check

---

## Deployment Gating

### When VPN Scan Blocks Deployment

**Scenario**: Pull request merge is blocked because VPN endpoint scan failed

**Resolution**:

1. **Investigate failure**:
   ```
   GitHub > Run details > Deep VPN Endpoint Scan > Logs
   ```

2. **Identify root cause**:
   - Check preflight section (secrets, config)
   - Check VPN interface setup
   - Check endpoint responses
   - Review debug-errors.log artifact

3. **Fix issue**:
   - If secret: Update GitHub secret and re-run
   - If service: Fix service on 192.168.168.31
   - If network: Verify VPN routing

4. **Re-run workflow**:
   ```
   GitHub > Re-run failed jobs
   ```

5. **Verify pass**:
   ```
   Check "Quality Gates" job for ✅ PASS status
   ```

---

## Monitoring and Alerting

### Check Scan Status
```bash
# Latest run
gh run list --workflow=vpn-enterprise-endpoint-scan-enhanced.yml --limit=1

# Full history
gh run list --workflow=vpn-enterprise-endpoint-scan-enhanced.yml --limit=30
```

### Access Artifacts
```bash
# Download results
gh run download <run-id> -n vpn-endpoint-scan-results -D ./results/

# Analyze
cat results/summary.json | jq .
cat results/debug-errors.log
```

### Slack Notifications (If Configured)
- Failures automatically posted to Slack
- Includes link to GitHub Actions run
- Includes base URL and action type

---

## Performance Baselines

| Metric | Expected | Alert Threshold |
|--------|----------|-----------------|
| Scan Duration | 5-10 min | > 30 min |
| Endpoint Response | < 1s avg | > 5s avg |
| Pass Rate | 100% | < 95% |
| Artifact Size | 1-5 MB | > 50 MB |

---

## Emergency Validation Checklist

Use this when operators need immediate verification:

- [ ] All 9 core services healthy (docker-compose ps)
- [ ] PostgreSQL replication < 1ms lag
- [ ] Redis replication < 1ms lag
- [ ] OAuth2 proxy responding to /oauth2/userinfo
- [ ] Prometheus scraping metrics
- [ ] Grafana dashboards rendering
- [ ] Jaeger receiving traces
- [ ] AlertManager processing alerts

**To validate all**:
```bash
# Run manual-verify action
gh workflow run vpn-enterprise-endpoint-scan-enhanced.yml \
  -f action=manual-verify
```

---

## Related Documentation

- [VPN Configuration Guide](../docs/vpn-setup.md)
- [Incident Response](../docs/incident-response.md)
- [Network Architecture](../ARCHITECTURE.md)
- [Deployment Gates](../docs/deployment-gates.md)

---

**Last Updated**: April 15, 2026  
**Owner**: DevOps / SRE Team  
**Status**: Production Ready
