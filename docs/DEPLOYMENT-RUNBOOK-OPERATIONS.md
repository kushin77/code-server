# Production Deployment Runbook - Simplified

**Purpose**: Quick reference for ops team to safely deploy code changes to both production replicas  
**Audience**: Operations Engineers, SRE, DevOps  
**Deployment Time**: 8-13 minutes (parallel)  
**Target Availability**: Zero downtime via load balancer switching  
**Last Updated**: April 24, 2026

---

## Quick Reference - 5 Minute Deployment

```bash
# Prerequisites: SSH keys configured, docker-compose pull credentials cached
# Location: Run from any Linux box with SSH access to 192.168.168.31 and 192.168.168.42

# Full deployment (parallel):
bash scripts/ops/redeploy.sh

# Service-specific deployment:
bash scripts/ops/redeploy-service.sh <service-name>

# With verification:
bash scripts/ops/verify-production-readiness.sh
```

---

## Prerequisites

### SSH Key Setup ✅

Ensure SSH keys are configured on your local machine:

```bash
# 1. Generate key (if not already done)
ssh-keygen -t ed25519 -f ~/.ssh/kushnir-prod -C "production@kushnir.cloud"

# 2. Copy public key to replicas
ssh-copy-id -i ~/.ssh/kushnir-prod.pub akushnir@192.168.168.31
ssh-copy-id -i ~/.ssh/kushnir-prod.pub akushnir@192.168.168.42

# 3. Test connectivity
ssh -i ~/.ssh/kushnir-prod akushnir@192.168.168.31 'echo Connected to R31'
ssh -i ~/.ssh/kushnir-prod akushnir@192.168.168.42 'echo Connected to R42'
```

### Docker Credentials

Ensure you have pull credentials for any private registries:

```bash
# On local machine (will be used for docker compose pull)
docker login <registry-url>
```

### Repository Access

```bash
# Clone or update repository
git clone https://github.com/kushin77/code-server.git
cd code-server
git checkout main
git pull origin main
```

---

## Deployment Procedures

### Option 1: Full Cluster Deployment (Parallel) ⚡

**Best for**: Code changes, configuration updates, new releases  
**Time**: 8-13 minutes (parallel to both replicas)  
**Downtime**: < 1 second (load balancer switch)

```bash
# 1. Navigate to repository
cd /path/to/code-server-enterprise

# 2. Review current state
git log --oneline -5
docker-compose ps

# 3. Execute parallel deployment
bash scripts/ops/redeploy.sh

# Expected output:
# 🚀 Executing standard redeploy on 192.168.168.31...
# 🚀 Executing standard redeploy on 192.168.168.42...
# ✅ Node 192.168.168.31 is up-to-date
# ✅ Node 192.168.168.42 is up-to-date

# 4. Verify deployment
bash scripts/ops/verify-deployment-state.sh
```

### Option 2: Sequential Deployment (Conservative)

**Best for**: Critical systems, manual verification between replicas  
**Time**: 15-18 minutes (sequential)  
**Downtime**: < 1 second per replica (if loadbalancer detects downtime)

```bash
# Deploy to Replica 1 (R31)
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose pull && \
  docker compose up -d --remove-orphans'

# Wait for services to start
sleep 60

# Verify R31 health
bash scripts/ops/validate-cluster-parity.sh 192.168.168.31

# Deploy to Replica 2 (R42)
ssh akushnir@192.168.168.42 'cd code-server-enterprise && \
  docker compose pull && \
  docker compose up -d --remove-orphans'

# Wait for services to start
sleep 60

# Final verification
bash scripts/ops/validate-cluster-parity.sh 192.168.168.42
```

### Option 3: Service-Specific Deployment

**Best for**: Updating individual services (Caddy, Prometheus, etc.)  
**Time**: 2-5 minutes  
**Downtime**: Service-specific (seconds to minutes)

```bash
# Deploy specific service to both replicas
bash scripts/ops/redeploy-service.sh caddy

# Or deploy to specific replica
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose pull caddy && \
  docker compose up -d caddy'
```

---

## Pre-Deployment Checklist

- [ ] Current main branch pulled and reviewed
- [ ] CI checks passing (GitHub Actions)
- [ ] No P0 or P1 issues blocking deployment
- [ ] SSH keys tested to both replicas
- [ ] Docker credentials cached
- [ ] Loadbalancer is healthy (curl HAProxy stats)
- [ ] Both replicas responding to health checks
- [ ] Stakeholder notification sent (if required)

