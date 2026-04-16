# PRODUCTION DEPLOYMENT RUNBOOK - April 18, 2026

**Deployment Window**: April 18, 2026 08:00 UTC  
**Expected Duration**: 2 hours (08:00-10:00 UTC)  
**Deployment Type**: Blue/Green Canary (1% → 10% → 50% → 100%)  
**Rollback Time**: < 60 seconds  
**RTO**: < 5 minutes  
**SLA**: 99.99% availability post-deployment  

---

## 🎯 DEPLOYMENT OBJECTIVES

1. ✅ Deploy all Phase 0-8 changes to production
2. ✅ Maintain 99.99% availability during deployment
3. ✅ Validate all services operationally
4. ✅ Monitor for 1 hour post-deployment
5. ✅ Document deployment execution
6. ✅ Prepare rollback if needed

---

## 📋 PRE-DEPLOYMENT CHECKLIST (EXECUTE APRIL 18, 07:30 UTC)

### Infrastructure Verification (15 min)
- [ ] SSH access to 192.168.168.31: Test connectivity
- [ ] SSH access to 192.168.168.56 (NAS): Test connectivity
- [ ] Docker daemon status: Verify running on 192.168.168.31
- [ ] Network connectivity: Ping all hosts
- [ ] DNS resolution: Test kushnir.local resolution
- [ ] Vault status: Verify unsealed and operational
- [ ] Database connectivity: Test PostgreSQL connection
- [ ] Redis connectivity: Test cache connection

**Validation Command**:
```bash
ssh akushnir@192.168.168.31 "
  echo '=== Docker Status ===' && docker ps
  echo '=== Vault Status ===' && vault status
  echo '=== Network ===' && ping -c 1 192.168.168.56
"
```

### Configuration Verification (10 min)
- [ ] .env files populated (no secrets in git)
- [ ] TLS certificates valid (not expired)
- [ ] SSH keys installed (proper permissions 0600)
- [ ] Caddyfile syntax valid: `caddy validate --config Caddyfile`
- [ ] Terraform syntax valid: `terraform validate`
- [ ] Docker Compose syntax valid: `docker-compose config > /dev/null`
- [ ] All required environment variables exported

**Validation Commands**:
```bash
# Verify Caddyfile
caddy validate --config Caddyfile

# Verify Terraform
cd terraform && terraform validate && terraform fmt -check

# Verify Docker Compose
docker-compose config > /dev/null && echo "✅ Docker Compose valid"
```

### Backup & Snapshot (10 min)
- [ ] Database backup: `pg_dump` to /backup/pre-deployment-$(date +%s).sql
- [ ] NAS snapshot: Snapshot 192.168.168.56 current state
- [ ] Configuration backup: Git commit current state
- [ ] Vault secrets exported: `vault kv list secret/`

**Backup Commands**:
```bash
# Database backup
ssh akushnir@192.168.168.31 "
  docker exec postgres pg_dump -U postgres code_server_db > /tmp/pre-deploy-$(date +%s).sql
  echo 'Database backup complete'
"

# Vault secrets validation
ssh akushnir@192.168.168.31 "
  vault kv list secret/
  vault kv get secret/database/postgres
  vault kv get secret/cache/redis
"
```

### Service Status Baseline (5 min)
- [ ] Record current API response times (baseline)
- [ ] Record current error rate (should be 0%)
- [ ] Record current memory usage
- [ ] Record current CPU usage
- [ ] Take Grafana dashboard screenshot (baseline)

---

## 🚀 DEPLOYMENT EXECUTION (08:00 UTC START)

### Phase 1: Canary Deployment (1%) - 08:00-08:15 UTC

**Objective**: Route 1% of traffic to new version, monitor for 15 minutes

**Steps**:
1. Pull latest code from main branch
   ```bash
   git fetch origin main
   git reset --hard origin/main
   ```

2. Build new Docker images with new version tag
   ```bash
   docker-compose build --no-cache
   ```

3. Update load balancer/Caddyfile to route 1% to new version
   ```bash
   # Update Caddyfile with canary weights
   caddy reload --config Caddyfile
   ```

4. Monitor metrics for 15 minutes
   - Error rate should remain < 0.1%
   - Latency p99 should remain < 100ms
   - No new errors in logs

