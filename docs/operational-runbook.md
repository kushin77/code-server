# code-server Operational Runbook

**Last Updated**: April 30, 2026  
**Scope**: code-server deployment operations on 192.168.168.31 (primary) and 192.168.168.42 (replica)

---

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Monitoring & Alerts](#monitoring--alerts)
3. [Incident Response](#incident-response)
4. [Deployment Procedures](#deployment-procedures)
5. [Troubleshooting](#troubleshooting)
6. [Emergency Procedures](#emergency-procedures)

---

## Daily Operations

### Pre-Deployment Checklist

Before applying any Terraform changes:

```bash
# 1. SSH to primary host to verify accessibility
ssh akushnir@192.168.168.31 'echo "PRIMARY: OK"'
ssh akushnir@192.168.168.42 'echo "REPLICA: OK"'

# 2. Run pre-apply validation
cd /home/akushnir/code-server
./scripts/ci/validate-pre-apply.sh

# Expected: All 12+ checks pass with no failures
# If failures: Review error messages and resolve before proceeding
```

### Pre-Deployment Policy Check

```bash
# Verify no drift-masking policies are violated
./scripts/ci/enforce-terraform-policies.sh

# Expected: "All policies compliant"
# If violations: Review terraform/environments/private/ and fix patterns
```

### Deployment Workflow

```bash
# 1. Validate infrastructure
cd /home/akushnir/code-server/terraform/environments/private
terraform plan -out=/tmp/tf.plan

# 2. Review plan carefully for unexpected changes
# If plan shows only expected changes:
terraform apply /tmp/tf.plan

# 3. Run full deployment test suite
cd /home/akushnir/code-server
./scripts/ops/full-deployment-test.sh --dry-run

# Expected: All 6 phases pass
# Phase 1: Infrastructure Validation ✓
# Phase 2: GitOps Drift Detection ✓
# Phase 2b: GitLab Compose Parity ✓
# Phase 3: Deployment Simulation ✓
# Phase 4: Health Check Validation ✓
# Phase 5: Rollback Verification ✓
```

### Post-Deployment Verification

```bash
# 1. Check container health on both hosts
ssh akushnir@192.168.168.31 'docker ps --filter="status=running" | wc -l'
ssh akushnir@192.168.168.42 'docker ps --filter="status=running" | wc -l'

# Expected: Similar counts (~50 containers each)

# 2. Check database replication
ssh akushnir@192.168.168.31 \
  'docker exec code-server-postgres psql -U postgres -c "SELECT version();"'

# 3. Verify Keepalived VRRP status
ssh akushnir@192.168.168.31 'docker logs code-server-keepalived | tail -5'
ssh akushnir@192.168.168.42 'docker logs code-server-keepalived | tail -5'

# Expected: Primary shows "MASTER", Replica shows "BACKUP"
```

---

## Monitoring & Alerts

### Enable Continuous Monitoring

```bash
# One-time setup (requires sudo)
sudo /home/akushnir/code-server/scripts/ops/setup-drift-monitoring.sh

# Verify it's running
systemctl status drift-monitor.timer
systemctl list-timers drift-monitor.timer

# Follow logs in real-time
journalctl -u drift-monitor.service -f
```

### Manual Drift Check

```bash
# Run watchdog once (doesn't require systemd)
/home/akushnir/code-server/scripts/ops/drift-monitoring-watchdog.sh

# Expected output:
# ✓ Drift check: OK
# ✓ Health check: OK
# ✓ Parity check: OK
# ✓ Disk space: OK
# ✓ VRRP status: OK
```

### Check Watchdog Alerts

```bash
# View alert history
cat /tmp/code-server-watchdog/alerts.log

# Follow new alerts (requires tail -f)
tail -f /tmp/code-server-watchdog/alerts.log

# Interpret alert levels:
# [INFO] - Normal operational messages
# [WARNING] - Action recommended but not critical
# [ERROR] - Critical issue requiring immediate attention
```

### Container Health Summary

```bash
# Quick health check
docker ps --format "{{.Names}}\t{{.Status}}" | grep -v healthy

# If unhealthy containers appear:
# 1. Note container names
# 2. Check logs: docker logs <container-name>
# 3. See "Container Health Issues" in Troubleshooting
```

---

## Incident Response

### Alert: Container Unhealthy

**Symptom**: Watchdog reports unhealthy containers
**Severity**: MEDIUM (unless critical service is down)
**Response**:

```bash
# 1. Identify which containers are unhealthy
docker ps --format "{{.Names}}\t{{.Status}}" | grep -v healthy

# 2. Check container logs
docker logs <container-name> | tail -50

# 3. Check docker events for recent restarts
docker events --filter 'container=<container-name>' --since '5m'

# 4. Determine if restart is needed
# If logs show transient error:
docker restart <container-name>

# If logs show configuration error:
# 1. Review terraform code for that container
# 2. Fix configuration
# 3. Re-deploy via terraform apply

# 5. Verify recovery
docker inspect <container-name> | grep -A 20 '"Health"'
```

### Alert: Terraform Drift Detected

**Symptom**: Watchdog reports "drift increased"
**Severity**: HIGH (drift indicates configuration mismatch)
**Response**:

```bash
# 1. Identify what drifted
cd /home/akushnir/code-server/terraform/environments/private
terraform plan -json | jq '.[] | select(.type == "resource_drift")'

# 2. Understand the drift
terraform plan | grep -A 3 "will be updated"

# 3. If drift is expected (manual Docker change):
# Plan to re-apply terraform to enforce IaC
# Requires approval from infrastructure team

# 4. If drift is unexpected:
# CRITICAL: Investigate root cause
# Options:
#   a) Container was restarted and config changed
#   b) Image was manually updated
#   c) Volume/mount was modified

# 5. Remediation
# Option A: Force update (re-apply terraform)
terraform apply

# Option B: Investigate and document manual change
# Then decide whether to update terraform or revert

# 6. Verify drift resolved
terraform plan | grep -c "resource_drift" || echo "0 drift"
```

### Alert: Disk Space High

**Symptom**: Watchdog reports >80% disk usage
**Severity**: MEDIUM (may cause container failures)
**Response**:

```bash
# 1. Check disk usage on both hosts
ssh akushnir@192.168.168.31 'df -h'
ssh akushnir@192.168.168.42 'df -h'

# 2. Identify space-consuming directories
ssh akushnir@192.168.168.31 'du -sh /var/lib/docker/* | sort -h'

# 3. Clean up old logs and images
docker system df              # Show space usage
docker system prune -a        # Clean unused images/containers/volumes (interactive)
docker system prune -a -f     # Same but non-interactive

# 4. Check for large container volumes
docker volume ls -q | xargs -I {} sh -c \
  'echo -n "Volume {} size: "; du -sh /var/lib/docker/volumes/{} 2>/dev/null'

# 5. If persistent database taking space:
# Check PostgreSQL data directory for old WAL logs
ls -lh /var/lib/docker/volumes/code-server-postgresql-data/_data/

# 6. Monitor disk after cleanup
df -h | grep /home
```

### Alert: Container Count Parity Mismatch

**Symptom**: Watchdog reports replica has fewer containers
**Severity**: MEDIUM (replica may not sync properly)
**Response**:

```bash
# 1. Compare container counts
ssh akushnir@192.168.168.31 'docker ps -q | wc -l'
ssh akushnir@192.168.168.42 'docker ps -q | wc -l'

# 2. Find missing containers on replica
PRIMARY_CONTAINERS=$(ssh akushnir@192.168.168.31 'docker ps -q | sort')
REPLICA_CONTAINERS=$(ssh akushnir@192.168.168.42 'docker ps -q | sort')

# 3. Sync compose file to replica (if out of date)
scp /home/akushnir/code-server/docker-compose.enterprise.yml \
  akushnir@192.168.168.42:/home/akushnir/code-server-enterprise/

# 4. Re-deploy containers to replica
ssh akushnir@192.168.168.42 \
  'cd /home/akushnir/code-server-enterprise && docker-compose up -d'

# 5. Verify parity restored
ssh akushnir@192.168.168.42 'docker ps -q | wc -l'
```

### Alert: Keepalived VRRP Down

**Symptom**: Watchdog reports keepalived not running
**Severity**: CRITICAL (failover mechanism broken)
**Response**:

```bash
# 1. Check keepalived containers
ssh akushnir@192.168.168.31 'docker ps | grep keepalived'
ssh akushnir@192.168.168.42 'docker ps | grep keepalived'

# 2. Check keepalived logs
docker logs code-server-keepalived | tail -50

# 3. Verify keepalived is configured correctly
docker exec code-server-keepalived cat /etc/keepalived/keepalived.conf

# 4. Restart keepalived
docker restart code-server-keepalived

# 5. Verify VRRP state transition (wait 10 seconds)
sleep 10
docker logs code-server-keepalived | grep -i "MASTER\|BACKUP"

# 6. If still failing:
# a) Check if Caddy is running (health check dependency)
docker ps | grep caddy

# b) Check network connectivity
ping -c 3 192.168.168.42

# c) Force manual failover testing (dangerous - requires approval)
# See "Manual Failover" in Emergency Procedures
```

---

## Deployment Procedures

### Regular Terraform Deployment

```bash
cd /home/akushnir/code-server

# 1. Pre-flight checks
./scripts/ci/validate-pre-apply.sh
./scripts/ci/enforce-terraform-policies.sh

# 2. Plan
cd terraform/environments/private
terraform plan -out=/tmp/tf.plan

# 3. Review and approve
# Carefully review all changes in the plan

# 4. Apply
terraform apply /tmp/tf.plan

# 5. Verify
cd /home/akushnir/code-server
./scripts/ops/full-deployment-test.sh --dry-run
```

### Rolling Update (Primary → Replica)

```bash
# Minimal downtime update process

# 1. Verify primary is healthy
./scripts/ops/drift-monitoring-watchdog.sh

# 2. Update replica first (non-production traffic)
ssh akushnir@192.168.168.42 'cd /home/akushnir/code-server-enterprise && docker-compose pull && docker-compose up -d'

# 3. Verify replica is healthy
ssh akushnir@192.168.168.42 'docker ps | wc -l'

# 4. Test replica (if applicable)
# Run integration tests against replica endpoint

# 5. Update primary
docker-compose pull
docker-compose up -d

# 6. Verify primary is healthy
docker ps | wc -l

# 7. Final validation
./scripts/ops/full-deployment-test.sh --dry-run
```

### Emergency Rollback

```bash
# If deployment causes issues:

# 1. Identify what went wrong
./scripts/ops/full-deployment-test.sh --dry-run
docker ps --filter="status=exited"
docker logs <failed-container> | tail -50

# 2. Rollback to last known-good state
cd /home/akushnir/code-server/terraform/environments/private
git log --oneline -10                    # Find last good commit
git checkout <commit-hash>
terraform apply -auto-approve

# 3. Verify rollback
cd /home/akushnir/code-server
./scripts/ops/full-deployment-test.sh --dry-run

# 4. Document incident
# Create post-mortem with:
#   - What went wrong
#   - Root cause
#   - Prevention for future
```

---

## Troubleshooting

### Container Fails to Start

**Problem**: Container in "Exited" state  
**Diagnosis**:

```bash
# 1. Check exit code
docker inspect <container> | grep -A 5 '"State"'

# 2. Check logs
docker logs <container> --tail=100

# 3. Common exit codes:
# 0 = Normal exit (check why it should still be running)
# 1 = Entrypoint error (check image/entrypoint)
# 127 = Command not found
# 137 = OOM killed (need more memory)
# 139 = Segmentation fault

# 4. If configuration issue:
# Fix terraform and re-apply
# OR manually override:
docker update --restart=always <container>
docker start <container>
```

### SSH Connection Fails to Host

**Problem**: "Connection refused" or "Permission denied"  
**Diagnosis**:

```bash
# 1. Check SSH connectivity
ssh -vvv akushnir@192.168.168.31 'echo OK'

# 2. Check SSH key
ls -la ~/.ssh/id_rsa
ssh-add ~/.ssh/id_rsa

# 3. Check if fail2ban blocked IP
ssh akushnir@192.168.168.31 'sudo fail2ban-client status sshd'

# 4. If blocked, request unban from host admin
# Or use VPN/bastion if available

# 5. Test connectivity
ping 192.168.168.31
```

### Terraform Plan Times Out

**Problem**: "terraform plan" hangs or times out  
**Diagnosis**:

```bash
# 1. Check if SSH is slow
time ssh akushnir@192.168.168.31 'echo OK'

# 2. Run terraform with timeout
timeout 120 terraform plan -no-color > /tmp/plan.log 2>&1

# 3. If timeout occurs, check logs
tail -100 /tmp/plan.log

# 4. Common causes:
# - Docker daemon not responding
# - SSH control socket issues
# - Network latency

# 5. Restart docker daemon (if safe)
ssh akushnir@192.168.168.31 'sudo systemctl restart docker'
```

### Database Connection Fails

**Problem**: "psql: could not connect"  
**Diagnosis**:

```bash
# 1. Check PostgreSQL container
docker ps | grep postgres
docker logs code-server-postgres | tail -20

# 2. Check port binding
docker port code-server-postgres

# 3. Test connectivity
docker exec code-server-postgres psql -U postgres -c 'SELECT 1'

# 4. If failing, check logs for:
# - Initialization errors
# - Port conflicts
# - Volume mount issues

# 5. Restart PostgreSQL
docker restart code-server-postgres
sleep 5
docker logs code-server-postgres | tail -10
```

---

## Emergency Procedures

### System Cannot Start

**Problem**: Primary host completely down or unresponsive  
**Response**:

```bash
# 1. Verify system is actually down
ping 192.168.168.31
ssh akushnir@192.168.168.31 'uptime'

# 2. If physical host:
# - Check power/console
# - Verify network cable
# - Contact infrastructure team

# 3. If VM:
# - Check hypervisor console
# - Check VM state (running/paused/stopped)
# - Power on if stopped

# 4. Once system boots:
# - SSH in to verify
# - Check Docker daemon
# - Run watchdog to assess state
```

### Primary & Replica Both Down

**Severity**: CRITICAL - Complete service outage  
**Response**:

```bash
# 1. Get status of both systems
ping 192.168.168.31
ping 192.168.168.42

# 2. Contact infrastructure team:
# - Physical datacenter check
# - Power status
# - Network connectivity

# 3. While waiting for physical access:
# - Begin recovery documentation
# - Prepare rollback plan
# - Notify affected users

# 4. Once systems are back:
# Follow normal startup procedure
```

### Manual Failover (Keepalived Not Working)

**Problem**: Keepalived broken, need to manually failover  
**Severity**: CRITICAL - Requires careful execution  
**Response**:

```bash
# WARNING: This is dangerous and should only be done by experienced operators

# 1. Understand current state
# Primary = 192.168.168.31
# Replica = 192.168.168.42
# VIP = 192.168.168.30

# 2. Stop keepalived on REPLICA to force primary to stay MASTER
ssh akushnir@192.168.168.42 'docker stop code-server-keepalived'

# 3. Verify primary is MASTER
ssh akushnir@192.168.168.31 'docker logs code-server-keepalived | grep MASTER'

# 4. If primary is BACKUP (shouldn't happen but check):
# Get priority values and investigate

# 5. Once stable, fix keepalived issue
# Contact infrastructure team to investigate root cause

# 6. Once fixed, restart keepalived on replica
ssh akushnir@192.168.168.42 'docker start code-server-keepalived'
```

---

## Appendix: Common Commands

### Container Management

```bash
# List all containers
docker ps -a

# View container logs
docker logs -f <container>
docker logs --tail=50 <container>

# Restart container
docker restart <container>

# Execute command in container
docker exec <container> <command>

# Get container IP
docker inspect <container> | grep "IPAddress"
```

### Network Diagnostics

```bash
# Test connectivity
ping 192.168.168.31
curl http://192.168.168.30/health

# Check open ports
docker ps --format "{{.Names}} {{.Ports}}"

# Network inspection
docker network inspect services
```

### System Health

```bash
# Disk space
df -h

# Memory usage
free -h

# CPU usage
top -bn1 | head -20

# System load
uptime

# Service status
systemctl status drift-monitor.timer
journalctl -n 20
```

---

## Contact & Escalation

| Issue | Contact | Severity |
|-------|---------|----------|
| Container down | Infrastructure team | MEDIUM |
| Database connectivity | Database team | HIGH |
| Network unreachable | Network team | CRITICAL |
| Host unreachable | Infrastructure team | CRITICAL |
| Unknown error | code-server admin | MEDIUM |

---

**Last Updated**: April 30, 2026  
**Next Review**: May 30, 2026

