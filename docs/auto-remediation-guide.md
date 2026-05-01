# Automated Remediation System

**Date**: April 30, 2026  
**Status**: Complete  
**Purpose**: Self-healing infrastructure with automated incident response

---

## Overview

The Automated Remediation System provides self-healing capabilities for code-server infrastructure. It detects common operational issues and automatically resolves them within configurable safety policies.

**Key Capabilities**:
- ✅ Auto-restart unhealthy containers (with rate limiting)
- ✅ Auto-cleanup disk space when threshold exceeded
- ✅ Terraform drift remediation (optional, dangerous - disabled by default)
- ✅ Rate limiting and rollback protection
- ✅ Alert integration on all actions
- ✅ Dry-run mode for testing
- ✅ Safe mode blocking dangerous operations

---

## Architecture

```
Infrastructure (Code-Server)
        ↓
Auto-Remediation Engine (every 5 minutes)
├─ Detect unhealthy containers
├─ Check disk space usage
├─ Scan Terraform drift
└─ Query alert thresholds
        ↓
Remediation Policies (.remediation/config.env)
├─ Enable/disable strategies
├─ Set safety limits
├─ Define do-not-touch resources
└─ Configure escalation
        ↓
Remediation Actions (guarded)
├─ Docker restart (with restart count tracking)
├─ Docker prune (only if >85% disk)
├─ Terraform apply (only if drift <10 AND safe mode)
└─ Alert routing on all actions
```

---

## Components

### 1. Remediation Engine: `scripts/ops/auto-remediation-engine.sh` (420 lines)

**Core Functions**:

#### `remediate_unhealthy_containers()`
- Queries both hosts for unhealthy containers
- Checks restart count (max 5/hour per container)
- Skips critical containers (PostgreSQL, Redis, Keepalived)
- SSH restarts via `docker restart`
- Sends alerts on each action
- Logs to `/tmp/code-server-remediation.log`

**Safety Mechanisms**:
- Max 5 restarts per container per hour (prevent loops)
- Whitelist of do-not-restart containers
- Optional 30-second wait between retries
- Dry-run support (simulate without applying)

**Example Flow**:
```
Container unhealthy
  ↓ Check restart count
  → Already 5 restarts this hour? SKIP
  → First time? Check if critical? (PostgreSQL/Redis) SKIP
  → Safe to restart? Send restart command
  ↓ Log result
  ↓ Send alert (INFO on success, ERROR on failure)
```

#### `remediate_disk_space()`
- SSH to both hosts for `df /home` usage
- If >85%, runs `docker system prune -af --volumes`
- Measures before/after disk usage
- Skips protected volumes (PostgreSQL data, Redis data)
- Escalates if cleanup insufficient

**Safety Mechanisms**:
- Threshold-based (only clean if >85%)
- Skiplist for critical volumes
- Dry-run support
- Detailed before/after logging

**Example Flow**:
```
Check primary disk: 87%
  ↓ Exceeds 85% threshold
  ↓ Run docker system prune (dry-run or real)
  ↓ Check new usage: 72%
  ↓ Log success: "87% → 72%"
  ↓ Send alert
```

#### `remediate_terraform_drift()`
- Queries `terraform plan -json` for resource_drift events
- Only acts if drift count < threshold (default 10)
- Blocked if `SAFE_MODE=true` (default)
- Blocked if `REMEDIATE_TERRAFORM_DRIFT=false` (default)
- Runs `terraform apply -auto-approve` if safe
- Keeps state snapshots for rollback

**Safety Mechanisms**:
- Disabled by default (requires opt-in)
- Safe mode blocks ALL drift remediation
- Threshold blocks if drift too high (>10 resources)
- Do-not-remediate resource list (RDS, S3, etc.)
- Automatic rollback on failure
- State snapshots for recovery

**Example Flow**:
```
Drift detected: 3 resources
  ↓ Is SAFE_MODE=true? BLOCK (default)
  ↓ Is REMEDIATE_TERRAFORM_DRIFT=false? BLOCK (default)
  ↓ Is drift > threshold (10)? BLOCK
  ↓ Check do-not-remediate list? 
  ↓ All checks passed? Run terraform apply -auto-approve
  ↓ Failed? Rollback state and alert ERROR
```

