# Phase 8: Availability SLO Runbook

**SLO**: Availability 99.95% (5 minutes downtime per month)  
**Alert Trigger**: < 99.80% for 2 minutes  
**Severity**: CRITICAL  
**On-Call**: DevOps Team (24/7)

---

## Quick Response (First 2 Minutes)

### 1. Confirm Alert
```bash
# Check Prometheus alert
curl http://localhost:9090/api/v1/alerts

# Check AlertManager
curl http://localhost:9093/api/v1/alerts | jq '.data[] | select(.labels.alertname=="SLOAvailabilityBreach")'
```

### 2. Identify Failed Service
```bash
# Get service status
docker-compose ps --format 'table {{.Service}}\t{{.Status}}' | grep -v 'Up.*healthy'

# Expected output example:
# postgres         Exit 1
# redis            Up 2 minutes (unhealthy)
```

### 3. Check Prometheus Targets
```bash
# Get failed targets
curl -s http://localhost:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.health=="down") | .labels.job'

# Example: postgres, redis, code-server
```

### 4. Restart Failed Service
```bash
# Replace SERVICE_NAME with failed service
docker-compose restart SERVICE_NAME

# Wait for health check (30-60 seconds)
docker-compose ps SERVICE_NAME

# Verify it's healthy
curl http://localhost:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.job=="SERVICE_NAME")'
```

---

## Detailed Troubleshooting (Next 5 Minutes)

### If PostgreSQL Failed

```bash
# Check logs
docker-compose logs postgres | tail -50

# Check disk space
docker exec postgres df -h /var/lib/postgresql/data

# Check replication status
docker-compose exec -T postgres psql -U codeserver -d codeserver << EOF
SELECT slot_name, restart_lsn, confirmed_flush_lsn 
FROM pg_replication_slots;

SELECT client_addr, backend_start, state 
FROM pg_stat_replication;
EOF

# If replication broken:
# 1. Check replica host 192.168.168.30
# 2. SSH to replica: ssh akushnir@192.168.168.30
# 3. Check postgres status: docker-compose ps postgres
# 4. Check logs: docker-compose logs postgres
# 5. If needed: re-initialize replication from primary

# Restart postgres
docker-compose down && docker-compose up -d postgres
```

### If Redis Failed

```bash
# Check logs
docker-compose logs redis | tail -50

# Check memory usage
docker exec redis redis-cli INFO memory

# Check eviction (if at limit)
docker exec redis redis-cli INFO stats | grep evicted_keys

# If memory issue:
# 1. Identify large keys: redis-cli --bigkeys
# 2. Clear old cache: redis-cli FLUSHDB (if safe)
# 3. Increase memory limit in docker-compose.yml
# 4. Restart: docker-compose restart redis

# Check data integrity
docker exec redis redis-cli --stat
```

### If code-server Failed

```bash
# Check logs
docker-compose logs code-server | tail -100

# Check file permissions
docker exec code-server ls -la /home/coder

# Check workspace directory
docker exec code-server df -h /home/coder

# If permission issue:
docker-compose exec code-server chown -R 1000:1000 /home/coder

# Restart
docker-compose restart code-server
```

### If Caddy Failed

```bash
# Check logs
docker-compose logs caddy | tail -100

# Check certificate validity
docker exec caddy curl http://localhost:2019/admin/config/apps/tls/certificates

# Check port binding
docker exec caddy netstat -tlnp | grep -E ':80|:443'

# If certificate expired:
docker exec caddy caddy reload

# Full restart if needed
docker-compose restart caddy
```

### If oauth2-proxy Failed

```bash
# Check logs
docker-compose logs oauth2-proxy | tail -100

# Check configuration
docker-compose exec -T oauth2-proxy env | grep OAUTH

# Verify Google OAuth credentials
echo "Client ID: $OAUTH2_PROXY_CLIENT_ID"
echo "Provider: $OAUTH2_PROXY_PROVIDER"

# Restart
docker-compose restart oauth2-proxy
```

---

## Network Diagnosis

```bash
# Check network connectivity
docker-compose exec caddy ping postgres
docker-compose exec code-server ping redis
docker-compose exec oauth2-proxy ping caddy

# Check DNS resolution
docker-compose exec postgres nslookup redis

# Check firewall
sudo ufw status
sudo ufw allow 5432  # PostgreSQL
sudo ufw allow 6379  # Redis
```

---

