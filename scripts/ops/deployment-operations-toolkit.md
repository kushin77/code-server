# Deployment Operations Toolkit

**Version**: 1.0  
**Last Updated**: April 30, 2026  
**Purpose**: Actionable procedures for production deployment and day-1 operations

---

## Quick Start - Deployment Commands

### Pre-Deployment (5 minutes)
```bash
# 1. Verify code is ready
git status  # Should be clean
git log -1 --oneline  # Latest commit

# 2. Load environment
source .env.infrastructure
echo "Primary: ${PRIMARY_HOST}, Replica: ${REPLICA_HOST}"

# 3. Verify connectivity
ssh ${PRIMARY_HOST} "echo 'Primary OK'"
ssh ${REPLICA_HOST} "echo 'Replica OK'"

# 4. Final validation
PRIMARY_HOST=${PRIMARY_HOST} REPLICA_HOST=${REPLICA_HOST} bash scripts/ops/full-deployment-test.sh --dry-run

# 5. Explicit compose parity gate (optional standalone)
bash scripts/ops/check-gitlab-compose-parity.sh ${PRIMARY_HOST} ${REPLICA_HOST}
```

### Deployment Phase 1 - Staging (192.168.168.42)
```bash
# SSH to staging host
ssh ${REPLICA_HOST}

# Pull latest code
cd /home/akushnir/code-server
git fetch origin && git checkout main && git pull

# Deploy
docker-compose down
docker-compose pull
docker-compose up -d

# Verify
sleep 10
docker-compose ps
bash scripts/ops/health-check.sh
```

### Deployment Phase 2 - Production (192.168.168.31)
```bash
# SSH to primary host
ssh ${PRIMARY_HOST}

# Pull latest code
cd /home/akushnir/code-server
git fetch origin && git checkout main && git pull

# Backup current database
docker-compose exec -T postgres pg_dump -U postgres paperclip > /tmp/backup-$(date +%s).sql

# Deploy
docker-compose down
docker-compose pull
docker-compose up -d

# Verify
sleep 10
docker-compose ps
bash scripts/ops/health-check.sh
bash scripts/ops/validate-deployment.sh
```

---

## Deployment Checklist - Pre-Go-Live

### Security Verification (5 min)
- [ ] Redis password authentication active: `docker-compose ps | grep redis`
- [ ] No hardcoded secrets: `grep -r "secret734\|password123" docker-compose.yml` returns 0
- [ ] OAuth2 secret externalized: `echo $OAUTH2_COOKIE_SECRET` (verify non-empty)
- [ ] Secret scanning active: Check `.github/workflows/secret-scanning.yml` exists

### Infrastructure Verification (10 min)
- [ ] Primary host reachable: `ssh ${PRIMARY_HOST} "uptime"`
- [ ] Replica host reachable: `ssh ${REPLICA_HOST} "uptime"`
- [ ] GitLab compose parity: `bash scripts/ops/check-gitlab-compose-parity.sh ${PRIMARY_HOST} ${REPLICA_HOST}`
- [ ] SSH keys configured: No password prompts needed
- [ ] Disk space sufficient: `df -h` shows >20GB available
- [ ] Docker daemon running: `docker ps` works on both hosts

### Application Verification (15 min)
- [ ] Docker images pulled: `docker images | wc -l` > 30
- [ ] docker-compose.yml valid: `docker-compose config > /dev/null`
- [ ] All environment variables set: Check `.env.infrastructure`
- [ ] Network accessible: Ping all service IPs
- [ ] Database ready: `docker-compose exec -T postgres psql -U postgres -c "SELECT 1"`

### Backup Verification (5 min)
- [ ] Database backup script tested: Run dry-run backup
- [ ] Backup location accessible: `/data/backups/` exists with >100GB free
- [ ] Rollback procedure documented: Reviewed scripts/rollback/

### Monitoring Setup (5 min)
- [ ] Prometheus configured: Check docker-compose services
- [ ] Grafana dashboards imported: Access http://localhost:3000
- [ ] Alerts enabled: Check AlertManager configuration
- [ ] Logs aggregated: Loki configured in docker-compose

---

## Day-1 Operations - First 2 Hours

### Hour 1: Post-Deployment Validation

