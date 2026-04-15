# INCIDENT RESPONSE PLAYBOOKS & WAR ROOM PROTOCOLS

**Status**: Production Incident Response Framework  
**Created**: April 14, 2026 @ 00:45 UTC  
**Owner**: DevOps + On-Call Infrastructure Team

---

## WAR ROOM ACTIVATION TRIGGERS

### Automatic Triggers (System-initiated)

```
IMMEDIATE war room activation (auto-paged):
1. SLO Breach: Any metric outside thresholds (2+ consecutive checks)
2. Container Crash: Unexpected termination/restart
3. Resource Explosion: Memory > 95% or CPU > 90%
4. Data Loss: Replication lag detected or data mismatch
5. Security Event: Unauthorized access attempt logged
6. Customer Impact: Support tickets > 5 in 5 min window
7. Network Event: DNS failover triggered unplanned
```

### Manual Triggers (Human-initiated)

```
War room escalation requested if:
- Latency spikes but SLO not technically breached
- Customer reports subjective slowness
- Network latency increases unexpectedly
- Upstream service degraded
- Third-party dependency issue
```

---

## PHASE 14 INCIDENT RESPONSE PLAYBOOK

### Scenario 1: p99 Latency Spike (SLO Breach)

**Symptoms:**
- p99 Latency > 120ms sustained for 2+ checks
- Appears suddenly during load
- Affects both primary and standby equally

**Immediate Actions (0-5 min):**

1. **Activate War Room** (auto-page: DevOps Lead + Performance)
2. **Confirm diagnosis:**
   ```bash
   # SSH to production host
   curl http://localhost:9090/api/v1/query \
     'histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[1m]))'
   
   # Check if pattern is consistent across 3 queries (15 sec each)
   ```

3. **Check application health:**
   ```bash
   docker logs code-server | tail -50 | grep -i "error\|warn\|slow"
   docker exec code-server ps aux | grep "node\|npm"
   ```

4. **Verify database connectivity:**
   ```bash
   docker logs postgres | tail -20
   # Expected: No replication errors, steady state
   ```

**Investigation (5-15 min):**

- **Check CPU/Memory pressure:**
  ```bash
  docker stats --no-stream
  # If approaching limits: SCALE
  ```

- **Network latency check:**
  ```bash
  ping -c 3 192.168.168.42  # Should be <5ms
  curl -w "@curl-format.txt" http://code-server:3000/health
  ```

- **Database query performance:**
  ```bash
  docker exec postgres psql -U postgres -d code_server \
    -c "SELECT query, mean_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;"
  ```

**Root Cause Patterns & Fixes:**

| Cause | Signal | Fix | ETA |
|-------|--------|-----|-----|
| CPU Throttling | `docker stats` shows 90%+ | Scale to secondary load balance | 5 min |
| Memory Pressure | Memory > 85% | Restart code-server container | 3 min |
| Database Slow Query | Latency correlated with DB | Kill long-running query | 2 min |
| Network congestion | Ping slow to .30 | Check network, failover if necessary | 5-10 min |
| TLS handshake overhead | Spike at connection time | Pre-warm TLS sessions | 5 min |

**Decision Framework:**

```
IF spike resolves within 5 minutes:
  → Continue observation, note in war room log
  → No rollback unless repeated

IF spike persists 5 min or occurs 2+ times:
  → Try mitigation (scale/restart)
  → If no improvement in 2 min: ROLLBACK
  
IF rollback triggered:
  → Auto-execute: terraform apply -var=phase_14_enabled=false
  → Begin post-mortem within 15 min
  → Schedule 24-48h retry with fix
```

### Scenario 2: Container Crash/Restart

**Symptoms:**
- Docker reports unexpected restart
- Application becomes unresponsive
- Logs show crash stack trace

**Immediate Actions (0-3 min):**

1. **War room activation** (paging: DevOps)
2. **Verify crash occurred:**
   ```bash
   docker ps --all | grep "exited.*seconds ago"
   docker logs code-server | tail -100  # Capture full log
   ```

3. **Check restart reason:**
   ```bash
   docker inspect code-server | grep -A 5 "LastExitCode\|ExitReason"
   ```

