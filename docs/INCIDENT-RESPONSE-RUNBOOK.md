# Production Incident Response Runbook

## Table of Contents
1. [Alert Escalation Path](#alert-escalation-path)
2. [Incident Response Workflow](#incident-response-workflow)
3. [Common Issues & Solutions](#common-issues--solutions)
4. [Rollback Procedures](#rollback-procedures)
5. [Post-Incident Process](#post-incident-process)

---

## Alert Escalation Path

### Tier 1 - On-Call Engineer (Responds in 5 min)

**Availability**: 24/7 rotation  
**Responsibilities**:
- Respond to alerts within 5 minutes
- Perform initial triage
- Determine alert severity
- Execute runbook procedures
- Document findings

**Contact**: PagerDuty on-call rotation  
**Tools**: Prometheus, Grafana, server SSH access

### Tier 2 - Engineering Lead (Escalate if needed - 15 min response)

**Availability**: Business hours + on-call for P0  
**Responsibilities**:
- Help diagnose complex issues
- Authorize scale-up or rollback
- Provide deeper system knowledge
- Make architectural decisions

**Escalation Criteria**:
- Tier 1 cannot resolve within 15 minutes
- High severity alert persists after initial response
- Unknown error pattern
- Multiple related alerts firing

**Contact**: Slack #incidents channel

### Tier 3 - VP Engineering (Critical issues only)

**Availability**: On-call for P0 emergencies  
**Responsibilities**:
- Final escalation authority
- Business decisions (customer communication, rollback timing)
- Resource allocation decisions

**Escalation Criteria**:
- Critical production outage (service down >10 min)
- Data loss risk
- Security incident
- Customer impact assessment needed

---

## Incident Response Workflow

### Phase 1: Alert Received (IMMEDIATE - 1 min)

**Step 1: Acknowledge Alert**
```bash
# Document in incident tracking system
Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Alert: [Copy alert name and severity]
Component: [Service/Component affected]
Triggered At: [From alert timestamp]
```

**Step 2: Verify Issue is Real (Not False Positive)**
```bash
# Check multiple sources to confirm
curl -s http://localhost:3000/api/health | jq '.status'

# Check service logs for errors
docker logs code-server --since 1m | grep -i error

# Check Prometheus metrics directly
# Navigate to http://localhost:9090
# Query: up{job="code-server"}
```

**Step 3: Assess Severity**
```
CRITICAL - Service unavailable or data at risk
  → Immediate action, escalate to Tier 2 after 3 min
  → Page on-call backup

HIGH - Major degradation but service operational
  → Investigate thoroughly, escalate if not resolved in 10 min
  → Monitor closely

MEDIUM - Minor degradation, service functional
  → Monitor trend, escalate if worsens
  → Fix within business hours

LOW - Informational, no immediate impact
  → Log for future optimization
  → No escalation needed
```

---

### Phase 2: Investigate (5-10 minutes)

#### Check Application Health
```bash
# Check if service is responding
curl -w "HTTP %{http_code} in %{time_total}s\n" \
  -s http://localhost:3000/api/health

# Check recent logs for errors
docker logs code-server --since 5m | grep -E "ERROR|CRITICAL|panic"

# Check response times
curl -w "Time: %{time_total}s\n" http://localhost:3000/api/workspaces
```

#### Check Infrastructure Metrics
```bash
# CPU usage
docker stats code-server --no-stream | awk 'NR==2 {print $3}'

# Memory usage
docker stats code-server --no-stream | awk 'NR==2 {print $4}'

# Disk space
df -h / | awk 'NR==2 {print $5}'

# Network connections
netstat -an | grep ESTABLISHED | wc -l
```

#### Check Database Health
```bash
# Connect to PostgreSQL
psql -U postgres -h localhost

# Check replication status
SELECT * FROM pg_stat_replication;

# Check slow queries
SELECT query, mean_exec_time FROM pg_stat_statements 
ORDER BY mean_exec_time DESC LIMIT 5;

# Check active connections
SELECT count(*) FROM pg_stat_activity;
```

#### Check Redis/Cache
```bash
# Test Redis connectivity
redis-cli ping

# Check memory usage
redis-cli info memory | grep used_memory_human

# Check eviction stats
redis-cli info stats | grep evicted
```

---

### Phase 3: Execute Runbook (10-15 minutes)

**Branch on issue type:**

- **Service Down** → [Service Down Runbook](#service-down-runbook)
- **High Error Rate** → [High Error Rate Runbook](#high-error-rate-runbook)
- **High Latency** → [High Latency Runbook](#high-latency-runbook)
- **Database Issues** → [Database Runbook](#database-runbook)
- **Memory Leak** → [Memory Leak Runbook](#memory-leak-runbook)
- **Disk Full** → [Disk Space Runbook](#disk-space-runbook)

---

### Phase 4: Remediate

**Option A: Quick Fix (if applicable)**
```bash
# Apply fix (depends on issue type)
# See specific runbooks below

# Verify fix worked
curl -s http://localhost:3000/api/health | jq '.status'

# Monitor metrics for 5 minutes
# Check: error rate, latency, resource usage
```

**Option B: Restart Service**
```bash
# Stop the service
docker compose stop code-server

# Start it again
docker compose start code-server

# Verify it's healthy
docker logs code-server --tail 20
curl http://localhost:3000/api/health
```

**Option C: Rollback**
```bash
# If recent deployment caused issue
git log --oneline -5

# Rollback to previous version
docker compose down
git checkout [previous-commit]
docker compose up -d code-server

# Verify
curl http://localhost:3000/api/health
```

---

### Phase 5: Post-Incident (Same day)

**Documentation**:
```bash
# Create incident report file
cat > artifacts/incidents/incident-[YYYY-MM-DD-HH-MM].md << EOF
# Incident Report

## Summary
- **Date/Time**: [Start] to [End]
- **Duration**: [minutes]
- **Severity**: [CRITICAL/HIGH/MEDIUM/LOW]
- **Affected Services**: [List]
- **User Impact**: [Yes/No - how many?]

## Timeline
- HH:MM Alert triggered: [alert name]
- HH:MM Acknowledged by: [engineer name]
- HH:MM Root cause identified: [brief description]
- HH:MM Remediation started: [action]
- HH:MM Service recovered: [verification]

## Root Cause
[Detailed explanation of what caused the issue]

## Remediation
[What was done to fix it]

## Preventive Measures
[What can we do to prevent this?]
- [ ] Action item 1
- [ ] Action item 2

## Lessons Learned
[What did we learn?]

## Follow-up
- [ ] Update monitoring/alerting if needed
- [ ] Update documentation
- [ ] Share with team in #incidents
EOF
```

**Team Communication**:
```bash
# Post to #incidents Slack channel
echo "Incident resolved: [Issue] - Duration: [X] minutes - Root cause: [Brief]"

# Schedule post-mortem if severe (P0/P1)
calendar_invite team@kushnir.cloud "Post-mortem: [Issue]" "24 hours after incident"
```

---

## Common Issues & Solutions

### Service Down Runbook

**Symptoms**: Service responding with HTTP 503/502, health check failing

**Investigation**:
```bash
# Check if container is running
docker ps | grep code-server

# Check recent errors
docker logs code-server --since 5m | grep -i error

# Check if port is bound
netstat -tln | grep 3000
```

**Solutions** (try in order):
1. **Restart the service**:
   ```bash
   docker restart code-server
   sleep 10
   curl http://localhost:3000/api/health
   ```

2. **Check disk space** (may prevent startup):
   ```bash
   df -h / 
   # If <10% free, clean up and restart
   docker system prune -a
   docker restart code-server
   ```

3. **Check database connection**:
   ```bash
   docker logs code-server | grep -i "connection"
   # If connection refused, ensure PostgreSQL is running
   docker restart postgres
   sleep 10
   docker restart code-server
   ```

4. **Rollback if recent deployment**:
   ```bash
   git log --oneline -1
   git revert HEAD
   docker compose up -d
   ```

**Recovery Verification**:
```bash
✓ Container running: docker ps | grep code-server
✓ Responding to requests: curl http://localhost:3000/api/health
✓ No errors in logs: docker logs code-server --since 2m | grep ERROR
✓ Response time acceptable: curl -w "%{time_total}\n" http://localhost:3000/api/health
```

---

### High Error Rate Runbook

**Symptoms**: >5% of requests returning 5xx errors for >2 minutes

**Investigation**:
```bash
# Check error rate by type
docker logs code-server | grep ERROR | tail -20

# Check if it's a specific endpoint
curl -v http://localhost:3000/api/workspaces 2>&1 | grep HTTP

# Check database for errors
psql -c "SELECT * FROM logs WHERE level='ERROR' ORDER BY created_at DESC LIMIT 10;"
```

**Solutions**:
1. **Check if deployment is in progress**:
   ```bash
   git status
   # If files modified, either stash or commit
   ```

2. **Identify failing endpoint**:
   ```bash
   # Monitor traffic in real-time
   docker logs code-server -f | grep -i error
   ```

3. **If it's a database issue**:
   ```bash
   # Check DB connection
   psql -c "\l"  # list databases
   
   # If unreachable, restart PostgreSQL
   docker restart postgres
   sleep 5
   ```

4. **If it's an application error**:
   ```bash
   # Restart the application
   docker restart code-server
   sleep 10
   
   # Verify error rate dropped
   curl -s http://localhost:3000/api/health
   ```

---

### High Latency Runbook

**Symptoms**: p99 latency >500ms for >5 minutes

**Investigation**:
```bash
# Check database query performance
psql -c "SELECT mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 5;"

# Check if slow query (>1s)
docker logs code-server | grep "SLOW"

# Check system resources
docker stats code-server --no-stream
```

**Solutions**:
1. **Scale up resources** (if CPU/memory high):
   ```bash
   # Update docker-compose.yml with higher limits
   # Change: 
   # cpus: '2'  → '4'
   # memory: 2g → 4g
   
   docker compose up -d
   ```

2. **Optimize slow query**:
   ```bash
   # Get slowest queries
   psql -c "SELECT query FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 5;"
   
   # Add index if missing
   psql -c "CREATE INDEX idx_name ON table_name(column_name);"
   ```

3. **Clear cache if needed**:
   ```bash
   redis-cli FLUSHALL
   ```

---

### Database Runbook

**Replication Lag High (>10s)**:
```bash
# Check replica status
ssh failover "pg_ctl status -D /var/lib/postgresql/data"

# Check if replica is keeping up
psql -c "SELECT * FROM pg_stat_replication;"

# If stuck, restart replica
ssh failover "sudo systemctl restart postgresql"

# Verify lag returned to normal
# Should be <100ms
```

**Connection Pool High**:
```bash
# See active connections
psql -c "SELECT count(*) FROM pg_stat_activity;"

# Kill idle connections (use carefully)
psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state='idle';"

# Or restart database
docker restart postgres
```

---

### Memory Leak Runbook

**Symptoms**: Memory usage continuously growing, reaches limit in hours

**Investigation**:
```bash
# Check memory trend
docker stats code-server --no-stream | awk 'NR==2 {print $4}'
# Run again 5 minutes later and compare

# Check for open file handles
lsof -p $(docker inspect -f '{{.State.Pid}}' code-server) | wc -l
```

**Solutions**:
1. **Identify memory-hungry process**:
   ```bash
   docker stats --no-stream | sort -k4 -h | tail -5
   ```

2. **Restart affected service**:
   ```bash
   docker restart code-server
   ```

3. **Check if cache is culprit**:
   ```bash
   redis-cli info memory
   # If high, flush cache
   redis-cli FLUSHALL
   ```

4. **Investigate code**:
   ```bash
   # Check recent changes
   git log --oneline -10
   
   # Run with profiler
   # (depends on language/framework)
   ```

---

### Disk Space Runbook

**Symptoms**: Disk >90% full, or <10% remaining

**Solutions**:
1. **Clean Docker**:
   ```bash
   docker system prune -a  # Remove unused images/containers
   docker volume prune     # Remove unused volumes
   ```

2. **Clean logs**:
   ```bash
   docker logs code-server --since 1h | wc -l  # Check log size
   # Truncate old logs if needed
   ```

3. **Check large files**:
   ```bash
   du -sh /* | sort -h | tail -10
   ```

4. **Expand disk** (if still needed):
   ```bash
   # Contact infrastructure team
   # May require VM restart
   ```

---

## Rollback Procedures

**When to Rollback**:
- Service broken after deployment
- Data corruption risk
- Security vulnerability deployed
- Performance worse than baseline

**Quick Rollback**:
```bash
# 1. Identify last good commit
git log --oneline -10

# 2. Rollback
docker compose down
git checkout [good-commit-hash]
docker compose up -d

# 3. Verify
curl http://localhost:3000/api/health
docker logs code-server --tail 20

# 4. Document
# Add rollback note to PR/commit
```

**Database Rollback**:
```bash
# 1. Stop application
docker stop code-server

# 2. Check backup
ls -lh /mnt/nas/backups/

# 3. Restore from backup
pg_restore -d [database] /mnt/nas/backups/[backup-file]

# 4. Restart app
docker restart code-server
```

---

## Post-Incident Process

**Same Day**:
- [ ] Complete incident report (see template above)
- [ ] Document root cause
- [ ] Identify preventive measures
- [ ] Escalate if P0/P1 severity
- [ ] Share in #incidents Slack channel

**Within 24 Hours**:
- [ ] Implement monitoring improvement (if applicable)
- [ ] Update runbook based on what was learned
- [ ] Create follow-up issues for preventive measures
- [ ] Schedule post-mortem if P0/P1

**Within 1 Week**:
- [ ] Complete all follow-up action items
- [ ] Update documentation
- [ ] Share learnings with team
- [ ] Verify preventive measures are working

---

## Incident Contact Info

**On-Call Rotation**: PagerDuty  
**Slack Channel**: #incidents  
**Escalation**: @engineering-lead  
**Emergency**: @vp-engineering (P0 only)

**Last Updated**: April 22, 2026  
**Maintained By**: Infrastructure Team
