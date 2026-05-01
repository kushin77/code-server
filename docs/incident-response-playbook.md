# Incident Response Playbook

**Purpose**: Provide structured procedures for responding to production incidents  
**Scope**: All production services (primary: 192.168.168.31, replica: 192.168.168.42)  
**Status**: ✅ Production Ready  
**Last Updated**: April 30, 2026

---

## Incident Response Framework

### Severity Levels

| Level | Definition | Response Time | Examples |
|-------|-----------|----------------|----------|
| **Critical** | Complete service outage or data loss | 5 minutes | Database down, all APIs unreachable |
| **High** | Service degradation, multiple users affected | 15 minutes | High latency, 50% requests failing |
| **Medium** | Limited functionality, few users affected | 1 hour | Single service slow, one feature broken |
| **Low** | Minor issue, workaround exists | 4 hours | UI glitch, non-critical feature |

### Incident Phases

1. **Detection** - Issue identified
2. **Triage** - Severity assessed, incident commander assigned
3. **Mitigation** - Immediate action to restore service
4. **Resolution** - Root cause fixed
5. **Recovery** - Normal operations restored
6. **Post-Mortem** - Lessons learned documented

---

## Critical Incidents: Service Outage

### Recognition
- ✗ All APIs returning 5xx errors
- ✗ VIP endpoint (192.168.168.250) unreachable
- ✗ Dashboard (3000) not responding
- ✗ Multiple containers in "Exited" state

### Immediate Response (First 5 minutes)

**Step 1: Declare Incident**
```bash
1. Activate war room: [Slack channel or Zoom link]
2. Page on-call engineer immediately
3. Notify incident commander and engineering lead
4. Message: "🚨 CRITICAL INCIDENT: [Service] down as of [time]"
```

**Step 2: Assess Current State**
```bash
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && \
  echo "=== SERVICE STATUS ===" && \
  docker compose ps && \
  echo "=== RECENT ERRORS ===" && \
  docker compose logs --tail=100 | grep -i "error\|fatal\|panic"'
```

**Step 3: Determine Cause Category**

