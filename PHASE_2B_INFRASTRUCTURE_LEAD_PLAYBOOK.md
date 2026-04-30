# PHASE 2B DEPLOYMENT - TEAM ROLE-SPECIFIC EXECUTION PLAYBOOK

**Status:** Role-specific detailed procedures  
**Authority:** All 6 Team Leads  
**Timeline:** May 1-21, 2026  

---

## 🎯 INFRASTRUCTURE LEAD - COMPLETE EXECUTION PLAYBOOK

### WEEK 1: STAGING DEPLOYMENT (May 1-12)

#### DAY 1 - TEAM ACTIVATION & HEALTH CHECKS

**Phase 1 Morning Standup (08:00 UTC)**
- [ ] Confirm all infrastructure accessible (PRIMARY, REPLICA, VIP)
- [ ] Confirm backup systems ready
- [ ] Confirm rollback procedures reviewed
- [ ] Team ready to proceed

**Phase 1 Execution (00:00-01:00 UTC)**
```bash
# SSH to PRIMARY
ssh user@192.168.168.31

# Health Check 1: Container Count
docker ps | grep -c healthy    # Expect: 87+
docker ps | grep healthy | wc -l

# Health Check 2: PostgreSQL Status
psql -h localhost -U postgres -c "SELECT version();"
psql -h localhost -U postgres -c "SELECT slot_name, restart_lsn FROM pg_replication_slots;"

# Health Check 3: Redis Status
redis-cli PING                 # Expect: PONG
redis-cli INFO replication

# Health Check 4: Keepalived VIP
ping -c 1 192.168.168.50       # Expect: Success

# Health Check 5: Network Connectivity
ping -c 1 192.168.168.42       # REPLICA - Expect: Success
```

**Decision Gate:** All checks PASS → Proceed to Phase 2 | Any FAIL → Escalate

#### DAYS 2-4: GITHUB PR PROCESS (May 2-4)

**Your Role:** Lead Infrastructure validation on GitHub PR

**Procedures:**
- [ ] Review GitHub PR (staging deployment procedures)
- [ ] Verify all procedures documented
- [ ] Verify all infrastructure references correct
- [ ] Add "Approved by Infrastructure Lead" comment
- [ ] Allow Operations Lead to review & approve
- [ ] PR ready for merge by end of Day 4

**Approval Checklist:**
```
GitHub PR Review Checklist:
- [ ] All Docker build procedures documented
- [ ] All deployment procedures clear
- [ ] All rollback procedures included
- [ ] All emergency contacts listed
- [ ] Infrastructure Lead approval: YES
- [ ] Operations Lead approval: YES
- [ ] Ready to merge
```

**Approval Comment Template:**
```
Approved by Infrastructure Lead - @[Your Name]

Infrastructure validation complete:
✅ Primary/Replica both 87+/88 containers
✅ PostgreSQL HA verified
✅ Redis HA verified  
✅ Keepalived VIP ready
✅ All procedures reviewed & verified
✅ Emergency procedures tested

Ready to merge and proceed with deployment.
```

#### DAYS 5-12: 8-PHASE DEPLOYMENT EXECUTION

**Phase 1: Docker Build & Registry (Day 5)**

```bash
# Step 1: Create Docker image
cd /path/to/gitlab-code
docker build -t gitlab:20260501 -f Dockerfile .
# Record: Build time _____ minutes

# Step 2: Verify image
docker images | grep gitlab:20260501
docker inspect gitlab:20260501 | grep Size

# Step 3: Push to registry
docker push registry.gitlab.com/kushin77/phase2b:20260501
# Record: Push time _____ minutes

# Step 4: Verify in registry
curl -H "Authorization: Bearer $TOKEN" \
  https://registry.gitlab.com/v2/kushin77/phase2b/tags/list
```

**Sign-off: Phase 1 COMPLETE (Docker build successful)**

---

**Phase 2: Environment Configuration (Days 5-6)**