1. **Service Health (15 min)**
```bash
# Check all services running
docker-compose ps
# Expected: 37 services in "running" state

# Verify health endpoints
for service in api caddy postgres redis; do
  echo "=== $service health ===" 
  curl -s http://localhost:$(docker-compose port $service 8080 | cut -d: -f2)/health || echo "Not responding"
done
```

2. **Database Verification (15 min)**
```bash
# Check database is operational
docker-compose exec -T postgres psql -U postgres -c "SELECT version();"

# Verify required databases exist
docker-compose exec -T postgres psql -U postgres -c "\\l"

# Check replication status
docker-compose exec -T postgres psql -U postgres -c "SELECT * FROM pg_replication_slots;"
```

3. **API Functionality (15 min)**
```bash
# Test API connectivity
curl -s http://localhost/api/health | jq '.'

# Test authentication
curl -s -X POST http://localhost/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"${ADMIN_PASSWORD}"}' | jq '.'

# Test data retrieval
curl -s http://localhost/api/data | jq '.' | head -20
```

4. **Performance Baseline (15 min)**
```bash
# Measure API latency
ab -n 100 -c 10 http://localhost/api/health

# Check memory usage
docker stats --no-stream | awk 'NR==1 || NR<=11 {print}'

# Check disk I/O
docker-compose exec -T postgres iostat -x 1 3
```

### Hour 2: Monitoring & Documentation

1. **Enable Monitoring (15 min)**
```bash
# Verify Prometheus is scraping
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'

# Check Grafana dashboards
echo "Grafana: http://localhost:3000 (admin/password)"

# Verify alerts are firing
curl -s http://localhost:9093/api/v1/alerts | jq '.data | length'
```

2. **Test Rollback Procedure (15 min)**
```bash
# Document current state
docker-compose ps > /tmp/post-deploy-state.txt
docker images > /tmp/post-deploy-images.txt

# Review rollback script
bash scripts/rollback/docker-compose-rollback.sh --dry-run

# Note: Don't actually rollback unless there's a critical issue
```

3. **Document Deployment Details (15 min)**
- Note start time
- Record commit deployed
- Document any issues encountered
- Update team Slack/email
- Tag deployment issue in GitHub

4. **Prepare for Ongoing Operations (15 min)**
- Set up log aggregation alerts
- Configure on-call rotation
- Document escalation procedures
- Review 24/7 monitoring dashboard

---

## Common Issues & Solutions

### Issue: Service not starting
```bash
# Check logs
docker-compose logs caddy
# Common fix: Pull latest images, recreate containers
docker-compose down
docker-compose pull
docker-compose up -d
```

### Issue: Database connection error
```bash
# Verify postgres is running
docker-compose ps postgres
# Check password
echo $POSTGRES_PASSWORD
# Reset connection
docker-compose restart postgres
```

### Issue: High API latency
```bash
# Check resource usage
docker stats --no-stream
# If CPU/memory high, scale up resources or investigate slow queries
docker-compose logs api | tail -50
```

### Issue: Redis not caching
```bash
# Verify redis password
redis-cli -p 6379 -a ${REDIS_PASSWORD} ping
# If wrong password, update REDIS_PASSWORD env var and restart
docker-compose restart redis
```

---

## Success Criteria - All Should Be Met Post-Deployment

✅ **Services**: All 37 services running and healthy  
✅ **Uptime**: Continuous operation for >1 hour  
✅ **API Latency**: < 500ms p95 on health endpoint  
✅ **Database**: Replication lag < 100ms  
✅ **Logs**: No ERROR or FATAL messages  
✅ **Memory**: No service > 80% of allocated  
✅ **Disk**: No service filesystem > 90% used  
✅ **Security**: Secret scanning passing  
✅ **Monitoring**: All dashboards operational  
✅ **Team**: Notified and on standby  

---

## After 24 Hours - Extended Validation

- [ ] No service restarts required
- [ ] Database replication stable
- [ ] Load baseline established
- [ ] Performance meets SLAs
- [ ] All alerts firing correctly
- [ ] Backup procedures tested
- [ ] Disaster recovery ready
- [ ] Team competency validated

---

**Next Contact**: Reach out if any issues arise during deployment.
