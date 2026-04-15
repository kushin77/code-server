# VPN-OPS-011: Manual VPN Endpoint Scan Runbook

**Purpose**: Execute VPN endpoint scan manually for incident response or operational verification  
**Scope**: On-premises infrastructure (192.168.168.31 + replica)  
**Audience**: Platform engineers, SREs, on-call operators  
**Last Updated**: April 15, 2026

---

## QUICK START (5 Minutes)

### Prerequisites
```bash
# Verify SSH access to primary host
ssh akushnir@192.168.168.31 "echo OK"

# Verify WireGuard config is loaded
ssh akushnir@192.168.168.31 "ls -la ~/.wireguard/config.conf"
```

### Execute Scan
```bash
# SSH to primary host
ssh akushnir@192.168.168.31

# Run scan with defaults
cd code-server-enterprise
bash scripts/vpn-enterprise-endpoint-scan.sh

# Or with custom base URL
VPN_SCAN_BASE_URL=https://custom.domain bash scripts/vpn-enterprise-endpoint-scan.sh
```

### Verify Results
```bash
# Check latest scan results
ls -lrt test-results/vpn-endpoint-scan/ | tail -5

# View summary
cat test-results/vpn-endpoint-scan/*/summary.json | jq .

# If scan passed
tail test-results/vpn-endpoint-scan/*/summary.json
```

---

## STEP-BY-STEP EXECUTION

### Step 1: Verify Prerequisites

```bash
# SSH to production host
ssh akushnir@192.168.168.31

# Verify git repo exists and is clean
cd code-server-enterprise
git status
git log --oneline -1

# Verify WireGuard interface exists and is up
ip link show wg0
# Expected output: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420

# Verify Node.js and npm are available
node --version   # Expected: v20.x or later
npm --version    # Expected: 9.x or later

# Verify scanner dependencies directory exists
test -d tests/vpn-enterprise-endpoint-scan && echo "✅ Scanner ready"
```

**Troubleshooting Step 1**:
- If git repo missing: `git clone https://github.com/kushin77/code-server code-server-enterprise`
- If WireGuard down: `sudo wg-quick up wg0`
- If Node.js missing: `curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt-get install -y nodejs`

---

### Step 2: Validate Secrets & Configuration

```bash
# Check WireGuard config exists
if [[ -f ~/.wireguard/config.conf ]]; then
  echo "✅ WireGuard config found"
else
  echo "❌ WireGuard config missing: ~/.wireguard/config.conf"
  exit 1
fi

# Test WireGuard connectivity
ping -c 1 192.168.168.31  # Should resolve on VPN
echo $?  # Should be 0

# Verify scan base URL is reachable
curl -Is https://ide.kushnir.cloud/healthz 2>&1 | head -1
# Expected: HTTP/1.1 200 OK or HTTP/2 200
```

**Troubleshooting Step 2**:
- If WireGuard config missing: Copy from GitHub Secrets or from backup
  ```bash
  # Retrieve from CI secret (requires GitHub CLI)
  gh secret view WIREGUARD_CONFIG --repo kushin77/code-server
  ```
- If URL unreachable: Verify VPN is up (`wg show wg0`), check firewall rules

---

### Step 3: Install Scanner Dependencies (if needed)

```bash
cd code-server-enterprise/tests/vpn-enterprise-endpoint-scan

# Install npm packages
npm install --no-audit --no-fund

# Install Playwright browser (first run only)
npx playwright install --with-deps chromium

# Verify installation
npm list   # Should show dependencies without errors
```

**Troubleshooting Step 3**:
- If npm install fails: `npm cache clean --force && npm install`
- If Playwright fails: `npx playwright install-deps && npx playwright install chromium`

---

### Step 4: Execute Scan

```bash
cd /root/code-server-enterprise

# Standard execution (uses defaults)
bash scripts/vpn-enterprise-endpoint-scan.sh

# Or with environment overrides
export VPN_SCAN_OUTPUT_ROOT=/tmp/vpn-scans  # Custom output directory
export VPN_INTERFACE=wg0                     # Explicit interface
export VPN_SCAN_BASE_URL=https://ide.kushnir.cloud  # Custom base URL
bash scripts/vpn-enterprise-endpoint-scan.sh
```

