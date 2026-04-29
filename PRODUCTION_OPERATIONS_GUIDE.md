# Phase 14-16: Production Operations Guide

**Date:** April 29, 2026  
**Status:** Production Deployment Phase  
**Audience:** DevOps, Site Reliability Engineers, Operations Team  

## Platform Status Summary

```
DEPLOYMENT TIER               SERVICES    NODES    CONTAINERS
────────────────────────────  ────────    ─────    ──────────
Phase 12: Infrastructure        22+        2        50+
Phase 13: Applications (Core)     6        2        12
Phase 14: Applications (Exp.)    10        2        20
────────────────────────────────────────────────────────────
TOTAL                            38        2        128+
```

## Quick Command Reference

### Health Check (1 minute)

```bash
# SSH to primary
ssh akushnir@192.168.168.31

# Container health
docker ps -a | grep "Exited\|Restarting" && echo "⚠️  Issues detected" || echo "✅ All healthy"

# Services running
docker ps | wc -l; echo "containers running"

# Database check
docker exec code-server-postgres psql -U postgres -c "SELECT 'DB OK';" 2>/dev/null || echo "⚠️  DB issue"

# Redis check
docker exec code-server-redis redis-cli PING 2>/dev/null || echo "⚠️  Redis issue"

exit
```

### Service Restart

```bash
# SSH to node where service is running
ssh akushnir@192.168.168.31
cd ~/code-server-enterprise-ops

# Restart single service
docker restart code-server-api-service

# Restart all Phase 13 services
docker restart code-server-*-service

# Full stack restart (causes brief outage)
docker-compose -f docker-compose.full-stack.yml restart

exit
```

### View Logs

```bash
# Live logs for service
docker logs -f code-server-api-service

# Recent logs (last 100 lines)
docker logs --tail 100 code-server-api-service

# Errors only
docker logs code-server-api-service 2>&1 | grep ERROR
```

## Monitoring & Alerts

### Key Metrics (Check via Grafana)

**Access:** http://192.168.168.31:3000

Dashboard Categories:
1. **Infrastructure**: CPU, Memory, Network, Disk
2. **Applications**: Error rate, Response time, Throughput
3. **Database**: Connections, Query latency, Replication
4. **Business**: Transactions, Users, Revenue metrics

### Alert Thresholds

```
ALERT LEVEL          METRIC                  THRESHOLD
─────────────        ──────────────────      ──────────
🔴 CRITICAL          Node Down               Any node unreachable
🔴 CRITICAL          API Error Rate          >10%
🔴 CRITICAL          Database Unavailable    >1 minute
🟠 WARNING           CPU Utilization         >80%
🟠 WARNING           Memory Utilization      >85%
🟠 WARNING           Error Rate              >5%
🟠 WARNING           Response Time (p95)     >1000ms
```

## Common Operations

### Deployment Procedures

**1. Deploy New Service Version**

```bash
# Prepare
ssh akushnir@192.168.168.31
docker pull registry.kushnir.cloud:5000/service:v2.0

# Perform blue-green update
docker tag registry.kushnir.cloud:5000/service:v2.0 service:v2.0
docker stop code-server-service
docker run -d --name code-server-service-new ... # with v2.0
# Test new version
# If good: remove old, rename new
# If bad: restart old version

docker start code-server-service
exit
```

**2. Scale Application (Add More Instances)**

```bash
# Create new compose file for additional services
docker-compose -f docker-compose.phase-15-scaling.yml up -d

# Verify
docker ps | grep "code-server" | wc -l
```

**3. Database Maintenance**

```bash
# Backup
docker exec code-server-postgres pg_dump app_db | gzip > /backups/db-$(date +%Y%m%d).sql.gz

# Optimize tables
docker exec code-server-postgres psql -U postgres app_db -c "VACUUM ANALYZE;"

# Reindex
docker exec code-server-postgres psql -U postgres app_db -c "REINDEX DATABASE app_db;"
```

## Incident Response Matrix

```
SYMPTOM                          ROOT CAUSE                SOLUTION
─────────────────────────────   ───────────────────────   ──────────────────
Service error rate spike        Memory/CPU exhaustion     Restart service
All APIs return 500              Database down             Check DB, restart
High latency on all requests    Network congestion        Check network, scale
Single node unavailable         Node failure              Failover to replica
Data replication lag            Network slowness          Check network link
Disk space running out          Log accumulation          Archive/prune logs
```

## Change Management

### Before Making Changes

1. **Notify stakeholders** (send status update)
2. **Backup current state** (git commit, database backup)
3. **Document changes** (update runbook)
4. **Test on non-prod** (if possible)
5. **Schedule maintenance window** (if impact expected)

### During Changes

1. **Monitor Grafana** (watch metrics real-time)
2. **Keep communication open** (status updates)
3. **Track changes** (git commits)
4. **Have rollback plan** (be ready to revert)

### After Changes

1. **Verify success** (health checks)
2. **Document results** (update runbook)
3. **Communicate completion** (notify stakeholders)
4. **Schedule follow-up** (if issues to monitor)

## Scheduled Maintenance

### Daily (Automated)
- Database backup at 02:00 UTC
- WAL archiving (hourly)
- Redis backup at 03:00 UTC
- Config backup at 04:00 UTC

### Weekly (Manual - Monday 2am UTC)
- Review backup completion
- Check disk space
- Verify replication health
- Review error logs

### Monthly (Manual - 1st of month 3am UTC)
- Capacity analysis
- Performance tuning
- Security review
- Disaster recovery drill (quarterly)

## Escalation Tree

**Tier 1:** Platform On-Call
- Response: 15 minutes
- Authority: Restart services, reboot containers
- Cannot: Modify databases, delete data

**Tier 2:** Platform Lead
- Response: 30 minutes
- Authority: All Tier 1 + database operations
- Cannot: Modify core infrastructure

**Tier 3:** DevOps Lead
- Response: 1 hour
- Authority: All operational decisions
- Can: Infrastructure changes, emergency procedures

**Tier 4:** CTO/Executive
- Response: As needed
- Authority: Executive decisions
- Consulted for: Critical incidents, data loss

## Success Metrics

### Availability
- Target: 99.9% uptime
- Acceptable: 99.5% uptime
- Measured: Monthly rolling basis

### Performance
- API response p95: <200ms (target), <500ms (acceptable)
- Error rate: <0.1% (target), <1% (acceptable)
- Zero data loss (non-negotiable)

### Recovery
- Mean Time to Detect (MTTD): <5 minutes
- Mean Time to Recovery (MTTR): <15 minutes
- Recovery Point Objective (RPO): <1 hour

## Contact & Resources

**Operations Team Contacts:**
- On-Call Rotation: [Slack channel: #ops-oncall]
- Platform Team: [platform@kushnir.cloud]
- Infrastructure: [infra-team@kushnir.cloud]

**Documentation:**
- Architecture: DOCKER_COMPOSE_ARCHITECTURE_GUIDE.md
- Deployment: DEPLOYMENT_MANIFEST.md
- Phase Reports: PHASE_13_APPLICATION_DEPLOYMENT.md, PHASE_14_EXPANSION_REPORT.md

**External Resources:**
- Docker Documentation: https://docs.docker.com/
- PostgreSQL Docs: https://www.postgresql.org/docs/
- Prometheus Docs: https://prometheus.io/docs/
- Grafana Docs: https://grafana.com/docs/

---

**Ready for Operations Handoff**  
**Phase 14B: Production Hardening (TLS, Monitoring, Backups)**  
**Phase 15: Advanced Features (Service Mesh, Auto-scaling)**  
**Phase 16: Operations Transition (Week 4)**
