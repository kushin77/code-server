# gVisor Workspace Isolation - Operations Runbook

**Status**: Production Deployment Ready  
**Version**: 1.0  
**Last Updated**: April 21, 2026  
**Owner**: Platform DevOS Team

---

## Deployment Strategy

### Rolling Deployment (Recommended for Production)

**Strategy**: Deploy gVisor support progressively across session-broker instances

**Timeline**: 30-45 minutes per host (2-3 hours full rollout)

**Process**:
```bash
# Phase 1: Prepare environment (all hosts)
1. Download gVisor runsc binary (offline)
2. Stage docker daemon.json with runsc runtime
3. Prepare environment variables for SANDBOX_POLICY
4. Create deployment checklist

# Phase 2: Deploy replica host first (192.168.168.42)
1. Install runsc binary
2. Update docker daemon.json with runsc config
3. Verify docker runtime: docker run --rm --runtime=runsc alpine echo OK
4. Set SANDBOX_POLICY=optional (safe fallback mode)
5. Restart session-broker service
6. Monitor logs for 10 minutes
7. Run smoke test: curl http://192.168.168.42:5000/health
8. Verify metrics: curl http://192.168.168.42:5000/metrics | grep sandbox

# Phase 3: Validate replica (5-10 minutes)
1. Create test session: curl -X POST http://192.168.168.42:5000/session/create
2. Verify gVisor runtime used: docker ps --format "table {{.Names}}\t{{.Runtime}}"
3. Check session logs for no errors
4. Confirm replica can fail back to runc if gVisor unavailable

# Phase 4: Deploy primary host (192.168.168.31)
1. Drain active sessions (if any): trigger graceful shutdown
2. Install runsc binary
3. Update docker daemon.json
4. Verify docker runtime setup
5. Set SANDBOX_POLICY=optional initially
6. Restart session-broker
7. Monitor logs (10 minutes)
8. Run smoke tests
9. Verify metrics

# Phase 5: Enable production policy (after validation)
1. After 1 hour of stable operation:
2. Update SANDBOX_POLICY=require on replica
3. Restart session-broker and monitor (15 min)
4. Update SANDBOX_POLICY=require on primary
5. Restart session-broker and monitor (15 min)
6. Verify fail-closed behavior: simulate missing gVisor → should fail

# Phase 6: Post-deployment validation
1. Run 1 hour of load testing
2. Verify all metrics reporting
3. Check audit logs for no isolation failures
4. Document baseline performance metrics
```

**Rollback**: At any phase, set `SANDBOX_POLICY=optional` and restart services

### Feature Flag Deployment (Alternative)

If using a feature flag system:

```bash
# 1. Deploy code with gVisor support but disabled
SANDBOX_POLICY=disabled

# 2. Gradually enable via feature flag
FEATURE_FLAG_GVISOR_ENABLED=true (0% → 10% → 50% → 100%)

# 3. Monitor at each step for errors/failures

# 4. Transition to require policy
SANDBOX_POLICY=require FEATURE_FLAG_GVISOR_ENABLED=true
```

### Canary Deployment

If deploying to multiple cluster regions:

```bash
# 1. Deploy to canary region (5% of traffic)
Region: US-WEST-2 (canary)
SANDBOX_POLICY=optional

# 2. Monitor for 30 minutes
- Check error rates
- Verify metrics
- Confirm no OOM or resource issues

# 3. Expand to 25% (secondary region)
Region: EU-WEST-1
SANDBOX_POLICY=optional

# 4. After 1 hour stable, full rollout
All regions: SANDBOX_POLICY=require
```

---

## Runbook & Troubleshooting

### Pre-Deployment Checklist

- [ ] gVisor runsc binary downloaded and tested offline
- [ ] Docker daemon.json backup created on all hosts
- [ ] Environment variables prepared (.env file)
- [ ] Rollback plan documented and tested
- [ ] Team trained on gVisor concepts
- [ ] Monitoring and alerting configured
- [ ] On-call engineer identified
- [ ] Incident communication channel ready

### Deployment Checklist

```bash
# Host: 192.168.168.42 (replica)
- [ ] Run: which runsc && runsc --version
- [ ] Run: docker run --rm --runtime=runsc alpine echo OK
- [ ] Update SANDBOX_MAX_MEMORY_MB=2048
- [ ] Set SANDBOX_POLICY=optional
- [ ] Restart session-broker
- [ ] Check logs: docker logs session-broker | grep -i sandbox
- [ ] Test: curl http://192.168.168.42:5000/health
- [ ] Metrics: curl http://192.168.168.42:5000/metrics | grep sandbox
- [ ] Run smoke test script

# Host: 192.168.168.31 (primary)
- [ ] (repeat same steps)
- [ ] Drain active sessions before restart
- [ ] Verify replica is healthy before primary restart
```