**Expected Output**:
```
[INFO] VPN Enterprise Endpoint Scan
[INFO] Output directory: /root/code-server-enterprise/test-results/vpn-endpoint-scan/20260415T150430Z
[INFO] VPN interface required: wg0
[✅] vpn-enterprise-endpoint-scan.sh: OK
[INFO] Running deep endpoint scan (Playwright + Puppeteer)...
[INFO] Scan status: pass
[✅] VPN enterprise endpoint scan passed
```

**Troubleshooting Step 4**:
- If script fails: Check `test-results/vpn-endpoint-scan/*/debug-errors.log`
- If VPN interface error: Run `sudo wg-quick up wg0`
- If Node.js error: Verify npm dependencies: `cd tests/vpn-enterprise-endpoint-scan && npm list`

---

### Step 5: Verify Scan Artifacts

```bash
# List scan directories (most recent last)
ls -lrt test-results/vpn-endpoint-scan/ | tail -5

# Set latest scan directory
LATEST_SCAN=$(ls -dt test-results/vpn-endpoint-scan/*/ | head -1)
echo "Latest scan: $LATEST_SCAN"

# Verify required artifacts exist
test -f "$LATEST_SCAN/summary.json" && echo "✅ summary.json"
test -f "$LATEST_SCAN/debug-errors.log" && echo "✅ debug-errors.log"
test -d "$LATEST_SCAN/traces" && echo "✅ traces/"
test -d "$LATEST_SCAN/screenshots" && echo "✅ screenshots/"

# View summary
cat "$LATEST_SCAN/summary.json" | jq .

# Check for failures
cat "$LATEST_SCAN/summary.json" | jq '.failures // empty'
```

---

## TROUBLESHOOTING MATRIX

| Symptom | Cause | Resolution |
|---------|-------|-----------|
| **`WIREGUARD_CONFIG: command not found`** | WireGuard interface down | `sudo wg-quick up wg0 && wg show` |
| **`Can't reach https://ide.kushnir.cloud`** | VPN tunnel broken | Check VPN status: `sudo wg show wg0` |
| **`Playwright browser not found`** | Browser not installed | `npx playwright install --with-deps chromium` |
| **`npm ERR!`** | Dependency issue | `npm cache clean --force && npm install` |
| **`timeout waiting for selector`** | Service unreachable | Verify service is up: `curl https://ide.kushnir.cloud/healthz` |
| **`No such file: summary.json`** | Scan didn't complete | Check `debug-errors.log` for details |
| **Scan hangs indefinitely** | Network/firewall issue | Restart VPN: `sudo wg-quick down wg0 && sudo wg-quick up wg0` |

---

## INCIDENT RESPONSE PROCEDURES

### Procedure 1: Scan Execution Failure

**Symptoms**: Scan script exits with error, no summary.json

**Steps**:
1. Check error log: `cat test-results/vpn-endpoint-scan/*/debug-errors.log | tail -50`
2. Verify VPN is up: `sudo wg show wg0`
3. Verify service is reachable: `curl -v https://ide.kushnir.cloud/healthz`
4. Re-run scan with verbose output: `bash -x scripts/vpn-enterprise-endpoint-scan.sh 2>&1 | tee /tmp/vpn-scan-verbose.log`
5. If still failing, check service health on primary:
   ```bash
   docker ps -a
   docker logs code-server
   docker logs oauth2-proxy
   ```
6. If services unhealthy, trigger Phase 7c failover (see Phase 7c runbook)

---

### Procedure 2: Specific Endpoint Failing

**Symptoms**: One or more endpoints fail checks in summary.json

**Steps**:
1. Identify failing endpoint: `cat test-results/vpn-endpoint-scan/*/summary.json | jq '.failures[]'`
2. Check corresponding screenshot: `ls test-results/vpn-endpoint-scan/*/screenshots/ | grep endpoint-name`
3. Check trace logs: `ls test-results/vpn-endpoint-scan/*/traces/`
4. Manually test endpoint:
   ```bash
   curl -v https://ide.kushnir.cloud/failing-endpoint
   ```
5. If manual test passes, re-run scan (may be transient)
6. If manual test fails:
   - Check application logs: `docker logs code-server`
   - Verify DNS resolution: `nslookup ide.kushnir.cloud`
   - Check firewall rules: `sudo iptables -L -n`

---

### Procedure 3: VPN Connectivity Loss During Scan

**Symptoms**: Scan hangs, timeouts, connection resets

**Steps**:
1. Kill running scan: `pkill -f vpn-enterprise-endpoint-scan`
2. Check VPN status: `sudo wg show wg0`
3. If interface down:
   ```bash
   sudo wg-quick down wg0
   sleep 2
   sudo wg-quick up wg0
   sudo wg show wg0  # Verify restoration
   ```