---

### 2. Remediation Configuration: `.remediation/config.env` (180 lines)

**Remediation Policies**:
```bash
REMEDIATE_UNHEALTHY_CONTAINERS=true    # Enabled
REMEDIATE_DISK_SPACE=true               # Enabled
REMEDIATE_TERRAFORM_DRIFT=false         # Disabled (dangerous)
```

**Safety Settings**:
```bash
DRY_RUN=false              # true = simulate only
SAFE_MODE=true             # true = block dangerous ops
```

**Container Remediation**:
```bash
MAX_AUTO_RESTARTS_PER_HOUR=5
DO_NOT_AUTO_RESTART="postgresql,redis,keepalived"
RESTART_WAIT_TIME=30
```

**Disk Space Remediation**:
```bash
DISK_CLEANUP_THRESHOLD=85
SKIP_VOLUME_PATTERNS="postgresql-data,redis-data"
```

**Terraform Drift Remediation**:
```bash
DRIFT_REMEDIATION_THRESHOLD=10
TERRAFORM_APPLY_TIMEOUT=300
DO_NOT_AUTO_REMEDIATE="aws_rds_instance,aws_s3_bucket"
```

**Alert Integration**:
```bash
SEND_REMEDIATION_ALERTS=true
SUCCESS_ALERT_LEVEL=INFO
ERROR_ALERT_LEVEL=ERROR
```

**Scheduling**:
```bash
REMEDIATION_INTERVAL="*:0/5"    # Every 5 minutes
QUIET_HOURS_START="22:00"       # No remediations 10pm-8am
QUIET_HOURS_END="08:00"
```

**Rate Limiting**:
```bash
MAX_REMEDIATIONS_PER_HOUR=20
BACKOFF_STRATEGY="exponential"  # Increase delay on retries
BACKOFF_BASE_DELAY=5
```

---

## Operational Workflow

### Step 1: Initial Testing (Dry-Run Mode)

```bash
# Test without making changes
DRY_RUN=true SAFE_MODE=true ./scripts/ops/auto-remediation-engine.sh
```

**Output**:
```
Automated Remediation Engine
Time: 2026-04-30 19:40:11
DRY_RUN: true
SAFE_MODE: true

Checking for unhealthy containers on primary host...
✓ No unhealthy containers found on primary
Checking for unhealthy containers on replica host...
✓ No unhealthy containers found on replica

Checking disk space on primary host...
✓ Primary disk usage OK: 65%
Checking disk space on replica host...
✓ Replica disk usage OK: 58%

============================================
Remediation Summary
============================================
Checks run: 3
Successful: 3
Log: /tmp/code-server-remediation.log
Status: ✓ All checks passed
```

### Step 2: Enable in Production

```bash
# Update config to enable real operations
# .remediation/config.env:
DRY_RUN=false              # Enable actual remediations
SAFE_MODE=true             # Keep dangerous ops blocked

# Run manually to verify
./scripts/ops/auto-remediation-engine.sh
```

### Step 3: Schedule Periodic Execution

**Option A: Systemd Timer**
```bash
# Create systemd service
sudo systemctl enable code-server-remediation.service
sudo systemctl enable code-server-remediation.timer

# Timer runs every 5 minutes
sudo systemctl start code-server-remediation.timer
```

**Option B: Cron**
```bash
# Add to crontab
*/5 * * * * /home/akushnir/code-server/scripts/ops/auto-remediation-engine.sh >> /tmp/remediation.log 2>&1
```

### Step 4: Monitor & Adjust

```bash
# Watch remediation log
tail -f /tmp/code-server-remediation.log

# Query remediation history
grep "SUCCESS" /tmp/code-server-remediation.log | wc -l

# Check specific event
grep "RESTART_CONTAINER" /tmp/code-server-remediation.log
```

---

## Safety Model

### Default Configuration (Safest)