5. **GO/NO-GO Decision**:
   - ✅ GO: If metrics stable, proceed to 10%
   - ❌ NO-GO: If issues detected, rollback immediately

### Phase 2: Gradual Rollout (1% → 10%) - 08:15-08:25 UTC

**Objective**: Increase traffic to 10%, monitor for 10 minutes

**Steps**:
1. Update load balancer weights to 10%
2. Monitor metrics for 10 minutes
3. Check application logs for errors
4. Verify all services responsive

**Monitoring Commands**:
```bash
# Check error rate
curl http://localhost:8080/metrics | grep -i error

# Check latency
curl http://localhost:8080/metrics | grep -i latency

# Check logs
docker-compose logs -f --tail=50
```

**GO/NO-GO Decision**:
- ✅ GO: If 10% stable, proceed to 50%
- ❌ NO-GO: If issues detected, rollback

### Phase 3: Full Rollout (10% → 50% → 100%) - 08:25-08:55 UTC

**Objective**: Complete deployment to 100% of traffic

**Steps**:
1. Update load balancer to 50% (08:30)
   - Monitor for 15 minutes
   - GO/NO-GO decision

2. Update load balancer to 100% (08:45)
   - All traffic now on new version
   - Final validation complete by 08:55

**Validation**:
- [ ] All containers running: `docker-compose ps`
- [ ] All services responsive: `curl http://localhost:8080/health`
- [ ] No errors in logs: `docker-compose logs | grep ERROR`
- [ ] Database connected: `docker exec postgres psql -U postgres -d code_server_db -c "SELECT 1"`
- [ ] Metrics from Prometheus: `curl http://localhost:9090/api/v1/query?query=up`

### Phase 4: Post-Deployment Validation (08:55-09:00 UTC)

**Objective**: Final validation that all systems operational

- [ ] Health endpoint returns 200: `curl -I http://localhost:8080/health`
- [ ] Prometheus scraping active targets
- [ ] AlertManager receiving no critical alerts
- [ ] Grafana dashboards updating in real-time
- [ ] No new errors in any service logs

---

## 📊 MONITORING DURING DEPLOYMENT (08:00-10:00 UTC)

### Metrics to Watch
| Metric | Threshold | Action |
|--------|-----------|--------|
| Error Rate | > 1% | ⚠️ Investigate, > 5% ROLLBACK |
| Latency p99 | > 150ms | ⚠️ Investigate, > 200ms ROLLBACK |
| CPU Usage | > 80% | ⚠️ Investigate, > 95% ROLLBACK |
| Memory Usage | > 85% | ⚠️ Investigate, > 95% ROLLBACK |
| Vault Unsealed | false | 🔴 CRITICAL - ROLLBACK |
| Database Connected | false | 🔴 CRITICAL - ROLLBACK |
| Network Latency | > 100ms | ⚠️ Investigate |

### Monitoring Commands
```bash
# Watch Prometheus metrics (refresh every 5 sec)
watch -n 5 'curl -s http://localhost:9090/api/v1/query?query=up | jq'

# Watch container logs in real-time
docker-compose logs -f

# Check all containers status
watch -n 5 'docker-compose ps'

# Check system resources
watch -n 5 'free -h && echo "---" && df -h'
```

### Alert Response Procedures

**If Alert: High Error Rate**
1. Check Docker logs: `docker-compose logs -f --tail=50`
2. Check Prometheus metrics: `curl http://localhost:9090/api/v1/targets`
3. Verify database: `docker exec postgres psql -U postgres -d code_server_db -c "SELECT 1"`
4. If unresolvable: ROLLBACK

**If Alert: High Latency**
1. Check container resources: `docker stats`
2. Check network: `ping 192.168.168.56`
3. Check database query time: `docker exec postgres psql -U postgres -d code_server_db -c "EXPLAIN ANALYZE SELECT 1"`
4. If > 200ms: ROLLBACK

**If Alert: Service Down**
1. Check container status: `docker-compose ps`
2. Restart container: `docker-compose restart <service>`
3. If still down: ROLLBACK immediately

---

## ⏮️ ROLLBACK PROCEDURE (EXECUTE IF NEEDED)

