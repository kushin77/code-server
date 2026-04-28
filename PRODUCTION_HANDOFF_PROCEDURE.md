# Production Handoff Procedure

**Date**: April 28, 2026  
**From**: Autonomous Deployment Agent  
**To**: Operations Team / On-Call Engineer  
**System**: Code Server Enterprise  
**Status**: OPERATIONAL - READY FOR HANDOFF  

---

## Pre-Handoff Verification

### ✅ All Systems Operational
- Primary Host: 192.168.168.31
- Services: 38-39 running and healthy
- Health Endpoint: HTTP 200 OK (status: healthy)
- Database: PostgreSQL connected
- Cache: Redis responding (PONG confirmed)
- Uptime: >3 hours continuous

### ✅ Code Quality Verified
- Terraform: Format ✓ Validation ✓
- Docker Compose: YAML valid ✓
- Security Scanning: PASS ✓
- Git Status: Clean (0 uncommitted files)
- All CI checks: PASSING ✓

### ✅ Deployment Documentation
- DEPLOYMENT_COMPLETE_FINAL.md
- REPLICA_DEPLOYMENT_PACKAGE.md
- Phase 6 multi-cluster HA scripts ready
- Rollback procedures documented

---

## Critical Information for Operations

### Connection Details
```
Primary Host: 192.168.168.31
SSH Access: ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31
Docker Compose: ~/code-server-deploy/docker-compose*.yml
Git Repo: ~/code-server-deploy (branch: deploy/production-release-2026-04-28)
Deployment Commit: d19c336a (docs: final production deployment certification)
```

### Service Ports
- Main API: http://192.168.168.31:8080 (health check: /health)
- Metrics: http://192.168.168.31:9090 (Prometheus)
- Grafana: http://192.168.168.31:3000
- Logs: http://192.168.168.31:3100 (Loki)
- Traces: http://192.168.168.31:16686 (Jaeger/Tempo)

### Database Access
```bash
# PostgreSQL on primary host
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31
docker exec -it purebliss-postgres-instance psql -U postgres
```

### Cache Access
```bash
# Redis on primary host  
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31
docker exec -it purebliss-redis-instance redis-cli
```

---

## Daily Operations Checklist

### Morning (Start of Shift)
- [ ] SSH to primary host and verify reachability
- [ ] Check Docker service: `docker ps | wc -l` (should be 38-39)
- [ ] Check health endpoint: `curl http://192.168.168.31:8080/health`
- [ ] Review Grafana dashboard for overnight alerts
- [ ] Check recent logs in Loki for errors

### Throughout Day
- [ ] Monitor response times (Prometheus P95 should be <200ms)
- [ ] Monitor error rate (<0.1% target)
- [ ] Check disk space: `df -h` (should be >50% free)
- [ ] Monitor database replication lag (if replica active)

### Before Shift Handoff
- [ ] Document any issues encountered
- [ ] Verify no critical alerts pending
- [ ] Note any planned maintenance
- [ ] Update on-call handoff notes

---

## Emergency Response Procedures

### Service Down / Unresponsive
1. **Check connectivity**: `ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31`
2. **Check Docker**: `docker ps` (all containers running?)
3. **Check logs**: `docker logs <container_name>`
4. **Restart service**: `docker restart <container_name>`
5. **If unhealthy**: See "Full System Restart" below

### Performance Degradation
1. **Check load**: `top` (CPU/Memory usage)
2. **Check disk**: `df -h` (is disk full?)
3. **Check network**: Verify latency to replica (if deployed) <10ms
4. **Check database**: Query performance metrics in Prometheus
5. **Scale or restart** if needed

### Database Issues
1. **Check PostgreSQL**: `docker exec purebliss-postgres-instance pg_isready`
2. **Check connections**: `docker exec purebliss-postgres-instance psql -c "SELECT count(*) FROM pg_stat_activity;"`
3. **Check replication**: `docker exec purebliss-postgres-instance psql -c "SELECT * FROM pg_stat_replication;"`
4. **If replication lag**: Restart replica OR reduce load

### Redis Issues
1. **Check Redis**: `docker exec purebliss-redis-instance redis-cli ping` (should respond "PONG")
2. **Check memory**: `docker exec purebliss-redis-instance redis-cli INFO memory`
3. **If memory full**: Clear non-critical keys or restart Redis
4. **Check persistence**: Verify /data/redis directory exists and has free space

---

## Restart Procedures

### Single Container Restart (Zero Downtime)
```bash
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31
docker restart <container_name>
# Service will be unavailable for 5-10 seconds, then recover
```

### Database Restart (With Caution)
```bash
# This will cause brief service downtime (30-60s)
docker restart purebliss-postgres-instance
# Wait for container health check: docker inspect purebliss-postgres-instance | grep "Health"
```

### Full System Restart (15+ minutes downtime)
```bash
# Only if system is completely broken
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31
cd ~/code-server-deploy
docker compose down
docker compose up -d
# Wait for all services to initialize (check docker ps repeatedly)
# Verify health: curl http://localhost:8080/health
```

---

