## P3 Phase 2 - Deployment Verification Checklist

**Date:** 2026-04-24
**Status:** Final Verification Phase

### Pre-Production Verification Checklist

#### Replica 1 (R31: 192.168.168.31)

**Services Status:**
- [ ] Caddy HEALTHY (port 443)
- [ ] Redis HEALTHY (port 6379)
- [ ] oauth2-proxy HEALTHY (port 4180)
- [ ] saas-api HEALTHY (port 5000)
- [ ] PostgreSQL HEALTHY (port 5432)
- [ ] Appsmith HEALTHY (port 80)

**API Endpoints Verification:**
- [ ] GET /api/orgs responds 200/403
- [ ] POST /api/orgs requires ADMIN_EMAILS (test with admin email)
- [ ] POST /api/users requires ADMIN_EMAILS (test with admin email)
- [ ] GET /api/audit-logs requires ADMIN_EMAILS
- [ ] POST /api/orgs/{id}/custom-domain accepts domain parameter
- [ ] GET /api/orgs/{id}/dns-verification returns TXT record status
- [ ] DELETE /api/orgs/{id}/custom-domain/{domain} soft-deletes

**Database Verification:**
- [ ] PostgreSQL connection pool working
- [ ] All 7 tables created (organizations, users, groups, memberships, audit_logs, custom_domains, domain_verification_attempts)
- [ ] All 26 indexes created
- [ ] Schema idempotent (can re-run migrations safely)