4. Wait 10 seconds for tunnel to stabilize
5. Re-run scan: `bash scripts/vpn-enterprise-endpoint-scan.sh`

---

## ARTIFACT RETENTION POLICY

### Directory Structure
```
test-results/
  vpn-endpoint-scan/
    20260415T150430Z/
      summary.json              # Scan results, keep 30 days
      debug-errors.log          # Error details, keep 30 days
      traces/                   # Playwright traces, keep 14 days
      screenshots/              # Failed screenshots, keep 30 days
      metadata.json             # Scan metadata, keep 90 days
```

### Cleanup Strategy

**Automatic (CI/CD)**:
- Keep last 30 scan results
- Delete traces older than 14 days
- Archive full results to NAS after 30 days
- Delete local results older than 90 days

**Manual Cleanup**:
```bash
# Delete old scan results (older than 30 days)
find test-results/vpn-endpoint-scan -type d -mtime +30 -exec rm -rf {} \;

# Archive results to NAS for long-term retention
rsync -av test-results/vpn-endpoint-scan/*.tar.gz nas:/backups/vpn-scans/
```

### Naming Convention

Scan directories follow ISO 8601 timestamp format:
```
YYYYMMDDTHHMMSSZ

Example: 20260415T150430Z
  - Year: 2026
  - Month: 04
  - Day: 15
  - Time: 15:04:30 UTC
```

---

## GOVERNANCE & DEPLOYMENT GATING

### When VPN Scan Must Pass

VPN scan results **BLOCK** deployment in these scenarios:

1. **Main branch deployment**: All critical endpoints must be reachable
2. **Networking changes**: After firewall/proxy/DNS modifications
3. **Service updates**: Before deploying code changes to production
4. **Failover testing**: Before declaring failover complete
5. **Post-incident**: Before resuming normal operations

### When VPN Scan Results Are Advisory

VPN scan results are **INFORMATIONAL** for:

1. Development/staging environments
2. Local testing (non-production)
3. CI dry-runs (workflow_dispatch with test flag)
4. Post-deployment health checks (non-blocking)

### Deployment Gate Policy

```yaml
# .github/workflows/ci-validate.yml
deployment_gate:
  - vpn_scan_must_pass: true
    affects: production-main-branch-merge
    blocking: true
    
  - vpn_scan_optional: false
    affects: feature-branch-pr
    blocking: false
```

---

## METRICS & MONITORING

### Key Metrics

Track these metrics from scan results:

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| **Scan success rate** | 100% | <95% = alert |
| **Endpoint response time** | <1s | >5s = alert |
| **Total scan duration** | <10m | >15m = alert |
| **Coverage (endpoints)** | >95% | <90% = alert |

### Integration with Observability

Results published to:
- **GitHub Artifacts**: Stored for 90 days
- **Prometheus**: Metrics exposed via `/metrics`
- **Grafana**: Dashboard: "VPN Scan Health"
- **AlertManager**: Alert: "VPN Scan Failure"

---

## NEXT STEPS AFTER SCAN

### If Scan PASSES ✅
1. Document any findings in issue/PR
2. Proceed with deployment/change as planned
3. No further action needed

### If Scan FAILS ❌
1. Review `debug-errors.log` and screenshots
2. Identify root cause using troubleshooting matrix
3. Remediate issue (fix service, check VPN, etc.)
4. Re-run scan to verify fix
5. Document incident in post-mortem

### If Scan Is INCONCLUSIVE
1. Re-run scan (may be transient network issue)
2. If persists, check both engines (Playwright + Puppeteer) individually
3. Review VPN connectivity: `sudo wg show wg0`
4. Contact platform engineering team

---

## RELATED DOCUMENTATION

- **[VPN Configuration](../VPN-CONFIGURATION.md)** - WireGuard setup
- **[Incident Response](../INCIDENT-RESPONSE.md)** - General IR procedures
- **[Phase 7c: Disaster Recovery](../PHASE-7C-DISASTER-RECOVERY-PLAN.md)** - Failover procedures
- **[CI/CD Workflows](../CI-CD-INTEGRATION.md)** - Automation integration

---

**Runbook Owner**: Platform Engineering  
**Last Updated**: April 15, 2026  
**Status**: Production (Issue #325 VPN-OPS-011)
