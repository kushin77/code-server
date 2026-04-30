# PHASE 2B DEPLOYMENT - CONTINGENCY & ROLLBACK FRAMEWORK

**Status:** Emergency procedures - Always available  
**Authority:** Operations Lead + CTO + Executive Sponsor  
**Scope:** Applicable during Weeks 1-3  

---

## 🚨 WHEN TO ACTIVATE CONTINGENCY

**Activate contingency procedures ONLY if:**

- Critical system failure (> 30 minutes unresolved)
- Data loss or corruption detected
- Security breach detected
- Capacity exhausted (cannot recover)
- > 10% of critical services down

**Do NOT activate contingency for:**
- Minor performance degradation
- Individual component failures (can be recovered)
- Expected maintenance windows
- Scheduled maintenance

---

## 🚨 CONTINGENCY ACTIVATION PROCEDURE

### STEP 1: IMMEDIATE ALERT (0-5 Minutes)

**Who:** Operations Lead or on-call engineer  
**Action:**
1. Declare CRITICAL incident
2. Alert all team leads immediately
3. Alert CTO (via phone/SMS)
4. Activate war room (emergency mode)
5. Document incident time & description

**Decision:** Can we fix this in < 2 hours?
- **YES:** Proceed with RECOVERY (see below)
- **NO:** Proceed to CONTINGENCY ASSESSMENT

---

### STEP 2: CONTINGENCY ASSESSMENT (5-30 Minutes)

**Who:** CTO + Operations Lead + Infrastructure Lead  
**Action:**
1. Assess root cause
2. Evaluate fix vs. rollback
3. Estimate time to fix
4. Estimate time to rollback
5. Evaluate data loss risk

**Decision Tree:**

```
Can we fix in < 2 hours?
├─ YES → Proceed with RECOVERY (Fix & Validate)
└─ NO → Proceed to ROLLBACK DECISION
    Can we rollback safely?
    ├─ YES → Proceed to ROLLBACK
    └─ NO → Proceed to DATA RECOVERY (Special procedures)
```

---

### STEP 3A: RECOVERY PATH (If fixable)

**Timeline: < 2 hours from incident**

**Recovery Procedure:**
1. Identify root cause
2. Implement fix (code/config/infrastructure)
3. Deploy fix to STAGING (if necessary)
4. Validate fix (health checks, tests)
5. Monitor for 30 minutes
6. Declare incident resolved
7. Document root cause & lessons learned

**Success Criteria:**
- ✅ All health checks PASS
- ✅ All critical services OPERATIONAL
- ✅ Zero errors in logs
- ✅ Performance acceptable
- ✅ Data integrity verified

**If PASS:** Incident resolved, continue deployment  
**If FAIL:** Escalate to ROLLBACK

---

### STEP 3B: ROLLBACK PATH (If unfixable)

**Timeline: Immediate activation if recovery fails**

**Rollback is authorized by CTO + Executive Sponsor only.**

---

## 🔄 FULL ROLLBACK PROCEDURE

### PHASE 1: ROLLBACK AUTHORIZATION (5 Minutes)

**Participants:** CTO, Operations Lead, Executive Sponsor  
**Required Approvals:** ALL 3 must approve rollback

**Approval Checklist:**
- [ ] CTO: "I authorize rollback"
- [ ] Operations Lead: "I authorize rollback"
- [ ] Executive Sponsor: "I authorize rollback"

**Rollback Decision Recorded:** Date: _______ Time: _______ UTC

---

### PHASE 2: PRE-ROLLBACK VALIDATION (10 Minutes)

**Owner:** Infrastructure Lead  
**Procedure:**

1. **Verify Backup Integrity**
   ```bash
   # Verify backup exists and is valid
   ls -lh /backups/staging_db_*.dump
   pg_restore --list /backups/staging_db_YYYYMMDD_HHMMSS.dump | head -20
   # Confirm: Backup size > 100 MB and contains schema
   ```

2. **Verify Previous Version**
   ```bash
   # Confirm previous Docker image available in registry
   docker image ls | grep gitlab:previous
   # Result should show image with tag
   ```

3. **Verify Network Connectivity**
   ```bash
   # Verify infrastructure accessible
   ping 192.168.168.31 (PRIMARY)
   ping 192.168.168.42 (REPLICA)
   ping 192.168.168.50 (VIP)
   # All must RESPOND
   ```

4. **Verify Data Consistency**
   ```bash
   # Run consistency checks on current state
   psql -h localhost -U postgres -c "SELECT datname, checksum FROM pg_stat_database;"
   # Record results for comparison
   ```