**TLS/SSL Verification:**
- [ ] Caddy serving HTTPS (https://ide.kushnir.cloud)
- [ ] Certificate valid (not self-signed)
- [ ] HSTS headers present

#### Replica 2 (R42: 192.168.168.42)

**Services Status:**
- [ ] Caddy HEALTHY (port 443)
- [ ] Redis HEALTHY (port 6379)
- [ ] oauth2-proxy HEALTHY (port 4180)
- [ ] saas-api HEALTHY (port 5000)
- [ ] PostgreSQL HEALTHY (port 5432)
- [ ] Appsmith HEALTHY (port 80)

**API Endpoints Verification:**
- [ ] GET /api/orgs responds 200/403
- [ ] POST /api/orgs requires ADMIN_EMAILS
- [ ] POST /api/users requires ADMIN_EMAILS
- [ ] GET /api/audit-logs requires ADMIN_EMAILS
- [ ] POST /api/orgs/{id}/custom-domain accepts domain parameter
- [ ] GET /api/orgs/{id}/dns-verification returns TXT record status
- [ ] DELETE /api/orgs/{id}/custom-domain/{domain} soft-deletes

**Database Verification:**
- [ ] PostgreSQL connection pool working
- [ ] All 7 tables created
- [ ] All 26 indexes created
- [ ] Schema idempotent

**TLS/SSL Verification:**
- [ ] Caddy serving HTTPS
- [ ] Certificate valid
- [ ] HSTS headers present

#### Cross-Replica Verification

**Load Balancing:**
- [ ] Round-robin via HAProxy/Cloudflare
- [ ] Both replicas receive traffic
- [ ] Session persistence across replicas

**Git Deployment:**
- [ ] 8 commits on main branch
- [ ] All commits have proper messages
- [ ] No merge conflicts
- [ ] Branch protection rules enforced

#### Test Infrastructure Verification

**Playwright Configuration:**
- [ ] playwright.config.ts has retry logic (3 retries)
- [ ] Timeout set to 30 seconds
- [ ] Trace capture on first retry
- [ ] Screenshot on failure
- [ ] Video on failure
- [ ] HTML reporter configured
- [ ] JSON reporter configured
- [ ] JUnit reporter configured

**Test Environment:**
- [ ] .env.test has all required variables
- [ ] TEST_BASE_URL correct (https://ide.kushnir.cloud)
- [ ] PORTAL_BASE_URL correct (https://kushnir.cloud)
- [ ] PLAYWRIGHT_RETRIES=3
- [ ] PLAYWRIGHT_TIMEOUT=30000

**Test Suite:**
- [ ] sso-flows.spec.ts has 26+ test cases
- [ ] 30+ total assertions
- [ ] Flow 1: New user (5 assertions)
- [ ] Flow 2: Returning user (5 assertions)
- [ ] Flow 3: VPN validation (5 assertions)
- [ ] Flow 4: Session expiry (6 assertions)
- [ ] Integration test (4 assertions)
- [ ] Smoke test (5 assertions)

**CI/CD Workflow:**
- [ ] .github/workflows/p3-1676-sso-validation.yml exists
- [ ] Schedule set to "0 2 * * *" (2 AM UTC daily)
- [ ] workflow_dispatch enabled (manual trigger)
- [ ] Node.js 20 setup
- [ ] Playwright install step
- [ ] Test execution command correct
- [ ] Slack webhook integration
- [ ] Artifact upload configured
- [ ] Result parsing implemented

#### Documentation Verification

**Files Present:**
- [ ] TEST-GUIDE-P3-1676.md (244 lines)
- [ ] PHASE-2-COMPLETION-REPORT.md (370 lines)
- [ ] playwright.config.ts (test configuration)
- [ ] .env.test (environment variables)

**Documentation Content:**
- [ ] Setup instructions clear
- [ ] Local execution commands provided
- [ ] CI workflow explained
- [ ] Retry logic documented
- [ ] Troubleshooting guide included
- [ ] Performance metrics provided
- [ ] Support contacts listed

#### GitHub Issues Verification

**Issue #1674 (SaaS Backend):**
- [ ] Issue created and open
- [ ] 3 comments posted (progress updates + closure summary)
- [ ] RBAC implementation documented
- [ ] Deployment status confirmed
- [ ] Phase 2 closure summary posted

**Issue #1675 (Custom Domains):**
- [ ] Issue created and open
- [ ] 3 comments posted (progress updates + closure summary)
- [ ] API endpoints documented
- [ ] Deployment status confirmed
- [ ] Phase 2 closure summary posted

**Issue #1676 (SSO Validation):**
- [ ] Issue created and open
- [ ] 5 comments posted (progress updates + enhancements + closure summary)
- [ ] Test suite documented
- [ ] CI workflow documented
- [ ] Retry logic documented
- [ ] Phase 2 closure summary posted

#### Production Readiness

**Code Quality:**
- [ ] No syntax errors
- [ ] No console errors in logs
- [ ] No database migration errors
- [ ] No Docker build failures

**Performance:**
- [ ] API response time < 500ms
- [ ] Database queries optimized
- [ ] No N+1 query problems
- [ ] Connection pooling configured

**Security:**
- [ ] RBAC middleware enforcing access control
- [ ] OAuth2 protection on all endpoints
- [ ] CORS headers set appropriately
- [ ] SQL injection prevention (parameterized queries)
- [ ] No sensitive data in logs

**Monitoring:**
- [ ] Health check endpoints responding
- [ ] Error logging configured
- [ ] Metrics collection ready
- [ ] Alert rules configured

#### Final Sign-Off

**Completion Status:**
- [ ] All API endpoints functional
- [ ] RBAC enforcement verified
- [ ] Custom domain endpoints working
- [ ] Test suite ready
- [ ] CI/CD workflow configured
- [ ] Documentation complete
- [ ] Both replicas HEALTHY
- [ ] All 8 commits on main
- [ ] All 3 issues documented with closure summaries

**Ready for Phase 3:**
- [ ] Production deployment successful
- [ ] First test execution scheduled (tomorrow 2 AM UTC)
- [ ] All stakeholders notified
- [ ] Monitoring active
- [ ] Incident response plan ready

---

## Verification Commands

### Check Replica Status
```bash
# SSH to R31
ssh user@192.168.168.31 docker-compose ps

# SSH to R42
ssh user@192.168.168.42 docker-compose ps
```

### Verify API Endpoints (R31)
```bash
# Test RBAC - should return 403 without admin
curl -H "X-Auth-Request-Email: user@example.com" https://ide.kushnir.cloud/api/orgs

# Test with admin - should return 200
curl -H "X-Auth-Request-Email: admin@example.com" https://ide.kushnir.cloud/api/orgs

# Test custom domain endpoint
curl -X POST https://ide.kushnir.cloud/api/orgs/test-id/custom-domain \
  -H "Content-Type: application/json" \
  -d '{"domain": "example.com"}'
```

### Verify Database
```bash
# SSH to R31
ssh user@192.168.168.31
psql -h localhost -U postgres -d saas-app

# List tables
\dt

# Check indexes
\di

# Count rows in each table
SELECT 'organizations' as table, COUNT(*) FROM organizations
UNION ALL
SELECT 'users', COUNT(*) FROM users
UNION ALL
SELECT 'groups', COUNT(*) FROM groups
UNION ALL
SELECT 'memberships', COUNT(*) FROM memberships
UNION ALL
SELECT 'audit_logs', COUNT(*) FROM audit_logs
UNION ALL
SELECT 'custom_domains', COUNT(*) FROM custom_domains;
```

### Verify GitHub Commits
```bash
git log --oneline -10

# Should show 8 Phase 2 commits at top
19c0c79 docs: Add P3 Phase 2 comprehensive completion report
5a5b391 docs(P3-1676): Add comprehensive test execution guide
764cd2d config(P3-1676): Add test environment configuration
2ec15b9 config(P3-1676): Add Playwright test configuration
2243b32 ci(P3-1676): Add daily SSO validation workflow
e58aaf40 feat(P3-1676): Implement Phase 2 Playwright E2E tests
333d476f feat(P3-1675): Implement custom domain API endpoints
1a6bec05 feat(P3-1674): Implement RBAC middleware in saas-api
```

### Verify GitHub Issues
```bash
gh issue view 1674 --json comments
gh issue view 1675 --json comments
gh issue view 1676 --json comments
```

---

**Status: VERIFICATION CHECKLIST READY FOR EXECUTION**
**Next Step: Execute verification commands and mark items complete**
**Phase 2 Closure:** All items marked complete = Ready to close issues and proceed to Phase 3
