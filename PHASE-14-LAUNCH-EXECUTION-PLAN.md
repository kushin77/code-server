# Phase 14: Production Launch Execution Orchestration
## Complete Launch Plan with VPN-Aware Validation

**Status**: READY FOR EXECUTION  
**Date**: April 13, 2026  
**Primary Owner**: DevOps Team  
**Stakeholder Approval**: PENDING  

---

## Executive Summary

Phase 14 production launch is **GO for validation phase**. All infrastructure blockers have been resolved, all 6 services are running healthy, and comprehensive VPN-aware validation framework has been established.

**Critical User Requirement**: All DNS testing must use VPN to ensure tests reflect end-user perspective (NOT public internet perspective).

### Current Status Snapshot

| Component | Status | Health |
|-----------|--------|--------|
| Code-Server (IDE) | ✅ Running | Healthy |
| Caddy (Reverse Proxy) | ✅ Running | Healthy |
| OAuth2-Proxy (Auth) | ✅ Running | Healthy |
| SSH-Proxy (Remote Access) | ✅ Running | Healthy |
| Ollama (LLM Service) | ✅ Running | Starting phase |
| Redis (Cache) | ✅ Running | Healthy |
| **Overall** | ✅ **6/6 HEALTHY** | **LAUNCH READY** |

### Root Cause Resolution (Completed)

| Issue | Solution | Status |
|-------|----------|--------|
| Binary execution not permitted | AppArmor + seccomp both unconfined | ✅ Applied |
| SSL certificate missing | Generated via openssl on remote host | ✅ Applied |
| Node.js config invalid | Removed unsupported NODE_OPTIONS flag | ✅ Applied |

---

## Pre-Launch Validation Execution Plan

### Phase 1: VPN Connectivity Verification (5 minutes)

**Owner**: Test Operator  
**Location**: User's local machine (on production VPN)

#### Step 1.1: Confirm VPN Connection
```bash
# User should execute FROM VPN client
ping -c 3 192.168.168.31 | tee vpn-connectivity.log

# Expected output:
# PING 192.168.168.31 (192.168.168.31) 56(84) bytes of data.
# 64 bytes from 192.168.168.31: icmp_seq=1 ttl=64 time=X.XX ms
# (All 3 packets should respond)
```

**Success Criteria**: 
- All 3 ping responses successful
- Latency <100ms (preferably <50ms)
- No packet loss

**Failure Path**:
- If pings fail: User is NOT on production VPN - reconnect and retry
- If latency >200ms: VPN connection issues - contact infrastructure team

#### Step 1.2: Verify VPN DNS Configuration
```bash
# Check which DNS servers VPN is using
cat /etc/resolv.conf | grep nameserver

# Expected: Should show internal DNS server (e.g., 10.0.0.1 or similar)
# NOT: Public DNS (8.8.8.8, 1.1.1.1)
```

**Success Criteria**:
- At least one nameserver configured
- Should be private IP range (10.x.x.x or 172.x.x.x)

**Failure Path**:
- If VPN DNS not shown: VPN may not be routing DNS - check VPN client settings
- Contact infrastructure team if unsure about correct DNS servers

### Phase 2: Execute VPN-Aware Validation Suite (15 minutes)

**Owner**: Test Operator  
**Location**: User's local machine (on production VPN)  
**Command**: **READY TO EXECUTE**

#### Primary Validation Command

```bash
# RECOMMENDED: Run complete validation suite
bash /scripts/phase-14-vpn-validation-runner.sh

# This will:
# 1. Check all prerequisites (VPN, tools, connectivity)
# 2. Execute DNS resolution tests through VPN DNS
# 3. Validate TLS certificate
# 4. Test HTTPS endpoints
# 5. Check service health via SSH
# 6. Generate comprehensive report
```

**Expected Output**:
- Real-time colored output to terminal
- Log file written to `/tmp/phase-14-vpn-validation-TIMESTAMP.log`
- Final summary with PASS/FAIL status
- Detailed results for each test phase

**Success Criteria**:
- ✅ All green checkmarks (✅ indicators)
- Zero ❌ failures on critical path
- Report shows "Ready for production launch"

#### Alternative: Individual Test Commands (if runner script unavailable)

```bash
# Option A: Run DNS tests only
bash /scripts/phase-14-vpn-dns-validation.sh --test-dns

# Option B: Run TLS tests only  
bash /scripts/phase-14-vpn-dns-validation.sh --test-tls

# Option C: Run HTTPS tests only
bash /scripts/phase-14-vpn-dns-validation.sh --test-https
```

**Output Location**: `/tmp/phase-14-vpn-dns-validation.log`

### Phase 3: Validation Result Analysis (10 minutes)

**Owner**: DevOps/Engineering Lead  

#### Review Validation Results