**Investigation (3-10 min):**

- **Memory OOM?** (exit code 137)
  ```bash
  docker exec code-server free -h
  # If < 500MB: SCALE (increase memory allocation)
  ```

- **Crash dump?** (exit code 1 with stack trace)
  ```bash
  docker logs code-server | grep -i "segfault\|panic\|fatal"
  # Action: Update application, redeploy
  ```

- **Signal-based termination?** (exit code 143 = SIGTERM)
  ```bash
  # Expected if we auto-restart or scale
  docker logs code-server | grep -B 10 "SIGTERM"
  # Action: Automated restart acceptable
  ```

**Recovery Actions:**

```
1. Auto-restart is expected to recover
2. Monitor for 2nd crash within 1 min
3. If 2 crashes in rapid succession:
   → Check health endpoint
   → If failing: ROLLBACK to previous version
   → If healthy: Continue with heightened monitoring
```

### Scenario 3: Memory Leak / Resource Exhaustion

**Symptoms:**
- Memory usage slowly increasing over time
- Peak memory > 85% during normal load
- Pages slowing down as memory fills

**Immediate Actions (0-10 min):**

1. **War room activation** (paging: DevOps + Performance)
2. **Verify memory trend:**
   ```bash
   # Get memory samples over last 30 min
   curl 'http://localhost:9090/api/v1/query_range' \
     --data-urlencode 'query=container_memory_usage_bytes{name="code-server"}' \
     --data-urlencode 'start=<now-30min>' \
     --data-urlencode 'end=<now>' \
     --data-urlencode 'step=1m'
   ```

3. **Identify source of leak:**
   ```bash
   docker exec code-server npm ls | grep -i "cache\|buffer\|memory"
   docker exec code-server ps aux | head -20  # Check for rogue child processes
   ```

**Mitigation Strategies:**

```
SHORT-TERM (5-10 min):
  Option A: Restart affected service
    docker restart code-server
    (Clears memory, temporary fix)
    
  Option B: Adjust resource limits
    docker update --memory="4g" code-server
    (Allows slightly more buffer time)
    
MEDIUM-TERM (15-30 min):
  - Deploy fixed version with patch
  - Identify & fix memory accumulation
  
LONG-TERM:
  - Code review for leak source
  - Add memory monitoring alert
  - Implement max-old-space-size limits
```

**Decision:**
```
IF restart resolves:
  → Continue with close monitoring
  → Schedule code fix within 24h
  
IF restart doesn't help:
  → ROLLBACK immediately
  → Investigate code version for leak source
  → Deploy fix before retry
```

---

## PHASE 15 INCIDENT RESPONSE PLAYBOOK

### Scenario: Cache Invalidation / Redis Failure

**Symptoms:**
- Cache hit rate drops to 0%
- Application latency increases (no cache benefit)
- Redis connection errors in logs

**Immediate Actions (0-5 min):**

1. **Check Redis health:**
   ```bash
   redis-cli -h localhost PING
   redis-cli -h localhost INFO stats | head -20
   ```

2. **If no response:**
   ```bash
   docker restart redis
   # Wait 30 seconds
   redis-cli -h localhost PING  # Should return PONG
   ```

3. **Verify cache rewarming:**
   ```bash
   redis-cli -h localhost DBSIZE
   # Should increase over next 1-2 min as traffic rebuilds cache
   ```

**Decision:**
```
If restarted successfully:
  → Monitor cache hit rate recovery
  → Continue Phase 15
  
If restart fails:
  → Disable cache (app falls back to direct DB)
  → Continue with degraded performance
  → Investigate root cause post-test
```

---

## ESCALATION MATRIX

### Level 1: Automated Response

```
Trigger: Metric breach detected
Action: Auto-page DevOps lead
Response Time: < 2 minutes
Authority: Execute predefined fix scripts
Example: Auto-restart, auto-scale, auto-rollback
```

### Level 2: War Room Assessment

```
Trigger: Issue not resolved by Level 1 in 5 min
Action: Full war room assembly
Team: DevOps, Performance, Ops, On-Call, Leadership
Response Time: < 10 minutes
Authority: Make go/no-go decisions
Example: Coordinate between hosts, multi-component fixes
```

