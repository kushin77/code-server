# Incident Response Playbook

## Overview

This playbook covers responses to common production incidents in code-server. Each incident has:
1. **Detection**: How to identify the issue
2. **Triage**: Assess severity and scope
3. **Mitigation**: Immediate steps to reduce user impact
4. **Root Cause**: Diagnosis and fix
5. **Prevention**: How to avoid in future

## Incident Severity Levels

| Level | SLA | Impact | Example |
|-------|-----|--------|---------|
| **SEV1** | 15 min | Complete service down, customers blocked | All pods crashed |
| **SEV2** | 1 hour | Significant degradation, some users affected | 10% error rate, 5s latency |
| **SEV3** | 4 hours | Partial degradation, workaround available | 1% error rate, slow response |
| **SEV4** | 1 day | Minor issue, no user impact likely | Log warnings, non-critical alerts |

## Common Incidents & Response

### 1. Code-Server Pod Crash Loop (SEV1)

**Detection**:
```bash
kubectl get pods -n code-server -l app=code-server
# STATUS: CrashLoopBackOff, RESTARTS: 5
```

**Triage**:
```bash
kubectl logs -n code-server -l app=code-server --tail=50
# Look for: OOM Killed, Panic, Fatal error
kubectl describe pod <pod-name> -n code-server
# Check: Resource limits, last restart time
```

**Mitigation** (IMMEDIATE):
- If OOM: Scale down other pods to free memory
- Scale up code-server replicas (new pods might succeed)
- If 100% failures: Rollback last deployment

```bash
kubectl scale deployment/code-server --replicas=1 -n code-server
# Wait for pod to start
kubectl logs -n code-server -l app=code-server
```

**Root Cause**:
- Memory leak in application → Review recent code changes
- Incorrect resource limit → Check kustomization overlay
- Dependency issue (Keycloak down) → Check init containers

**Fix**:
```bash
# If code issue
git revert <problematic-commit> && git push origin main && redeploy

# If memory limit issue
kubectl set resources deployment/code-server -n code-server --limits=memory=3Gi
```

**Prevention**:
- Regular memory profiling in staging
- Load testing before deployments
- Proper circuit breakers for external dependencies

---

### 2. Agent API Latency Spike (SEV2)

**Detection**:
```
Prometheus Alert: p99_latency{service="agent-api"} > 5s
OR manually: curl -s https://api.agents.prod/metrics | grep request_duration
```

**Triage**:
```bash
# Check pod metrics
kubectl top pod -n agents -l app=agent-api

# Check logs for slow queries
kubectl logs -n agents -l app=agent-api | grep "duration"

# Check database connection pool
curl -s http://prometheus:9090/api/v1/query?query=db_connection_pool_in_use
```

**Root Cause Analysis**:
1. Database connection pool exhausted → Scale agent-api replicas
2. Expensive query running → Check slow query log
3. Redis latency → Check redis-cli response times
4. Network latency → Check inter-pod communication

```bash
# Check Redis performance
redis-cli --latency-history
# Check DB connection stats
SELECT stat WHERE name LIKE 'connection%'
```

**Mitigation**:
```bash
# Scale up agent-api (more connections)
kubectl scale deployment/agent-api --replicas=10 -n agents

# Kill long-running queries (if any)
# Restart Redis if it's the bottleneck
kubectl delete pod redis-0 -n code-server
```

**Root Fix**:
- Add database indexes for slow queries
- Increase connection pool size in config
- Optimize query in code

**Prevention**:
- Regular query performance audits
- Load testing to identify bottlenecks
- Alerting on query duration > 100ms

---

### 3. Redis Cache Miss Cascade (SEV2)

**Detection**:
```
Agent API error rate spikes to 20%
OR manually: redis-cli INFO stats | grep keyspace_misses
```

**Triage**:
```bash
# Check Redis connectivity
redis-cli ping
# Check memory usage
redis-cli INFO memory | grep used_memory_human
# Check eviction stats
redis-cli INFO stats | grep evicted_keys
```