```bash
# Step 1: Deploy config files
kubectl apply -f /configs/staging-env.yaml
# OR
docker-compose -f docker-compose.env-staging.yml config

# Step 2: Verify env vars
docker exec gitlab-rails env | grep GITLAB
# Record: All required env vars present: YES / NO

# Step 3: Validate configuration
/scripts/validate-configuration.sh
# Record: Validation result: PASS / FAIL
```

**Sign-off: Phase 2 COMPLETE (Environment configuration verified)**

---

**Phase 3: Database Migration (Days 6-7)**

```bash
# Step 1: Create pre-migration backup
cd /backups
sudo su - postgres
pg_dump -Fc gitlab_db > gitlab_db_pre_migration_$(date +%Y%m%d_%H%M%S).dump
# Record: Backup size _____ GB, Time _____ minutes

# Step 2: Execute migration
psql -h localhost -U postgres gitlab_db -f /migrations/migration_script.sql
# Record: Migration duration _____ minutes

# Step 3: Verify data integrity
psql -h localhost -U postgres gitlab_db << EOF
SELECT COUNT(*) as project_count FROM projects;
SELECT COUNT(*) as user_count FROM users;
SELECT COUNT(*) as issue_count FROM issues;
EOF
# Record: Project count _____, User count _____, Issue count _____

# Step 4: Verify replication
psql -h localhost -U postgres -c "SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;"
# Record: Replication lag _____ MB
```

**Sign-off: Phase 3 COMPLETE (Database migration verified)**

---

**Phase 4: Non-Critical Services (Days 7-8)**

```bash
# Step 1: Deploy non-critical services
docker-compose -f docker-compose.yml up -d \
  gitlab-registry \
  gitlab-mattermost \
  gitlab-pages

# Step 2: Verify services operational
docker ps | grep -E "registry|mattermost|pages"
# Record: All services running: YES / NO

# Step 3: Health checks
curl -I http://registry:5000/           # Expect: 200
curl -I http://mattermost:8065/         # Expect: 200 or 302
curl -I http://pages:8090/              # Expect: 200 or 302
```

**Sign-off: Phase 4 COMPLETE (Non-critical services deployed)**

---

**Phase 5: Critical Services (Days 8-9)**

```bash
# Step 1: Deploy critical services
docker-compose -f docker-compose.yml up -d \
  gitlab-rails \
  gitlab-sidekiq \
  gitlab-puma

# Step 2: Verify services operational
docker ps | grep -E "rails|sidekiq|puma"
# Record: All services running: YES / NO

# Step 3: Load test (20 req/sec for 5 minutes)
ab -n 6000 -c 20 http://localhost/
# Record: Requests succeeded _____, Failed _____, Avg response time _____ ms
```

**Sign-off: Phase 5 COMPLETE (Critical services deployed & load tested)**

---

**Phase 6: Health Checks & Validation (Days 9-10)**

```bash
# Comprehensive health check
bash /scripts/comprehensive-health-check.sh

# Record all results:
Database connectivity: ✅/❌
Cache connectivity: ✅/❌
API responsive: ✅/❌
Web UI responsive: ✅/❌
All containers healthy: ✅/❌
Replication working: ✅/❌
No errors in logs: ✅/❌
```

**Sign-off: Phase 6 COMPLETE (All health checks PASSED)**

---

**Phase 7: Performance Baseline (Days 10-11, 24 hours)**

```bash
# Capture baseline metrics for 24 hours
# From Prometheus:

Query 1: CPU usage (avg)
Result: _____ %

Query 2: Memory usage (avg)
Result: _____ %

Query 3: Disk I/O (avg)
Result: _____ MB/s

Query 4: Database latency (p95)
Result: _____ ms

Query 5: API latency (p95)
Result: _____ ms

# Document baseline
# IMPORTANT: Keep this for comparison during production deployment
```

**Sign-off: Phase 7 COMPLETE (24-hour baseline captured)**

---

**Phase 8: Integration Tests (Days 11-12)**

