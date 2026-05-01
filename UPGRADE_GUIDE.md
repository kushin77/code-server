# Platform Upgrade Guide v1.0.0

**Document Version**: 1.0.0  
**Last Updated**: May 1, 2026  
**Current Version**: 1.0.0-production  
**Next Target**: 1.1.0 (Q2 2026)

---

## Overview

This guide provides procedures for upgrading the code-server platform to newer versions with zero-downtime strategies, automatic rollback, and comprehensive validation.

**Key Principles**:
- ✅ **Zero-downtime**: Replica standby maintains service availability during primary upgrade
- ✅ **Automated rollback**: Previous version easily reverted if issues detected
- ✅ **Comprehensive testing**: Full validation suite runs before marking upgrade complete
- ✅ **Staged rollout**: Optional per-service upgrade for large changes

---

## Pre-Upgrade Checklist

### 1. Backup Critical Data

```bash
# Backup PostgreSQL
docker exec postgresql-primary pg_dump -U postgres > database-backup-$(date +%Y%m%d-%H%M%S).sql

# Backup Redis
docker exec redis-primary redis-cli BGSAVE
docker exec redis-primary redis-cli LASTSAVE

# Backup Redpanda offsets
docker exec redpanda-primary rpk topic export -o backup.txt my-topic

# Backup application secrets
docker exec vault-primary vault kv get -format=json secret/all > vault-backup.json

# Backup Terraform state
cp terraform/environments/private/terraform.tfstate terraform/environments/private/terraform.tfstate.backup-$(date +%Y%m%d)
```

### 2. Pre-Upgrade Validation

```bash
# Run full validation suite
scripts/ops/full-deployment-test.sh

# Capture baseline metrics
docker exec prometheus curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length' > baseline-targets.txt

# Record system health
docker exec postgresql-primary psql -U postgres -c "SELECT version();" > baseline-postgres-version.txt
redis-cli INFO server > baseline-redis-info.txt

# Check available disk space
df -h / > baseline-disk-space.txt
```

### 3. Communication

```bash
# Notify users of maintenance window
echo "Upgrade scheduled: $(date -d '+1 hour') UTC"
echo "Expected duration: 15-30 minutes"
echo "Services: All (with zero-downtime via HA failover)"

# Post to #incidents channel
# Subject: Platform upgrade v1.0.0 → v1.1.0 scheduled
```

---

## Upgrade Procedures

### Strategy 1: Rolling Upgrade (Zero-Downtime) - RECOMMENDED

Upgrade replica first, then primary, with automatic failover via Keepalived VIP.

#### Phase 1: Prepare New Version

```bash
# Clone new version to temporary directory
cd /tmp
git clone https://github.com/code-server-enterprise/platform.git platform-v1.1.0
cd platform-v1.1.0
git checkout v1.1.0

# Run pre-deployment validation
scripts/ops/full-deployment-test.sh --dry-run

# Build new Docker images (if applicable)
docker build -t code-server:1.1.0 .
```

#### Phase 2: Upgrade Replica (Standby Host)

The replica upgrade happens without service interruption since primary is handling traffic.

```bash
# SSH to replica host
ssh ops@192.168.168.42

# On replica, stop services in reverse dependency order
docker-compose -f docker-compose.yml -f docker-compose.enterprise.yml \
  -f docker-compose.prod.yml stop \
  appsmith code-server-ide gitlab vault

# Backup current state
docker commit code-server-ide code-server-ide:1.0.0-backup
docker commit appsmith appsmith:1.0.0-backup

# Update to new version
cd /home/ops/code-server
git fetch origin v1.1.0
git checkout v1.1.0

# Pull new images
docker-compose -f docker-compose.yml -f docker-compose.enterprise.yml \
  -f docker-compose.prod.yml pull

# Start services with new version
docker-compose -f docker-compose.yml -f docker-compose.enterprise.yml \
  -f docker-compose.prod.yml up -d \
  appsmith code-server-ide gitlab vault

# Wait for services to become healthy
sleep 30
docker-compose ps
```

