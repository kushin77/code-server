# PHASE 6: ADVANCED PRODUCTION HARDENING & OPTIMIZATION
**Status**: READY FOR IMMEDIATE EXECUTION (No external dependencies)

---

## 6a: Database Performance Optimization (4 hours)

### Objective
Implement connection pooling, query optimization, and sharding preparation

### Immediate Deliverables
1. **PgBouncer Configuration** (Session/Transaction pooling)
   - SSH to 192.168.168.31
   - Deploy pgbouncer container alongside postgres
   - Configure connection limits: 500 max_client_conn, 100 default_pool_size
   - Test with sysbench (concurrent connections)

2. **Query Performance Analysis**
   - Enable pg_stat_statements extension
   - Identify slow queries (>100ms)
   - Add missing indexes
   - Optimize N+1 query patterns in code-server

3. **Connection Pooling Tests**
   - Baseline: Direct postgres connection (100 conn/s)
   - With pgbouncer: Target 500+ conn/s
   - Measure latency impact

### Success Criteria
✅ pgbouncer accepting 500+ concurrent connections
✅ <5% latency increase vs direct connection
✅ Zero dropped connections under 2x load

---

## 6b: Advanced Security Hardening (6 hours)

### Objective
Implement network segmentation, secret rotation, and compliance scanning

### Immediate Deliverables
1. **Network Segmentation**
   - Create docker networks:
     * frontend (caddy, oauth2-proxy)
     * backend (code-server, postgres, redis)
     * monitoring (prometheus, grafana, alertmanager)
   - Restrict inter-service communication
   - Document network flow

2. **Secret Management**
   - Migrate all .env secrets to HashiCorp Vault (Docker container)
   - Implement secret rotation (30-day policy)
   - Add audit logging for secret access
   - Test secret injection during deployment

3. **Compliance Scanning**
   - OWASP Top 10 vulnerability scan
   - Container security scan (Trivy)
   - Dependency vulnerability scan (Dependabot)
   - Generate compliance report

### Success Criteria
✅ All secrets in Vault (none in .env)
✅ Network policies enforced (no cross-segment communication)
✅ Zero high/critical vulnerabilities found
✅ Compliance report generated

---

## 6c: Load Testing & Capacity Planning (5 hours)

### Objective
Validate infrastructure at 2x/5x/10x scale

### Immediate Deliverables
1. **Load Testing Setup**
   - Deploy locust (Python load testing tool)
   - Create realistic user flow tests:
     * OAuth login
     * File operations (create/read/write)
     * IDE navigation
     * Search queries
   - Baseline: 100 concurrent users → target throughput

2. **Performance Metrics**
   - Latency: p50, p95, p99 (target <100ms p99)
   - Throughput: requests/second (target 1000+ rps)
   - Error rate: <0.1%
   - Resource utilization: CPU <70%, Memory <80%

3. **Scaling Tests**
   - 1x load: Baseline (verify stability)
   - 2x load: Double users (verify headroom)
   - 5x load: 500 concurrent (verify graceful degradation)
   - 10x load: 1000 concurrent (stress test)

### Success Criteria
✅ Passes 5x load with <150ms p99 latency
✅ Graceful degradation at 10x (no crashes)
✅ Auto-scaling triggers at 70% CPU utilization
✅ Capacity plan documented (scale at 75% load)

---

## 6d: Disaster Recovery & Backup (3 hours)

### Objective
Implement automated backups and recovery procedures

### Immediate Deliverables
1. **Backup Strategy**
   - Daily postgres backups (to /backups on 192.168.168.31)
   - Weekly full VM snapshots (via Proxmox if available)
   - 30-day retention policy
   - Test restore procedure weekly

2. **Recovery Testing**
   - Document RTO (Recovery Time Objective): <5 minutes
   - Document RPO (Recovery Point Objective): <1 hour
   - Test postgres restore from backup
   - Test application recovery from snapshot

3. **High Availability Preparation**
   - Setup standby host (192.168.168.30)
   - Configure failover procedure
   - Document switchover process
   - Test failover (non-destructive)

### Success Criteria
✅ Automated daily backups running
✅ Restore from backup tested & <5min RTO verified
✅ Standby host synchronized
✅ Failover procedure documented & tested

---

## 6e: Advanced Monitoring & Alerting (4 hours)

### Objective
Implement SLO/SLI framework and intelligent alerting

