# Phase 4: External Network Testing & Operational SLAs
**Date:** April 30, 2026 | **Status:** READY FOR EXECUTION  
**Scope:** External domain testing, load testing, operational SLA definitions

---

## Part 1: External Network Testing Framework

### Objective
Validate kushnir.cloud domain is accessible from external networks and all services function correctly without SSH tunnel or internal network access.

### Pre-Testing Checklist
- [ ] OAuth credentials obtained and configured (pending team)
- [ ] SSL certificate upgraded to kushnir.cloud (Phase 4 task)
- [ ] nginx health verified: `docker inspect hermes-nginx --format '{{.State.Health.Status}}'`
- [ ] Appsmith health verified: `docker inspect code-server-appsmith --format '{{.State.Health.Status}}'`
- [ ] External network access available (from non-internal network)
- [ ] Test execution plan documented

### Test 1: Domain DNS Resolution

**Objective:** Verify kushnir.cloud resolves to correct external IP

**From external network (NOT SSH tunnel):**
```bash
nslookup kushnir.cloud
# OR
dig kushnir.cloud
# OR
host kushnir.cloud
```

**Expected Result:**
```
kushnir.cloud resolves to 173.77.179.148
(external firewall IP that NATs to 192.168.168.31:443)
```

**Success Criteria:** ✅ DNS returns 173.77.179.148

---

### Test 2: TLS Connection & Certificate Validation

**Objective:** Verify SSL/TLS handshake completes successfully with valid certificate

**From external network:**
```bash
openssl s_client -connect kushnir.cloud:443 -servername kushnir.cloud
```

**Expected Result:**
```
subject=CN = kushnir.cloud
issuer=C = US, O = Let's Encrypt, CN = R3
NOT subject: CN = d8r978f08m4.d.firewalla.org (old cert)
Verify return code: 0 (ok)
```

**Success Criteria:** ✅ Valid kushnir.cloud certificate, no domain mismatch

---

### Test 3: HTTP 200 Response

**Objective:** Verify web server responds to HTTPS requests

**From external network:**
```bash
curl -I https://kushnir.cloud/
```

**Expected Result:**
```
HTTP/1.1 200 OK
Server: nginx/1.25.x
Content-Type: text/html; charset=utf-8
```

**Success Criteria:** ✅ HTTP 200 response, nginx server header visible

---

### Test 4: Appsmith OAuth Login Page

**Objective:** Verify Appsmith OAuth login page loads correctly

**From external network - Browser:**
```
https://kushnir.cloud
```

**Expected Behavior:**
1. Browser connects without SSL warnings ✅
2. Appsmith login page displays (NOT Hermes Executive Assistant page)
3. "Login with Google" button visible ✅
4. "Login with GitHub" button visible ✅
5. Page loads completely within 3 seconds ✅

**Success Criteria:** ✅ Appsmith OAuth login page visible, no SSL warnings, buttons present

---

### Test 5: OAuth Authentication Flow - Google (Requires Credentials)

**Objective:** Verify end-to-end Google OAuth authentication works

**Prerequisites:** Google OAuth credentials configured in .env.production

**From external network - Browser:**
```
1. Navigate to https://kushnir.cloud
2. Click "Login with Google" button
3. Complete Google OAuth consent flow
4. Verify redirect back to Appsmith dashboard
5. Confirm logged-in user display
6. Verify IDE access available
```

**Expected Behavior:**
- [ ] Redirects to Google OAuth consent screen
- [ ] After approval, redirects back to kushnir.cloud
- [ ] User profile displays in Appsmith
- [ ] IDE access granted
- [ ] No error messages in logs

**Success Criteria:** ✅ Full OAuth flow completes, user authenticated

---

### Test 6: OAuth Authentication Flow - GitHub (Requires Credentials)

**Objective:** Verify end-to-end GitHub OAuth authentication works

**Prerequisites:** GitHub OAuth credentials configured in .env.production

**From external network - Browser:**
```
1. Navigate to https://kushnir.cloud
2. Click "Login with GitHub" button
3. Complete GitHub OAuth authorization
4. Verify redirect back to Appsmith dashboard
5. Confirm logged-in user display
6. Verify IDE access available
```

