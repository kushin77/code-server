# PHASE 21: INCIDENT RESPONSE RUNBOOKS
# Production Incident Management Procedures
# Date: April 14, 2026

---

## RUNBOOK 1: Database Failover (P1 CRITICAL)

### Condition That Triggers This Runbook
- Replication lag > 60 seconds
- Primary database unreachable (connection refused)
- Alert: `DatabaseFailoverDetected` or `DatabasePrimaryDown`

### Initial Response (0-5 minutes)
1. **Acknowledge alert** in PagerDuty (if not auto-acknowledged)
2. **Assess impact**:
   ```bash
   curl -I https://ide.kushnir.cloud/health
   # Expected: HTTP 200 if failover automatic
   # Expected: HTTP 503 if failover pending
   ```
3. **Check replication status**:
   ```bash
   docker exec postgres-ha-primary psql -U postgres -c "SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;"
   ```
4. **Notify stakeholders** (Slack #incidents):
   - "Database failover detected - investigating now"

### Investigation (5-15 minutes)
1. **Check primary database logs**:
   ```bash
   docker logs postgres-ha-primary | tail -100
   ```
2. **Verify replication stream**:
   ```bash
   docker exec postgres-ha-primary psql -U postgres -c "SELECT * FROM pg_stat_replication;"
   ```
3. **Check network connectivity**:
   ```bash
   docker exec postgres-ha-primary ping <replica-ip>
   ```

### Automatic Failover Verification
- PostgreSQL HA configured with automatic failover (pg_auto_failover)
- Expected RTO: <30 seconds
- Expected RPO: <500KB WAL
- Application automatically switches to new primary via connection string

### Manual Failover (If Automatic Fails)
1. **Trigger manual failover**:
   ```bash
   docker exec postgres-ha-primary psql -U postgres -c "SELECT pg_ctl('failover', 'immediate');"
   ```
2. **Update connection strings** in:
   - `docker-compose.yml` (postgres-ha-primary target)
   - Code-server environment variables
3. **Verify new primary**:
   ```bash
   docker exec postgres-ha-primary psql -U postgres -c "SELECT version();"
   ```
4. **Restore replication**:
   ```bash
   docker restart postgres-ha-replica
   ```

### Resolution
- [ ] Failover completed
- [ ] New primary verified operational
- [ ] Application reconnected successfully
- [ ] Monitoring shows normal latency
- [ ] Replication lag < 100ms

### Post-Incident Actions
1. **Root cause analysis**: Why did primary go down?
2. **Post-mortem**: Within 24 hours, document and share findings
3. **Runbook improvements**: Update this runbook based on learnings

### Slack Update
"✅ Database failover completed. RTO: X minutes. Investigating root cause."

---

## RUNBOOK 2: High Latency Spike (P2 HIGH)

### Condition That Triggers This Runbook
- P99 latency > 200ms (target: < 100ms)
- Alert fires after 5 minutes of sustained high latency
- Alert: `LatencySpike`

### Initial Response (0-3 minutes)
1. **Assess severity*
   - p99 < 150ms: Investigate, may self-resolve
   - p99 150-300ms: Investigate & consider scaling
   - p99 > 300ms: Investigate immediately, consider rollback

2. **Check current metrics**:
   - Dashboard: Grafana → Production Overview
   - Metrics: Check p50, p95, p99 to identify percentile impact

3. **Notify team** (Slack #incidents):
   - "Latency spike detected (p99: XXXms) - investigating"

### Investigation (3-15 minutes)
1. **Identify slow endpoints**:
   ```bash
   # Check Grafana: Dashboard "Application Performance"
   # Filter by endpoint, sort by latency
   curl -s http://localhost:9090/api/v1/query?query='histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))%20by%20(endpoint)' | jq
   ```

2. **Check database slow queries**:
   ```bash
   docker exec postgres-ha-primary psql -U postgres -c "
   SELECT query, mean_exec_time, calls
   FROM pg_stat_statements
   ORDER BY mean_exec_time DESC LIMIT 10;
   "
   ```

3. **Check resource utilization**:
   - CPU: `docker stats` (code-server, postgres, redis)
   - Memory: Same command
   - Disk I/O: `iotop` or equivalent
   - Network: Connection pool saturation?

4. **Check for recent changes**:
   - Git log (any recent deployments?)
   - Terraform changes (any scaling changes?)

### Quick Fixes (Pick One)
- **Increase replicas** (if available):
  ```bash
  terraform apply -var="code_server_replicas=3"
  ```
- **Clear cache**:
  ```bash
  docker exec redis redis-cli FLUSHDB
  ```
- **Kill slow queries**:
  ```bash
  docker exec postgres-ha-primary psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE query_start < now() - INTERVAL '5 minutes';"
  ```
- **Restart service** (if memory leak suspected):
  ```bash
  docker restart code-server; sleep 30; curl https://ide.kushnir.cloud/health
  ```

### Monitoring Resolution
- [ ] Latency drops back to p99 < 100ms
- [ ] All endpoints responding normally
- [ ] No secondary indicators (CPU, memory normal)
- [ ] Dashboard shows recovery

### Post-Incident Actions
1. **Determine root cause**: Code? Infrastructure? Usage spike?
2. **Plan improvement**: Add caching? Optimize query? Scale permanently?
3. **Update runbook**: Add specific symptoms if known

### Slack Update
"Resolved latency spike. Root cause: [X]. Action taken: [Y]"

---

## RUNBOOK 3: Error Rate Spike (P2 HIGH)

### Condition That Triggers This Runbook
- Error rate > 1% (target: < 0.1%)
- Sustained for > 5 minutes
- Alert: `ErrorRateHigh`

### Initial Response (0-2 minutes)
1. **Assess impact**:
   - Check if specific endpoint affected
   - Check if all users affected or subset
   - Gravit Check application health: `curl https://ide.kushnir.cloud/health`

2. **Notify stakeholders**:
   - Slack #incidents: "Error rate spike detected - investigating"

### Investigation (2-10 minutes)
1. **Identify error type**:
   ```bash
   curl -s http://localhost:9090/api/v1/query?query='rate(http_requests_total{status=~"5.."}[5m])%20by%20(status,endpoint)' | jq
   ```
   - 500: Server error (code bug)
   - 502: Bad gateway (upstream down)
   - 503: Service unavailable (overloaded)

2. **Check application logs**:
   ```bash
   docker logs code-server --tail=50 | grep -i error
   ```

3. **Check upstream services**:
   - OAuth2 proxy: `docker ps | grep oauth2`
   - Redis: `docker exec redis redis-cli PING`
   - Postgres: `docker exec postgres-ha-primary psql -U postgres -c 'SELECT 1;'`

### Quick Fixes
- **Restart service**:
  ```bash
  docker restart code-server
  sleep 10; curl https://ide.kushnir.cloud/health
  ```
- **Scale up** (if load-related):
  ```bash
  docker-compose up -d --scale code-server=3
  ```
- **Check upstream**:
  ```bash
  docker logs oauth2-proxy | tail -20
  ```

### Resolution
- [ ] Error rate drops to < 0.1%
- [ ] All endpoints returning 200/3xx
- [ ] Application logs show no errors
- [ ] Dashboard confirms recovery

### Post-Incident Actions
1. **Root cause**: Code bug? Timeout? Resource issue?
2. **Plan fix**: Hotfix deployment? Scaling? Config change?
3. **Prevent recurrence**: Add monitoring for earlier detection

---

## RUNBOOK 4: Redis Memory Critical (P2 HIGH)

### Condition That Triggers This Runbook
- Redis memory usage > 90% of max
- Alert: `RedisMemoryCritical`

### Initial Response (0-2 minutes)
1. **Check current memory**:
   ```bash
   docker exec redis redis-cli INFO memory
   ```

2. **Assess impact**:
   - If eviction policy is LRU: Some sessions will be evicted
   - If eviction policy is noeviction: New sessions will fail

### Quick Fixes
1. **Clear old sessions** (0-2 minutes):
   ```bash
   docker exec redis redis-cli
   > SCAN 0 MATCH "session:*" COUNT 1000
   > For each expired session: DEL key
   ```

2. **Flush cache safely** (2-5 minutes):
   ```bash
   docker exec redis redis-cli MEMORY STATS
   # Identify which keys consuming most memory
   docker exec redis redis-cli KEYS "*" | wc -l
   # If > 100K keys, flush and investigate
   docker exec redis redis-cli FLUSHDB ASYNC
   ```

3. **Increase Redis memory allocation**:
   ```bash
   # Update docker-compose.yml redis memory limit
   docker-compose up -d
   ```

### Verification
- [ ] Memory usage drops to < 70%
- [ ] No session loss (test login)
- [ ] Application performance normal

### Investigation
- **Why did memory spike?**: Leak? Increased users? Caching issue?
- **Is 12GB enough?**: Monitor trend, may need 16GB+

---

## RUNBOOK 5: Certificate Expiry (P3 MEDIUM)

### Condition That Triggers This Runbook
- SSL certificate expires in < 7 days
- Alert: `CertificateNearExpiry`

### Resolution (Non-Urgent)
1. **Caddy auto-renews** (expected behavior):
   - Let's Encrypt automatic renewal
   - No action needed if using Caddy

2. **If manual certificate**:
   ```bash
   curl -I https://ide.kushnir.cloud
   openssl s_client -connect ide.kushnir.cloud:443 | grep "Not After"
   ```

3. **Manual renewal**:
   ```bash
   docker exec caddy caddy reload
   ```

### Follow-up
- Verify certificate renewed
- Update monitoring (7-day warning threshold)

---

## RUNBOOK 6: Disk Space Low (P3 MEDIUM)

### Condition That Triggers This Runbook
- Available disk space < 10%
- Alert: `DiskSpaceLow`

### Investigation
1. **Find large files**:
   ```bash
   du -sh /* | sort -hr | head -10
   ```

2. **Check container volumes**:
   ```bash
   docker system df
   ```

3. **Clean up**:
   ```bash
   docker system prune -a  # Remove unused images/containers
   docker system prune --volumes  # Remove unused volumes
   ```

### Resolution
- [ ] Disk space > 20% available
- [ ] Services running normally
- [ ] Monitor disk growth rate

---

## RUNBOOK 7: Service Restart Cycles

### Condition
- Docker container restarting repeatedly
- Alert: None yet (add if needed)

### Investigation
1. **Check restart logs**:
   ```bash
   docker inspect <container> | grep -A 5 "RestartCount"
   ```

2. **Check container logs**:
   ```bash
   docker logs --since 10m <container>
   ```

3. **Check resource limits**:
   ```bash
   docker stats <container>
   ```

### Common Causes & Fixes
| Cause | Fix |
|-------|-----|
| OOMKilled | Increase memory limit in docker-compose.yml |
| Health check failed | Review health check logic, extend timeout |
| Port conflict | Check `netstat -tlnp | grep <port>` |
| Missing environment variable | Update docker-compose.yml |

---

## ESCALATION & COMMUNICATION

### P1 Critical (Database, 5xx errors, complete outage)
- [ ] Acknowledge alert within 30 seconds
- [ ] Start investigation immediately
- [ ] Update Slack #incidents every 5 minutes
- [ ] Escalate to manager if unresolved after 15 minutes
- [ ] Target resolution: 30 minutes

### P2 High (High latency, memory critical)
- [ ] Acknowledge within 2 minutes
- [ ] Update #incidents when starting investigation
- [ ] Escalate if unresolved after 1 hour
- [ ] Target resolution: 2 hours

### P3 Medium (Certificate, disk space)
- [ ] Fix within business hours
- [ ] Document in ticket
- [ ] No escalation needed

---

## POST-INCIDENT RETROSPECTIVE

After ANY incident, record:
1. **Timeline**: When did it start? When detected? When resolved?
2. **Root cause**: Why did this happen?
3. **Impact**: How many users affected? For how long?
4. **Detection**: How did we find it? Could it be earlier?
5. **Resolution**: What fixed it? Was it the right approach?
6. **Prevention**: How do we prevent this again?
7. **Learning**: What did we learn?

**Retrospective format**: Slack thread in #incidents, document in wiki

---

**Remember**: Stay calm, communicate clearly, follow procedures. You've got this! 🚀
