# Production Failover Test Runbook
## Issue #1175 - Full Stack Validation (Primary ↔ Replica)

**Status**: Ready for execution after secret rotation (#1163) complete  
**Estimated Effort**: 4-6 hours total  
**Risk Level**: MEDIUM (real failover → temporary service interruption)  
**Prerequisite**: Issue #1163 (IDE_SESSION_LB_SECRET rotation)

---

## Overview

This runbook validates that the entire HA setup works correctly before production traffic:
1. Both hosts are healthy and synchronized
2. Failure detection works (Caddy health checks)
3. Traffic reroutes to replica when primary fails
4. OAuth and JWT session continuity through failover
5. Failback to primary completes cleanly

The test uses **DRY_RUN mode by default** (safe simulation). Real failover requires explicit `DRY_RUN=0`.

---

## Prerequisites

- ✅ Issue #1163 (secret rotation) is complete
- ✅ Both hosts SSH-accessible via `ssh akushnir@<host>`
- ✅ GCP CLI (`gcloud`) available for secret verification
- ✅ Docker Compose v2+ on both hosts
- ✅ Cloudflare DNS configured with health checks

**Verification**:
```bash
# Confirm #1163 complete
bash scripts/ops/verify-ide-session-lb-secret.sh
# Exit 0 = ready to proceed
```

---

## Step 1: Pre-Execution Checklist (5 min)

### 1.1 Ensure Connectivity

```bash
# Test SSH to primary
ssh akushnir@192.168.168.31 "echo Primary OK"

# Test SSH to replica
ssh akushnir@192.168.168.42 "echo Replica OK"
```

**Expected Output**: `Primary OK` and `Replica OK`

### 1.2 Backup Current State

```bash
# Snapshot docker state on both hosts
ssh akushnir@192.168.168.31 "docker-compose ps > /tmp/primary-state-$(date +%s).log"
ssh akushnir@192.168.168.42 "docker-compose ps > /tmp/replica-state-$(date +%s).log"

# Verify services running
ssh akushnir@192.168.168.31 "docker-compose ps | grep -c running"  # Should be ~14
ssh akushnir@192.168.168.42 "docker-compose ps | grep -c running"  # Should be ~8
```

### 1.3 Document Current DNS Routing

```bash
# Check current Cloudflare routing
dig +short ide.kushnir.cloud @8.8.8.8
# Note the IP address pointing to primary or replica
```

### 1.4 Get Pre-Test Baseline Metrics

```bash
# Record response times
curl -w "Primary response time: %{time_total}s\n" https://ide.kushnir.cloud/health
curl -w "Replica response time: %{time_total}s\n" https://ide-replica.kushnir.cloud/health
```

---

## Step 2: Dry-Run Test (Safe Simulation - 5 min)

First, validate the test script with **DRY_RUN=1** (default, safe):

```bash
# Run with default DRY_RUN=1 (no real impact)
bash scripts/ops/run-production-failover-test.sh

# Outputs:
# - artifacts/triage/production-failover-report-*.md
# - artifacts/triage/failover-timing-*.json
```

**Outputs to Review**:
- ✓ Preflight checks passed
- ✓ Simulated failover scenario
- ✓ Simulated OAuth/JWT validation
- ✓ Simulated failback scenario
- ✓ Timing report generated

**If dry-run fails**: Review error log, fix connectivity issues, retry dry-run.

---

## Step 3: Real Failover Execution (20-30 min)

⚠️ **WARNING**: This will stop services on primary temporarily. Schedule during maintenance window.

### 3.1 Notify On-Call Team

```bash
# Send Slack notification (if configured)
echo "Starting real production failover test. Expect temporary service interruption."
```

### 3.2 Start Real Failover Test

```bash
# Enable real failover mode
DRY_RUN=0 bash scripts/ops/run-production-failover-test.sh

# Script will:
# 1. Ask for confirmation (type "yes" to proceed)
# 2. Stop IDE (code-server) on primary
# 3. Wait 15 seconds for Caddy to detect failure
# 4. Verify traffic reroutes to replica
# 5. Test OAuth/JWT on replica
# 6. Restart IDE on primary
# 7. Verify failback complete
```

### 3.3 Monitor During Execution

In a separate terminal, monitor real-time metrics:

```bash
# Watch primary services
watch -n 2 'ssh akushnir@192.168.168.31 "docker-compose ps"'

# In another terminal, watch replica services
watch -n 2 'ssh akushnir@192.168.168.42 "docker-compose ps"'

# In another terminal, test continuous connectivity
while true; do
  echo "$(date): Testing IDE endpoint..."
  curl -s https://ide.kushnir.cloud/health | jq .
  sleep 5
done
```

### 3.4 Verify Failover Occurred

When script stops primary IDE:
```bash
# Check from replica host that it's now serving traffic
ssh akushnir@192.168.168.42 "curl -s http://localhost:8080/health | jq ."
```

---

## Step 4: Post-Test Validation (10 min)

### 4.1 Review Generated Report

```bash
# View the failover report
cat artifacts/triage/production-failover-report-*.md

# Example output:
# - Preflight: 45 seconds
# - Failover detection: 8,234 ms (↓ well under 30s threshold)
# - Traffic reroute: 3,912 ms (↓ well under 15s threshold)  
# - Failback recovery: 6,145 ms (↓ well under 30s threshold)
```

### 4.2 Verify Post-Failback State

```bash
# Services should be running on both hosts again
ssh akushnir@192.168.168.31 "docker-compose ps | grep -E 'code-server|caddy' | grep running"
ssh akushnir@192.168.168.42 "docker-compose ps | grep -E 'code-server|caddy' | grep running"

# Verify DNS routing (should point to primary)
dig +short ide.kushnir.cloud @8.8.8.8
```

### 4.3 Check Application Logs for Errors

```bash
# Look for exceptions during failover
ssh akushnir@192.168.168.31 "docker-compose logs --since 30m code-server | grep -i 'error\|exception' || echo 'No errors found'"
ssh akushnir@192.168.168.42 "docker-compose logs --since 30m code-server | grep -i 'error\|exception' || echo 'No errors found'"

# Check session-broker for JWT token handling
ssh akushnir@192.168.168.31 "docker-compose logs --since 30m session-broker | grep -i 'error\|revoked' || echo 'No session errors'"
ssh akushnir@192.168.168.42 "docker-compose logs --since 30m session-broker | grep -i 'error\|revoked' || echo 'No session errors'"
```

### 4.4 Performance Comparison

Compare baseline vs post-test:
```bash
# Response time after failback
curl -w "Response time: %{time_total}s\n" https://ide.kushnir.cloud/health
# Should match or improve from pre-test baseline
```

---

## Success Criteria

All of the following must pass:

| Check | Criterion | Impact |
|-------|-----------|--------|
| **Preflight** | All 4 checks pass | P0 blocker if failed |
| **Failover Detection** | < 30 seconds | Service unavailability window |
| **Traffic Reroute** | < 15 seconds | Session continuity check |
| **Replica Acceptance** | 100% of traffic | HA validation |
| **OAuth on Replica** | Login endpoint responds | User experience |
| **JWT Continuity** | Session broker operational | Token refresh capability |
| **Failback Recovery** | < 30 seconds | Primary restoration |
| **No Error Logs** | Zero errors during test | Data consistency |
| **Response Times** | Within ±10% of baseline | Performance validation |

---

## Troubleshooting

### Issue: SSH Connectivity Failed

```bash
# Verify credentials
ssh -v akushnir@192.168.168.31 "echo test"

# Check if host is accessible
ping -c 3 192.168.168.31

# Verify public key in authorized_keys
ssh akushnir@192.168.168.31 "cat ~/.ssh/authorized_keys | wc -l"
```

### Issue: Failover Detection Timeout

```bash
# Check Caddy health check configuration
ssh akushnir@192.168.168.31 "grep -A 5 'health' Caddyfile | head -20"

# Verify Caddy is running
ssh akushnir@192.168.168.31 "docker-compose ps caddy"

# Check Caddy logs for health check errors
ssh akushnir@192.168.168.31 "docker-compose logs --tail 50 caddy | grep health"
```

### Issue: Traffic Not Rerouting to Replica

```bash
# Check replica is configured in upstream
ssh akushnir@192.168.168.31 "grep -i replica Caddyfile"

# Verify replica is accessible from primary
ssh akushnir@192.168.168.31 "curl -s http://192.168.168.42:8080/health | jq ."

# Check load balancer state
ssh akushnir@192.168.168.31 "docker-compose logs --tail 20 caddy | grep -i 'failed\|unhealthy'"
```

### Issue: OAuth Endpoint Not Responding on Replica

```bash
# Check oauth2-proxy is running on replica
ssh akushnir@192.168.168.42 "docker-compose ps oauth2-proxy"

# Verify OAuth configuration
ssh akushnir@192.168.168.42 "grep -i oauth Caddyfile"

# Test OAuth endpoint directly
curl -s https://192.168.168.42/oauth2/start -k 2>&1 | head -20
```

### Issue: Failback Timeout

```bash
# Check primary is online
ssh akushnir@192.168.168.31 "echo OK"

# Restart primary services manually if needed
ssh akushnir@192.168.168.31 "docker-compose restart"

# Verify primary can reach replica
ssh akushnir@192.168.168.31 "curl -s http://192.168.168.42:8080/health | jq ."
```

---

## Rollback Procedure

If test reveals critical issues:

### Quick Recovery (< 2 min)

```bash
# Restart all services on primary
ssh akushnir@192.168.168.31 "docker-compose restart"

# Force DNS to primary only (bypass health checks temporarily)
# Contact Cloudflare admin to disable replica in health check
```

### Full State Restore

```bash
# Use snapshots from pre-test backups
ssh akushnir@192.168.168.31 "docker-compose down && docker-compose up -d"
ssh akushnir@192.168.168.42 "docker-compose down && docker-compose up -d"

# Verify both hosts healthy
bash scripts/ops/session-broker-ha-health.sh
```

---

## Test Scenarios

### Scenario 1: Graceful Primary Shutdown

**What's tested**:
- Service graceful shutdown (no dropped connections)
- Replica accepts in-flight requests
- Session state preserved

**Expected Result**: ✅ All requests complete, sessions preserved

### Scenario 2: Primary Network Partition

**What's tested**:
- Replica takes over when primary is unreachable
- No split-brain (two primaries)
- Failback merges state correctly

**Expected Result**: ✅ Clean handoff, no data duplication

### Scenario 3: OAuth During Failover

**What's tested**:
- New logins work on replica mid-failover
- Existing sessions remain valid
- JWT token refresh uninterrupted

**Expected Result**: ✅ OAuth accessible, no reauthentication required

### Scenario 4: Rapid Primary Restart

**What's tested**:
- Primary rejoins cluster immediately
- No stale data conflicts
- Traffic smoothly returns to primary

**Expected Result**: ✅ Primary becomes active within 30s, no errors

---

## Metrics & Success Indicators

Generated report includes timing data:

```json
{
  "test_start": "2026-05-12T14:30:00Z",
  "test_mode": "real",
  "primary_host": "192.168.168.31",
  "replica_host": "192.168.168.42",
  "timing_records": {
    "preflight_primary_services_check": 2345,
    "preflight_replica_services_check": 1890,
    "failover_detection_time": 8234,
    "failover_traffic_reroute_time": 3912,
    "failback_recovery_detection_time": 6145,
    "failover_total": 18291,
    "failback_total": 6145
  }
}
```

**Key Metrics to Monitor**:
- Failover Detection Time: < 30s (Caddy health check interval)
- Traffic Reroute Time: < 15s (session reestablishment)
- Failback Recovery Time: < 30s (primary rejoin)
- Error Rate: 0% (no 5xx errors during transition)
- Session Preservation: 100% (no forced reauthentication)

---

## After Test Completion

### 1. Document Results

```bash
# Commit test report to repo
git add artifacts/triage/production-failover-report-*.md artifacts/triage/failover-timing-*.json
git commit -m "docs: Add production failover test results (#1175)"
git push origin main
```

### 2. Update Issue #1175

Post comment with:
- Test execution date/time
- DRY_RUN vs REAL mode used
- Timing data (detection, reroute, recovery)
- Any issues discovered
- Remediation actions taken

### 3. Verify Production Readiness

```bash
# Run final pre-deployment checks
bash scripts/ci/validate-dedup-registry.sh
bash scripts/ci/check-no-hardcoded-credentials.sh

# Confirm no regressions
pnpm -r typecheck && pnpm test:run
```

### 4. Notify Production Team

Share timing metrics and confirm HA validation complete before production canary.

---

## References

- [Caddy Health Checks](https://caddyserver.com/docs/caddyfile/options#health)
- [Docker Compose Service Recovery](https://docs.docker.com/compose/compose-file/05-services/)
- [AWS Failover Best Practices](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/)
- Issue #1163: IDE_SESSION_LB_SECRET Rotation
- [DNS Health Checks - Cloudflare](https://developers.cloudflare.com/load-balancing/concepts/health-checks/)

---

## Support

If test fails or you have questions:
1. Check troubleshooting section above
2. Review logs: `docker-compose logs --since 1h <service>`
3. Contact SRE team
4. Open GitHub issue with test report and logs attached

---

**Last Updated**: April 22, 2026  
**Maintained By**: SRE Team  
**Status**: Ready for Production Deployment Phase