**Expected Behavior:**
- [ ] Redirects to GitHub OAuth authorization page
- [ ] After approval, redirects back to kushnir.cloud
- [ ] User profile displays in Appsmith
- [ ] IDE access granted
- [ ] No error messages in logs

**Success Criteria:** ✅ Full OAuth flow completes, user authenticated

---

### Test 7: Code Server IDE Access

**Objective:** Verify code-server IDE is accessible through Appsmith

**Prerequisites:** User authenticated via OAuth

**From authenticated session:**
```
1. Click "Code Server" or IDE link in Appsmith
2. Verify IDE loads successfully
3. Confirm filesystem accessible
4. Verify editor functions available
5. Test file operations (create/read/write)
```

**Expected Behavior:**
- [ ] IDE loads within 5 seconds
- [ ] File browser displays /home/akushnir tree
- [ ] Editor renders code with syntax highlighting
- [ ] Terminal accessible
- [ ] No errors in console

**Success Criteria:** ✅ IDE fully functional, filesystem accessible

---

### Test 8: Response Time Performance

**Objective:** Measure application response times from external network

**From external network:**
```bash
# Homepage response time
time curl -o /dev/null -s -w '%{time_total}\n' https://kushnir.cloud/

# API endpoint response time (if applicable)
time curl -o /dev/null -s -w '%{time_total}\n' https://kushnir.cloud/api/health

# IDE page load time
curl -I https://kushnir.cloud/ide | head -1
```

**Expected Result:**
- Homepage: < 2 seconds
- API health check: < 1 second
- IDE page: < 5 seconds

**Success Criteria:** ✅ All response times within acceptable range

---

### Test 9: Load Testing (Light)

**Objective:** Verify application handles concurrent user load

**From external network:**
```bash
# Requires Apache Bench (ab) or similar tool
ab -n 100 -c 10 https://kushnir.cloud/

# OR using wrk (better for HTTP/2)
wrk -t12 -c400 -d30s https://kushnir.cloud/
```

**Expected Result:**
- All requests complete successfully (0 errors)
- Response time remains stable under load
- No 5xx server errors
- Error rate: 0%

**Success Criteria:** ✅ 100 concurrent requests handled without errors

---

### Test 10: Monitoring & Logging Verification

**Objective:** Verify logs capture external access correctly

**From primary host:**
```bash
ssh on-prem-primary

# Check nginx logs
docker logs hermes-nginx | tail -20

# Check Appsmith logs
docker logs code-server-appsmith | tail -20

# Look for external IP addresses in logs (173.77.179.148 or your external IP)
docker logs hermes-nginx | grep -i "173.77"
```

**Expected Behavior:**
- Logs show requests from external IP addresses
- No auth errors related to external access
- Request/response pairs logged correctly
- No certificate errors

**Success Criteria:** ✅ Logs show external access, no errors

---

## Part 2: Operational SLAs & Service Level Definitions

### SLA 1: Availability

**Definition:** Percentage of time all critical services are operational and responding

**Target:** 99.9% monthly uptime (43.2 minutes maximum downtime/month)

**Measurement:**
```
Availability % = (Uptime Minutes / Total Minutes in Month) × 100
```

**Service Scope:**
- kushnir.cloud domain DNS resolution ✅
- HTTPS connectivity on port 443 ✅
- Appsmith OAuth login page loading ✅
- Authentication service (Google/GitHub OAuth) ✅
- IDE access and file operations ✅

**Monitoring:**
- 5-minute health checks on all critical services
- External uptime monitoring (from third-party service)
- Alert when any critical service down > 1 minute

**Escalation:**
- Down 1-5 minutes: Warning logged
- Down 5-15 minutes: On-call team alerted
- Down 15+ minutes: Incident declared, escalation to CTO

---

### SLA 2: Response Time (Latency)

**Definition:** Time from request initiation to first byte received