### Common Issues and Solutions

#### Issue 1: "runsc: command not found"

**Symptom**: 
```
WARN gVisor unavailable, falling back to runc
error: runsc not found in PATH
```

**Solution**:
```bash
# Verify installation
which runsc
runsc --version

# If missing, install:
sudo apt-get install -y runsc

# Verify in Docker
docker run --rm --runtime=runsc alpine echo OK

# If still failing, restart Docker daemon
sudo systemctl restart docker
```

#### Issue 2: "Docker: Error response from daemon: runtime not available"

**Symptom**:
```
Error: runtime runsc not found
```

**Solution**:
```bash
# 1. Check Docker daemon config
cat /etc/docker/daemon.json | jq .runtimes

# 2. Verify runsc path is correct
which runsc  # Should be /usr/local/bin/runsc or /usr/bin/runsc

# 3. Update daemon.json if needed
{
  "runtimes": {
    "runsc": {
      "path": "/usr/local/bin/runsc"
    }
  }
}

# 4. Restart Docker
sudo systemctl restart docker

# 5. Test
docker run --rm --runtime=runsc alpine echo OK
```

#### Issue 3: Sessions using runc instead of runsc

**Symptom**:
```
Expected: runsc runtime
Actual: runc runtime
```

**Cause**: `SANDBOX_POLICY=optional` and gVisor check failed silently

**Solution**:
```bash
# 1. Check gVisor availability
docker run --rm --runtime=runsc alpine echo OK

# 2. If that fails, gVisor not available
# Run diagnostic:
bash scripts/ops/diagnose-gvisor-support.sh

# 3. Check session logs
docker logs <session-container-id> | grep -i sandbox

# 4. Temporarily disable to unblock
SANDBOX_POLICY=disabled  # Falls back to runc safely

# 5. Resolve gVisor issue, then re-enable
```

#### Issue 4: High memory usage with gVisor

**Symptom**:
```
OOMKilled container
Memory limit exceeded
```

**Cause**: gVisor has additional kernel memory overhead

**Solution**:
```bash
# Increase memory limit
SANDBOX_MAX_MEMORY_MB=3072  # Increased from 2048

# Verify allocation
docker inspect <container> | grep -A 5 Memory

# Or reduce session memory if not needed
SANDBOX_MAX_MEMORY_MB=1024  # For light workloads

# Monitor actual usage
docker stats --no-stream | grep session-
```

#### Issue 5: Slow container startup

**Symptom**:
```
Session creation latency > 10 seconds
```

**Cause**: gVisor (runsc) slower than runc on ptrace platform

**Solution**:
```bash
# 1. Check gVisor platform
docker inspect <container> | grep -i gvisor

# 2. If using ptrace, try kvm (faster)
export GVISOR_PLATFORM=kvm  # Requires CPU support

# 3. Verify CPU KVM support
grep -i vmx /proc/cpuinfo  # Intel CPUs
grep -i svm /proc/cpuinfo  # AMD CPUs

# 4. Adjust timeout if needed (temporary)
export SANDBOX_TIMEOUT_SECONDS=7200  # Increased

# 5. Monitor with metrics
curl http://localhost:5000/metrics | grep container_startup_duration
```

---

## Rollback Plan

### Immediate Rollback (Emergency)

**Time estimate**: 2-5 minutes

**Steps**:
```bash
# 1. On primary host (192.168.168.31)
export SANDBOX_POLICY=disabled
sudo systemctl restart session-broker

# 2. On replica host (192.168.168.42)  
export SANDBOX_POLICY=disabled
sudo systemctl restart session-broker

# 3. Verify sessions running with runc
docker ps --format "table {{.Names}}\t{{.Runtime}}"
# Should show: runc (not runsc)

# 4. Verify health
curl http://192.168.168.31:5000/health
curl http://192.168.168.42:5000/health
```

**Status**: Rolled back to non-sandboxed runtime (runc)  
**User Impact**: Minimal (sessions continue, just without gVisor isolation)  
**Next Steps**: Investigate gVisor issue, plan remediation

### Full Rollback (Remove gVisor)

**Time estimate**: 10-15 minutes

