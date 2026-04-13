# Phase 14 Operations Runbook

**Operational Document for code-server Production**  
**Audience**: SRE, Operations, On-Call Engineers  
**Last Updated**: April 14, 2026  
**Status**: ACTIVE - PRODUCTION ENVIRONMENT

---

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Incident Response](#incident-response)
3. [Scaling Operations](#scaling-operations)
4. [Maintenance Procedures](#maintenance-procedures)
5. [Troubleshooting Guide](#troubleshooting-guide)
6. [Emergency Procedures](#emergency-procedures)

---

## Daily Operations

### Morning Standup Checklist (Daily @ 9:00am UTC)

**Duration**: 5 minutes  
**Owner**: On-call engineer  
**Audience**: SRE team, operations

```bash
#!/bin/bash
# Quick health check script
REMOTE_HOST="192.168.168.31"
REMOTE_USER="akushnir"

echo "=== PHASE 14 MORNING STANDUP ==="
echo "Time: $(date -u)"

# Check 1: Container status
ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" \
  "docker ps --format 'table {{.Names}}\t{{.Status}}'"

# Check 2: SLO metrics (last 24 hours)
echo -e "\n=== SLO METRICS (24H) ==="
echo "p99 Latency: (check Grafana)"
echo "Error Rate: (check Grafana)"
echo "Availability: (check Grafana)"

# Check 3: Recent incidents
echo -e "\n=== RECENT INCIDENTS ==="
echo "(check #ops-critical channel)"

# Check 4: Planned maintenance
echo -e "\n=== PLANNED MAINTENANCE ==="
echo "(check maintenance calendar)"
```

**Report Format**:
```
✅ All 3 containers running
✅ SLOs met (p99: 45ms, error rate: 0.02%, availability: 99.97%)
✅ No recent incidents (>30 min)
⚠️ Backup running (ETA: 10 mins)
➡️ Today: Scheduled database optimization (2pm UTC)
```

---

### Weekly Operations Review (Every Friday @ 2:00pm UTC)

**Duration**: 30 minutes  
**Owner**: SRE lead  
**Attendees**: Operations, Engineering leads, Product

**Agenda**:
1. **Weekly SLO Analysis** (5 min)
   - Review metrics from past 7 days
   - Identify trends (improving/degrading)
   - Compare vs. targets
   
2. **Incident Review** (10 min)
   - List incidents from past week
   - MTTR analysis (target <5 min)
   - Root cause summaries
   
3. **Capacity Planning** (5 min)
   - Current load (concurrent users)
   - Projected growth rate
   - Scaling decisions
   
4. **Optimization Opportunities** (5 min)
   - Cache hit ratios
   - Query performance
   - Network optimization
   
5. **Team Feedback** (5 min)
   - Developer complaints
   - Performance observations
   - Maintenance impacts

**Documentation**: Update PHASE-14-OPERATIONS-LOG.md with findings

---

## Incident Response

### SLO Violation Response

**Alert**: p99 Latency > 100ms for 1+ minutes

```
Timeline:
T+0:00 - Alert fires in PagerDuty (page on-call)
T+0:01 - Check Grafana dashboard for context
T+0:02 - Review container logs (docker logs <container>)
T+0:03 - Decision point:
   ├─ If memory spike → possible memory leak
   ├─ If CPU spike → possible hot loop/load
   ├─ If network lag → check external calls
   └─ If all normal → check database queries

T+0:05 - Implement fix:
   ├─ If recoverable → restart container (RTO <1s)
   ├─ If database issue → run optimization query
   ├─ If sustained → escalate to SRE lead
   └─ If critical → initiate rollback

T+0:10 - Document incident:
   ├─ Log in #ops-critical Slack channel
   ├─ Create incident in PagerDuty
   └─ Start post-mortem timer

T+0:15+ - Resolve and document
   ├─ Implement permanent fix
   ├─ Deploy fix to production
   ├─ Verify metrics return to normal
   └─ Close incident with RCA
```

**Runbook Decision Tree**:

```
Is p99 Latency > 100ms?
├─ YES: Check Grafana
│   ├─ Memory > 80%?
│   │  └─ YES → Restart container (RTO <1s)
│   ├─ CPU > 80%?
│   │  └─ YES → Scale horizontally if possible
│   └─ Network latency high?
│       └─ YES → Check external calls
└─ NO: False alarm (return to normal)
```

### Error Rate Spike (>0.1%)

**Alert**: HTTP 5xx rate > 1% for 5+ minutes

```
Immediate Actions:
1. Check error logs: docker logs --tail=100 code-server-31 | grep ERROR
2. Identify common pattern:
   - Same endpoint? → code bug
   - Random errors? → resource issue
   - Auth failures? → OAuth service issue
3. Response:
   - Code bug → hotfix and deploy
   - Resource → restart container
   - Auth → contact OAuth provider
```

### Container Restart Detected

**Alert**: Container exited unexpectedly (CRITICAL)

```
Emergency Response (T+0:00-0:01):
1. Page on-call engineer immediately
2. Check restart reason: docker inspect <container> | grep RestartCount
3. Check logs: docker logs <container> --tail=50
4. If OOM (Out of Memory):
   → Increase memory limit
   → Restart container
   → Monitor for recurrence
5. If crashloop:
   → Rollback to previous version
   → Escalate to engineering team
6. Document: Incident ticket + Slack notification
```

---

## Scaling Operations

### Detecting Need for Scale

**Indicators**:

1. **Latency Degradation**
   - p99 latency trending upward
   - Threshold: > 80ms (yellow), > 100ms (red)
   
2. **Memory Usage**
   - Container memory > 70% limit
   - Risk: OOM kill, restart
   
3. **CPU Saturation**
   - CPU > 80% for 5+ minutes
   - Symptom: Increased request queuing
   
4. **Error Rate Increase**
   - 5xx rate > 0.5%
   - Indicates resource exhaustion
   
5. **Concurrent User Growth**
   - Forecast: current users + 20% growth tolerance

**Decision Matrix**:

| Metric | Threshold | Action |
|--------|-----------|--------|
| Concurrent Users | 80-100 | Plan horizontal scale |
| p99 Latency | > 80ms | Optimize queries |
| p99 Latency | > 100ms | Add capacity |
| Memory | > 70% | Increase limit or scale |
| CPU | > 80% | Add nodes (Kubernetes) |
| Error Rate | > 0.5% | Immediate scale |

### Horizontal Scaling Procedure

**Scenario**: Need to add 2nd code-server node

```bash
# Step 1: Provision new node
terraform apply -var="instance_count=2"

# Step 2: Configure load balancer
# Update HAProxy to include new node
# haproxy.cfg: backend code_servers
#   server server1 192.168.168.31:8080
#   server server2 192.168.168.32:8080  # NEW

# Step 3: Deploy containers on new node
ssh -o StrictHostKeyChecking=no akushnir@192.168.168.32 << 'EOF'
docker-compose -f docker-compose.yml up -d code-server-32 caddy-32 ssh-proxy-32
EOF

# Step 4: Verify new node health
curl http://192.168.168.32:8080

# Step 5: Update monitoring
# Add new node to Prometheus scrape config
# Add new node to Grafana dashboard

# Step 6: Gradual traffic shift (blue-green deployment)
# Shift 10% traffic to new node (monitor for 5 min)
# Shift 50% traffic to new node (monitor for 10 min)
# Shift 100% traffic (equal distribution)

# Step 7: Monitor metrics
# Verify latency, error rate, memory on both nodes
# Ensure even distribution

# Step 8: Document
echo "Scaled to 2 nodes at $(date)" >> SCALING.log
```

### Vertical Scaling Procedure

**Scenario**: Need to increase resources on existing nodes

```bash
# Step 1: Increase memory limit
docker update --memory 4G code-server-31

# Step 2: Increase CPU limit
docker update --cpus 2.0 code-server-31

# Step 3: Verify limits
docker stats code-server-31

# Step 4: Monitor for improvement
watch -n 1 'curl -s http://localhost:8080/metrics | grep http_request_duration'

# Step 5: If issue persists, restart container
docker restart code-server-31

# Step 6: Document change
echo "Increased memory to 4GB for code-server-31 at $(date)" >> SCALING.log
```

---

## Maintenance Procedures

### Scheduled Maintenance Window

**Frequency**: Every 2 weeks (Sunday 2:00am UTC)  
**Duration**: 30 minutes  
**Status Page**: Notify users 24h in advance

**Procedure**:

```bash
#!/bin/bash
# Scheduled maintenance script

echo "=== MAINTENANCE START ==="
echo "Time: $(date -u)"

# Step 1: Notify users
echo "Sending maintenance notification to all users..."
# Send Slack notification
# Update status page

# Step 2: Enable maintenance mode (optional, if applicable)
# Gracefully drain active connections

# Step 3: Back up database
echo "Backing up database..."
ssh -o StrictHostKeyChecking=no akushnir@192.168.168.31 << 'EOF'
mkdir -p /tmp/backup
cp -r /var/lib/code-server /tmp/backup/code-server-$(date +%Y%m%d)
EOF

# Step 4: Apply updates
echo "Applying system updates..."
ssh -o StrictHostKeyChecking=no akushnir@192.168.168.31 << 'EOF'
# sudo apt-get update && sudo apt-get upgrade -y
# (or use containerized approach)
docker pull code-server:latest
docker pull caddy:latest
EOF

# Step 5: Roll out updates
echo "Rolling out container updates..."
# Update docker-compose.yml
# docker-compose up -d --force-recreate

# Step 6: Verify health
echo "Verifying health checks..."
sleep 30
curl -f http://localhost:8080 || exit 1

# Step 7: Re-enable full traffic
echo "Re-enabling full traffic..."
# Remove maintenance mode

# Step 8: Notify completion
echo "Maintenance complete at $(date -u)"
```

### Certificate Renewal

**Frequency**: Automatic (via Caddy, every 60 days)  
**Manual Check**: Last Friday of each month

```bash
#!/bin/bash
# Certificate renewal verification

CERT_PATH="/etc/caddy/ssl/certs"

echo "=== CERTIFICATE STATUS ==="

# Check each certificate
for cert in $CERT_PATH/*.crt; do
    echo "Certificate: $(basename $cert)"
    openssl x509 -in "$cert" -noout -dates
done

# Alert if expiring within 7 days
openssl x509 -in "$cert" -noout -dates | grep "notAfter" | \
  awk '{print "Expiring: " $3 " " $4 " " $5 " " $6}'
```

---

## Troubleshooting Guide

### Common Issues & Solutions

#### Issue 1: High Latency (p99 > 100ms)

**Diagnosis**:
```bash
# Check container resource usage
docker stats code-server-31

# Check system resources
free -h  # memory
top     # CPU

# Check logs for errors
docker logs code-server-31 --tail=50 | grep -i error

# Check HTTP response times
curl -w "@curl-format.txt" -o /dev/null http://localhost:8080
```

**Solutions** (in order):
1. Restart container (if recently increased load)
2. Increase memory limit (if using >80%)
3. Optimize database queries
4. Scale horizontally (add more nodes)

---

#### Issue 2: Memory Leak

**Detection**:
```bash
# Monitor memory trend
while true; do
  echo "$(date): $(docker stats --no-stream code-server-31 | grep code-server | awk '{print $4}')"
  sleep 300  # Every 5 minutes
done
```

**Diagnosis**:
```bash
# Dump heap (if applicable)
# docker exec code-server-31 /path/to/heap-dump.sh

# Check recent changes
git log --oneline | head -10

# Monitor for OOM kills
dmesg | grep -i "out of memory"
```

**Resolution**:
1. Identify commit that introduced leak
2. Revert or patch code
3. Deploy fix
4. Restart container
5. Verify memory stabilizes

---

#### Issue 3: Authentication Fails

**Error**: "OAuth2 service unavailable"

**Diagnosis**:
```bash
# Check OAuth endpoint connectivity
curl -v https://github.com/login/oauth/access_token

# Check DNS resolution
dig github.com

# Check firewall rules
iptables -L -n | grep 443
```

**Solutions**:
1. Check GitHub OAuth service status (github.status.io)
2. Verify firewall allows outbound HTTPS
3. Check authentication configuration
4. If unable to authenticate, use emergency access keys

---

#### Issue 4: Container Won't Start

**Error**: "Container exited with code 1"

**Diagnosis**:
```bash
# Check logs for startup errors
docker logs <container_id>

# Check configuration files
docker inspect <container_id> | grep -A 20 "Env"

# Check required volumes are mounted
docker inspect <container_id> | grep -A 20 "Mounts"
```

**Common Causes & Solutions**:

| Cause | Solution |
|-------|----------|
| Port already in use | `lsof -i :8080` to find process, kill it |
| Missing volume mount | Verify docker-compose.yml volume config |
| Bad environment var | Check .env file for typos |
| Corrupted config | Restore from backup or reset |
| OOM (no memory) | Increase available memory, restart |

---

## Emergency Procedures

### Emergency Restart All Containers

**Situation**: Multiple containers failing or system unstable

```bash
#!/bin/bash
# Emergency restart procedure

echo "=== EMERGENCY CONTAINER RESTART ==="
echo "Initiated at: $(date -u)"

# Step 1: Stop all containers
docker-compose -f docker-compose.yml down

# Step 2: Wait 5 seconds (let system stabilize)
sleep 5

# Step 3: Restart all containers
docker-compose -f docker-compose.yml up -d

# Step 4: Wait for containers to be healthy
sleep 10

# Step 5: Verify health
docker ps --format 'table {{.Names}}\t{{.Status}}'

# Step 6: Run health checks
curl -f http://localhost:8080 || echo "WARNING: Health check failed"

echo "=== RESTART COMPLETE ==="
echo "RTO: ~15 seconds"
```

### Emergency Rollback

**Situation**: Newly deployed code is causing critical issues

```bash
#!/bin/bash
# Emergency rollback to previous version

# Step 1: Identify previous known-good version
PREVIOUS_VERSION="code-server:2024-04-13"  # Last known good

# Step 2: Update docker-compose.yml
sed -i "s|code-server:.*|$PREVIOUS_VERSION|" docker-compose.yml

# Step 3: Pull previous version
docker pull $PREVIOUS_VERSION

# Step 4: Restart containers
docker-compose -f docker-compose.yml up -d --force-recreate

# Step 5: Verify immediate health
sleep 10
curl -f http://localhost:8080

echo "Rolled back to $PREVIOUS_VERSION at $(date -u)"
```

### Full System Recovery

**Situation**: Complete failure, need to recover from backup

```bash
#!/bin/bash
# Full system recovery procedure

echo "=== FULL SYSTEM RECOVERY START ==="

# Step 1: Stop all services
docker-compose down -v  # Remove volumes too if needed

# Step 2: Restore from backup
BACKUP_DATE="2026-04-13"
BACKUP_PATH="/backup/code-server-$BACKUP_DATE"

if [ -d "$BACKUP_PATH" ]; then
    cp -r "$BACKUP_PATH" /var/lib/code-server
    echo "Restored from backup: $BACKUP_DATE"
else
    echo "ERROR: Backup not found at $BACKUP_PATH"
    exit 1
fi

# Step 3: Restart services
docker-compose up -d

# Step 4: Verify recovery
sleep 30
curl -f http://localhost:8080

echo "=== FULL SYSTEM RECOVERY COMPLETE ==="
```

---

## Escalation Procedures

### SRE Team Escalation

**Duration**: Incident ongoing for >5 minutes

```
On-Call Engineer → SRE Lead (Slack + Phone)
↓
If >15 mins: Platform Engineering Manager
↓
If >30 mins: VP Engineering (critical only)
```

### Severity Classification

| Severity | Response Time | Action |
|----------|---------------|--------|
| Critical | <1 min | Page on-call, escalate immediately |
| High | <5 min | Notify SRE, begin investigation |
| Medium | <15 min | Create ticket, plan fix |
| Low | <1 day | Document for next sprint |

---

## Contact Information

**On-Call Schedule**: [link to calendar]  
**Slack Channels**: #code-server-production, #ops-critical  
**Status Page**: status.example.com  
**Incident Tracker**: Jira / PagerDuty  

---

## Appendix: Useful Commands

```bash
# View container logs (last 50 lines)
docker logs --tail=50 code-server-31

# Monitor container in real-time
docker stats code-server-31

# Execute command in container
docker exec -it code-server-31 /bin/bash

# View container environment
docker inspect code-server-31 | grep Env

# Restart specific container
docker restart code-server-31

# View system metrics
free -h          # Memory usage
df -h            # Disk usage
top              # CPU usage
netstat -tuln    # Network connections

# SSH to remote host
ssh -o StrictHostKeyChecking=no akushnir@192.168.168.31

# View Prometheus metrics from host
curl http://localhost:9090/api/v1/query?query=http_request_duration_seconds
```

---

**Last Updated**: April 14, 2026  
**Next Review**: April 21, 2026  
**Owner**: SRE Team
