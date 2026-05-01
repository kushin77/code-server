# Deployment Validation Checklist

**Purpose**: Ensure production deployments meet all quality, security, and operational requirements  
**Scope**: All code-server deployments to 192.168.168.31 (primary) and 192.168.168.42 (replica)  
**Frequency**: Before every production deployment

---

## Pre-Deployment (Code Review)

### Code Quality
- [ ] All commits are squashed or rebased (clean history)
- [ ] Commit messages follow convention: `type(scope): description`
- [ ] No hardcoded credentials, API keys, or passwords
- [ ] No debugging code left (console.log, pdb, print statements in loops)
- [ ] All new functions have docstrings/comments
- [ ] Test coverage for new features ≥ 80%

### Configuration
- [ ] All variables sourced from `.env.*` files (never hardcoded)
- [ ] `.env.base` updated with canonical defaults
- [ ] Changes respect environment hierarchy (base → infrastructure → deployment → cluster → production)
- [ ] No duplicate variable definitions across `.env.*` files
- [ ] Configuration validated:
  ```bash
  source .env.base && source .env.infrastructure && \
  source .env.deployment && source .env.cluster && \
  source .env.production
  echo "Variables loaded: $(set | wc -l)"
  ```

### Docker Composition
- [ ] `docker-compose config --quiet` returns no errors
- [ ] All image tags are pinned (no `:latest`, no unversioned tags)
- [ ] Images use `@sha256:` digests where possible
- [ ] Resource limits set appropriately:
  - CPU: limits=4, reservations=2 (or higher if justified)
  - Memory: appropriate for service (db=8gb, cache=6gb, etc.)
- [ ] Profiles correctly configured (gpu, vault, minio, override)
- [ ] Port mappings don't conflict with system ports
- [ ] Health checks defined for all critical services

### Dependencies
- [ ] npm/pip dependencies audited: `npm audit`, `pip check`
- [ ] No high/critical vulnerabilities
- [ ] All dependency updates are from approved versions
- [ ] Dependabot/Renovate PRs merged and tested

### Documentation
- [ ] Changes documented in relevant `.md` files
- [ ] README updated if deployment procedure changed
- [ ] CHANGELOG entry added
- [ ] Operations team notified of any manual steps

---

## Pre-Deployment (Automation)

### CI/CD Validation
- [ ] All GitHub Actions workflows pass:
  - [ ] Syntax validation
  - [ ] Image pin validation
  - [ ] Health check tests
  - [ ] Docker compose idempotency
  - [ ] Template enforcement
- [ ] No warnings in workflow logs
- [ ] Deployment artifacts built and staged

### Security Checks
- [ ] Container images scanned for vulnerabilities
  ```bash
  docker scan <image>  # No high/critical issues
  ```
- [ ] Network policies validated
- [ ] TLS certificates valid (check expiry)
- [ ] Secrets not exposed in logs/configs
- [ ] OPA policies current and enforced

### Database Checks
- [ ] Database migrations reviewed and tested
- [ ] Schema changes backward-compatible
- [ ] Backup exists and tested before migrations
- [ ] Replication lag acceptable (< 1 second)

---

## Pre-Deployment (Manual Verification)

### Environment Verification

**Primary Node (192.168.168.31)**
```bash
✓ SSH access verified
✓ Docker daemon running: docker ps -q | wc -l
✓ Disk space available: df -h / | grep -v Filesystem
✓ Network connectivity: ping 192.168.168.42 && echo "✅ Can reach replica"
✓ NAS mounted: mount | grep /mnt/nas
✓ Latest code pulled: git status shows "On branch X, Your branch is ahead by N commits"
```

**Replica Node (192.168.168.42)**
```bash
✓ SSH access verified
✓ Docker daemon running
✓ Disk space available
✓ Network connectivity to primary
✓ Replication status: SELECT slot_name FROM pg_replication_slots;
```

### Service Dependency Check
```bash
# Verify all services can start (test on staging first)
docker compose up -d
sleep 30
docker compose ps | grep -E "Up|Exited"

# All should show "Up". If any show "Exited", check logs:
docker compose logs <service-name> | tail -20
```

### Backup Verification
```bash
✓ Latest backup exists: ls -lt /mnt/nas/backups/daily/ | head -1
✓ Backup size reasonable: du -sh /mnt/nas/backups/daily/postgres-latest.dump
✓ Backup timestamp recent: [ $(( $(date +%s) - $(stat -c %Y /mnt/nas/backups/daily/postgres-latest.dump) )) -lt 86400 ] && echo "✅ Within 24 hours"
```

---

## Deployment Phase

### Primary Node Deployment

**Step 1: Pre-deployment Snapshot**
```bash
✓ Record current state:
  - docker compose ps > /tmp/pre-deployment-ps.txt
  - docker images > /tmp/pre-deployment-images.txt
  - du -s /var/lib/docker/volumes/*/data > /tmp/pre-deployment-volumes.txt
  - Current git commit: git rev-parse HEAD > /tmp/pre-deployment-commit.txt
```

**Step 2: Load Configuration**
```bash
✓ source .env.base
✓ source .env.infrastructure
✓ source .env.deployment
✓ source .env.cluster
✓ source .env.production
✓ Verify critical variables:
  - [ ] APEX_DOMAIN is set
  - [ ] DATABASE_HOST is set
  - [ ] REDIS_HOST is set
  - [ ] No variable is empty (grep "=$" .env.*)
```