---

## Deployment Execution Steps

### Step 1: Pre-Flight Validation

```bash
# Check cluster health before deployment
bash scripts/ops/verify-production-readiness.sh

# Expected output: All checks passing ✅
```

### Step 2: Pre-Deployment Snapshot

```bash
# Document current state
docker-compose ps > /tmp/pre-deploy-services.txt
ssh akushnir@192.168.168.31 'docker-compose ps' >> /tmp/pre-deploy-services.txt
ssh akushnir@192.168.168.42 'docker-compose ps' >> /tmp/pre-deploy-services.txt

# Check current versions
git log --oneline -1
```

### Step 3: Execute Deployment

```bash
# Deploy to both replicas in parallel
bash scripts/ops/redeploy.sh

# Monitor output for errors
# Should see: "Pulling image", "Container XXX started", "✅ Node is up-to-date"
```

### Step 4: Post-Deployment Health Checks

```bash
# Verify health endpoints responding
curl -s http://192.168.168.31:8080/health  # Should return 200 OK
curl -s http://192.168.168.42:8080/health  # Should return 200 OK

# Verify HTTPS health endpoint
curl -s -k https://192.168.168.31/health    # Should return 200 OK
curl -s -k https://192.168.168.42/health    # Should return 200 OK

# Check service parity
bash scripts/ops/validate-cluster-parity.sh
```

### Step 5: Verification Checklist

- [ ] Both replicas reporting healthy status
- [ ] Load balancer distributing traffic correctly
- [ ] All core services running (code-server, caddy, postgres, redis, etc.)
- [ ] Database replication lag < 1 second
- [ ] Redis Sentinel reporting healthy
- [ ] Prometheus scraping all targets
- [ ] Grafana accessible and showing metrics
- [ ] No error logs in docker-compose logs

---

## Health Check Endpoints

### Quick Health Status

```bash
# HTTP health endpoint (unencrypted)
curl -s http://192.168.168.31:8080/health
curl -s http://192.168.168.42:8080/health

# HTTPS health endpoint (via IDE domain, uses loadbalancer certificate)
curl -s -k https://ide.kushnir.cloud/health

# Response format (200 OK):
# { "status": "UP", "timestamp": "2026-04-24T10:00:00Z", "version": "4.115.0" }
```

### Service-Specific Health

```bash
# Code-Server health
curl -s http://localhost:8443/api/v1/applications/overview

# PostgreSQL replication status
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose exec postgres-primary psql -U postgres -c "SELECT slot_name, active FROM pg_replication_slots;"'

# Redis Sentinel status
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker compose exec redis-sentinel redis-cli -p 26379 sentinel masters'

# Prometheus targets
curl -s http://192.168.168.31:9090/api/v1/targets | jq '.data.activeTargets | length'
```

---

## Parallel Execution Timing

**Typical deployment timeline** (parallel mode):

| Phase | Duration | Activity |
|-------|----------|----------|
| Pull Docker images | 2-4 min | Both replicas download new images in parallel |
| Stop old containers | 30 sec | Graceful shutdown of old services |
| Start new containers | 1-2 min | Services starting on both replicas in parallel |
| Service initialization | 1-2 min | Apps binding ports, connecting to databases |
| Health check verification | 30 sec | Load balancer confirms both replicas healthy |
| **Total** | **8-13 min** | Full parallel deployment |

**Key optimization**: Steps 1-3 run in parallel on both replicas, reducing total time by 50% vs sequential.

---

## Troubleshooting

### Issue: Health Check Timeout

**Symptoms**: Health endpoint not responding after deployment

**Causes**:
- Services still initializing (wait 30-60 seconds)
- Container startup failed (check logs)
- Network connectivity issue

**Resolution**:
```bash
# Check service logs
docker-compose logs --tail 50 caddy
docker-compose logs --tail 50 code-server

# Restart specific service
docker-compose restart caddy

# Wait for health check to pass (30-60 seconds)
curl -s http://192.168.168.31:8080/health
```

### Issue: Database Replication Lag High

**Symptoms**: `pg_stat_replication` shows lag > 1 MB

**Causes**:
- Heavy write load during deployment
- Network latency between replicas
- Replication temporary backlog

