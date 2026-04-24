# Change Management Policy

**Document ID:** CMP-001  
**Version:** 1.0  
**Effective Date:** April 22, 2026  
**Classification:** Internal - Confidential

## 1. Purpose

Ensure all infrastructure and application changes are planned, tested, and documented.

## 2. Change Classification

### 2.1 Change Types

| Type | Examples | Approval | Testing | Deployment |
|------|----------|----------|---------|-----------|
| **Critical** | OIDC key rotation, security patch | Security owner + CTO | Staging + prod-like | Immediate |
| **Major** | DB schema change, TLS upgrade | Tech lead + security | Staging (48 hours) | Off-peak |
| **Minor** | Config change, package upgrade | Tech lead | Unit tests + staging | Off-peak |
| **Documentation** | README, runbook updates | Tech lead | N/A | Anytime |

### 2.2 Change Risk Assessment

**Questions to answer:**
1. Does it affect availability? (service down risk?)
2. Does it affect security? (credential/access risk?)
3. Is it reversible? (rollback possible?)
4. What's the blast radius? (1 user? 1 service? all services?)
5. Have we tested this before?

**Risk Score = Probability × Impact**
- Score > 8: Critical (immediate, max testing)
- Score 5-8: Major (off-peak, staging test)
- Score 2-5: Minor (standard test, anytime)
- Score < 2: Documentation (no testing)

## 3. Change Request Process

### 3.1 Submit Change Request

**In GitHub:**
1. Create new issue with label `change-request`
2. Title: `[CHANGE][type] Brief description`
3. Body includes:
   - What is changing?
   - Why? (business rationale / security fix)
   - Risk assessment (use checklist above)
   - Testing plan (unit test, staging, smoke test post-deploy)
   - Rollback plan (how to undo if needed)
   - Deployment window (date/time, expected duration)

**Example:**
```
Title: [CHANGE][Major] Upgrade TLS cipher suites

What:
- Remove weak cipher suites (RC4, DES)
- Add only strong ciphers (AES-256-GCM, CHACHA20)

Why:
- Security requirement for SOC2 Type II compliance
- Industry best practice (NIST guidelines)

Risk Assessment:
- Availability: Low (certificate/key unchanged)
- Security: Positive (stronger ciphers)
- Reversible: Yes (revert Caddy config)
- Blast radius: All HTTPS connections
- Previous experience: Yes (similar done in 2023)
- Risk score: 2 (low prob × medium impact = low)

Testing:
- [ ] Unit test: TLS handshake with old + new ciphers
- [ ] Staging: All clients connect successfully
- [ ] Smoke test (post-deploy): HTTPS works, no errors

Rollback:
- Revert Caddy config (git revert)
- Restart Caddy service (< 1 minute)
- Verify HTTPS still works

Deployment Window:
- Date: 2026-04-29 (Friday)
- Time: 2:00 AM - 3:00 AM UTC (off-peak)
- Expected duration: 15 minutes
```

### 3.2 Review and Approval

**Review Checklist:**
- [ ] Change request is complete (all fields filled)
- [ ] Risk assessment is reasonable
- [ ] Testing plan is sufficient
- [ ] Rollback procedure exists
- [ ] Deployment window is appropriate (off-peak for Major)
- [ ] No conflicts with other scheduled changes

**Approval by:**
- **Critical changes:** Security owner + CTO
- **Major changes:** Tech lead + security owner
- **Minor changes:** Tech lead
- **Documentation:** Any team member

**Approval timeline:**
- Critical: Same day if possible (security critical)
- Major: Within 24 hours (allows time for review)
- Minor: Within 48 hours

## 4. Testing and Validation

### 4.1 Testing Levels

**Unit Tests:**
- Fast, isolated testing
- Changes to code: Must have passing unit tests
- CI/CD enforces: No merge without tests

**Integration Tests:**
- Test interaction between services
- Changes to APIs: Must have integration tests
- Staging environment: Run full integration test suite

**Staging Deployment:**
- Deploy to non-production environment
- Mimic production configuration
- Run smoke tests
- User acceptance testing (UAT)

**Production Smoke Tests (Post-Deploy):**
- Quick validation that system is up
- Check critical endpoints (health, login, etc.)
- Monitor for 1 hour post-deploy

### 4.2 Test Documentation

**For each change:**
- [ ] List of tests executed
- [ ] Pass/fail results
- [ ] Any issues found and how resolved
- [ ] Date/time of testing

## 5. Deployment Procedure

### 5.1 Deployment Window Coordination

**Before deployment:**
- Notify all stakeholders (ops team, developers, product)
- Disable auto-scaling (if applicable) to prevent side effects
- Enable verbose logging
- Have rollback team on standby

**During deployment:**
- Follow change request deployment steps
- Parallel terminal: Monitor logs for errors
- Check application metrics (latency, error rate)
- Every 5 minutes: Verbal status update