Go to appropriate section:
- [Database Down](#database-down)
- [All Services Crashed](#all-services-crashed)
- [Networking Down](#networking-down)
- [Disk Full](#disk-full-outage)

---

## Incident Playbooks

### Database Down

**Recognition**
```
docker compose exec -T code-server-postgres psql -U postgres -c "SELECT 1;"
# Error: connection refused OR psql: could not translate host name
```

**Mitigation (5-10 minutes)**

```bash
# Step 1: Check if service running
docker compose ps code-server-postgres  # Should show "Up"

# Step 2: If not running, start it
docker compose up -d code-server-postgres

# Step 3: If service running but not responsive, check logs
docker compose logs code-server-postgres | tail -50

# Common issues:
# "out of memory" → Increase memory: docker update --memory 16g code-server-postgres
# "disk full" → Go to [Disk Full Outage]
# "too many connections" → Restart or wait for connections to drop
```

**Resolution (10-30 minutes)**

```bash
# Step 1: Check replication status
docker compose exec -T code-server-postgres psql -U postgres -c \
  "SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;"

# Step 2: If replication broken, rebuild replica
# SSH to replica: ssh akushnir@192.168.168.42
# docker compose down
# docker compose up -d code-server-postgres
# Monitor: docker compose logs -f code-server-postgres

# Step 3: If primary corrupted, failover to replica
./scripts/ops/failover.sh --to-replica

# Step 4: Once up, run integrity check
docker compose exec -T code-server-postgres psql -U postgres -c \
  "SELECT datname, pg_database.oid FROM pg_database;" | wc -l
```

**Recovery**
```bash
# Monitor application errors
docker compose logs --since=5m --follow | grep ERROR

# Once stable for 30 minutes, declare resolved
echo "✅ Database incident resolved at $(date)"
```

---

### All Services Crashed

**Recognition**
```bash
docker compose ps | grep "Exited" | wc -l  # Should be < 2, critical if > 5
```

**Mitigation (5 minutes)**

```bash
# Step 1: Don't panic - don't immediately restart everything
# Step 2: Check why they exited
docker compose logs --tail=200 | grep -E "FATAL|OOMKilled|signal"

# Step 3: If OOMKilled detected
df -h /                    # Check disk
docker system df          # Check docker storage
# If disk < 10% free: go to [Disk Full Outage]

# Step 4: If all services exited cleanly (not killed)
docker compose up -d      # Restart all
sleep 30
docker compose ps         # Check status
```

**Resolution (10-30 minutes)**

```bash
# Step 1: Check for deployment issues
git log --oneline -3      # Did deployment happen recently?
git diff HEAD~1           # What changed?

# Step 2: If bad deployment, rollback
git revert HEAD --no-edit
docker compose down
docker compose pull
docker compose up -d

# Step 3: If issue persists, check host-level problems
top -b -n 1              # CPU/Memory usage
iostat -x 1 5           # Disk I/O
netstat -i              # Network errors

# Step 4: For persistent issues, trigger failover
./scripts/ops/failover.sh --to-replica
```

**Recovery**
```bash
# Gradually restart services in dependency order
docker compose up -d code-server-postgres    && sleep 30
docker compose up -d code-server-redis       && sleep 20
docker compose up -d code-server-redpanda    && sleep 20
docker compose up -d                         && sleep 60

# Verify
docker compose ps | grep "Up" | wc -l
```

---

### Networking Down

**Recognition**
```bash
ping 192.168.168.42  # Replica unreachable
ping 8.8.8.8         # Internet unreachable
docker network ls    # Docker networks broken
```

**Mitigation (5-10 minutes)**

```bash
# Step 1: Check network status
ip link show          # Are NICs up?
ip route show         # Are routes defined?
ss -tulpn | grep 8000 # Are services listening?

# Step 2: Restart docker networking
systemctl status docker
systemctl restart docker

# Step 3: Wait for containers to reconnect
sleep 30
docker compose ps

# Step 4: If still broken, check firewall
ufw status            # Is firewall blocking?
netstat -an | grep ESTABLISHED | wc -l

# Step 5: Check specific service connectivity
docker compose exec -T code-server-control-plane \
  curl -s http://code-server-postgres:5432
```

**Resolution (15-30 minutes)**

```bash
# Step 1: If Docker networking broken beyond repair
docker network ls | grep code-server | awk '{print $1}' | xargs -I {} docker network rm {}

# Step 2: Restart docker daemon completely
docker compose down
systemctl restart docker
docker compose up -d

# Step 3: If network bridge issue, rebuild network
docker compose down --remove-orphans
docker network prune -f
docker compose up -d
```

**Recovery**
```bash
# Monitor DNS resolution
nslookup code-server-postgres
# Should resolve to internal IP

# Test inter-service communication
docker compose exec -T code-server-control-plane \
  curl -s http://code-server-postgres:5432

# Declare resolved once all services can communicate
```

---

### Disk Full Outage

**Recognition**
```bash
df -h / | awk '{print $(NF-1)}'  # Shows 100%
docker system df                 # Mostly used by containers or images
ls -lhSd /var/lib/docker/containers/*/logs | head -5  # Large logs
```

**Mitigation (10-20 minutes)**

```bash
# Step 1: Identify what's using disk
du -sh /var/lib/docker/*
du -sh /var/lib/docker/containers/*/

# Step 2: Stop services (reduces pressure)
docker compose down

# Step 3: Clean unused containers and images
docker system prune -a --force  # Removes all unused images
docker container prune -f       # Removes all stopped containers

# Step 4: If still full, truncate large logs
for container in $(docker ps -aq); do
  truncate -s 0 /var/lib/docker/containers/$container/*.log
done

# Step 5: Restart services
docker compose up -d
sleep 60
df -h /  # Should show more space now
```

**Resolution (20-30 minutes)**

```bash
# Step 1: Find what's consuming disk long-term
docker system df -v | sort -k4 -hr | head -10

# Step 2: If container logs too large, configure rotation
# Edit /etc/docker/daemon.json:
# {
#   "log-driver": "json-file",
#   "log-opts": {
#     "max-size": "10m",
#     "max-file": "3"
#   }
# }
systemctl restart docker

# Step 3: Check backup storage isn't filling disk
du -sh /mnt/nas/backups

# Step 4: Archive old backups if needed
mkdir -p /mnt/nas/backups/archive/
mv /mnt/nas/backups/daily/$(date --date="30 days ago" +%Y-%m-%d)* \
   /mnt/nas/backups/archive/ 2>/dev/null || true
```

**Prevention**
```bash
# Monitor disk monthly
crontab -e
# Add: 0 9 * * 1 df -h / | mail -s "Disk usage report" ops@example.com

# Set up alerting
# In prometheus.yml:
# - alert: DiskUsageHigh
#   expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.15
```

---

### High Memory Pressure

**Recognition**
```bash
docker stats --no-stream | grep -E "100%|99%"  # Services at memory limit
docker compose logs --tail=50 | grep -i "oomkilled"
free -h | grep -i swap                          # Swap being used
```

**Mitigation (10-15 minutes)**

```bash
# Step 1: Identify memory hogs
docker stats --no-stream | sort -k4 -hr | head -5

# Step 2: Increase memory for top consumer (if justified)
docker update --memory 16g code-server-postgres

# Step 3: Restart service to apply
docker compose restart code-server-postgres

# Step 4: If system RAM exhausted, restart docker
docker system prune -a --force  # Remove unused
systemctl restart docker
docker compose up -d
```

**Resolution (15-30 minutes)**

```bash
# Step 1: Analyze memory usage pattern
# Check if specific service has memory leak
docker compose logs code-server-control-plane | grep "memory\|cache"

# Step 2: If memory leak suspected
docker compose restart code-server-control-plane
# Monitor: docker stats code-server-control-plane --no-stream

# Step 3: Check for query bloat in PostgreSQL
docker compose exec -T code-server-postgres psql -U postgres -c \
  "SELECT query, calls, mean_memory FROM pg_stat_statements \
   ORDER BY mean_memory DESC LIMIT 5;"

# Step 4: Clear PostgreSQL caches if needed
docker compose exec -T code-server-postgres psql -U postgres -c \
  "DISCARD PLANS; DISCARD CACHES;"

# Step 5: Clear Redis if consuming too much
docker compose exec -T code-server-redis redis-cli FLUSHDB ASYNC
```

---

### High CPU Usage

**Recognition**
```bash
docker stats --no-stream | awk '{print $(NF-1)}' | grep -E ">90%|100%"
top -b -n 1 | grep -i code-server
```

**Mitigation (5-10 minutes)**

```bash
# Step 1: Identify CPU hog
docker stats --no-stream | sort -k3 -hr | head -3

# Step 2: Check what's consuming CPU
docker compose exec <service> ps aux

# Step 3: For queries using CPU
docker compose exec code-server-postgres psql -U postgres -c \
  "SELECT pid, query, state FROM pg_stat_activity WHERE state != 'idle';"

# Step 4: Kill slow queries if needed
docker compose exec code-server-postgres psql -U postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity \
   WHERE duration > interval '5 minutes';"

# Step 5: Restart service if stuck
docker compose restart code-server-control-plane
```

**Resolution (15-30 minutes)**

```bash
# Step 1: Check for query explosion
docker compose exec code-server-postgres psql -U postgres -c \
  "SELECT mean_exec_time, query FROM pg_stat_statements \
   ORDER BY mean_exec_time DESC LIMIT 3;"

# Step 2: Look for optimization opportunities
# Add indexes, optimize queries (requires development work)

# Step 3: Monitor for improvement
watch -n 5 'docker stats --no-stream | head -5'

# Step 4: Once CPU drops below 70%, declare resolved
```

---

### API Latency

**Recognition**
```bash
# Response time > 5 seconds
curl -w "@/dev/stdin" -o /dev/null -s -w 'Time: %{time_total}\n' \
  http://192.168.168.31:8000/health
  
# From Prometheus
# histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 5
```

**Mitigation (10-15 minutes)**

```bash
# Step 1: Check if specific endpoint affected
for endpoint in /health /api/status /api/execute; do
  echo "Testing $endpoint..."
  curl -w "Time: %{time_total}s\n" -o /dev/null -s \
    http://192.168.168.31:8000$endpoint
done

# Step 2: Check database query time
docker compose exec -T code-server-postgres psql -U postgres -c \
  "SELECT mean_exec_time, calls, query FROM pg_stat_statements \
   ORDER BY mean_exec_time DESC LIMIT 3;"

# Step 3: Check connection pool usage
docker compose exec -T code-server-postgres psql -U postgres -c \
  "SELECT count(*) FROM pg_stat_activity;"

# Step 4: If connection pool exhausted, restart application
docker compose restart code-server-control-plane
```

**Resolution (20-30 minutes)**

```bash
# Step 1: Monitor latency improvement
watch -n 2 'curl -w "Time: %{time_total}s\n" -o /dev/null -s \
  http://192.168.168.31:8000/health'

# Step 2: Once consistently < 2s for 5 minutes, check Prometheus
# Rate should return to normal
# No 5xx errors should be present

# Step 3: Once latency returns to < 500ms p95, declare resolved
```

---

## Post-Incident Procedures

### Incident Commander Duties

**During Recovery**
1. Maintain war room/channel updates every 5-10 minutes
2. Track start time, mitigation time, resolution time
3. Document all actions taken and their outcomes
4. Identify if escalation needed (call in experts)

**After Resolution**
```bash
# Document incident
cat > /tmp/incident-$(date +%Y%m%d-%H%M%S).md << EOF
# Incident Report

**Incident ID**: [Auto-assigned]
**Title**: [Brief description]
**Start Time**: [Time detected]
**Detection**: [How discovered]
**Severity**: [Critical/High/Medium/Low]
**Time to Mitigation**: [Minutes]
**Time to Resolution**: [Minutes]
**Services Affected**: [List]
**Impact**: [User count, revenue, etc]

## Timeline
- [Time 1] Event 1
- [Time 2] Event 2
- [Time 3] Resolution

## Root Cause
[Identified cause]

## Actions Taken
- [Action 1]
- [Action 2]

## Prevention
[What will prevent recurrence]

## Follow-up
- [ ] Code fix committed
- [ ] Monitoring alert added
- [ ] Runbook updated
- [ ] Team training scheduled

**Incident Commander**: [Name]
**Date**: [Date]
EOF

# Schedule post-mortem within 24-48 hours
```

### Post-Mortem Template

```markdown
# Post-Mortem: [Incident Title]

**Date**: [Date]  
**Incident Commander**: [Name]  
**Attendees**: [Names]

## Executive Summary
[2-3 sentences about what happened and impact]

## Timeline
- 10:45 AM - User reports slow API
- 10:47 AM - Ops detects database CPU spike
- 10:50 AM - Root cause identified: runaway query
- 11:05 AM - Query killed, service recovered
- 11:15 AM - Monitoring alert added

## Root Cause Analysis
**Primary Cause**: Missing index on frequently-queried column  
**Contributing Factors**: 
1. Code review didn't catch optimization issue
2. No load testing before deployment
3. Monitoring wasn't alerting on slow queries

## Impact
- Duration: 30 minutes
- Users Affected: 2,000
- Revenue Impact: $5,000

## Resolution
- Added index to critical table
- Added monitoring alert for slow queries
- Implemented query review in code review process

## Action Items
- [ ] Backport index to production (Priority: P0, Owner: [Name], Due: Today)
- [ ] Add query performance SLO to dashboard (P1, [Name], Due: This week)
- [ ] Implement query review checklist (P2, [Name], Due: Next sprint)

## Prevention
1. All future queries must be load-tested
2. Code review must include performance checklist
3. Monitoring must alert on p95 latency > 2s
```

---

## Escalation Contacts

| Role | Name | Phone | Email |
|------|------|-------|-------|
| Incident Commander | [Name] | [Phone] | [Email] |
| On-Call Engineer | [Rotating] | [Phone] | [Email] |
| Engineering Lead | [Name] | [Phone] | [Email] |
| VP Engineering | [Name] | [Phone] | [Email] |

**Escalation Path**:
1. First 15 min: On-call engineer
2. 15-30 min: Add engineering lead
3. 30+ min: Add VP Engineering + trigger status page

---

## Monitoring & Alerting

### Critical Alerts

```yaml
# Should trigger page to on-call
- alert: ServiceDown
  expr: up == 0
  for: 2m
  
- alert: ErrorRateCritical
  expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.1
  for: 1m
  
- alert: DatabaseUnresponsive
  expr: pg_up == 0
  for: 1m
  
- alert: DiskFull
  expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.05
```

### Non-Critical Alerts

```yaml
# Should create ticket but not page
- alert: HighLatency
  expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 5
  for: 5m
  
- alert: MemoryPressure
  expr: (container_memory_usage_bytes / container_memory_max_bytes) > 0.9
  for: 10m
```

---

## Testing & Drills

### Monthly Drill Schedule

| Week | Scenario | Lead |
|------|----------|------|
| 1st | Database failover | DBA |
| 2nd | Network outage | NetOps |
| 3rd | Disk full | Storage |
| 4th | Application crash | AppOps |

**Drill Procedure**:
```bash
# 1. Announce drill (notify all, disable escalations)
# 2. Simulate incident
# 3. Measure response time and actions taken
# 4. Document what worked and what needs improvement
# 5. Update runbook based on findings
```

---

## Runbook Maintenance

**Update Frequency**: Quarterly or after each incident  
**Review By**: DevOps Lead + Engineering Lead  
**Approval**: VP Engineering

**Update Checklist**:
- [ ] Add any new incidents encountered
- [ ] Update contact information if changed
- [ ] Add monitoring improvements
- [ ] Verify commands still work
- [ ] Test procedures in staging

---

**Document Version**: 1.0  
**Status**: ✅ Production Ready  
**Last Reviewed**: April 30, 2026  
**Next Review**: July 30, 2026