#### Phase 3: Validate Replica Upgrade

```bash
# Test replica services
curl -s http://192.168.168.42:8090 -I | head -1  # Code-Server IDE
curl -s http://192.168.168.42:3000 -I | head -1  # Grafana
curl -s http://192.168.168.42:8200 -I | head -1  # Vault

# Check database replication
docker exec postgresql-replica psql -U postgres -c \
  "SELECT now() - pg_last_xact_replay_time();"

# Should show <1 second lag
```

#### Phase 4: Manual Failover to Replica

Now that replica is upgraded, we failover to it and upgrade primary.

```bash
# Step 1: Manually move VIP to replica
ssh ops@192.168.168.42

docker exec keepalived-replica sudo ip addr add 192.168.168.50/24 dev eth0

# Step 2: Verify applications are now using replica
curl -s http://192.168.168.50:8090 -I | head -1
ssh ops@192.168.168.50 "docker ps" | wc -l  # Should show ~50 containers

# Note: If automatic VIP failover exists, verify it triggered:
docker exec keepalived-replica ip addr show | grep 192.168.168.50
```

#### Phase 5: Upgrade Primary (Old Primary, Now Standby)

```bash
# SSH to old primary (now standby)
ssh ops@192.168.168.31

# Verify VIP is no longer here
docker exec keepalived-primary ip addr show | grep 192.168.168.50  # Should be empty

# Safe to upgrade - no traffic being served
docker-compose -f docker-compose.yml -f docker-compose.enterprise.yml \
  -f docker-compose.prod.yml pull

docker-compose -f docker-compose.yml -f docker-compose.enterprise.yml \
  -f docker-compose.prod.yml restart

# Wait for healthy state
sleep 30
docker-compose ps

# Verify database is catching up with replica
docker exec postgresql-primary psql -U postgres -c \
  "SELECT pg_last_wal_receive_lsn(), pg_current_wal_lsn();"
```

#### Phase 6: Validate Complete Platform

```bash
# Run full validation suite
scripts/ops/full-deployment-test.sh

# Expected output:
# ✅ Phase 1: Infrastructure Check - PASSED
# ✅ Phase 2: Drift Detection - PASSED
# ✅ Phase 3: Deployment Simulation - PASSED
# ✅ Phase 4: Health Checks - PASSED
# ✅ Phase 5: Rollback Testing - PASSED
# ✅ Phase 6: GitLab Parity - PASSED

# Monitor metrics during upgrade completion
docker exec prometheus curl -s http://localhost:9090/api/v1/query?query=up | jq '.data.result | length'
```

#### Phase 7: Failback to Primary (Optional)

If you want primary to be active again:

```bash
# Option A: Manual failback
docker exec keepalived-primary sudo ip addr add 192.168.168.50/24 dev eth0

# Option B: Let Keepalived handle it (if configured with automatic priority)
# Keepalived automatically fails back when primary recovers
```

---

### Strategy 2: Blue-Green Deployment (Alternative)

Run both versions simultaneously, switch traffic via load balancer.

#### Setup (Preparation Phase)

```bash
# Provision new infrastructure (Green environment)
terraform workspace new green
terraform -chdir=terraform/environments/private apply -var environment=green

# Deploy v1.1.0 to green environment
git checkout v1.1.0
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Run validation on green
scripts/ops/full-deployment-test.sh
```

#### Traffic Switch

```bash
# Update DNS or load balancer to point to green
# Old (Blue): 192.168.168.31
# New (Green): 192.168.168.100

# Method 1: DNS CNAME switch (if using Keepalived VIP)
docker exec keepalived ip addr del 192.168.168.50 dev eth0
docker exec keepalived ip addr add 192.168.168.100 dev eth0

# Method 2: Update load balancer config
# Update Traefik backend targets to point to green

# Verification
curl -s http://192.168.168.50/api/version  # Should show v1.1.0
```

#### Cleanup (Post-Switch)