**Step 3: Stop Services (Graceful)**
```bash
✓ docker compose down --timeout=60
✓ Wait 10 seconds: sleep 10
✓ Verify stopped: docker compose ps | grep -c "Up" == 0
```

**Step 4: Apply Changes**
```bash
✓ git pull origin main
✓ docker compose config --quiet (validate syntax)
✓ docker compose pull (update images)
✓ docker compose up -d
✓ Wait for stabilization: sleep 60
```

**Step 5: Post-Deployment Verification**
```bash
✓ All services running: docker compose ps | grep -c "Up" >= 20
✓ No services restarting: docker compose ps | grep -v "Up" | wc -l <= 1
✓ Logs look healthy:
  - docker compose logs --tail=50 | grep -i "error" | wc -l <= 2 (some errors OK, excessive ones not)
  - docker compose logs --tail=50 | grep -i "fatal" | wc -l == 0
```

**Step 6: Health Checks**
```bash
✓ Database responsive:
  docker compose exec -T code-server-postgres psql -U postgres -c "SELECT 1;"

✓ Redis responsive:
  docker compose exec -T code-server-redis redis-cli ping

✓ Application endpoints:
  curl -s http://localhost:8000/health | grep -q "ok"
  curl -s http://localhost:3000/api/health | grep -q "UP"

✓ API gateway responsive:
  curl -s http://192.168.168.31:8000/health
```

### Replica Node Deployment

**Repeat Steps 1-6 for replica node (192.168.168.42)**
```bash
ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && ...'
```

---

## Post-Deployment Validation

### Immediate Checks (0-5 minutes)

```bash
✓ Application dashboard accessible: open https://192.168.168.31:3000
✓ API responding: curl -s http://192.168.168.250/health | jq .
✓ User actions working:
  - [ ] Can login
  - [ ] Can create resource
  - [ ] Can execute query
  - [ ] Can view logs
✓ No error spikes in monitoring:
  - Prometheus: rate(errors_total[5m]) < 0.01
  - Grafana: No red alerts
  - Loki: No spike in error logs
```

### Extended Checks (5-30 minutes)

```bash
✓ Database replication steady:
  SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;
  
✓ Cache working:
  docker compose exec code-server-redis redis-cli INFO stats | grep -E "total_commands|keyspace_hits"

✓ Message queue processing:
  docker compose logs code-server-event-bus | grep -i "processed\|consuming"

✓ Performance baseline:
  - Page load time < 2 seconds
  - API response time p95 < 500ms
  - Database query time p95 < 100ms
```

### Monitoring (30 minutes - 2 hours)

```bash
✓ Resource utilization normal:
  - CPU: < 60% for most services, < 80% peak acceptable
  - Memory: < 80% for all services, no OOM kills
  - Disk: < 70% for /var/lib/docker
  
✓ No degraded services:
  - Check metrics for all services
  - Verify SLO compliance (availability > 99.9%)
  
✓ Logs reviewed for anomalies:
  - No repeated errors
  - No performance warnings
  - No security warnings
  
✓ Notify ops team:
  - Deployment completed successfully
  - Link to monitoring dashboard
  - Notable changes/improvements
```

---

## Rollback Procedures

### Immediate Rollback (Within 30 minutes)

**If any critical issue detected:**

```bash
# Step 1: Stop current deployment
docker compose down

# Step 2: Revert code
git revert HEAD --no-edit

# Step 3: Restart with previous version
docker compose pull
docker compose up -d

# Step 4: Verify
sleep 30
docker compose ps | grep -c "Up"
curl http://localhost:8000/health
```

### Partial Rollback (Specific Services)

```bash
# If only specific service failed:
docker compose restart <service-name>

# Or rollback just that service:
docker compose up -d <service-name>  # Uses previous version
```

### Database Rollback

```bash
# If migrations failed, restore from backup:
docker compose down
docker compose exec code-server-postgres pg_restore -U postgres \
  -C < /mnt/nas/backups/daily/postgres-latest.dump
docker compose up -d
```

---

## Sign-Off Checklist

- [ ] Deployment lead reviewed all checks
- [ ] Primary node validated
- [ ] Replica node validated
- [ ] Post-deployment checks passed
- [ ] Monitoring shows stable metrics
- [ ] Ops team notified
- [ ] Incident response team on standby (for critical deployments)
- [ ] Runbook updated if procedures changed
- [ ] Deployment logged with timestamp and git commit

**Deployment Lead**: _______________________  
**Date/Time**: _______________________  
**Git Commit**: _______________________  
**Issues**: _______________________  
**Notes**: _______________________

---

## Quick Reference

**Abort Deployment**:
```bash
docker compose down && git revert HEAD --no-edit && docker compose up -d
```

**Check Service Status**:
```bash
docker compose ps && docker compose logs --tail=20
```

**View Monitoring**:
```bash
open https://192.168.168.31:9090  # Prometheus
open https://192.168.168.31:3000  # Grafana
```

**Emergency Contacts**:
- On-Call Engineer: [Phone/Email]
- Engineering Lead: [Phone/Email]
- Escalation: [Manager]

---

**Document Version**: 1.0  
**Last Updated**: April 30, 2026  
**Status**: ✅ Production Ready