## Failover to Replica (if Primary Critical)

```bash
# 1. Verify replica is healthy
ssh akushnir@192.168.168.42
docker-compose ps

# 2. Promote replica to primary
docker-compose exec postgres psql -U codeserver << EOF
SELECT pg_wal_replay_resume();
SELECT pg_promote();
EOF

# 3. Update HAProxy to use replica as primary
# Edit /etc/haproxy/haproxy.cfg on primary
# Or update docker-compose.yml: POSTGRES_HOST=192.168.168.42
docker-compose restart haproxy

# 4. Bring primary back (when recovered)
# SSH to primary, restore service, promote back when ready
```

---

## Escalation (> 5 Minutes Downtime)

### Level 1: Team Lead
- Alert: Slack message to #alerts-critical
- Action: Review metrics, assess impact
- Timeout: 5 minutes

### Level 2: Director
- Notify: director@kushnir.cloud
- Status page: Update https://status.kushnir.cloud (if available)
- Communication: Notify affected users

### Level 3: Executive
- Notify: cto@kushnir.cloud
- Post-incident: Schedule RCA (Root Cause Analysis)
- Client impact: Assess SLA breach, compensation if needed

---

## Post-Incident (After Recovery)

### 1. Verify Full Recovery
```bash
# Check all services healthy
docker-compose ps

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets

# Check recent errors
curl http://localhost:9090/api/v1/query?query='increase(errors_total[5m])'

# Clear any stuck alerts
curl -X DELETE http://localhost:9093/api/v1/alerts -d '{"silence": "SLOAvailabilityBreach"}'
```

### 2. Collect Evidence
```bash
# Export logs
docker-compose logs > incident-logs-$(date +%Y%m%d-%H%M%S).txt

# Export metrics
curl http://localhost:9090/api/v1/query_range?query='up'&start=<before>&end=<after>' > metrics.json

# Export alerts
curl http://localhost:9093/api/v1/alerts?silenced=false > alerts.json
```

### 3. Create Incident Report
```bash
cat > incident-report-$(date +%Y%m%d-%H%M%S).md << EOF
# Incident Report

## Summary
- **Duration**: XX minutes
- **Impact**: All 9 services offline
- **Root Cause**: [TBD]
- **Resolution**: [TBD]

## Timeline
- HH:MM - Alert triggered
- HH:MM - Investigation started
- HH:MM - Root cause identified
- HH:MM - Service restored
- HH:MM - Verification complete

## Root Cause Analysis
[Detailed explanation]

## Remediation
[Steps to prevent recurrence]

## Action Items
- [ ] Fix root cause
- [ ] Update runbook
- [ ] Monitor for recurrence
EOF
```

### 4. Schedule RCA (Root Cause Analysis)
- Within 24 hours of incident
- Attendees: DevOps, Engineering Lead, Director
- Output: Documented action items
- Follow-up: Verify fixes implemented

---

## Prevention (Ongoing)

### Weekly Health Check
```bash
# Run every Monday 9 AM
docker-compose ps
curl http://localhost:9090/api/v1/targets
curl http://localhost:3000/api/health
docker exec postgres psql -U codeserver -c "SELECT version();"
```

### Monthly Capacity Review
```bash
# Check resource trends
docker stats --no-stream
# Identify growing memory/CPU usage

# Check disk usage
df -h | grep -E 'postgres|redis|code-server'

# Review error rates
curl http://localhost:9090/api/v1/query?query='rate(errors_total[1h])'
```

### Quarterly Failover Drill
- Simulate primary failure
- Practice failover to replica
- Test recovery procedures
- Document lessons learned

---

## Contact Information

**Primary On-Call**: [Team Lead Name]
**Backup On-Call**: [Senior Engineer Name]
**Director**: [Director Name]
**Escalation**: [CTO/VP Name]

**Slack Channel**: #alerts-critical
**PagerDuty**: [URL]

---

## Related Runbooks

- [Error Rate Runbook](PHASE-8-ERROR-RATE-RUNBOOK.md)
- [Latency Runbook](PHASE-8-LATENCY-RUNBOOK.md)
- [Throughput Runbook](PHASE-8-THROUGHPUT-RUNBOOK.md)
- [Disaster Recovery](PHASE-7-EXECUTION-COMPLETE.md#disaster-recovery)

---

**Last Updated**: April 16, 2026  
**Next Review**: April 23, 2026 (weekly)