**After deployment:**
- Run smoke tests
- Monitor for 1 hour
- Gather metrics (latency, errors, resource usage)
- Document actual vs. planned duration

### 5.2 Traffic / Service Management

**If service restart required:**
1. Drain gracefully (wait for in-flight requests to complete)
2. Shut down service
3. Deploy new version
4. Start service
5. Health check passes
6. Gradually send traffic back (if load balancer used)

**If database migration required:**
1. Backup database
2. Run migration in transaction
3. Verify data integrity
4. Commit transaction (or rollback on error)

## 6. Rollback Procedures

### 6.1 When to Rollback

- **Immediate rollback if:**
  - Service fails to start
  - Database migration fails / data loss
  - Error rate > 5% (vs. baseline < 1%)
  - Critical functionality broken

- **Within 1 hour if:**
  - Performance degradation > 50% (latency 5x higher)
  - User-facing failures

### 6.2 Rollback Execution

**Steps:**
1. Incident commander makes rollback decision
2. Run rollback procedure (specific to change type)
3. Verify service healthy post-rollback
4. Notify stakeholders
5. Schedule RCA within 24 hours

**Examples:**

**Code Rollback:**
```bash
# Revert to previous deployment
git revert <commit-sha>
docker-compose up -d
# Verify service health
curl https://api.kushnir.cloud/health
```

**Database Rollback:**
```bash
# Restore from backup
pg_restore -d prod_db < /backups/pre-migration.sql
# Verify data integrity
SELECT COUNT(*) FROM users;  # Should match count before migration
```

**Configuration Rollback:**
```bash
# Revert Caddy config
git checkout HEAD -- Caddyfile
# Reload Caddy (no restart needed)
caddy reload --config Caddyfile
```

## 7. Post-Deployment

### 7.1 Monitoring

**Automated alerts:**
- Error rate > 5% (vs. baseline)
- Latency p99 > 2x baseline
- CPU usage > 80%
- Disk usage > 90%
- Database connections > 100

**Manual checks (1 hour post-deploy):**
- [ ] Login functionality works
- [ ] API endpoints respond normally
- [ ] No unexpected errors in logs
- [ ] Database replication lag < 1s
- [ ] Backup completed successfully

### 7.2 Change Log

**Document in Change Log (changelog.md):**
```
## [2026-04-29] - TLS Cipher Suite Upgrade

### Changed
- Upgraded TLS cipher suites to NIST-approved algorithms
- Removed weak ciphers: RC4, DES, MD5
- Added strong ciphers: AES-256-GCM, CHACHA20

### Impact
- Zero downtime (certificate/key unchanged)
- Slightly improved TLS handshake latency (negligible)
- Enhanced security compliance (SOC2 Type II)

### Verified
- All clients connecting with new ciphers
- Error rate 0.8% (within normal range)
- No rollback needed
```

## 8. Emergency Changes

### 8.1 Hot Patch Procedure

For critical security issues only:
1. **Skip full review:** Security owner makes judgment call
2. **Minimal testing:** Verify fix doesn't break core functionality
3. **Immediate deployment:** No waiting for off-peak window
4. **Notification:** Full stakeholder notification (even if middle of night)
5. **RCA scheduled:** Do full testing in 24 hours post-deployment

**Example:**
- CVE-2025-XXXXX (critical RCE) disclosed
- Hot patch available but not yet in release
- Deploy immediately (skip normal process)
- Full testing in 24 hours

## 9. Change Calendar and Blackout Dates

### 9.1 Restricted Windows

**No deployments during:**
- Major product launches (notify ops)
- High-traffic periods (Friday evenings, Black Friday)
- Customer maintenance windows (if SLA requires it)
- Unplanned incidents (focus on recovery first)

**Preferred deployment windows:**
- Tuesday-Thursday, 2:00 AM - 6:00 AM UTC
- Off-peak for all geographies

## 10. Appendix: Change Checklist

### Pre-Deployment
- [ ] Change request reviewed and approved
- [ ] All tests passing (unit + integration)
- [ ] Staging tested successfully
- [ ] Rollback procedure documented and tested
- [ ] Stakeholders notified
- [ ] Deployment window confirmed
- [ ] Backup taken (if needed)

### During Deployment
- [ ] Verbose logging enabled
- [ ] Team on standby
- [ ] Monitor logs actively
- [ ] Every 5 min status update
- [ ] Smoke tests pass (post-deploy)

### Post-Deployment
- [ ] Metrics reviewed (latency, errors, CPU)
- [ ] No unexpected issues
- [ ] Notifications sent (if applicable)
- [ ] Changelog updated
- [ ] Runbook updated (if procedure changed)

---

**Document Owner:** Engineering Team  
**Related Issues:** #1070  
**Next Review:** July 22, 2026