```bash
# Run comprehensive integration test suite
/scripts/integration-tests.sh

# Record results:
Total tests: _____
Passed: _____
Failed: _____
Skipped: _____
Coverage: _____%
Duration: _____ hours

# Tests must be: 100% PASSED
```

**Sign-off: Phase 8 COMPLETE (All integration tests PASSED)**

---

### WEEK 2: PRODUCTION READINESS (May 8-14)

**Your Role:** Lead production infrastructure validation & sign-off

**Production Sign-Off Checklist (Level 1 - Infrastructure Lead):**

- [ ] All 8 staging phases COMPLETE
- [ ] All validation tests PASSED
- [ ] Zero critical issues in staging
- [ ] Performance baseline meets SLA
- [ ] Disaster recovery drill successful
- [ ] Backup procedures verified
- [ ] HA failover tested (8/8 passed)
- [ ] Team trained on production procedures

**Production Sign-Off Document:**

```
INFRASTRUCTURE LEAD PRODUCTION SIGN-OFF
Date: May 14, 2026
Time: _____ UTC

All infrastructure validation complete:
✅ Staging deployment: 100% complete
✅ All validation tests: PASSED
✅ Zero critical issues: Verified
✅ HA failover: 8/8 tests PASSED
✅ Backup procedures: Verified operational
✅ Disaster recovery: Drill completed successfully

Infrastructure Status: READY FOR PRODUCTION DEPLOYMENT

Signed: _________________________ (Infrastructure Lead)
Date: _________________________ Time: _____________
```

---

### WEEK 2-3: PRODUCTION DEPLOYMENT (May 15-21+)

**Your Role:** Lead blue-green deployment & HA restoration

**Day 1: Final Pre-Deployment Checks**
- [ ] REPLICA infrastructure health verified
- [ ] PRIMARY infrastructure health verified
- [ ] Database backup created & verified
- [ ] All procedures reviewed one final time
- [ ] Team positioned & ready

**Day 2: REPLICA Deployment**
```bash
# SSH to REPLICA (192.168.168.42)
ssh user@192.168.168.42

# Deploy latest image to REPLICA
docker pull registry.gitlab.com/kushin77/phase2b:20260501
docker-compose up -d

# Verify REPLICA operational
docker ps | grep -c healthy    # Expect: 88
```

**Day 3: REPLICA 24-Hour Validation**
- [ ] Monitor REPLICA for 24 hours
- [ ] Verify replication working
- [ ] Verify all services stable
- [ ] Zero critical errors

**Day 4: DNS Cutover**
```bash
# Change DNS to point to REPLICA
# OR
# Point load balancer to REPLICA
# Verify traffic routing

# 6-hour production load test on REPLICA
```

**Day 5: PRIMARY Deployment**
```bash
# SSH to PRIMARY
# Deploy latest image
# Verify operational
```

**Day 6: HA Restoration**
- [ ] Both nodes operational
- [ ] Failover capability tested
- [ ] Keepalived VIP active
- [ ] Replication working

**Days 7-9: 72-Hour Observation**
- [ ] Hour-by-hour monitoring (Day 1)
- [ ] Daily standups (Days 2-3)
- [ ] Zero critical issues target
- [ ] Team confidence verified

**Sign-off: Production deployment COMPLETE & STABLE**

---

## ✅ INFRASTRUCTURE LEAD - FINAL RESPONSIBILITIES

### END OF WEEK 3
- [ ] Production systems stable for 72+ hours
- [ ] All metrics within SLA
- [ ] Final sign-off obtained
- [ ] Operations team ready for handoff
- [ ] Document lessons learned

---

## 📞 INFRASTRUCTURE LEAD ESCALATION PATH

**Issue > 30 minutes unresolved:** Call Operations Lead  
**Critical infrastructure failure:** Call CTO immediately  
**Data loss or corruption:** Emergency escalation to Executive Sponsor  

---

**Created:** April 30, 2026  
**Authority:** Autonomous Master Engineer  
**Role:** Infrastructure Lead  

**"Execute precisely. Track everything. Escalate appropriately. Success depends on infrastructure excellence."**