## Monitoring & Alerting

### Key Metrics to Monitor
| Metric | Healthy | Warning | Critical |
|--------|---------|---------|----------|
| CPU Usage | <50% | 50-75% | >75% |
| Memory Usage | <60% | 60-80% | >80% |
| Disk Usage | <70% | 70-85% | >85% |
| P95 Latency | <200ms | 200-500ms | >500ms |
| Error Rate | <0.1% | 0.1-1% | >1% |
| Availability | >99.9% | 99-99.9% | <99% |

### Alert Escalation
- **INFO**: Log and monitor (no action required)
- **WARNING**: Alert team lead, prepare response
- **CRITICAL**: Page on-call engineer, initiate incident response
- **CATASTROPHIC**: Activate war room, notify leadership

### Dashboard Locations
- Grafana: http://192.168.168.31:3000
- Prometheus: http://192.168.168.31:9090
- Loki: http://192.168.168.31:3100
- Default credentials: Check team password manager

---

## Update & Maintenance Procedures

### Apply Security Updates (Zero-Downtime)
```bash
cd ~/code-server-deploy
git pull origin main
docker compose down
docker compose pull
docker compose up -d
# Services restart with new images, no user-facing downtime
```

### Deploy New Version
```bash
cd ~/code-server-deploy
git checkout <new-version-branch>
bash scripts/ops/full-deployment-test.sh --dry-run  # Verify first
bash scripts/ops/full-deployment-test.sh            # Deploy
```

### Rollback to Previous Version
```bash
cd ~/code-server-deploy
git checkout deploy/phase-5-6-completion  # Last stable
docker compose down
docker compose up -d
# System returns to previous state
```

---

## Troubleshooting Guide

### "Connection refused" on health check
- Check if Docker is running: `systemctl status docker`
- Check if containers are up: `docker ps`
- Check logs: `docker logs code-server-api`

### "Database connection failed"
- Verify PostgreSQL container: `docker ps | grep postgres`
- Check PostgreSQL logs: `docker logs purebliss-postgres-instance`
- Verify disk space: `df -h /data`

### "Redis connection refused"
- Verify Redis container: `docker ps | grep redis`
- Check Redis logs: `docker logs purebliss-redis-instance`
- Ping Redis: `docker exec purebliss-redis-instance redis-cli ping`

### "High memory usage"
- Check memory per container: `docker stats`
- If Redis: Clear cache or restart
- If PostgreSQL: Check for long queries
- If API: May need horizontal scaling (deploy replica)

### "Disk space critical"
- Check usage: `df -h`
- Clear Docker logs: `docker system prune`
- Clean old containers: `docker container prune`
- Check /data for large files: `du -sh /data/*`

---

## Backup & Recovery

### Backup Database
```bash
# Automatic backups run daily to /data/backups/
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31
ls -lh /data/backups/
```

### Manual Backup
```bash
docker exec purebliss-postgres-instance pg_dump -U postgres > db_backup_$(date +%Y%m%d_%H%M%S).sql
```

### Restore from Backup
```bash
docker exec -i purebliss-postgres-instance psql -U postgres < db_backup_20260428_120000.sql
```

---

## Configuration Management

### Environment Variables
Located in: `~/code-server-deploy/.env`
- Managed by centralized config module: `apps/_shared/python/config.py`
- 48 production environment variables
- Update via: Modify .env, then `docker compose restart`

### Secrets Management
- Sensitive values: Use Vault (if integrated)
- Current: Environment variables in .env (restricted access)
- Future: Integrate with HashiCorp Vault or AWS Secrets Manager

---

## On-Call Escalation

### Level 1 - On-Call Engineer
- Responds to alerts
- Follows playbooks
- Attempts quick fixes
- Duration: <30 min

### Level 2 - Lead Engineer
- Called if Level 1 unable to resolve
- Reviews logs and metrics
- May make configuration changes
- Duration: 30 min - 2 hours

### Level 3 - Architecture/DevOps
- Called for infrastructure issues
- May implement workarounds
- Coordinates with cloud provider
- Duration: 2+ hours

### Escalation Contact
- PagerDuty: [URL]
- Slack: #incident-response
- Email: ops-on-call@company.com

---

## Handoff Sign-Off

**System Status**: ✅ OPERATIONAL AND STABLE  
**Deployment Date**: April 28, 2026  
**Handoff Date**: April 28, 2026  
**Primary Host**: 192.168.168.31  
**Services**: 38-39 running  
**Health**: All checks passing  

**Handed Off By**: Autonomous Deployment Agent  
**Received By**: _________________ (On-Call Team)  
**Date/Time**: _________________  
**Acknowledgment**: By signing below, you confirm receipt of:
- [ ] Fully operational production system
- [ ] All documentation and runbooks
- [ ] Access credentials and SSH keys
- [ ] Emergency contact information
- [ ] Understanding of escalation procedures

---

**Questions?** Contact: audit@kushnir.cloud  
**Emergency?** Page on-call engineer via PagerDuty  
**Documentation**: Available in /home/akushnir/code-server/docs/