**Approval:** [ ] Pre-rollback validation PASSED

---

### PHASE 3: TRAFFIC CUTOVER (5-10 Minutes)

**Owner:** Operations Lead  
**Procedure:**

**If in STAGING (Week 1):**
```bash
# Revert DNS to point to previous staging environment
# OR
# Revert load balancer to point to previous staging environment
# (Exact procedure depends on your DNS/LB setup)

# Verify traffic actually redirected
curl -I http://staging.gitlab.example.com
# Should return 200 OK from previous version
```

**If in PRODUCTION (Week 2-3):**
```bash
# CRITICAL: Use DNS cutover (fastest, cleanest)
# 1. Revert DNS VIP to point to known-good previous configuration
# 2. Verify all traffic routed to previous version
# 3. Confirm in logs: all requests going to previous version

# Verification
dig +short staging.gitlab.example.com
# Result should show previous VIP or previous server IP
```

**Approval:** [ ] Traffic cutover completed & verified

---

### PHASE 4: DATA ROLLBACK (15-30 Minutes)

**Owner:** Infrastructure Lead  
**Database Rollback Procedure:**

```bash
# 1. Stop all applications (if necessary)
docker stop gitlab-rails gitlab-sidekiq gitlab-puma

# 2. Restore from backup
psql -h localhost -U postgres -d gitlab_db -c "DROP SCHEMA public CASCADE;"
pg_restore -h localhost -U postgres -d gitlab_db /backups/staging_db_YYYYMMDD_HHMMSS.dump

# 3. Verify restoration
psql -h localhost -U postgres -d gitlab_db -c "SELECT COUNT(*) FROM projects;"
# Record count for comparison with pre-incident

# 4. Restart applications
docker start gitlab-rails gitlab-sidekiq gitlab-puma

# 5. Verify application startup
docker logs gitlab-rails | grep "Application started successfully"
# Should see success message
```

**Data Consistency Check:**
```bash
# Verify data integrity after restore
psql -h localhost -U postgres -d gitlab_db << EOF
SELECT datname, checksum FROM pg_stat_database WHERE datname='gitlab_db';
SELECT COUNT(*) FROM projects;
SELECT COUNT(*) FROM users;
SELECT COUNT(*) FROM issues;
EOF
# Compare with pre-incident numbers
```

**Approval:** [ ] Data rollback completed & verified

---

### PHASE 5: APPLICATION VALIDATION (15-20 Minutes)

**Owner:** QA/Test Lead  
**Validation Checklist:**

- [ ] Application UI accessible (curl, browser)
- [ ] Authentication working (login/logout)
- [ ] Projects visible (project list displayed)
- [ ] Repositories functional (pull/push operations)
- [ ] Database connected (no connection errors)
- [ ] APIs responding (health check endpoints)
- [ ] No critical errors in logs
- [ ] Performance acceptable

**Validation Commands:**
```bash
# Check application status
curl http://staging.gitlab.example.com/api/v4/user -H "PRIVATE-TOKEN: $TOKEN"
# Should return user info (200 OK)

# Check database connectivity
psql -h localhost -U postgres -c "SELECT version();"
# Should return PostgreSQL version

# Check cache connectivity
redis-cli PING
# Should return PONG

# Check all critical endpoints
for endpoint in "/signin" "/api/v4/version" "/health"; do
  echo "Testing $endpoint:"
  curl -s -w "Status: %{http_code}\n" http://staging.gitlab.example.com$endpoint
done
# All should return 200 or 302 (redirect)
```

**Approval:** [ ] Application validation PASSED

---

### PHASE 6: MONITORING VERIFICATION (5 Minutes)

**Owner:** Monitoring Lead  
**Procedure:**

- [ ] Prometheus scraping actively (all targets UP)
- [ ] Grafana dashboards showing current data
- [ ] AlertManager operational (no error alerts)
- [ ] No false positives in alerts
- [ ] Baseline metrics returning to normal

**Verification:**
```bash
# Check Prometheus targets
curl http://prometheus:9090/api/v1/targets | jq '.data.activeTargets | length'
# Should show 8+ active targets

# Check AlertManager status
curl http://alertmanager:9093/api/v1/alerts | jq '.data | length'
# Should show manageable number of alerts (likely none if rollback successful)
```

**Approval:** [ ] Monitoring verification PASSED

---

### PHASE 7: INCIDENT DECLARATION (2 Minutes)

**Owner:** Operations Lead  
**Action:**

1. Document incident closure time
2. Declare incident resolved
3. Notify all stakeholders
4. Schedule post-incident review (within 24 hours)