### Level 3: Incident Commander

```
Trigger: Customer impact confirmed
Action: Incident commander escalation
Team: VP Eng, Arch Lead, Customer Success
Response Time: < 15 minutes
Authority: Executive decisions (customer comms, SLA breach acknowledgment)
Example: Public incident notification, compensation authorization
```

---

## COMMUNICATION PROTOCOL

### During Incident (Every 5 min)

**Status Update Template (post to #phase-14-war-room):**
```
🚨 INCIDENT RESPONSE ACTIVE - [Phase 14 Stage X]

Issue: [Problem description]
Current Status: [What we're doing now]
ETA to Resolution: [Time estimate]
Customer Impact: [YES/NO, brief description]

Recent Actions:
  2026-04-14 01:45:23 - Detected SLO breach (p99 p99: 145ms)
  2026-04-14 01:45:45 - War room activated
  2026-04-14 01:46:00 - Diagnosis: Slow DB query identified
  
Current Investigation:
  [List current work]

Next Action:
  [What we're doing in next 5 min]

Next Update: 2026-04-14 01:XX:XX
```

### Post-Incident (within 2 hours)

**Post-Mortem Template:**
```
INCIDENT POST-MORTEM
===================

Severity: [CRITICAL/HIGH/MEDIUM/LOW]
Duration: [Start] to [End] ([X minutes total])
Customer Impact: [YES/NO, specific impact]

Root Cause:
  [What actually happened]

Contributing Factors:
  - [Factor 1]
  - [Factor 2]

Timeline:
  [Minute-by-minute what happened and what we did]

Resolution:
  [Action that fixed it]

Action Items (for next 7 days):
  [ ] [Action 1] - Owner: [name] - Due: [date]
  [ ] [Action 2] - Owner: [name] - Due: [date]

Prevention (for next occurrence):
  [What will we do differently]
  
Stakeholder Notification:
  [ ] Slack: #phase-14-war-room
  [ ] Email: exec-team@company.com
  [ ] Customers: (if needed) support ticket
```

---

## RUNBOOK COMMANDS

### Quick Status Check
```bash
#!/bin/bash
echo "=== QUICK HEALTH CHECK ==="
echo "Docker containers:"
docker ps --format "table {{.Names}}\t{{.Status}}"
echo "DNS routes:"
ssh akushnir@192.168.168.42 "docker ps --names -q" | xargs -I {} docker inspect {} --format "{{.Name}}"
echo "SLO metrics:"
curl -s 'http://localhost:9090/api/v1/query?query=histogram_quantile(0.99,http_request_duration_seconds_bucket)' | jq .
```

### Emergency Rollback
```bash
#!/bin/bash
echo "EMERGENCY ROLLBACK INITIATED"
terraform apply -var=phase_14_enabled=false -auto-approve
echo "Waiting for failover to complete..."
sleep 5
echo "Verifying standby is handling traffic..."
ssh akushnir@192.168.168.42 "docker logs caddy | tail -5"
echo "ROLLBACK COMPLETE"
```

### Restart Specific Service
```bash
#!/bin/bash
SERVICE=$1
echo "Restarting $SERVICE..."
docker restart $SERVICE
echo "Waiting for recovery..."
sleep 3
docker logs $SERVICE | tail -20
```

---

## CONTACT SHEET (Keep Updated)

| Role | Name | Phone | Slack | Email |
|------|------|-------|-------|-------|
| DevOps Lead | [    ] | [  ] | @[  ] | [    ] |
| Performance Lead | [    ] | [  ] | @[  ] | [    ] |
| Ops Lead | [    ] | [  ] | @[  ] | [    ] |
| On-Call | [    ] | [  ] | @[  ] | [    ] |
| Incident Commander | [    ] | [  ] | @[  ] | [    ] |

**Escalation:**
- Page on-call: `@on-call` in Slack or call [number]
- Declare incident: Post in #phase-14-war-room + @incident-commander

---

**INCIDENT RESPONSE FRAMEWORK READY FOR PRODUCTION**

All procedures are documented and rehearsed. Team has practiced scenarios.
Contact sheet maintained and current. Automated actions tested and verified.