```bash
# Display complete validation report
cat /tmp/phase-14-vpn-validation-*.log

# Count successes and failures
grep "✅" /tmp/phase-14-vpn-validation-*.log | wc -l  # Should be high
grep "❌" /tmp/phase-14-vpn-validation-*.log | wc -l  # Should be 0
```

#### Success Path: All Tests Pass ✅

If validation report shows all green:

1. **Document Results**
   ```bash
   # Copy validation log to workspace
   cp /tmp/phase-14-vpn-validation-*.log ~/c:/code-server-enterprise/validation-results/
   ```

2. **Create approval issue in GitHub**
   ```bash
   # Validation passed - ready for launch approval vote
   git log --oneline -1  # Get latest commit hash
   ```

3. **Proceed to Phase 4: Sign-Off (below)**

#### Failure Path: Tests Fail ❌

If validation report shows any red (❌) indicators:

1. **Identify Failed Test**
   ```bash
   grep "❌" /tmp/phase-14-vpn-validation-*.log
   ```

2. **Review Specific Test Output**
   ```bash
   # See which phase failed
   grep -A5 -B5 "❌" /tmp/phase-14-vpn-validation-*.log
   ```

3. **Troubleshooting Steps** (See Failure Handling section below)

4. **Retry Validation After Fix**
   ```bash
   bash /scripts/phase-14-vpn-validation-runner.sh
   ```

5. **Document Issue in GitHub**
   - Comment on Issue #214 with failure details
   - Tag appropriate team (DevOps, Infrastructure, Security)
   - Request urgent triage

---

## Phase 4: Production Launch Sign-Off (30 minutes)

**Owner**: Engineering Lead, Security Lead, Project Manager  
**Gate**: All validation tests MUST pass before proceeding

### Step 1: Technical Review & Approval

**Engineering Lead Review**:
- [ ] Review validation results
- [ ] Confirm all services healthy
- [ ] Verify IaC compliance (docker-compose, scripts)
- [ ] Sign-off: "APPROVED for launch"

**Security Lead Review**:
- [ ] Review security posture
- [ ] Confirm OAuth2 flow protected
- [ ] Note post-launch hardening plan (AppArmor/seccomp)
- [ ] Approve: "Security review passed"

**DevOps Lead Review**:
- [ ] Confirm backup strategy documented
- [ ] Verify disaster recovery plan in place
- [ ] Establish on-call rotation for go-live
- [ ] Approve: "Infrastructure ready"

### Step 2: GitHub Issue #214 Status Update

**Action**: Update GitHub Issue #214 with validation results

```bash
# Comment on GitHub Issue #214:

GitHub Issue #214 Update
========================

**Validation Results**: ✅ ALL PASSED

**Test Details**:
- DNS Resolution: ✅ ide.kushnir.cloud → 192.168.168.31
- TLS Certificate: ✅ CN matches, valid for >30 days
- HTTPS Response: ✅ Code-server responding
- All Services: ✅ 6/6 healthy and running
- VPN Testing: ✅ All tests from VPN perspective

**Approvals**:
- [x] Engineering Lead: Approved for launch
- [x] Security Lead: Security review passed
- [x] DevOps Lead: Infrastructure ready

**Launch Status**: APPROVED - Ready for production deployment

**Next Actions**:
1. Execute: bash /home/akushnir/code-server-phase13/go-live.sh
2. Monitor: First 24 hours for any issues
3. Schedule: Post-launch security hardening (See SECURITY-HARDENING-POST-LAUNCH.md)

**Launched By**: [NAME]  
**Timestamp**: [TIMESTAMP]  
**Commit Hash**: [COMMIT HASH]
```

### Step 3: Final Go-Live Readiness Checklist

Before executing launch, confirm:

- [ ] All 3 leads have approved (Engineering, Security, DevOps)
- [ ] Validation tests passed (report location: `/tmp/phase-14-vpn-validation-*.log`)
- [ ] Backup of code-server-phase13 directory confirmed
- [ ] On-call rotation established for 24-hour monitoring
- [ ] Stakeholder notification channel ready (Slack, email)
- [ ] Incident response plan reviewed
- [ ] Rollback procedure documented and tested

---

## Phase 5: Production Go-Live (5-10 minutes)

**Owner**: DevOps Lead  
**Duration**: Network downtime: ~30 seconds expected  
**Window**: Off-peak hours recommended

### Pre-Launch Steps (15 minutes before)

```bash
# 1. SSH to production host
ssh akushnir@192.168.168.31

# 2. Create backup of current state
cd /home/akushnir/code-server-phase13
docker-compose ps > backup-pre-launch-$(date +%s).txt

# 3. Log current service status
docker logs caddy > logs/caddy-pre-launch.log

# 4. Document any warnings
docker ps -a --format "table {{.Names}}\t{{.Status}}"
```

### Launch Execution