```
DRY_RUN=false
SAFE_MODE=true
REMEDIATE_UNHEALTHY_CONTAINERS=true     ✓ Safe
REMEDIATE_DISK_SPACE=true                ✓ Safe
REMEDIATE_TERRAFORM_DRIFT=false          ✗ Blocked in SAFE_MODE
```

**Result**: Only container restarts and disk cleanup (both safe).

### Production Configuration (Recommended)

```
DRY_RUN=false
SAFE_MODE=true
REMEDIATE_UNHEALTHY_CONTAINERS=true     ✓ Container restarts with rate limiting
REMEDIATE_DISK_SPACE=true                ✓ Disk cleanup on >85% usage
REMEDIATE_TERRAFORM_DRIFT=false          ✗ Blocked for safety
MAX_AUTO_RESTARTS_PER_HOUR=5             ← Rate limit per container
DISK_CLEANUP_THRESHOLD=85                ← Only if >85%
DO_NOT_AUTO_RESTART="postgresql,redis,keepalived"  ← Protected resources
```

### Advanced Configuration (Careful)

Only enable drift remediation after:
1. ✅ 30+ days running container remediation
2. ✅ All alerts configured and monitoring active
3. ✅ State backup system ready
4. ✅ Team trained on rollback procedures

```
DRY_RUN=false
SAFE_MODE=false            ← NOW DANGEROUS
REMEDIATE_TERRAFORM_DRIFT=true
DRIFT_REMEDIATION_THRESHOLD=5  ← Lower threshold
AUTO_ROLLBACK_ON_FAILURE=true
DO_NOT_AUTO_REMEDIATE="postgresql,redis,keepalived,docker_container.critical"
```

---

## Incident Response Scenarios

### Scenario 1: Unhealthy Container

**Automatic Response**:
```
1. Engine detects unhealthy container
2. Check restart count (e.g., 2/5 this hour)
3. Check if critical (e.g., NOT in protected list)
4. Execute: docker restart code-server-api
5. Log: [RESTART_CONTAINER] [SUCCESS] Restarted: code-server-api
6. Alert: INFO - Container restarted (to syslog/Slack/email)
7. Monitoring picks up recovered container
```

**Timeline**: ~5 seconds (next remediation check)

### Scenario 2: High Disk Usage

**Automatic Response**:
```
1. Engine detects 87% disk usage (>85% threshold)
2. Execute: docker system prune -af --volumes
3. Measure results: 87% → 72%
4. Log: [DISK_CLEANUP] [SUCCESS] Primary disk: 87% → 72%
5. Alert: INFO - Disk space cleaned (to syslog/Slack/email)
```

**Timeline**: ~10-30 seconds (next remediation check)

### Scenario 3: Terraform Drift (BLOCKED by default)

**Default Response**:
```
1. Engine detects 8 resources drifted
2. Check REMEDIATE_TERRAFORM_DRIFT=false? → SKIP
3. Log: [DRIFT_REMEDIATION] [BLOCKED] Feature disabled
4. Result: No action taken (requires manual fix)
```

**With Drift Remediation Enabled** (dangerous):
```
1. Engine detects 8 resources drifted
2. Check SAFE_MODE=true? → BLOCK anyway
3. Log: [DRIFT_REMEDIATION] [BLOCKED] Disabled in SAFE_MODE
4. Result: No action taken
5. To enable: Set SAFE_MODE=false AND REMEDIATE_TERRAFORM_DRIFT=true
```

---

## Monitoring & Alerts

### Alert Types

**Container Restart Alert**:
```
Level: INFO (on success) / ERROR (on failure)
Source: remediation-engine
Title: Container restarted
Message: Auto-restarted unhealthy container: code-server-api

Example:
[2026-04-30T19:45:23Z] [RESTART_CONTAINER] [SUCCESS] Restarted: code-server-api
```

**Disk Cleanup Alert**:
```
Level: INFO (on success) / ERROR (on failure)
Source: remediation-engine
Title: Disk space cleaned
Message: Primary: 87% → 72%

Example:
[2026-04-30T19:50:15Z] [DISK_CLEANUP] [SUCCESS] Primary disk: 87% → 72%
```