```bash
# After 24-48 hours of stable operation
terraform workspace select blue
terraform destroy  # Decommission old environment

# Promote green to primary
terraform workspace delete blue
terraform workspace rename green blue
```

---

## Service-Specific Upgrades

### Upgrading PostgreSQL

```bash
# PostgreSQL major version upgrades require special handling
# Example: 13 → 14

# 1. Create backup of current database
docker exec postgresql-primary pg_dumpall > /backup/postgres-13-full.sql

# 2. On replica, upgrade first
ssh ops@192.168.168.42
docker exec postgresql-replica pg_upgrade \
  -b /usr/lib/postgresql/13/bin \
  -B /usr/lib/postgresql/14/bin \
  -d /var/lib/postgresql/13/data \
  -D /var/lib/postgresql/14/data

# 3. After replica validated, upgrade primary (during failover window)

# 4. Analyze query performance post-upgrade
docker exec postgresql-primary ANALYZE;
```

**Estimated downtime**: 5-15 minutes (replica upgrade), then failover window

### Upgrading Redis

```bash
# Redis upgrades are usually non-breaking
# Just pull new image and restart

docker pull redis:7.2.0

docker-compose -f docker-compose.yml -f docker-compose.enterprise.yml \
  -f docker-compose.prod.yml pull redis-primary

docker-compose restart redis-primary redis-replica

# Verify cluster state
docker exec redis-primary redis-cli CLUSTER INFO
```

**Estimated downtime**: 30 seconds (auto-failover to replica)

### Upgrading Redpanda

```bash
# Redpanda broker rolling upgrade
# Upgrade one broker at a time, waiting for cluster recovery between

# 1. Upgrade replica broker
docker pull redpanda:v24.1
docker-compose pull redpanda-replica
docker-compose restart redpanda-replica

# 2. Wait for cluster health
sleep 30
docker exec redpanda-primary rpk cluster info

# 3. Upgrade primary broker
docker-compose restart redpanda-primary

# 4. Verify topic replication
docker exec redpanda-primary rpk topic status -d
```

**Estimated downtime**: Zero (broker rolling upgrade)

### Upgrading Prometheus

```bash
# Prometheus configuration may change
# Always backup configuration before upgrade

cp prometheus.yml prometheus.yml.backup

docker pull prom/prometheus:latest

# Validate configuration before starting
docker run --rm -v $(pwd):/etc/prometheus prom/prometheus:latest \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus

# Restart
docker-compose restart prometheus

# Verify targets loaded
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'
```

**Estimated downtime**: <1 minute (metrics collection paused during restart)

### Upgrading Application Services

```bash
# For stateless services (Code-Server, Appsmith, GitLab)

# 1. Update image tag in docker-compose.yml
# Change: image: code-server:1.0.0
# To:     image: code-server:1.1.0

# 2. Pull and restart
docker-compose pull code-server-ide
docker-compose restart code-server-ide

# 3. Verify service health
docker-compose ps code-server-ide
curl -I http://localhost:8090/health
```

**Estimated downtime**: <30 seconds (service restart window)

---

## Rollback Procedures

### Rollback Entire Platform

If upgrade encounters critical issues:

#### Option 1: Git Rollback (Simplest)

```bash
# If issues detected during upgrade
git log --oneline | head -10

# Identify previous version commit
PREVIOUS_COMMIT=abc1234

# Checkout previous version
git checkout $PREVIOUS_COMMIT

# Restart services
docker-compose -f docker-compose.yml -f docker-compose.enterprise.yml \
  -f docker-compose.prod.yml pull

docker-compose -f docker-compose.yml -f docker-compose.enterprise.yml \
  -f docker-compose.prod.yml up -d

# Run validation
scripts/ops/full-deployment-test.sh
```

#### Option 2: Docker Image Rollback

```bash
# If previous version committed to Docker
docker ps | grep code-server-ide
docker stop code-server-ide

# Start previous version
docker run -d --name code-server-ide:prev code-server-ide:1.0.0-backup

# If using docker-compose
docker-compose down
git checkout HEAD~1  # Previous commit
docker-compose up -d
```

