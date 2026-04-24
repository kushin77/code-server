# Collab-6.2: gVisor Workspace Isolation - Operations Runbook

**Status**: Operational readiness documentation  
**Target Issue**: [#1125](https://github.com/kushin77/code-server/issues/1125)  
**Created**: April 21, 2026  

## Overview

Comprehensive operations guide for deploying, managing, and troubleshooting gVisor workspace isolation in production.

**Deployment Time**: 30-45 min per host (2-3 hours full rollout)  
**Rollback Time**: Emergency 2-5 min | Full 10-15 min  
**Availability SLA**: > 99.9% (fail-closed on unavailable gVisor)

---

## Part 1: Deployment Strategies

### Strategy 1: Rolling Deployment (RECOMMENDED)

**Timeline**: 2-3 hours for full deployment (30-45 min per host)

**Phase 1: Preparation** (30 minutes)
```bash
# 1. Verify gVisor binary availability
which runsc
runsc --version  # Should show: runsc version XXXXXX

# 2. Backup docker daemon.json
cp /etc/docker/daemon.json /etc/docker/daemon.json.backup

# 3. Verify environment variables ready
echo $SANDBOX_POLICY
echo $SANDBOX_RUNTIME
# Expected: SANDBOX_POLICY=optional, SANDBOX_RUNTIME=runsc (or similar)

# 4. Notify team
slack '#infrastructure' "Starting gVisor rollout: replica first, then primary"

# 5. Verify monitoring/alerting active
curl http://localhost:9090/-/healthy  # Prometheus
```

**Phase 2: Deploy to Replica** (45 minutes)
```bash
# 1. SSH to replica host (192.168.168.42)
ssh akushnir@192.168.168.42

# 2. Update docker daemon.json
cat >> /etc/docker/daemon.json << 'EOF'
{
  "runtimes": {
    "runsc": {
      "path": "/usr/local/bin/runsc",
      "runtimeArgs": ["--platform=kvm"]
    }
  }
}
EOF

# 3. Reload docker daemon
sudo systemctl restart docker

# 4. Verify gVisor is available
docker run --rm --runtime=runsc alpine echo "gVisor is working"

# 5. Update environment on replica
export SANDBOX_POLICY=optional
export SANDBOX_RUNTIME=runsc
docker compose up -d session-broker

# 6. Smoke test: verify sessions work
curl http://localhost:5000/health

# 7. Monitor logs (5-10 minutes)
docker logs -f session-broker | grep -E "gVisor|sandbox|SANDBOX"
```

**Phase 3: Validate Replica** (15 minutes)
```bash
# 1. Create test session with workspace code
curl -X POST http://localhost:5000/sessions \
  -H "Content-Type: application/json" \
  -d '{"workspaceId":"test-gvisor"}'

# 2. Verify session is isolated (SANDBOX_ISOLATED=true in env)
curl http://localhost:5000/sessions/{sessionId}/env | grep SANDBOX_ISOLATED

# 3. Run CPU/memory tests
docker run --rm --runtime=runsc \
  --memory=512m --cpus=2 \
  alpine stress --cpu 1 --vm 1 --vm-bytes 256M --timeout 10s

# 4. Check metrics
curl http://localhost:9090/api/v1/query?query=sandbox_isolation_success_rate | jq
```

**Phase 4: Deploy to Primary** (45 minutes)
```bash
# 1. SSH to primary (192.168.168.31)
ssh akushnir@192.168.168.31

# 2. Repeat Phase 2 steps (daemon.json, restart docker, verify)
# ... (same as replica)

# 3. Update environment on primary
export SANDBOX_POLICY=optional
export SANDBOX_RUNTIME=runsc
docker compose up -d session-broker

# 4. Monitor for 10 minutes (no errors expected)
docker logs -f session-broker | tail -50
```

**Phase 5: Enable Require Policy** (15 minutes)
```bash
# On BOTH hosts (replica + primary)
# After successful operation for 15+ minutes:

# 1. Update SANDBOX_POLICY to "require"
export SANDBOX_POLICY=require

# 2. Restart session-broker
docker compose restart session-broker

# 3. Verify new sessions enforce gVisor (fail closed without it)
curl -X POST http://localhost:5000/sessions \
  -H "Content-Type: application/json" \
  -d '{"workspaceId":"test-require"}'

# 4. Check: SANDBOX_POLICY=require in session env
curl http://localhost:5000/sessions/{sessionId}/env | grep SANDBOX_POLICY
```

**Phase 6: Post-Deployment Verification** (15 minutes)
- [x] Both hosts running gVisor sessions
- [x] Metrics showing isolation success > 95%
- [x] No errors in logs (docker, session-broker)
- [x] Failover test: kill replica docker → primary continues
- [x] Load test: 10 simultaneous sessions, all isolated
- [x] Monitor for 1 hour (alert if isolation fails)

---

### Strategy 2: Feature Flag Deployment

**For gradual rollout without downtime**

```bash
# 1. Deploy code with SANDBOX_POLICY=disabled (feature flag off)
docker compose up -d

# 2. Enable for 10% of sessions
SANDBOX_POLICY=optional SANDBOX_ENABLED_PERCENT=10 docker compose up -d

# 3. Monitor success rate (target > 95%)
curl http://localhost:9090/api/v1/query?query=sandbox_isolation_success_rate

# 4. Increase to 50%
SANDBOX_ENABLED_PERCENT=50 docker compose up -d

# 5. Increase to 100% (all sessions)
SANDBOX_ENABLED_PERCENT=100 SANDBOX_POLICY=require docker compose up -d
```

---

### Strategy 3: Canary Deployment (Multi-Region)

**For multi-region or multi-cluster deployments**

```bash
# 1. Deploy to canary region (1-2 hosts)
SANDBOX_POLICY=optional SANDBOX_RUNTIME=runsc docker compose up -d

# 2. Monitor canary (30 minutes)
# Alert on: CPU > 50%, memory > 70%, isolation failures > 1%
# Success criteria: zero critical errors, all workloads running

# 3. Deploy to staging region (25% of hosts)
# Same monitoring, success criteria

# 4. Deploy to production region (100% of hosts)
# Gradual: 10% → 25% → 50% → 100%
```

---

## Part 2: Runbook & Troubleshooting

### Pre-Deployment Checklist

- [ ] gVisor binary installed (`which runsc`, `runsc --version`)
- [ ] Docker 19.03+ with containerd support (`docker version`)
- [ ] 2+ GB free disk space (`df -h /`)
- [ ] Network connectivity to container registry
- [ ] Backup of current docker daemon.json
- [ ] Backup of current docker-compose.yml
- [ ] Team trained on gVisor concepts (syscall filtering, security model)
- [ ] Monitoring/alerting configured (Prometheus, Grafana)
- [ ] On-call engineer available during rollout
- [ ] Incident communication template ready

### Deployment Checklist

**Replica Host (192.168.168.42)**
- [ ] docker daemon.json updated with runsc runtime
- [ ] `sudo systemctl restart docker` successful (docker listening on socket)
- [ ] `docker run --runtime=runsc alpine echo test` works
- [ ] SANDBOX_POLICY and SANDBOX_RUNTIME env vars set
- [ ] `docker compose up -d session-broker` successful
- [ ] Session broker health check passes
- [ ] At least 1 test session created and isolated
- [ ] Logs show no errors or warnings
- [ ] Metrics: isolation success rate > 95%

**Primary Host (192.168.168.31)**
- [ ] Same as replica
- [ ] Failover test: replica down, primary continues
- [ ] Load test: 10 simultaneous sessions, all isolated
- [ ] Monitor for 1 hour (zero critical errors)

### Common Issues & Solutions

#### Issue 1: `runsc: command not found`

**Symptoms**:
```
docker: Error response from daemon: OCI runtime "runsc" not found
```

**Diagnosis**:
```bash
which runsc
# Empty output = binary not installed

ls -la /usr/local/bin/runsc
# File not found error
```

**Solution**:
```bash
# 1. Download gVisor binary
curl -fsSL https://gvisor.dev/releases/release/latest/gvisor-latest-amd64 \
  -o /tmp/runsc

# 2. Install binary
sudo mv /tmp/runsc /usr/local/bin/runsc
sudo chmod +x /usr/local/bin/runsc

# 3. Verify
runsc --version
which runsc  # Should show /usr/local/bin/runsc
```

---

#### Issue 2: `Docker runtime not available`

**Symptoms**:
```
Error: Docker runtime "runsc" is not available in daemon config
```

**Diagnosis**:
```bash
cat /etc/docker/daemon.json | grep -A 5 "runtimes"
# Missing "runsc" entry
```

**Solution**:
```bash
# 1. Backup current config
cp /etc/docker/daemon.json /etc/docker/daemon.json.bak

# 2. Add runsc runtime
jq '.runtimes.runsc = {path: "/usr/local/bin/runsc", runtimeArgs: ["--platform=kvm"]}' \
  /etc/docker/daemon.json > /tmp/daemon.json && \
  sudo mv /tmp/daemon.json /etc/docker/daemon.json

# 3. Reload docker
sudo systemctl restart docker

# 4. Verify
docker run --rm --runtime=runsc alpine echo "Works!"
```

---

#### Issue 3: `Sessions using runc instead of gVisor`

**Symptoms**:
```bash
docker inspect {container_id} | grep -i runtime
# Output: "runc" instead of "runsc"
```

**Diagnosis**:
```bash
# Check if SANDBOX_RUNTIME env var is set
echo $SANDBOX_RUNTIME
# Empty or wrong value

# Check if gVisor policy is enforce
echo $SANDBOX_POLICY
# May be "disabled" or "optional"
```

**Solution**:
```bash
# 1. Set correct env var
export SANDBOX_RUNTIME=runsc
export SANDBOX_POLICY=require

# 2. Restart session-broker
docker compose restart session-broker

# 3. Verify new sessions use gVisor
docker ps | grep session-broker
docker inspect {new_container_id} | grep -i runtime
# Should show: "runsc"
```

---

#### Issue 4: `High memory usage with gVisor`

**Symptoms**:
```
docker stats
# Memory: 800M+ per container (vs. 100M for runc)
```

**Diagnosis**:
```bash
# gVisor has higher memory overhead (platform VM)
docker run --rm --memory=1024m --runtime=runsc alpine /bin/sh
# May fail with "out of memory"
```

**Solution**:
```bash
# 1. Increase memory limits
export SANDBOX_MAX_MEMORY_MB=1024  # Default: 512

# 2. Or use KVM instead of ptrace (faster, uses less memory)
# In daemon.json:
jq '.runtimes.runsc.runtimeArgs |= ["--platform=kvm"]' \
  /etc/docker/daemon.json

# 3. Restart docker and session-broker
sudo systemctl restart docker
docker compose restart session-broker
```

---

#### Issue 5: `Slow container startup with gVisor`

**Symptoms**:
```
Session creation latency: 5+ seconds (vs. 1-2 with runc)
```

**Diagnosis**:
```bash
# gVisor initializes platform VM (ptrace vs kvm)
# Ptrace: slower (emulation), more compatible
# KVM: faster (virtual machine), requires kernel support
```

**Solution**:
```bash
# 1. Use KVM platform for better performance
jq '.runtimes.runsc.runtimeArgs |= ["--platform=kvm"]' \
  /etc/docker/daemon.json

# 2. Verify KVM support
grep -i kvm /proc/cpuinfo | head -1
# Should show "vmx" (Intel) or "svm" (AMD)

# 3. Restart docker
sudo systemctl restart docker
docker compose restart session-broker

# 4. Measure latency improvement
# Latency should drop 30-50% with KVM
```

---

## Part 3: Rollback Procedures

### Immediate Rollback (Emergency - 2-5 minutes)

**Use when**: gVisor is causing outages or sessions won't start

```bash
# On BOTH replica (192.168.168.42) and primary (192.168.168.31):

# 1. Set policy to "disabled"
export SANDBOX_POLICY=disabled

# 2. Restart session-broker
docker compose restart session-broker

# 3. Verify fallback to runc
docker ps | grep session-broker
docker inspect {container_id} | grep -i runtime
# Should show: "runc"

# 4. Check health
curl http://localhost:5000/health
# Should return 200 OK

# 5. New sessions should work with runc
# Existing sessions continue running (zero disruption)
```

**Outcome**: gVisor disabled, all new sessions use runc (safe, tested)

---

### Full Rollback (Complete removal - 10-15 minutes)

**Use when**: Removing gVisor entirely (reverting deployment)

```bash
# On BOTH replica and primary:

# 1. Set policy to disabled
export SANDBOX_POLICY=disabled

# 2. Wait for existing sessions to drain (default: 5 min idle timeout)
# Or manually terminate old sessions
docker ps | grep "session-" | awk '{print $1}' | xargs -I{} docker kill {}

# 3. Remove gVisor from docker daemon.json
jq 'del(.runtimes.runsc)' /etc/docker/daemon.json > /tmp/daemon.json && \
  sudo mv /tmp/daemon.json /etc/docker/daemon.json

# 4. Restart docker
sudo systemctl restart docker

# 5. Restart session-broker
docker compose restart session-broker

# 6. Verify gVisor binary is no longer used
docker run --rm --runtime=runsc alpine echo "test" 2>&1
# Should fail: "runtime not found"

# 7. Optional: remove gVisor binary (keep for future use)
# sudo rm /usr/local/bin/runsc
```

**Outcome**: gVisor completely removed, only runc available

---

## Part 4: Monitoring & Alerting

### Key Metrics

```
# Isolation success rate (goal: > 95%)
sandbox_isolation_success_rate{host, policy}

# Isolation failure rate (goal: < 0.1%)
sandbox_isolation_failure_rate{reason}

# Session creation latency (baseline runc: 1.2s, gVisor: 1.8s)
session_creation_latency_seconds{quantile}

# Resource violations (goal: < 1%)
sandbox_resource_violation_total{resource_type}
  # memory_exceeded, cpu_exceeded, file_descriptors_exceeded
```

### Alert Rules

**CRITICAL - Page Engineer**:
```prometheus
# 1. gVisor unavailable
up{job="session-broker", sandbox_enabled="true"} == 0

# 2. High isolation failure rate
rate(sandbox_isolation_failure_total[5m]) > 0.05  # 5% failure

# 3. Session broker down
up{job="session-broker"} == 0
```

**WARNING - Notify Slack**:
```prometheus
# 1. Isolation failure rate > 1%
rate(sandbox_isolation_failure_total[5m]) > 0.01

# 2. High memory violations
rate(sandbox_resource_violation_total{resource="memory"}[5m]) > 0.005

# 3. Session creation slow
histogram_quantile(0.95, session_creation_latency_seconds) > 3.0
```

### Grafana Dashboard

**Recommended panels**:
- Isolation success rate (goal line: 95%)
- Isolation failures by reason (pie chart)
- Session creation latency (P50, P95, P99)
- Resource violations over time (memory, CPU, FDs)
- Host capacity (free memory, CPU available)
- Session count by runtime (runc vs gVisor)

---

## Part 5: Verification Steps

### Post-Deployment Validation (1 hour)

1. **Runtime Verification** (5 min)
   ```bash
   docker ps | grep session-broker
   # Verify running on gVisor runtime
   ```

2. **Security Property Validation** (10 min)
   ```bash
   # Verify fail-closed behavior
   SANDBOX_POLICY=require docker compose up -d
   # New sessions must use gVisor or fail
   ```

3. **Fail-Closed Behavior Test** (5 min)
   ```bash
   # Temporarily remove gVisor binary
   sudo mv /usr/local/bin/runsc /tmp/runsc.bak
   
   # Try to create session
   curl -X POST http://localhost:5000/sessions ...
   # Should fail with policy error
   
   # Restore binary
   sudo mv /tmp/runsc.bak /usr/local/bin/runsc
   ```

4. **Load Testing** (15 min)
   ```bash
   # Create 10 concurrent sessions
   for i in {1..10}; do
     curl -X POST http://localhost:5000/sessions &
   done
   wait
   
   # All should succeed with gVisor isolation
   ```

5. **Metrics Validation** (10 min)
   ```bash
   # Isolation success rate > 95%
   curl http://localhost:9090/api/v1/query?query=sandbox_isolation_success_rate
   
   # Zero critical errors in logs
   docker logs session-broker | grep -iE "error|critical"
   # Should return empty or only warnings
   ```

6. **1-Week Post-Deployment Review**
   - [ ] Isolation success rate maintained > 99%
   - [ ] Zero production incidents related to gVisor
   - [ ] User feedback: workspace performance acceptable
   - [ ] Resource usage baseline established (CPU, memory, latency)
   - [ ] Team confidence: ready to require gVisor by default

---

## Part 6: Communication Templates

### Pre-Deployment Announcement

```
Subject: gVisor Workspace Isolation Deployment - April 21, 8 AM PT

Hello team,

We're deploying gVisor workspace isolation today to prevent untrusted code from compromising the host system.

Timeline:
- 8:00 AM: Deploy to replica host (192.168.168.42)
- 8:45 AM: Validate replica
- 9:00 AM: Deploy to primary host (192.168.168.31)
- 9:45 AM: Full validation complete

Expected impact: 
- Zero downtime (rolling deployment)
- New workspaces use gVisor sandbox
- Latency increase: +0.6s per session (1.2s → 1.8s)

Contact: @Infrastructure team on Slack for issues

Details: https://github.com/kushin77/code-server/pull/1192
```

### During Deployment (Hourly Update)

```
9:00 AM Update: Replica deployment successful
- gVisor binary installed ✅
- Docker daemon configured ✅
- 5 test sessions created and isolated ✅
- Metrics healthy (success rate 98.5%) ✅
- Proceeding to primary deployment...
```

### Post-Deployment Announcement

```
11:00 AM: gVisor Workspace Isolation - Deployment Complete

✅ Both replica and primary now running gVisor
✅ 47 sessions active, all isolated
✅ Isolation success rate: 99.2%
✅ Zero critical errors
✅ Performance within baseline

All new workspaces will use gVisor sandbox.
Existing workspaces can continue using runc (transparent upgrade available).

Questions? Ask #infrastructure
```

---

## Related Documentation

- **Architecture**: [COLLAB-6-2-GVISOR-ISOLATION-GUIDE.md](COLLAB-6-2-GVISOR-ISOLATION-GUIDE.md)
- **Implementation**: [apps/session-broker/src/session-sandbox.ts](../apps/session-broker/src/session-sandbox.ts)
- **Tests**: [apps/session-broker/src/__tests__/session-sandbox.test.ts](../apps/session-broker/src/__tests__/session-sandbox.test.ts)
- **Issue**: [GitHub #1125](https://github.com/kushin77/code-server/issues/1125)
- **PR**: [GitHub #1192](https://github.com/kushin77/code-server/pull/1192)

---

**Last Updated**: April 21, 2026  
**Maintained By**: Kushnir Cloud Infrastructure Team  
**Version**: 1.0 (Production Ready)