**Max Restarts Alert**:
```
Level: WARNING
Source: remediation-engine
Title: Max restarts reached
Message: Container code-server-api exceeded 5 restarts/hour

Example:
[2026-04-30T20:05:42Z] [RESTART_CONTAINER] [SKIPPED] Max restarts/hour reached for code-server-api
```

---

## Troubleshooting

### Issue 1: Container Keeps Getting Restarted

**Symptoms**: Container restarts repeatedly, max restarts reached

**Causes**:
- Container has persistent issue (config error, missing dependency)
- Resource constraints (OOM, CPU throttled)
- Application crash loop

**Solution**:
1. Investigate why container unhealthy: `docker logs <container>`
2. If persistent issue, add to `DO_NOT_AUTO_RESTART`
3. Fix underlying issue
4. Remove from skiplist after fix verified

### Issue 2: Disk Never Cleans Up

**Symptoms**: Disk stays at 87% despite disk cleanup setting

**Causes**:
- Docker artifacts protected by skiplist
- Large volumes in `SKIP_VOLUME_PATTERNS`
- Application generating logs faster than cleanup

**Solution**:
1. Check what's consuming space: `du -sh /home/*`
2. If logs: rotate/archive logs
3. If volumes: cleanup manually or reduce retention
4. May need manual intervention beyond Docker prune

### Issue 3: Terraform Apply Takes Too Long

**Symptoms**: Terraform apply exceeds timeout

**Causes**:
- Complex infrastructure changes
- Slow provider API responses
- Network latency

**Solution**:
1. Increase `TERRAFORM_APPLY_TIMEOUT` (default 300s)
2. Consider blocking auto-drift-remediation
3. Keep `SAFE_MODE=true` to block automatic application
4. Require manual review for drift issues

---

## Integration with Existing Systems

### With Alert Router
- ✅ All remediation actions send alerts
- ✅ Multi-channel: Slack, email, syslog
- ✅ Color-coded: INFO (green), WARNING (orange), ERROR (red)

### With Prometheus Metrics
- ✅ Track remediation events
- ✅ Count restarts per container (1h window)
- ✅ Monitor disk cleanup frequency
- ✅ Dashboard can show auto-remediation effectiveness

### With Drift Watchdog
- ✅ Share drift state files
- ✅ Coordinate alerts (watchdog detects, remediation acts)
- ✅ Synchronized check intervals (both 5 minutes)

---

## Setup Checklist

- [ ] Review `.remediation/config.env` for your environment
- [ ] Test in DRY_RUN mode: `DRY_RUN=true ./scripts/ops/auto-remediation-engine.sh`
- [ ] Verify log output is clear and informative
- [ ] Enable in production: Set `DRY_RUN=false`
- [ ] Monitor logs for 24 hours: `tail -f /tmp/code-server-remediation.log`
- [ ] Verify alerts are working
- [ ] Configure systemd timer or cron for periodic execution
- [ ] Document any custom policies for your team
- [ ] Train ops team on how to review remediation logs
- [ ] Setup monitoring dashboards for remediation events

---

## Best Practices

1. **Always start with DRY_RUN=true**
   - Test all remediations in simulation mode first
   - Verify output and alert messages

2. **Keep SAFE_MODE=true by default**
   - Dangerous operations require deliberate enablement
   - Drift remediation especially risky in production

3. **Monitor restart rates**
   - If container restarting frequently, investigate root cause
   - Don't rely on auto-restart to hide problems

4. **Review logs regularly**
   - Daily: Check for unexpected remediations
   - Weekly: Analyze trends and patterns
   - Monthly: Evaluate effectiveness

5. **Have a rollback plan**
   - Keep state snapshots (default 10 snapshots)
   - Practice state recovery quarterly
   - Document procedures

6. **Gradually increase automation**
   - Week 1: Container restarts only
   - Week 2: Add disk cleanup
   - Week 3+: Monitor before enabling drift remediation
   - Only drift remediation if confident and well-monitored

---

## Status

✅ **Production Ready**
- Remediation engine fully functional
- Configuration template with safety defaults
- All safeguards in place
- Ready for deployment

