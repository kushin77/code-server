# Phase 5 May 1 Pre-Flight Checklist & Quick Reference
**Date:** May 1, 2026 | **Start Time:** 09:00 UTC | **Duration:** 3 hours

---

## 🚀 Quick Start: May 1 Execution Overview

**What's Happening Today:**
1. SSL Certificate Upgrade (30 min) - DevOps
2. SSL Verification (15 min) - DevOps  
3. External Network Testing (20 min) - Operations
4. OAuth Testing Prep (15 min) - QA

**Success = All 4 Tasks Complete + No Critical Failures**

---

## 📋 Pre-Execution Checklist (Complete Before 09:00 UTC)

### DevOps Team - Pre-Execution

- [ ] SSH access confirmed to 192.168.168.31 (primary host)
- [ ] Terminal access ready (NOT SSH sudo, proper terminal)
- [ ] Git pulled latest code: `git pull origin fix/domain-variability-caddy`
- [ ] Read: PHASE_5_TEAM_EXECUTION_ACTION_PLAN.md (SSL upgrade section)
- [ ] Backup location identified: `/etc/nginx/nginx.conf.backup.*`
- [ ] Rollback procedure understood and documented locally
- [ ] Certbot version checked: `certbot --version`
- [ ] Let's Encrypt ACME terms reviewed
- [ ] Email address ready for certificate registration
- [ ] All team members briefed on procedure
- [ ] Estimated downtime confirmed: 5-10 minutes (acceptable)

**DevOps Sign-Off:** _____________ **Time:** _____

### Operations Team - Pre-Execution

- [ ] Git pulled latest code: `git pull origin fix/domain-variability-caddy`
- [ ] Read: PHASE_5_EXECUTION_READINESS_REPORT.md
- [ ] External testing network access verified
- [ ] Testing procedures documented and printed/available
- [ ] Curl or similar tool available for testing
- [ ] Test domain (kushnir.cloud) resolves: `dig kushnir.cloud`
- [ ] Port 443 connectivity verified: `nc -zv kushnir.cloud 443`
- [ ] Test report template prepared
- [ ] All team members briefed on procedures
- [ ] Monitoring tools available (Grafana, Prometheus, or equivalent)

**Operations Sign-Off:** _____________ **Time:** _____

### Security Team - Pre-Execution