#### Option 3: Database Rollback

```bash
# If data corruption in upgrade
# Restore from backup

# Stop services
docker-compose down

# Restore PostgreSQL
docker exec postgresql-primary pg_restore < database-backup-20260501.sql

# Restore Redis
docker cp redis-backup.rdb redis-primary:/data/dump.rdb
docker restart redis-primary

# Restart all services
docker-compose up -d

# Verify data integrity
docker exec postgresql-primary psql -U postgres -c "SELECT COUNT(*) FROM users;"
```

#### Option 4: Full Infrastructure Rollback (Terraform)

```bash
# Most aggressive - destroys and rebuilds infrastructure

# Backup current state
terraform state pull > terraform.state.backup

# Revert code to previous version
git checkout v1.0.0
git pull

# Reapply previous infrastructure
terraform -chdir=terraform/environments/private apply

# Deploy services
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Restore data if needed
docker exec postgresql-primary pg_restore < database-backup.sql
```

**Estimated recovery time**: 30-45 minutes

### Rollback Specific Service

```bash
# If only one service needs rollback

# Identify current version
docker inspect code-server-ide | grep -i version

# Revert to previous image tag
docker pull code-server:1.0.0
docker stop code-server-ide
docker rm code-server-ide

# Edit docker-compose.yml to use old version
# Restart service
docker-compose up -d code-server-ide
```

---

## Monitoring During Upgrade

### Real-Time Metrics

```bash
# Watch service health during upgrade
watch -n 2 'docker-compose ps'

# Monitor resource usage
watch -n 2 'docker stats --no-stream | head -15'

# Track Prometheus scrape targets
watch -n 5 'curl -s http://localhost:9090/api/v1/targets | jq ".data.activeTargets | length"'

# Monitor database replication lag
watch -n 5 'docker exec postgresql-replica psql -U postgres -c "SELECT now() - pg_last_xact_replay_time();"'
```

### Alert Configuration

```yaml
# Add to prometheus-alerts.yml during upgrade
- alert: UpgradeInProgress
  expr: metric_name_indicates_upgrade
  for: 1h
  annotations:
    summary: "Platform upgrade in progress"

- alert: HighReplicationLag
  expr: replication_lag_seconds > 10
  annotations:
    severity: "warning"
    summary: "Database replication lag detected during upgrade"
```

---

## Upgrade Validation Checklist

After upgrade completes, validate:

- [ ] All containers healthy: `docker-compose ps`
- [ ] Database replication working: `SELECT * FROM pg_stat_replication;`
- [ ] Prometheus scraping metrics: `curl localhost:9090/api/v1/targets`
- [ ] Loki ingesting logs: `curl localhost:3100/loki/api/v1/labels`
- [ ] Web UIs responsive:
  - [ ] Code-Server (8090)
  - [ ] Grafana (3000)
  - [ ] Prometheus (9090)
  - [ ] Redpanda Console (8003)
  - [ ] GitLab (8101)
  - [ ] Appsmith (8084)
  - [ ] Vault (8200)
- [ ] Full deployment test passes: `scripts/ops/full-deployment-test.sh`
- [ ] No error logs: `docker logs <service> | grep -i error | wc -l`
- [ ] Performance baseline restored: Compare to baseline metrics
- [ ] End-to-end tests passing
- [ ] User acceptance testing complete

---

## Upgrade Failure Scenarios

### Scenario 1: Service Won't Start After Upgrade

```bash
# Issue: Container exits immediately with error

# Diagnosis
docker logs service-name --tail 50

# Resolution
# Option A: Incompatible configuration - update config
docker exec service-name ls /etc/config/

# Option B: Data format changed - migrate data
docker exec service-name migration-script.sh

# Option C: Rollback to previous version
git checkout v1.0.0
docker-compose pull service-name
docker-compose restart service-name
```

### Scenario 2: Database Migration Fails