**Decision Point**: Any critical metric exceeds threshold

**Rollback Steps**:
```bash
# 1. Identify last stable commit
git log --oneline -5

# 2. Create rollback commit
git revert <unstable_commit_sha>

# 3. Deploy rollback
git push origin main

# 4. Verify rollback on production host
ssh akushnir@192.168.168.31 "
  cd code-server-enterprise
  git fetch origin main
  git reset --hard origin/main
  docker-compose down
  docker-compose pull
  docker-compose up -d
"

# 5. Validate rollback
curl http://localhost:8080/health
docker-compose ps
docker-compose logs --tail=20
```

**Rollback Time**: < 60 seconds target  
**Rollback Validation**: 5 minutes  
**Total Rollback Window**: < 5 minutes

---

## ✅ POST-DEPLOYMENT VALIDATION (09:00-10:00 UTC)

### 1-Hour Monitoring (09:00-10:00 UTC)

**Continuous Monitoring**:
- [ ] Error rate stable (< 0.1%)
- [ ] Latency stable (< 100ms p99)
- [ ] All containers running
- [ ] All services healthy
- [ ] No critical alerts
- [ ] Database replication healthy

**1-Hour Checks**:
- [ ] 09:15 UTC: Full metric review
- [ ] 09:30 UTC: End-to-end functionality test
- [ ] 09:45 UTC: Security scan (no new CVEs)
- [ ] 10:00 UTC: Final sign-off

### End-to-End Functionality Test
```bash
# API endpoint test
curl -X GET http://localhost:8080/api/health \
  -H "Authorization: Bearer $TOKEN" \
  -w "\nHTTP Status: %{http_code}\n"

# Database connectivity
docker exec postgres psql -U postgres -d code_server_db \
  -c "SELECT COUNT(*) as connection_test"

# Vault accessibility
vault kv get secret/database/postgres

# Metrics collection
curl http://localhost:9090/api/v1/query?query=up
```

### Sign-Off Checklist
- [ ] Team lead reviews all metrics
- [ ] No critical issues identified
- [ ] SLA targets met (99.99% availability)
- [ ] Runbook documented with actual timings
- [ ] Deployment complete stamp: ✅ APPROVED

---

## 📝 DEPLOYMENT LOG TEMPLATE

**Deployment Date**: April 18, 2026  
**Started**: 08:00 UTC  
**Completed**: _____ UTC  
**Duration**: _____ minutes  
**Status**: ✅ SUCCESS / ⚠️ PARTIAL / ❌ ROLLBACK  

### Phase Timings
| Phase | Start | End | Duration | Status | Notes |
|-------|-------|-----|----------|--------|-------|
| Pre-flight checks | 07:30 | | | | |
| Canary (1%) | 08:00 | | | | |
| Gradual (10%) | | | | | |
| Full (100%) | | | | | |
| Post-deployment | | | | | |

### Issues Encountered
1. _____
2. _____
3. _____

### Resolutions Applied
1. _____
2. _____
3. _____

### Rollback Triggers (if applicable)
- [ ] High error rate (> 1%)
- [ ] High latency (> 150ms p99)
- [ ] Service unavailability
- [ ] Database connection loss
- [ ] Vault unsealed

---

## 🚨 EMERGENCY CONTACTS

**On-Call Engineer**: [TBD]  
**Manager**: [TBD]  
**Escalation**: [TBD]  

**Communication Channel**: Slack #deployments  
**Status Updates**: Every 15 minutes during deployment  
**Post-Deployment Review**: April 18, 11:00 UTC  

---

## 📚 REFERENCES

- [PHASES-6-8-FINAL-COMPLETION.md](PHASES-6-8-FINAL-COMPLETION.md) — Readiness validation
- [PRODUCTION-STANDARDS.md](PRODUCTION-STANDARDS.md) — Production compliance
- [docker-compose.production.yml](docker-compose.production.yml) — Production config
- [CONTRIBUTING.md](CONTRIBUTING.md) — Deployment procedures

---

**Status**: ✅ READY FOR APRIL 18 DEPLOYMENT  
**Approval**: Pending April 17 final review  
**Last Updated**: April 15, 2026  