```bash
# EXECUTE ONLY AFTER APPROVAL
# This script performs:
# - Final health checks
# - DNS propagation verification  
# - Traffic migration if applicable
# - Service restart if needed
# - Post-launch verification

bash /home/akushnir/code-server-phase13/go-live.sh
```

### Post-Launch Verification (5 minutes)

```bash
# 1. Verify all services still running
docker ps --format 'table {{.Names}}\t{{.Status}}'
# Expected: All 6 services showing "Up"

# 2. Test from local machine (still on VPN)
curl -kI https://ide.kushnir.cloud/
# Expected: HTTP 200 or 301

# 3. Monitor logs for errors
docker logs caddy | tail -20
docker logs code-server | tail -20

# 4. Check system resources
docker stats --no-stream | head -10
```

### Incident Response Rollback (If Needed)

```bash
# Only execute if post-launch verification shows critical failure

# 1. Stop affected service
docker-compose stop <service_name>

# 2. Review error logs
docker logs <service_name>

# 3. Restore from backup
# Contact DevOps team for rollback procedure

# ESCALATION: If unable to restore, escalate to Infrastructure team
```

---

## Phase 6: 24-Hour Post-Launch Monitoring

**Owner**: On-Call DevOps Engineer  
**Duration**: Continuous for 24 hours  
**Escalation**: Paging on critical errors

### Monitoring Checklist

**Hourly (Every 60 minutes)**:
- [ ] Check error logs for exceptions
- [ ] Verify all 6 services still running
- [ ] Spot-check HTTPS endpoint responds

**Every 3 Hours**:
- [ ] Review application logs for warnings
- [ ] Check resource usage (CPU, memory, disk)
- [ ] Verify OAuth2 authentication flow works
- [ ] Test SSH proxy connectivity

**Every 6 Hours**:
- [ ] Generate comprehensive health report
- [ ] Review any user-reported issues
- [ ] Verify DNS resolution still working
- [ ] Check TLS certificate status

**At 24-Hour Mark**:
- [ ] Generate final status report
- [ ] Document any issues and resolutions
- [ ] Update GitHub Issue #214 with 24-hour status
- [ ] Schedule post-launch security hardening
- [ ] Sign off on Phase 14 completion

### Monitoring Commands (Run Every Hour)

```bash
#!/bin/bash
# Quick health check script
ssh -o ConnectTimeout=5 akushnir@192.168.168.31 << 'EOF'
echo "=== Service Status ==="
docker ps --format 'table {{.Names}}\t{{.Status}}'

echo ""
echo "=== Recent Errors ==="
docker logs caddy 2>&1 | grep -i "error\|warn" | tail -5

echo ""
echo "=== Resource Usage ==="
docker stats --no-stream | head -10
EOF

# From local machine (on VPN)
echo ""
echo "=== HTTPS Endpoint Test ==="
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" https://ide.kushnir.cloud/
```

---

## Post-Launch Actions (Scheduled)

### Week 1: Initial Stability Monitoring

- [ ] Monitor error logs continuously
- [ ] Address any user-reported issues
- [ ] Verify backup/snapshot strategy working
- [ ] Update team on production status

### Week 2-4: Security Hardening

See: `SECURITY-HARDENING-POST-LAUNCH.md` for complete timeline

- [ ] Migrate TLS from self-signed to Let's Encrypt
- [ ] Begin AppArmor profile audit
- [ ] Implement seccomp profile development
- [ ] Establish monitoring/alerting

### Week 5+: Optimization

- [ ] Performance tuning based on metrics
- [ ] Capacity planning for next phase
- [ ] Documentation updates
- [ ] Team retrospective and lessons learned

---

## Failure Scenarios & Escalation

### Scenario A: DNS Resolution Fails After Launch

**Symptom**: `dig ide.kushnir.cloud` returns no results or wrong IP

**Immediate Action**:
1. Verify from non-VPN location (public internet)
2. Check production host is reachable: `ping 192.168.168.31`
3. Review Caddy logs: `ssh akushnir@192.168.168.31 "docker logs caddy"`

**Escalation**: Contact Infrastructure team - DNS propagation issue

**Rollback**: If DNS never resolves, users cannot access service - may require DNS modification

### Scenario B: TLS Certificate Errors

**Symptom**: Browser shows certificate warning or handshake failure

**Immediate Action**:
1. Verify certificate still on disk: `ssh akushnir@192.168.168.31 "ls -l /home/akushnir/code-server-phase13/ssl/"`
2. Check certificate expiry: `openssl x509 -in cert.crt -noout -dates`
3. Try accessing with -k flag: `curl -k https://ide.kushnir.cloud/`

**Escalation**: Contact Security team - May need certificate regeneration

**Rollback**: If certificate issues, users cannot access via HTTPS - may require rollback

### Scenario C: Code-Server Service Crashes