```bash
# Issue: Schema migration hangs or errors

# Kill stuck migration
docker exec postgresql-primary psql -U postgres -c \
  "SELECT pg_cancel_backend(pid) FROM pg_stat_activity WHERE query LIKE 'ALTER%';"

# Rollback schema changes
docker exec postgresql-primary psql -U postgres < rollback.sql

# Retry migration manually
docker exec postgresql-primary psql -U postgres < migrations/v1.1.0.sql
```

### Scenario 3: Failover Doesn't Work During Upgrade

```bash
# Issue: Keepalived VIP not moving to replica

# Manual intervention
ssh ops@192.168.168.42

# Force VIP to replica
docker exec keepalived-replica sudo ip addr add 192.168.168.50/24 dev eth0

# Verify connectivity via VIP
curl -I http://192.168.168.50:8090

# Complete upgrade of primary
ssh ops@192.168.168.31
docker-compose up -d
```

---

## Scheduling Upgrades

### Recommended Upgrade Windows

| Environment | Recommended Day | Duration | Notification |
|-------------|-----------------|----------|--------------|
| **Staging** | Any day | 30 min | 1 hour notice |
| **Production** | Sunday evening UTC | 45 min | 48 hours notice |
| **Critical patch** | Immediate (on-call) | 15 min | Urgent notification |

### Upgrade Planning

```bash
# Schedule upgrade 2 weeks in advance
# Create calendar event: "Platform v1.0.0 → v1.1.0 upgrade"

# Prepare:
# - Week 1: Code review of v1.1.0 changes
# - Week 1: Test upgrade in staging environment
# - Week 2: Backup all data
# - Day of: Notify users, have rollback plan ready

# Execute:
# - T-30min: Final pre-upgrade checks
# - T+0: Start upgrade process
# - T+15-30min: Upgrade complete, validation running
# - T+45min: All systems confirmed operational

# Post-upgrade:
# - Monitor for 24 hours for anomalies
# - Collect upgrade metrics and lessons learned
```

---

## Upgrade Checklist Template

```markdown
# v1.0.0 → v1.1.0 Upgrade Checklist

**Date**: ________  
**Operator**: ________  
**Reviewer**: ________  

## Pre-Upgrade
- [ ] Full backup taken (PostgreSQL, Redis, Redpanda)
- [ ] Terraform state backed up
- [ ] Users notified of maintenance window
- [ ] On-call engineer available
- [ ] Previous version commit saved
- [ ] Validation suite tested in staging
- [ ] Rollback procedure reviewed

## Upgrade Phase 1: Replica
- [ ] VIP confirmed on primary
- [ ] Replica services stopped
- [ ] New version pulled
- [ ] Replica services started
- [ ] Replica health checks passing
- [ ] Database replication lag <5 sec

## Upgrade Phase 2: Failover
- [ ] VIP manually moved to replica
- [ ] Traffic verified on replica
- [ ] Primary confirmed in standby state

## Upgrade Phase 3: Primary
- [ ] New version pulled on primary
- [ ] Primary services restarted
- [ ] Primary services healthy
- [ ] Database replication catching up

## Post-Upgrade Validation
- [ ] All containers healthy
- [ ] Database replication working
- [ ] Prometheus scraping targets
- [ ] Full deployment test: PASSED
- [ ] Web UIs responsive
- [ ] Performance baseline met
- [ ] No error logs detected

## Sign-Off
- Operator: ____________________  Date: ________
- Reviewer: ____________________  Date: ________
```

---

## Support & Documentation

- **Upgrade Issues**: #platform-upgrades Slack channel
- **Rollback Questions**: Contact DevOps team
- **Performance After Upgrade**: Review TROUBLESHOOTING_GUIDE.md
- **Architecture Changes**: See ARCHITECTURE_OVERVIEW.md for v1.1.0 changes

---

**Last Updated**: May 1, 2026  
**Author**: Deployment Automation  
**Status**: Production Ready ✅

**Next Review**: August 1, 2026  
**Planned v1.1.0 Release**: Q2 2026
