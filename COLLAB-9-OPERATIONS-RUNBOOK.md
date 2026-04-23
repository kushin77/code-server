# COLLAB-9 PRODUCTION OPERATIONS RUNBOOK

**Version**: 1.0  
**Date**: April 24, 2026  
**Status**: Ready for Production  

---

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [Deployment](#deployment)
3. [Monitoring](#monitoring)
4. [Troubleshooting](#troubleshooting)
5. [Incident Response](#incident-response)
6. [Maintenance](#maintenance)
7. [Rollback Procedures](#rollback-procedures)

---

## Quick Reference

### Service URLs

| Component | Replica 1 | Replica 2 |
|-----------|-----------|----------|
| Health Probe | http://192.168.168.31:3000/health | http://192.168.168.42:3000/health |
| Metrics | http://192.168.168.31:3000/metrics/github-task-sync | http://192.168.168.42:3000/metrics/github-task-sync |
| Audit Logs | http://192.168.168.31:3000/audit/events | http://192.168.168.42:3000/audit/events |
| WebSocket | ws://192.168.168.31:3000/ws/task-sync | ws://192.168.168.42:3000/ws/task-sync |

### SSH Shortcuts

\`\`\`bash
# Login to replicas
ssh akushnir@192.168.168.31
ssh akushnir@192.168.168.42

# Check container status
docker compose ps

# View logs
docker compose logs -f backend

# Restart services
docker compose restart

# Stop/start services
docker compose down
docker compose up -d
\`\`\`

### Critical Endpoints

\`\`\`bash
# Quick health check
curl http://192.168.168.31:3000/health/ready

# View metrics
curl http://192.168.168.31:3000/metrics/github-task-sync | jq .

# View active alerts
curl http://192.168.168.31:3000/health/alerts | jq .

# Query recent errors
curl http://192.168.168.31:3000/audit/errors?limit=10 | jq .
\`\`\`

---

## Deployment

### Pre-Deployment Checklist

- [ ] All code committed to main branch
- [ ] All tests passing (320+ scenarios)
- [ ] No uncommitted changes
- [ ] Replica connectivity verified
- [ ] Backup of current state (optional)

### Standard Deployment

**Automated (recommended)**:
\`\`\`bash
bash scripts/ops/collab-9-deploy.sh
\`\`\`

**Manual (step by step)**:
\`\`\`bash
# SSH to Replica 1
ssh akushnir@192.168.168.31

# Pull latest code
cd code-server-enterprise
git pull origin main

# Pull new images
docker compose pull

# Start containers
docker compose up -d

# Verify health
curl http://localhost:3000/health/ready

# Repeat for Replica 2
ssh akushnir@192.168.168.42
# ... same steps ...
\`\`\`

### Dry Run (Verify without deploying)

\`\`\`bash
bash scripts/ops/collab-9-deploy.sh --dry-run
\`\`\`

### Deployment Troubleshooting

**Issue: Git pull fails**
\`\`\`bash
# Check git status
git status

# Reset if needed
git reset --hard HEAD
git pull origin main
\`\`\`

**Issue: Docker pull fails**
\`\`\`bash
# Check Docker daemon
docker ps

# Restart Docker
sudo systemctl restart docker

# Try pull again
docker compose pull
\`\`\`

**Issue: Health check fails after deploy**
\`\`\`bash
# View container logs
docker compose logs backend

# Check if port 3000 is bound
sudo netstat -tlnp | grep 3000

# Restart container
docker compose restart backend
\`\`\`

---

## Monitoring

### Real-Time Dashboard

\`\`\`bash
bash scripts/ops/collab-9-monitoring.sh --interval 5
\`\`\`

This shows:
- Cluster status (all replicas)
- Per-replica metrics
- Active alerts
- Auto-refreshes every 5 seconds

### Manual Health Checks

**Quick status**:
\`\`\`bash
for host in 192.168.168.31 192.168.168.42; do
  echo "=== \$host ==="
  curl -s http://\$host:3000/health | jq '{status, timestamp, alerts: (.alerts | length)}'
done
\`\`\`

**Detailed metrics**:
\`\`\`bash
curl http://192.168.168.31:3000/metrics/github-task-sync | jq '.'
\`\`\`

**Prometheus metrics**:
\`\`\`bash
curl http://192.168.168.31:3000/metrics/prometheus
\`\`\`

### Key Metrics to Monitor

| Metric | Target | Alert Threshold |
|--------|--------|------------------|
| Webhook Success Rate | >95% | <90% |
| Webhook Latency (p95) | <1000ms | >1500ms |
| WebSocket Message Success | >95% | <90% |
| WebSocket Latency (p95) | <500ms | >750ms |
| Event Success Rate | >95% | <90% |
| Dedup Cache Hit Rate | >50% | <30% |

### Setting Up Prometheus Scraping

**prometheus.yml**:
\`\`\`yaml
scrape_configs:
  - job_name: 'collab-9'
    static_configs:
      - targets: ['192.168.168.31:3000', '192.168.168.42:3000']
    metrics_path: '/metrics/prometheus'
    scrape_interval: 15s
\`\`\`

---

## Troubleshooting

### Interactive Troubleshooting

\`\`\`bash
bash scripts/ops/collab-9-troubleshoot.sh [--replica IP] [--issue TYPE]
\`\`\`

Supported issues:
- \`low-success\`: Low success rate
- \`high-latency\`: High latency
- \`websocket\`: WebSocket issues
- \`resources\`: Memory/resource issues
- \`webhooks\`: Webhook failures
- \`errors\`: View recent errors
- \`health\`: Health status check

### Common Issues

#### Issue: Low Webhook Success Rate

**Symptoms**: \`webhook.successRate < 90%\`

**Diagnosis**:
\`\`\`bash
# View webhook errors
curl http://192.168.168.31:3000/audit/webhooks?limit=20 | jq '.data.events[] | select(.outcome == "failure")'

# Check for signature errors
curl http://192.168.168.31:3000/audit/events?eventType=webhook.failed_verification&limit=10
\`\`\`

**Solutions**:
1. Verify GitHub webhook secret matches \`GITHUB_WEBHOOK_SECRET\`
2. Check webhook signature verification in code
3. Verify webhook URL is reachable
4. Check server logs for parsing errors

#### Issue: High WebSocket Latency

**Symptoms**: \`websocket.latency.p95 > 750ms\`

**Diagnosis**:
\`\`\`bash
# Check active connections
curl http://192.168.168.31:3000/metrics/github-task-sync | jq '.websocket'

# Check container resources
docker stats --no-stream backend
\`\`\`

**Solutions**:
1. Check server CPU/memory usage (should be <50% memory)
2. Increase Docker container resources if needed
3. Check network latency (\`ping 192.168.168.31\`)
4. Review WebSocket processing time in audit logs

#### Issue: Memory Growth

**Symptoms**: Container memory constantly increasing

**Diagnosis**:
\`\`\`bash
# Check dedup cache size
curl http://192.168.168.31:3000/metrics/github-task-sync/deduplication | jq '.cacheSize'

# Check audit log size
ls -lh logs/audit/

# Monitor over time
watch -n 5 'docker stats --no-stream backend | tail -1'
\`\`\`

**Solutions**:
1. Verify dedup cache eviction is working (should auto-evict at 10k entries)
2. Check audit log rotation is functioning
3. Verify metrics histogram trimming (should keep last 1000 values)
4. Restart services if memory leak suspected

---

## Incident Response

### Critical Incident (All Replicas Down)

**1. Assess situation** (5 min):
\`\`\`bash
# Try to reach both replicas
for host in 192.168.168.31 192.168.168.42; do
  echo "=== \$host ==="
  curl -s http://\$host:3000/health || echo "UNREACHABLE"
done
\`\`\`

**2. SSH to primary replica** (5 min):
\`\`\`bash
ssh akushnir@192.168.168.31

# Check if containers are running
docker compose ps

# Check Docker daemon
sudo systemctl status docker

# Check available disk
df -h
\`\`\`

**3. Restart containers** (5 min):
\`\`\`bash
cd code-server-enterprise
docker compose restart

# Wait for startup
sleep 30

# Verify health
curl http://localhost:3000/health/ready
\`\`\`

**4. Repeat on secondary replica**:
\`\`\`bash
ssh akushnir@192.168.168.42
# ... same restart steps ...
\`\`\`

**5. Verify cluster health** (5 min):
\`\`\`bash
# Check both replicas are healthy
curl http://192.168.168.31:3000/health | jq '.status'
curl http://192.168.168.42:3000/health | jq '.status'

# Check metrics are being collected
curl http://192.168.168.31:3000/metrics/github-task-sync | jq '.webhook'
\`\`\`

### Major Incident (One Replica Down)

**1. Assess**:
\`\`\`bash
curl http://192.168.168.31:3000/health || echo "DOWN"
curl http://192.168.168.42:3000/health || echo "DOWN"
\`\`\`

**2. Failover to healthy replica**:
- Load balancer should automatically route traffic to healthy replica
- Verify via \`curl http://LOADBALANCER/health\`

**3. Fix failed replica**:
\`\`\`bash
ssh akushnir@DOWN_IP

# Try restart first
docker compose restart

# If that fails, check logs
docker compose logs backend

# Full restart if needed
docker compose down
docker compose up -d
\`\`\`

**4. Rejoin cluster**:
\`\`\`bash
# Verify newly restarted replica is healthy
curl http://192.168.168.31:3000/health/ready

# Load balancer will resume traffic automatically
\`\`\`

### Performance Degradation

**1. Detect**:
\`\`\`bash
curl http://192.168.168.31:3000/health | jq '.status'
# Should return "healthy" or "degraded" (not "unhealthy")
\`\`\`

**2. Diagnose**:
\`\`\`bash
# Check metrics
curl http://192.168.168.31:3000/metrics/github-task-sync | jq '.'

# View alerts
curl http://192.168.168.31:3000/health/alerts | jq '.alerts'

# Check resources
ssh akushnir@192.168.168.31 'docker stats --no-stream'
\`\`\`

**3. Mitigate**:
- If CPU high: Increase resources or reduce load
- If memory high: Monitor for leaks, restart if necessary
- If latency high: Check network, database, or processing bottleneck

---

## Maintenance

### Regular Checks (Daily)

\`\`\`bash
# Quick health check
bash scripts/ops/collab-9-monitoring.sh --interval 0 | head -30

# Check error rate (should be <5%)
curl http://192.168.168.31:3000/audit/summary | jq '.errorCount'

# Verify metrics collection
curl http://192.168.168.31:3000/metrics/github-task-sync | jq '.timestamp'
\`\`\`

### Weekly Maintenance

**1. Review audit logs**:
\`\`\`bash
# Check for patterns in errors
curl http://192.168.168.31:3000/audit/errors?limit=100 | jq '.data.events[] | .context.errorType' | sort | uniq -c | sort -rn
\`\`\`

**2. Check resource usage trends**:
\`\`\`bash
ssh akushnir@192.168.168.31 'docker stats --no-stream backend'
ssh akushnir@192.168.168.42 'docker stats --no-stream backend'
\`\`\`

**3. Review webhook delivery**:
\`\`\`bash
curl http://192.168.168.31:3000/audit/webhooks?limit=50 | jq '.data.events[] | .outcome' | sort | uniq -c
\`\`\`

### Monthly Maintenance

**1. Clean up old logs**:
\`\`\`bash
ssh akushnir@192.168.168.31 '
cd code-server-enterprise
# Archive logs older than 30 days
find logs/ -name "*.log.gz" -mtime +30 -exec rm {} \;
'
\`\`\`

**2. Review performance trends**:
\`\`\`bash
# Compare metrics across weeks
# Use Prometheus or export metrics to analytics system
\`\`\`

**3. Update documentation**:
- Review and update this runbook
- Document any operational changes
- Update runbook links if URLs change

---

## Rollback Procedures

### Rollback to Previous Commit

**1. Identify the commit to rollback to**:
\`\`\`bash
git log --oneline | head -10
# Find the commit you want to rollback to
\`\`\`

**2. Update both replicas**:
\`\`\`bash
# Replica 1
ssh akushnir@192.168.168.31
cd code-server-enterprise
git checkout COMMIT_SHA
docker compose pull
docker compose up -d

# Replica 2
ssh akushnir@192.168.168.42
cd code-server-enterprise
git checkout COMMIT_SHA
docker compose pull
docker compose up -d
\`\`\`

**3. Verify health**:
\`\`\`bash
curl http://192.168.168.31:3000/health/ready
curl http://192.168.168.42:3000/health/ready
\`\`\`

**4. Return to main**:
\`\`\`bash
# After issue is resolved
ssh akushnir@192.168.168.31
cd code-server-enterprise
git checkout main
git pull origin main
docker compose pull
docker compose up -d

# Repeat on Replica 2
\`\`\`

### Partial Rollback (Single Replica)

If only one replica is having issues:

\`\`\`bash
ssh akushnir@DOWN_IP
cd code-server-enterprise

# Rollback just that replica
git checkout LAST_GOOD_COMMIT
docker compose pull
docker compose up -d

# Verify
curl http://localhost:3000/health/ready

# When ready, rejoin cluster
git checkout main
git pull
docker compose pull
docker compose up -d
\`\`\`

---

## Contact & Escalation

| Level | Contact | Response Time |
|-------|---------|----------------|
| L1 (Operational) | On-Call Engineer | 15 min |
| L2 (Technical) | Backend Team Lead | 30 min |
| L3 (Critical) | Tech Lead | Immediate |

**Critical Indicators for Escalation**:
- All replicas down (P0)
- Data loss suspected (P0)
- Security breach (P0)
- >50% error rate (P1)
- Service unavailable >30 min (P1)

---

## Appendix: Command Reference

### Health Checking
\`\`\`bash
# Single line health check
curl -s http://192.168.168.31:3000/health/ready | jq '.status'

# Full health report
curl -s http://192.168.168.31:3000/health | jq '.'

# Kubernetes liveness probe
curl -s http://192.168.168.31:3000/health/live | jq '.status'
\`\`\`

### Metrics Querying
\`\`\`bash
# All metrics
curl -s http://192.168.168.31:3000/metrics/github-task-sync | jq '.'

# Just webhook metrics
curl -s http://192.168.168.31:3000/metrics/github-task-sync/webhook | jq '.'

# Prometheus format (for Prometheus scraping)
curl -s http://192.168.168.31:3000/metrics/prometheus | head -20
\`\`\`

### Audit Log Querying
\`\`\`bash
# Recent events
curl -s http://192.168.168.31:3000/audit/events?limit=20 | jq '.'

# Recent errors
curl -s http://192.168.168.31:3000/audit/errors?limit=10 | jq '.'

# Webhook events
curl -s http://192.168.168.31:3000/audit/webhooks?limit=20 | jq '.'

# User-specific events
curl -s http://192.168.168.31:3000/audit/user/user123 | jq '.'

# Repository-specific events
curl -s http://192.168.168.31:3000/audit/repository/owner/repo | jq '.'
\`\`\`

### Docker Commands
\`\`\`bash
# View all containers
docker compose ps

# View logs (streaming)
docker compose logs -f backend

# View logs (last 50 lines)
docker compose logs backend | tail -50

# Restart specific service
docker compose restart backend

# Full restart
docker compose down
docker compose up -d

# Resource usage
docker stats --no-stream
\`\`\`

---

## Document History

| Version | Date | Changes |
|---------|------|----------|
| 1.0 | 2026-04-24 | Initial release |

---

**Last Updated**: April 24, 2026  
**Next Review**: May 24, 2026  
**Owner**: Collab-9 Operations Team