**Resolution**:
```bash
# Monitor replication lag
watch -n 5 'ssh akushnir@192.168.168.31 "cd code-server-enterprise && \
  docker compose exec postgres-primary psql -U postgres -c \"SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;\""'

# Wait for lag to reduce to < 1 second (typically 30-60 seconds)
```

### Issue: Service Failed to Start

**Symptoms**: `docker-compose ps` shows container with status `Exited (1)`

**Causes**:
- Port conflict
- Configuration error
- Insufficient resources

**Resolution**:
```bash
# Check service logs
docker-compose logs <service-name> --tail 100

# Verify port availability
netstat -tlnp | grep 8443
netstat -tlnp | grep 5432

# Rollback to previous version
git checkout HEAD~1
docker-compose pull
docker-compose up -d
```

### Issue: Load Balancer Not Switching Traffic

**Symptoms**: Old version still serving after deployment

**Causes**:
- Load balancer health checks stale
- Load balancer not detecting replica restart
- Connection pooling holding old connections

**Resolution**:
```bash
# Force load balancer health check
curl -s http://192.168.168.31:8080/health  # Should return 200
curl -s http://192.168.168.42:8080/health  # Should return 200

# Reload loadbalancer (Caddy)
docker-compose restart caddy

# Wait 30 seconds for connection drain
sleep 30

# Verify traffic switched to new version
curl -s http://ide.kushnir.cloud/api/version  # Check version header
```

---

## Rollback Procedures

### Quick Rollback (< 5 minutes)

```bash
# If deployment failed, immediately revert to previous commit
git revert HEAD
git push origin main

# Or revert to specific known-good commit
git reset --hard eb05d50a
git push -f origin main

# Re-run deployment with known-good version
bash scripts/ops/redeploy.sh
```

### Database Rollback

```bash
# If schema migration fails
ssh akushnir@192.168.168.31 'cd code-server-enterprise && \
  docker-compose exec postgres-primary bash -c "
    pg_dump -U postgres mydb > /tmp/backup-$(date +%s).sql
    psql -U postgres mydb < /tmp/previous-schema-backup.sql
  "'
```

---

## Monitoring During Deployment

### Real-Time Metrics

```bash
# Monitor in separate terminal
watch -n 5 'bash scripts/ops/verify-deployment-state.sh'

# Or use Grafana dashboard
# Navigate to: http://192.168.168.31:3000 → Dashboards → Cluster Health
# Look for: Replica availability, service count, replication lag
```

### Log Aggregation

```bash
# Stream logs from both replicas
ssh akushnir@192.168.168.31 'docker-compose logs -f' &
ssh akushnir@192.168.168.42 'docker-compose logs -f' &
wait
```

---

## Post-Deployment Validation

### Run Full Validation Suite

```bash
# Comprehensive post-deployment verification
bash scripts/ops/verify-production-readiness.sh
bash scripts/ops/validate-cluster-parity.sh
bash scripts/ops/verify-deployment-state.sh

# All checks should pass ✅
```

### Manual Verification Checklist

- [ ] Both replicas showing same version (git rev-parse HEAD)
- [ ] All services running (docker-compose ps)
- [ ] Health endpoints returning 200 OK
- [ ] Database replication lag < 1 second
- [ ] No error logs in container output
- [ ] IDE accessible at https://ide.kushnir.cloud
- [ ] Portal accessible at https://kushnir.cloud
- [ ] Monitoring dashboards updating correctly

---

## Emergency Contacts

- **Ops Team Lead**: akushnir (primary)
- **Escalation**: Check GitHub issue #1663 (Failover Runbook) for escalation procedures
- **On-Call SRE**: See PagerDuty rotation
- **Communication**: #ops Slack channel

---

## Related Documentation

- [Failover Runbook](FAILOVER-RUNBOOK-SIMPLIFIED.md) - Disaster recovery procedures
- [SLA & Metrics](PRODUCTION-SLA-METRICS.md) - Monitoring and alerting
- [Grafana Setup](GRAFANA-DASHBOARD-SETUP.md) - Dashboard installation
- [Infrastructure Reference](IaC-DEPLOYMENT-REFERENCE.md) - Infrastructure as Code details

---

**Version**: 1.0  
**Last Updated**: April 24, 2026  
**Status**: ✅ Production-Ready  
**Next Review**: May 24, 2026