- [ ] Read: PHASE_4_SSL_CERTIFICATE_UPGRADE.md (SSL section)
- [ ] Certificate vendor (Let's Encrypt) approved
- [ ] Audit logging ready for certificate change
- [ ] Change control ticket created (if required)
- [ ] Rollback approval obtained
- [ ] Post-upgrade verification steps documented

**Security Sign-Off:** _____________ **Time:** _____

### QA/Testing Team - Pre-Execution

- [ ] Git pulled latest code: `git pull origin fix/domain-variability-caddy`
- [ ] OAuth credentials status: [ ] Ready [ ] Pending (contact Product/Identity)
- [ ] OAuth testing procedures reviewed
- [ ] Testing environment prepared
- [ ] Post-testing verification steps documented
- [ ] All team members briefed on OAuth flow

**QA Sign-Off:** _____________ **Time:** _____

---

## 🔄 May 1 Execution Tasks - Quick Reference

### Task 1: SSL Certificate Upgrade (09:00-09:30)

**Owner:** DevOps Lead  
**Duration:** 30 minutes  
**Downtime:** 5-10 minutes acceptable

**Quick Steps:**
1. SSH to primary: `ssh on-prem-primary`
2. Stop nginx: `docker stop hermes-nginx`
3. Generate cert: `sudo certbot certonly --standalone -d kushnir.cloud`
4. Update config: Point nginx to `/etc/letsencrypt/live/kushnir.cloud/`
5. Start nginx: `docker start hermes-nginx`
6. Verify: `openssl s_client -connect kushnir.cloud:443 -servername kushnir.cloud`
7. Setup renewal: Configure certbot renewal hook

**Success Criteria:**
✅ Certificate generated successfully  
✅ nginx started without errors  
✅ Port 443 responding  
✅ Certificate subject: CN = kushnir.cloud  

**If Failed - Rollback:**
```
docker stop hermes-nginx
sudo cp /etc/nginx/nginx.conf.backup.* /etc/nginx/nginx.conf
docker start hermes-nginx
Verify nginx is healthy
```

**Status at 09:30:**
- [ ] PASS - Move to Task 2
- [ ] FAIL - Stop and investigate, document issue

---

### Task 2: SSL Verification (09:30-09:45)

**Owner:** DevOps Lead  
**Duration:** 15 minutes

**Verification Steps:**
1. Check certificate deployed: `openssl s_client -connect kushnir.cloud:443 -servername kushnir.cloud`
2. Verify subject: `CN = kushnir.cloud` (not d8r978f08m4)
3. Verify issuer: `Let's Encrypt` (not self-signed)
4. Test from external: `curl -I https://kushnir.cloud`
5. Expected: HTTP 200 or redirect (NOT SSL error)

**Success Criteria:**
✅ Certificate subject correct  
✅ Issuer is Let's Encrypt  
✅ No SSL warnings  
✅ HTTP 200/301/302 response  

**Status at 09:45:**
- [ ] PASS - Move to Task 3
- [ ] FAIL - Contact DevOps Lead immediately

---

### Task 3: External Network Testing (09:45-10:05)

**Owner:** Operations Lead  
**Duration:** 20 minutes

**Test Procedure (6 Quick Scenarios):**

```bash
# Test 1: DNS Resolution
dig kushnir.cloud +short
# Expected: 173.77.179.148

# Test 2: Port 443 Connectivity  
nc -zv kushnir.cloud 443
# Expected: Connection successful

# Test 3: TLS Certificate
openssl s_client -connect kushnir.cloud:443 -servername kushnir.cloud </dev/null 2>&1 | grep -E "subject=|issuer=|Verify"
# Expected: subject=CN = kushnir.cloud, Verify return code: 0

# Test 4: HTTP Response
curl -I https://kushnir.cloud --insecure 2>&1 | head -1
# Expected: HTTP/2 200 or HTTP/1.1 200

# Test 5: Appsmith Access
curl -s https://kushnir.cloud | grep -i "appsmith" | head -1
# Expected: Appsmith content present

# Test 6: Response Time
time curl -s https://kushnir.cloud > /dev/null 2>&1
# Expected: <2 seconds
```

**Success Criteria:**
✅ All 6 tests PASS  
✅ No unexpected errors  
✅ Response time <2s  

**Report Template:**
```
EXTERNAL TESTING REPORT - May 1, 2026
Executor: [Name]
Time: [HH:MM UTC]

Test Results:
- DNS Resolution: [PASS/FAIL]
- Port Connectivity: [PASS/FAIL]
- TLS Certificate: [PASS/FAIL]
- HTTP Response: [PASS/FAIL]
- Appsmith Access: [PASS/FAIL]
- Response Time: [PASS/FAIL]

Overall: [ALL PASS/ISSUES FOUND]
Issues: [None/Describe any issues]

Tester Signature: _______________
Date: _____________
```

**Status at 10:05:**
- [ ] ALL PASS - Move to Task 4
- [ ] ISSUES - Document and escalate to Operations Lead

---

### Task 4: OAuth Testing Prep (10:05-10:20)

**Owner:** QA Lead  
**Duration:** 15 minutes

**Preparation Steps:**
1. Verify OAuth credentials received: [ ] Yes [ ] No
2. If YES, update .env.production with credentials
3. Restart Appsmith: `docker restart code-server-appsmith`
4. Wait for healthy: `docker ps | grep appsmith` (should show "healthy")
5. Schedule OAuth E2E testing for May 1 afternoon (14:00)
6. Document any blockers

**Credential Status:**
- [ ] Google OAuth: Ready
- [ ] GitHub OAuth: Ready
- [ ] Both ready - Schedule E2E testing immediately
- [ ] Still pending - Document blocker, schedule for May 1-2

**Status at 10:20:**
- [ ] READY - OAuth E2E testing scheduled
- [ ] PENDING CREDS - Follow up with Product/Identity Team

---

## 📊 May 1 Success Metrics

| Task | Target | Status | Sign-Off |
|------|--------|--------|----------|
| SSL Certificate Upgrade | Complete | [ ] | DevOps: _____ |
| SSL Verification | 100% pass | [ ] | DevOps: _____ |
| External Testing | 6/6 PASS | [ ] | Operations: _____ |
| OAuth Prep | Framework ready | [ ] | QA: _____ |

**Overall May 1 Status:**
- [ ] ALL TASKS PASS - Ready for May 2
- [ ] ISSUES FOUND - Document and escalate

---

## 🆘 Emergency Contacts

| Role | Name | Phone | Email | Status |
|------|------|-------|-------|--------|
| DevOps Lead | _____________ | _____________ | _____________ | On-Site |
| Operations Lead | _____________ | _____________ | _____________ | On-Site |
| Security Lead | _____________ | _____________ | _____________ | On-Call |
| Infrastructure Lead | _____________ | _____________ | _____________ | Primary |
| CTO | _____________ | _____________ | _____________ | Available |

**Escalation Path:**
1. Issue detected → Notify task owner (Level 1)
2. Can't resolve in 15 min → Escalate to Infrastructure Lead (Level 2)
3. Service down >30 min → CTO escalation (Level 3)

---

## 📝 Documentation Quick Links

**Must Read Before 09:00 UTC:**
- [ ] PHASE_5_TEAM_EXECUTION_ACTION_PLAN.md (complete guide)
- [ ] PHASE_4_SSL_CERTIFICATE_UPGRADE.md (SSL procedures)
- [ ] PHASE_5_EXECUTION_READINESS_REPORT.md (readiness verification)
- [ ] FINAL_OPERATIONAL_HANDOFF_CHECKLIST.md (what to verify)

**Reference During Execution:**
- [ ] SSL upgrade step-by-step (in action plan)
- [ ] External testing scenarios (in readiness report)
- [ ] OAuth procedures (in action plan)
- [ ] Rollback procedure (in SSL upgrade guide)

---

## ⏰ Timeline - May 1 Execution

```
08:45 - All teams arrive, review procedures
08:50 - Final infrastructure check
08:55 - Team briefing, confirm all ready
09:00 - START Task 1: SSL Upgrade

  09:00-09:30: DevOps executes SSL upgrade
  09:30 - Operations standing by to test
  
09:30 - Task 2: SSL Verification begins
09:45 - Task 2 complete, Task 3 begins
  
09:45-10:05: Operations runs external tests
10:05 - Operations completes testing
  
10:05-10:20: QA prepares OAuth framework
10:20 - Task 4 complete, all May 1 tasks done

10:20 - Review all results
10:30 - Debrief and next steps briefing
14:00 - OAuth E2E Testing (if credentials ready)
```

---

## ✅ May 1 Pre-Flight Completion

**All Teams Ready:** [ ] Yes [ ] No

**All Procedures Reviewed:** [ ] Yes [ ] No

**All Contacts Confirmed:** [ ] Yes [ ] No

**All Equipment Tested:** [ ] Yes [ ] No

**Rollback Procedures Understood:** [ ] Yes [ ] No

**Emergency Contacts Updated:** [ ] Yes [ ] No

**Infrastructure Baseline Captured:** [ ] Yes [ ] No

**GO/NO-GO Decision:** [ ] GO (Proceed May 1) [ ] NO-GO (Delay)

---

## 📋 Sign-Offs - Pre-Flight Complete

**DevOps Lead:** _________________ **Time:** _____ **Date:** _____

**Operations Lead:** _________________ **Time:** _____ **Date:** _____

**Security Lead:** _________________ **Time:** _____ **Date:** _____

**Infrastructure Lead:** _________________ **Time:** _____ **Date:** _____

**CTO/Executive:** _________________ **Time:** _____ **Date:** _____

---

## 🎯 May 1 Day-Of Quick Reference

**Keep This Sheet With You During Execution**

### SSL Upgrade (DevOps)
```
1. SSH to-prem-primary
2. docker stop hermes-nginx
3. sudo certbot certonly --standalone -d kushnir.cloud
4. Update nginx.conf paths
5. docker start hermes-nginx
6. Verify: openssl s_client -connect kushnir.cloud:443
7. Verify subject: CN = kushnir.cloud
```

### External Testing (Operations)
```
1. dig kushnir.cloud +short → 173.77.179.148
2. nc -zv kushnir.cloud 443 → Connected
3. openssl s_client ... → CN = kushnir.cloud
4. curl -I https://kushnir.cloud → 200
5. curl -s https://kushnir.cloud | grep appsmith → Found
6. time curl ... → <2s
```

### OAuth Prep (QA)
```
1. Credentials status check
2. If ready: Update .env.production
3. docker restart code-server-appsmith
4. Wait for healthy status
5. Schedule E2E testing
```

---

## 🔐 Rollback Quick Reference

**If SSL Upgrade Fails:**
```bash
docker stop hermes-nginx
sudo cp /etc/nginx/nginx.conf.backup.* /etc/nginx/nginx.conf
docker start hermes-nginx
Verify: docker ps | grep hermes-nginx
```

**If External Tests Fail:**
```bash
Check DNS: dig kushnir.cloud
Check connectivity: nc -zv kushnir.cloud 443
Check nginx: docker logs hermes-nginx
Document issue and escalate
```

**If OAuth Setup Fails:**
```bash
Wait for credentials
Check env vars: grep OAUTH .env.production
Restart Appsmith: docker restart code-server-appsmith
Verify: docker logs code-server-appsmith
```

---

**This Checklist Prepared:** April 30, 2026 | **Ready for:** May 1, 2026 09:00 UTC

**Status:** ✅ READY FOR EXECUTION