**Root Cause**:
- LRU eviction triggered → Cache too small for working set
- Redis restarted → Lost all cache
- Network partition → Apps can't reach Redis

**Mitigation** (IMMEDIATE):
```bash
# Increase Redis memory limit
kubectl set resources statefulset/redis --requests=memory=3Gi --limits=memory=3Gi

# Or scale up cache layer
kubectl scale statefulset/redis --replicas=3

# Monitor recovery
watch -n 1 'redis-cli INFO stats | grep hits'
```

**Root Fix**:
- Analyze cache hit ratio and adjust TTLs
- Increase Redis memory allocation
- Implement cache warming strategies

---

### 4. Embeddings Service Degradation (SEV2)

**Detection**:
```
Vector search queries failing or slow (>2s)
OR Prometheus: histogram_quantile(0.99, embeddings_request_duration) > 2s
```

**Triage**:
```bash
# Check pod resources
kubectl top pod -n agents -l app=embeddings

# Check model load status
curl http://embeddings-X.embeddings.agents.svc.cluster.local:8001/health

# Check memory for model cache
kubectl exec -n agents embeddings-0 -- free -h
```

**Root Cause**:
- Model not loaded in memory → Check for OOM
- GPU unavailable (if using) → Check node resources
- Too many concurrent requests → Queue backing up

**Mitigation**:
```bash
# Scale up replicas (distribute load)
kubectl scale deployment/embeddings --replicas=5 -n agents

# Or restart pods to reload models
kubectl rollout restart deployment/embeddings -n agents
```

**Prevention**:
- Pre-load models on startup (warm cache)
- Use smaller, optimized model variants in prod
- Implement request queuing with backpressure

---

## General Emergency Response

### Page On-Call (SEV1-2)
```bash
# Send alert to on-call channel
curl -X POST $SLACK_WEBHOOK \
  -d '{"text": "🚨 SEV1: Code-server down - page on-call"}'

# Page via PagerDuty API
curl -X POST https://api.pagerduty.com/incidents \
  -H 'Authorization: Token $PD_TOKEN' \
  -d '{"incident": {"title": "Production Incident", "urgency": "high"}}'
```

### Instant Rollback (if cause unclear)
```bash
# Last known-good deployment
kubectl rollout history deployment/code-server -n code-server
kubectl rollout undo deployment/code-server -n code-server --to-revision=1
kubectl rollout undo deployment/agent-api -n agents --to-revision=1
```

### Disable Feature (temporary fix)
```bash
# If new feature is causing issues, disable via feature flag
kubectl set env deployment/code-server FEATURE_NEW_SEARCH=false -n code-server

# Restart with flag disabled
kubectl rollout restart deployment/code-server -n code-server
```

## Post-Incident Process

### Within 24 hours:
1. **Writeup**: Document what happened, timeline, impact
2. **Root Cause**: Why did this happen?
3. **Fix**: What code/config changes are needed?
4. **Prevention**: How do we avoid this in future?

### Post-Mortem Template

```markdown
# [INCIDENT] Code-Server Pod Crashes - 2026-04-13

## Timeline
- **2026-04-13 15:23** Initial alert: CrashLoopBackOff
- **2026-04-13 15:25** On-call paged
- **2026-04-13 15:30** Rollback initiated
- **2026-04-13 15:35** Service restored

## Impact
- Duration: 12 minutes
- Users affected: ~500
- Error rate: 100%
- Revenue impact: $X

## Root Cause
New logging feature allocated 2GB of memory on startup, exceeding 1.5GB limit.

## Fix
- Increase memory limit to 3GB in kustomization
- Profile memory usage in staging before deployments

## Follow-up Tasks
- [ ] Update deployment checklist to include memory profiling
- [ ] Add memory regression tests to CI/CD
- [ ] Review all recent memory-intensive changes
```

## Contact Info for Escalation

On-Call Rotation: #on-call-engineering
Engineering Lead: @alice
CTO: @bob
Network Team: #network-incidents
Database Team: #database-incidents