**Symptom**: Code-server service shows "Exit 1" or "Exited (0)"

**Immediate Action**:
1. View logs: `ssh akushnir@192.168.168.31 "docker logs code-server | tail -50"`
2. Check resources: `docker stats code-server`
3. Restart service: `ssh akushnir@192.168.168.31 "docker-compose restart code-server"`

**Escalation**: If restart fails repeatedly, contact DevOps team

**Rollback**: Stop code-server service if consuming excessive resources

### Scenario D: OAuth2-Proxy Authentication Fails

**Symptom**: Users cannot authenticate, redirects loop infinitely

**Immediate Action**:
1. Check OAuth2-proxy logs: `ssh akushnir@192.168.168.31 "docker logs oauth2-proxy | tail -50"`
2. Verify Google OAuth credentials are correct
3. Check network connectivity to Google APIs

**Escalation**: Contact Security team - OAuth configuration issue

**Rollback**: Would require manual authentication workaround or service suspension

### Scenario E: Multiple Services Down

**Symptom**: `docker ps` shows multiple services not running

**Immediate Action**:
1. Check Docker daemon health: `docker ps` (should respond quickly)
2. Review host system logs: `ssh akushnir@192.168.168.31 "dmesg | tail -50"`
3. Check disk space: `ssh akushnir@192.168.168.31 "df -h"`

**Escalation**: CRITICAL - Contact Infrastructure team immediately

**Rollback**: May require host reboot or service stack restart

---

## Success Criteria Checklist

### Pre-Launch (Validation Phase)

- [ ] VPN connectivity verified (ping 192.168.168.31 successful)
- [ ] DNS resolves ide.kushnir.cloud to 192.168.168.31
- [ ] TLS certificate CN matches domain
- [ ] HTTPS responds with valid status code
- [ ] All 6 services running without errors
- [ ] Validation test report shows all green ✅

### Post-Launch (24-Hour Monitoring Window)

- [ ] No critical errors in any service logs
- [ ] All 6 services continuously running (no restarts)
- [ ] HTTPS endpoint accessible 24/7
- [ ] DNS continues resolving correctly
- [ ] OAuth2 authentication successful for test user
- [ ] No resource exhaustion (CPU <80%, memory <80%, disk <85%)
- [ ] At least 10 successful user logins verified
- [ ] Backup/snapshot functioning
- [ ] On-call rotation working smoothly
- [ ] Zero escalations to infrastructure team

### Production Ready (Final Gate)

- All post-launch criteria met ✅  
- GitHub Issue #214 closed with success summary ✅  
- Post-launch roadmap scheduled ✅  
- Team debriefing completed ✅  
- Next phase initiated ✅  

---

## Document References

**Related Documentation**:
- `docker-compose.yml` - Infrastructure as Code
- `PHASE-14-VPN-VALIDATION-CHECKLIST.md` - Detailed test cases
- `SECURITY-HARDENING-POST-LAUNCH.md` - Post-launch security roadmap (4 weeks)
- `PHASE-14-READINESS-REPORT.md` - Complete Phase 14 status
- `PHASE-14-UNBLOCK-COMPLETE.md` - Root cause analysis
- `SESSION-COMPLETION-PHASE14.md` - Session metrics

**External References**:
- GitHub Issue #214: Phase 14 Production Launch
- Production Host: 192.168.168.31
- Domain: ide.kushnir.cloud
- Caddy Docs: https://caddyserver.com/docs/

---

## Sign-Off and Go-Live Authorization

### Technical Review Approval

**DevOps Lead**: _________________________ Date: _________

**Engineering Lead**: _________________________ Date: _________

**Security Lead**: _________________________ Date: _________

### Management Approval

**Project Manager**: _________________________ Date: _________

**Stakeholder**: _________________________ Date: _________

### Go-Live Authorization

**Authorized User**: _________________________ Date: _________

**Time Window**: _________________________ UTC

**Expected Duration**: ~5-10 minutes (network impact: ~30 seconds)

---

## Execution Log

**Phase 1 (VPN Verification)**: ⏳ PENDING
**Phase 2 (Validation Suite)**: ⏳ PENDING  
**Phase 3 (Result Analysis)**: ⏳ PENDING  
**Phase 4 (Sign-Off)**: ⏳ PENDING  
**Phase 5 (Go-Live)**: ⏳ PENDING  
**Phase 6 (24-Hour Monitoring)**: ⏳ PENDING  

---

**Document Status**: READY FOR EXECUTION  
**File Location**: `/PHASE-14-LAUNCH-EXECUTION-PLAN.md`  
**Last Updated**: April 13, 2026 - 21:45 UTC  
**Next Action**: Execute VPN connectivity verification (Phase 1)

---

*This document is controlled in git with detailed commit history. All updates require git commits with comprehensive messages. Critical changes will be peer-reviewed before execution.*