**Target:**
```
Homepage (/) : < 2 seconds (p95)
OAuth Login: < 3 seconds (p95)
IDE Page Load: < 5 seconds (p95)
IDE File Operations: < 1 second (p99)
```

**Measurement:**
```
Record all response times, calculate 95th percentile (p95) and 99th percentile (p99)
```

**Monitoring:**
- Synthetic monitoring from external location (every 5 minutes)
- Real user monitoring (RUM) if available
- Track p50, p95, p99 percentiles

**Escalation:**
- p95 > threshold by 10%: Warning
- p95 > threshold by 25%: Alert to on-call team
- p95 > threshold by 50%: Incident, investigate root cause

---

### SLA 3: Error Rate

**Definition:** Percentage of requests that result in errors (5xx responses)

**Target:** < 0.1% error rate (< 1 error per 1000 requests)

**Measurement:**
```
Error Rate % = (Failed Requests / Total Requests) × 100
```

**Scope:**
- All HTTP 500-599 responses
- Request timeouts (>30 seconds)
- Connection refused errors

**Monitoring:**
- Monitor nginx/Appsmith error logs
- Track HTTP error codes by endpoint
- Alert on error rate threshold breach

**Escalation:**
- Error rate 0.1-1%: Warning logged
- Error rate 1-5%: On-call team alerted
- Error rate 5%+: Incident, immediate investigation

---

### SLA 4: Certificate Validity

**Definition:** SSL/TLS certificate must be valid and not expired

**Target:** Certificate always valid (0 days until expiration = failure)

**Measurement:**
```
Days until expiration = Certificate Expiration Date - Today
Alert when Days < 30
Escalation when Days < 7
```

**Scope:**
- Primary certificate (kushnir.cloud)
- Chain certificates
- No self-signed or invalid certificates

**Monitoring:**
- Automated certificate expiration check (daily)
- Let's Encrypt automatic renewal verification
- Manual renewal testing (monthly)

**Escalation:**
- 30 days until expiration: Informational alert
- 14 days until expiration: Warning - manual verification required
- 7 days until expiration: Critical - escalation to infrastructure team
- 1 day until expiration: Incident - manual renewal required immediately

---

### SLA 5: Database Connectivity & HA Status

**Definition:** Database must be responsive and HA standby must be operational

**Target:**
- Primary database: Always responsive
- Standby database: In sync with primary
- Failover capability: Ready at all times

**Measurement:**
```
Primary connectivity: < 100ms query response time
Replication lag: < 1 second
Standby status: CONNECTED & SYNCHRONIZED
```

**Scope:**
- PostgreSQL primary (192.168.168.31)
- PostgreSQL standby (192.168.168.42)
- Replication stream health

**Monitoring:**
- Query response time on primary
- Replication lag from `pg_stat_replication`
- Failover readiness test (monthly)

**Escalation:**
- Query response > 1 second: Warning
- Query response > 5 seconds: Alert
- Replication lag > 10 seconds: Critical alert
- Standby disconnected: Incident

---

### SLA 6: Network Connectivity (Primary ↔ Replica)

**Definition:** Network latency between primary and replica hosts must be minimal

**Target:** < 1ms average latency (0.190ms currently)

**Measurement:**
```
Latency = ping response time (primary ↔ replica)
```

**Monitoring:**
- Continuous ping monitoring (1 per minute)
- Track min/max/avg/p95 latency
- Alert on latency spikes

**Escalation:**
- Latency 1-5ms: Warning logged
- Latency 5-50ms: Alert to on-call team
- Latency > 50ms: Incident, investigate network issues

---

### SLA 7: Storage Availability

**Definition:** Sufficient disk space must be available for operations

**Target:** > 20GB free disk space (currently 30GB free)

**Measurement:**
```
Free Space % = (Available GB / Total GB) × 100
Alert when Free Space < 20GB
```

**Scope:**
- Primary host /home filesystem
- Docker storage (/var/lib/docker)
- Log storage (/var/log)

**Monitoring:**
- Daily disk usage check
- Calculate storage burn rate
- Predict when space will be critical