### Immediate Deliverables
1. **SLO/SLI Definition**
   - Availability SLO: 99.9% (4 9's)
   - Latency SLI: p99 < 100ms
   - Error Rate SLI: <0.1%
   - Track monthly error budget

2. **Advanced Alerts**
   - Error rate spike (>1%)
   - Latency regression (p99 > 150ms)
   - Database connection pool exhaustion
   - Disk space <10% remaining
   - Certificate expiration <30 days

3. **Runbook Automation**
   - Database connection pool exhaustion → Restart pgbouncer
   - High error rate → Trigger canary rollback
   - Memory leak detected → Alert ops + auto-restart
   - Certificate expiration → Auto-renew (Let's Encrypt)

### Success Criteria
✅ SLO/SLI dashboard in Grafana
✅ All critical alerts defined
✅ Runbooks linked to alerts
✅ Alert routing configured (on-call team)

---

## EXECUTION SEQUENCE (No Wait - Do Now)

### Hour 1-4: Phase 6a (Database Optimization)
`ash
# SSH to production
ssh akushnir@192.168.168.31

# Deploy pgbouncer
docker run -d --name pgbouncer \
  --network code-server-network \
  -e DATABASES_HOST=postgres \
  -e DATABASES_PORT=5432 \
  -e DATABASES_USER=postgres \
  -e DATABASES_PASSWORD=\ \
  -p 6432:6432 \
  pgbouncer:latest

# Test connection pooling
for i in {1..100}; do 
  psql -h localhost -p 6432 -U postgres -c "SELECT 1" &
done
wait
`

### Hour 5-10: Phase 6b (Security Hardening)
`ash
# Create docker networks
docker network create frontend
docker network create backend
docker network create monitoring

# Deploy Vault
docker run -d --name vault \
  --network backend \
  -e VAULT_DEV_ROOT_TOKEN_ID=myroot \
  -p 8200:8200 \
  vault:latest

# Migrate secrets
# (script to move all .env → Vault)
`

### Hour 11-15: Phase 6c (Load Testing)
`ash
# Deploy locust
docker run -d --name locust \
  --network code-server-network \
  -p 8089:8089 \
  locustio/locust:latest \
  -f locustfile.py \
  --headless -u 100 -r 10 -t 1h

# Monitor results (Grafana dashboard)
# http://192.168.168.31:3000/d/load-testing
`

### Hour 16-18: Phase 6d (Disaster Recovery)
`ash
# Automated backups (cron)
0 2 * * * docker exec postgres pg_dump -U postgres > /backups/db_\.sql

# Test restore
docker exec postgres pg_restore -U postgres /backups/db_latest.sql
`

### Hour 19-22: Phase 6e (Advanced Monitoring)
`ash
# Add SLO/SLI dashboard to Grafana
# Configure alert channels (Slack, PagerDuty)
# Create runbook automations
`

---

## DELIVERABLES (To Create)

1. **PHASE-6-DATABASE-OPTIMIZATION.md** (PgBouncer setup guide)
2. **PHASE-6-SECURITY-HARDENING.md** (Network segmentation + Vault)
3. **PHASE-6-LOAD-TESTING.md** (Locust + capacity planning)
4. **PHASE-6-DISASTER-RECOVERY.md** (Backup/restore procedures)
5. **PHASE-6-MONITORING-ADVANCED.md** (SLO/SLI framework)
6. **locustfile.py** (Load testing scenarios)
7. **slo-dashboard.json** (Grafana dashboard)
8. **alert-rules-advanced.yml** (AlertManager rules)

---

## TIMELINE
- **Total Duration**: 22 hours (parallel where possible)
- **Phase 6a**: 4 hours (database optimization)
- **Phase 6b**: 6 hours (security hardening) - parallel with 6a
- **Phase 6c**: 5 hours (load testing) - parallel with 6a/6b
- **Phase 6d**: 3 hours (disaster recovery)
- **Phase 6e**: 4 hours (advanced monitoring)

---

## SUCCESS CRITERIA (ALL MUST PASS)

✅ pgbouncer: 500+ concurrent connections, <5% latency increase
✅ Security: Network segmented, all secrets in Vault, 0 high/critical vulns
✅ Load testing: Passes 5x load at <150ms p99, graceful degradation at 10x
✅ Disaster recovery: RTO <5min, RPO <1hr, restore tested
✅ Monitoring: SLO/SLI dashboard live, all alerts configured, runbooks automated
✅ Documentation: All 8 deliverables complete and committed
✅ Production: No interruption during implementation
✅ Rollback: All changes reversible, procedures documented

---

## BLOCKERS
None - All work can proceed immediately without external dependencies

## RISK LEVEL
LOW - All techniques proven in production, no customer-facing changes until validation complete