**Incident Summary:**
```
Incident #: [Generated]
Start Time: [RECORDED]
End Time: [NOW]
Duration: [CALCULATED]
Root Cause: [IDENTIFIED]
Resolution: [ROLLBACK TO PREVIOUS VERSION]
Data Loss: [ASSESS - NONE/MINIMAL/SIGNIFICANT]
System Recovery: [VERIFIED]
Status: ✅ RESOLVED
Next Steps: 1) Post-incident review (24h)
            2) Root cause analysis (48h)
            3) Preventive measures (72h)
```

**All Stakeholders Notified:** [ ] YES

---

## 📋 ROLLBACK SUCCESS CRITERIA

**Rollback is successful when ALL of the following are TRUE:**

- ✅ Traffic successfully redirected to previous version
- ✅ Previous version responding to all requests (< 1% errors)
- ✅ Database restored with zero data loss (if rollback required)
- ✅ No critical errors in application logs
- ✅ All health checks PASSING
- ✅ Performance within acceptable range
- ✅ All monitoring systems functional
- ✅ All stakeholders confirmed system stable

**If ALL are TRUE:** Incident resolved, proceed to post-incident review  
**If ANY is FALSE:** Escalate to Level 3 (CTO) for extended troubleshooting

---

## 🔍 POST-INCIDENT REVIEW PROCEDURE

**Timeline:** Within 24 hours of incident  
**Owner:** Project Manager + All Team Leads  

### SECTION 1: INCIDENT SUMMARY

**Incident Details:**
- Date/Time: ___________________________________
- Duration: ___________________________________
- Services Affected: ___________________________________
- Root Cause: ___________________________________
- Resolution: ___________________________________

### SECTION 2: TIMELINE

**Hour-by-hour breakdown of incident:**

| Time | Event | Owner | Status |
|------|-------|-------|--------|
| 10:00 UTC | Incident detected | Ops | ✅ |
| 10:05 UTC | Escalated to CTO | PM | ✅ |
| 10:15 UTC | Root cause identified | Infra | ✅ |
| ... | ... | ... | ✅ |

### SECTION 3: ROOT CAUSE ANALYSIS

**Primary Cause:** ___________________________________  
**Contributing Factors:** ___________________________________  
**Why Detection Was Delayed:** ___________________________________  
**Why Resolution Was Difficult:** ___________________________________  

### SECTION 4: IMPACT ASSESSMENT

**Systems Affected:** ___________________________________  
**User Impact:** ___________________________________  
**Data Loss/Corruption:** ___________________________________  
**Reputational Impact:** ___________________________________  
**Financial Impact:** ___________________________________  

### SECTION 5: PREVENTION MEASURES

**What will prevent this in future:**

1. ___________________________________
2. ___________________________________
3. ___________________________________
4. ___________________________________
5. ___________________________________

### SECTION 6: PROCESS IMPROVEMENTS

**What will improve our response time:**

1. ___________________________________
2. ___________________________________
3. ___________________________________

### SECTION 7: SIGN-OFFS

**CTO:** _________________ Date: _______ Approved: [ ]  
**Operations Lead:** _________________ Date: _______ Approved: [ ]  
**Project Manager:** _________________ Date: _______ Approved: [ ]  

---

## ✅ WHEN TO DECLARE VICTORY AFTER ROLLBACK

**After rollback is complete, declare victory when:**

- ✅ System stable for 2 hours (no new errors)
- ✅ All health checks passing
- ✅ Performance metrics normal
- ✅ No critical alerts
- ✅ Team confident in stability

**Victory Declaration:**

```
Date: [DATE]
Time: [TIME] UTC
Status: ✅ SYSTEM RESTORED & STABLE
Confidence: [HIGH / MEDIUM / LOW]
Next Action: [Continue deployment / Investigate root cause / Schedule post-incident review]
```

---

## 📞 ESCALATION - WHEN TO CALL CTO

**Call CTO if ANY of the following occur:**

1. **Incident unresolved after 30 minutes**
2. **Data loss detected or suspected**
3. **Multiple critical systems down simultaneously**
4. **Rollback procedures failing**
5. **Uncertainty about continue vs. rollback decision**
6. **Any incident affecting production users**

**CTO Contact:** ______________________  
**CTO Phone:** ______________________  
**CTO Email:** ______________________  

**Always call - do not wait for email response**

---

**Framework Created:** April 30, 2026  
**Authority:** Autonomous Master Engineer  
**Status:** Ready for deployment (Weeks 1-3)  

**"Contingency is prepared. Escalation paths are clear. If we must rollback, we will do it safely and swiftly."**