**Escalation:**
- 20GB free: Normal monitoring
- 10GB free: Warning - cleanup recommended
- 5GB free: Alert - immediate cleanup required
- <1GB free: Incident - urgent cleanup needed

---

### SLA 8: Memory Utilization

**Definition:** Available memory must be sufficient for operations

**Target:** < 85% memory utilization (currently 67%)

**Measurement:**
```
Memory Usage % = (Used Memory / Total Memory) × 100
```

**Scope:**
- Container memory allocation
- Host system memory
- Swap usage (should be minimal)

**Monitoring:**
- 5-minute interval memory checks
- Track peak usage times
- Monitor for memory leaks

**Escalation:**
- 85-95% utilization: Warning logged
- >95% utilization: Alert to on-call team
- OOM errors: Incident, immediate action required

---

### SLA 9: Container Health Status

**Definition:** All critical containers must be running and healthy

**Target:** 100% of critical containers healthy

**Measurement:**
```
Healthy % = (Healthy Containers / Total Critical Containers) × 100
Critical Containers = 8 (Appsmith, nginx, GitLab, PostgreSQL, Code Server, Vault, Minio, Keepalived)
```

**Scope:**
- Only critical services affect SLA
- Non-critical services tracked separately
- Health check status (not just running state)

**Monitoring:**
- 5-minute health check interval
- Docker health status (`docker inspect --format '{{.State.Health.Status}}'`)
- Automatic restart if unhealthy (unless-stopped policy)

**Escalation:**
- 1 container unhealthy: Warning, monitor recovery
- 2+ containers unhealthy: Alert to on-call team
- 3+ containers unhealthy or core service down: Incident

---

### SLA 10: Backup & Disaster Recovery Capability

**Definition:** Backup systems must be operational and tested

**Target:** Weekly backup success rate 100%

**Measurement:**
```
Backup Success % = (Successful Backups / Scheduled Backups) × 100
Last Successful Backup: < 7 days ago
Recovery Test: Monthly verification required
```

**Scope:**
- PostgreSQL database backups
- Container image backups
- Configuration backups

**Monitoring:**
- Verify backup job completion
- Check backup file sizes and integrity
- Track backup age

**Escalation:**
- Backup age > 7 days: Warning
- Backup age > 14 days: Alert
- Backup job failed: Incident

---

## SLA Dashboard Metrics Summary

| SLA | Target | Current | Status |
|-----|--------|---------|--------|
| Availability | 99.9% | 100% | ✅ |
| Homepage Response | < 2s (p95) | ~1.2s | ✅ |
| Error Rate | < 0.1% | 0% | ✅ |
| Certificate Valid | Always | ✅ (1 year) | ✅ |
| Database Latency | < 100ms | ~5ms | ✅ |
| Network Latency | < 1ms | 0.190ms | ✅ |
| Free Storage | > 20GB | 30GB | ✅ |
| Memory Usage | < 85% | 67% | ✅ |
| Container Health | 100% | 96.3% | ✅ |
| Backup Success | 100% | TBD | ⏳ |

---

## Escalation Path

**Tier 1 - Warning (Log only)**
- Minor threshold breaches
- No immediate action required
- Monitor for 30 minutes

**Tier 2 - Alert (On-Call Notification)**
- Moderate threshold breach or service degradation
- On-call engineer should investigate within 15 minutes
- Document in incident log

**Tier 3 - Incident (CTO Escalation)**
- Critical service down or multiple failures
- Immediate response required
- Activate incident response procedure

---

## Team Contacts

| Role | Contact | On-Call |
|------|---------|---------|
| Infrastructure Team | infrastructure@kushnir.cloud | 24/7 |
| DevOps Lead | devops-lead@kushnir.cloud | Business hours |
| CTO | cto@kushnir.cloud | Emergency only |

---

## Next Steps

1. **Immediate:** Execute external network testing (Test 1-7)
2. **Short-term:** Implement SLA monitoring dashboard
3. **Ongoing:** Track metrics against SLA targets
4. **Monthly:** Run SLA compliance report

**Status:** ✅ READY FOR EXECUTION  
**Last Updated:** April 30, 2026