**Steps**:
```bash
# 1. Disable gVisor policy on all hosts
SANDBOX_POLICY=disabled
systemctl restart session-broker  # Both hosts

# 2. Wait for all sessions to drain
watch -n 5 'docker ps | grep session-'

# 3. Remove runsc binary
sudo rm /usr/local/bin/runsc

# 4. Remove from Docker daemon config
# Edit /etc/docker/daemon.json: remove "runtimes" block

# 5. Restart Docker
sudo systemctl restart docker

# 6. Verify runc is default
docker run --rm alpine echo OK
# Should use runc
```

**Status**: gVisor completely removed  
**Redeployment**: Will require reinstalling runsc + code changes

---

## Monitoring & Alerting

### Key Metrics to Monitor

```bash
# Success Rate
curl http://localhost:5000/metrics | grep sandbox_sessions_isolated
# Should be > 95% (if gVisor available)

# Failure Rate
curl http://localhost:5000/metrics | grep sandbox_isolation_failures
# Should be 0 (if SANDBOX_POLICY=require and gVisor available)

# Resource Violations
curl http://localhost:5000/metrics | grep sandbox_memory_violations
# Should be < 1% of sessions

# Session Creation Latency
curl http://localhost:5000/metrics | grep session_creation_duration_ms
# Baseline: 1.2s (runc), 1.8s (gVisor) - acceptable overhead
```

### Alerting Rules

Create alerts for:

1. **gVisor Unavailable** (Critical)
   - Condition: `sandbox_runtime == 'runc'` AND `SANDBOX_POLICY == 'require'`
   - Action: Page on-call engineer

2. **High Isolation Failure Rate** (Warning)
   - Condition: `rate(sandbox_isolation_failures[5m]) > 0`
   - Action: Notify platform team

3. **High Memory Violation Rate** (Warning)
   - Condition: `rate(sandbox_memory_violations[5m]) > 5`
   - Action: Investigate session workloads

---

## Verification Steps

### Post-Deployment Validation

```bash
# 1. Verify gVisor runtime is used
docker run --rm --runtime=runsc alpine echo "gVisor OK"

# 2. Create a test session
curl -X POST http://localhost:5000/session/create \
  -H "Content-Type: application/json" \
  -d '{"userId":"test-user-123"}'

# 3. Verify it used gVisor
docker ps --filter "label=userId=test-user-123" \
  --format "table {{.Names}}\t{{.Runtime}}"
# Should show: runsc

# 4. Verify security properties
# Inside container, should see gVisor in /proc/version
docker exec <container-id> grep -i gvisor /proc/version

# 5. Verify fail-closed behavior
# Temporarily move runsc binary
sudo mv /usr/local/bin/runsc /tmp/
# Wait 5 minutes for cache to expire
# New sessions should fail with SANDBOX_POLICY=require
sudo mv /tmp/runsc /usr/local/bin/

# 6. Load test
bash scripts/ops/run-gvisor-load-test.sh --duration 60 --concurrency 10
```

---

## Communication

### Deployment Announcement

Before starting deployment:

```
Subject: gVisor Workspace Isolation - Rolling Deployment Starting

Team,

We are deploying gVisor workspace isolation (PR #1192) starting at [TIME].

Timeline:
- 14:00 UTC: Begin replica deployment
- 14:30 UTC: Validate replica
- 15:00 UTC: Begin primary deployment
- 15:30 UTC: Complete deployment
- 15:30-16:30 UTC: Stability monitoring

Expected Impact: None (graceful fallback to runc)
Rollback Time: 5 minutes (if needed)
Contact: @platform-oncall

Questions? Reach out in #platform-oncall
```

### Status Updates

During deployment, post hourly:
- Current phase
- Metrics (error rate, latency, resource usage)
- Any issues detected
- Next steps

### Completion Announcement

After validation:

```
Subject: gVisor Deployment - Complete ✓

Deployment successfully completed!

Metrics:
- Sessions isolated: 98% (goal: > 95%)
- Failure rate: 0% (goal: 0%)
- Latency overhead: +45% (goal: < 50%)

All services running with gVisor enabled.
Rollback capability available for 24 hours.

Next review: [DATE + 7 days]
```

---

## Post-Deployment Review (1 Week)

Schedule review to assess:

1. **Stability**: Error rates, failure rates, crashes
2. **Performance**: Latency impact, resource overhead, throughput
3. **Security**: Isolation effectiveness, audit logs, compliance
4. **Operational**: Runbook accuracy, alerting effectiveness, team feedback
5. **Next Steps**: Tuning, optimizations, or roll-out to other services

Document findings and update runbook accordingly.

---

**Document Version**: 1.0  
**Last Updated**: April 21, 2026  
**Review Date**: May 21, 2026
