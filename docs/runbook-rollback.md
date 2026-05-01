# Infrastructure Rollback Runbook

**Document**: RUNBOOK-ROLLBACK.md  
**Last Updated**: April 26, 2026  
**IaC Lifecycle Control**: Issue #1531  
**Governance**: GOV-002 - Immutable, idempotent rollback procedures  

## Overview

This runbook documents all procedures for rolling back infrastructure changes in the code-server-enterprise deployment. All rollback procedures are immutable, idempotent, and can be executed multiple times safely.

## Quick Reference

| Scenario | Command | Time |
|----------|---------|------|
| **Health check failed** | Auto-triggered | 2-5 min |
| **Manual rollback** | `bash scripts/ops/rollback.sh manual` | 5-10 min |
| **Emergency shutdown** | `bash scripts/ops/rollback.sh emergency` | 1-2 min |
| **List checkpoints** | `bash scripts/ops/rollback.sh list` | <1 min |

## Prerequisites

- SSH access to primary host (192.168.168.31) or local deployment machine
- Git repository at `/home/akushnir/code-server-enterprise/` or equivalent
- Docker and Docker Compose installed
- Terraform 1.6.0+ installed
- Sufficient disk space for backups (minimum 10 GB)

## Rollback Types

### 1. Automatic Rollback (Health Check Failure)

**Trigger**: Automatically initiated when health checks fail 3 consecutive times

**Process**:
```bash
# This runs automatically when deployed
scripts/ops/health-check-and-rollback.sh

# If health check fails:
# 1. Creates rollback checkpoint
# 2. Stops all containers gracefully
# 3. Restores last-known-good configuration
# 4. Restarts containers
# 5. Re-validates health
```

**Recovery Time**: 2-5 minutes

**Success Criteria**:
- All 20+ services report healthy ✅
- API endpoints responding with valid status ✅
- Caddy gateway returning 200 OK for /health ✅

### 2. Manual Rollback (Operator Initiated)

**Trigger**: Executed by operator when infrastructure changes introduce issues

**Procedure**:

#### Step 1: SSH into primary host
```bash
ssh -i ~/.ssh/id_rsa_onprem_wsl akushnir@192.168.168.31
cd code-server-enterprise
```

#### Step 2: Load canonical configuration
```bash
source scripts/_common/_base-config.env
_validate_required_env
```

#### Step 3: Execute manual rollback
```bash
bash scripts/ops/rollback.sh manual
```

**What happens**:
1. Creates pre-rollback checkpoint (backed up to `.rollback-backups/`)
2. Stops all Docker Compose services gracefully
3. Restores Docker Compose configuration
4. Restarts all services
5. Validates health checks
6. Cleans up old backups (>7 days)

**Recovery Time**: 5-10 minutes

**Success Criteria**:
- All services restart without errors ✅
- Health checks pass after restart ✅
- No data loss (persistent volumes retained) ✅

### 3. Emergency Rollback (Catastrophic Failure)

**Trigger**: Used when system is completely non-functional and manual intervention is needed

**Procedure**:

```bash
ssh -i ~/.ssh/id_rsa_onprem_wsl akushnir@192.168.168.31
cd code-server-enterprise
source scripts/_common/_base-config.env
bash scripts/ops/rollback.sh emergency
```

**Prompts for confirmation**:
```
EMERGENCY ROLLBACK - All services will be forcibly stopped and reset
Are you sure? Type 'YES' to confirm: 
```

**What happens**:
1. **FORCE STOP**: Immediately stops all containers (-v removes volumes)
2. **RESET**: Clears temporary state files
3. **RESTORE**: Reloads configuration from Git
4. **RESTART**: Brings all services back online
5. **VALIDATE**: Runs comprehensive health checks

**Recovery Time**: 1-2 minutes

**⚠️ Warning**: This is destructive - only use if absolutely necessary
- Temporary data (Redis cache, pending tasks) will be lost
- Persistent volumes (PostgreSQL, Qdrant) are preserved

**Success Criteria**:
- All services running without errors ✅
- Core functionality (PostgreSQL, API) operational ✅
- No corruption in persistent volumes ✅

## Rollback Checkpoints

### Checkpoint Management

Rollback checkpoints are created automatically before changes and stored in `.rollback-backups/`:

```bash
# List available checkpoints
bash scripts/ops/rollback.sh list

# Output example:
# Available rollback checkpoints:
#   - checkpoint-1724072800 (12 files)
#   - checkpoint-1724069200 (12 files)
#   - checkpoint-1724065600 (12 files)
```

### Checkpoint Contents

Each checkpoint includes:
- Docker Compose configuration snapshots
- Caddy gateway configuration
- Git state information (SHA, logs, status)
- Container runtime state snapshot
- Environment variables (.env file)

### Retention Policy

- Checkpoints retained for 7 days by default
- Older checkpoints automatically cleaned up
- To manually clean: `bash scripts/ops/rollback.sh cleanup`

## Step-by-Step Rollback Scenarios

### Scenario A: Deployment introduced service errors

**Symptoms**:
- Some services failing to start
- Health checks timing out
- API returning 500 errors

**Resolution**:

```bash
# 1. SSH into primary host
ssh -i ~/.ssh/id_rsa_onprem_wsl akushnir@192.168.168.31
cd code-server-enterprise

# 2. Verify current state
docker-compose ps
curl -fsS http://localhost/health

# 3. Check service logs
docker-compose logs --tail=50 execution-scheduler

# 4. Execute manual rollback
source scripts/_common/_base-config.env
bash scripts/ops/rollback.sh manual

# 5. Verify recovery
docker-compose ps
curl -fsS http://localhost/health | jq .
```

**Expected output**:
```
✅ Docker Compose rollback completed
✅ Terraform rollback completed
✅ Caddy rollback completed
✅ All systems healthy
```

### Scenario B: Configuration files corrupted

**Symptoms**:
- Docker Compose syntax errors
- Caddy returning 400/500 errors
- Services unable to find configuration

**Resolution**:

```bash
# 1. SSH and verify Git state
ssh -i ~/.ssh/id_rsa_onprem_wsl akushnir@192.168.168.31
cd code-server-enterprise

# 2. Check what's uncommitted (should be nothing)
git status

# 3. If corrupted, revert to last known-good
git checkout HEAD -- docker-compose.yml config/caddy/Caddyfile

# 4. Execute rollback
source scripts/_common/_base-config.env
bash scripts/ops/rollback.sh manual

# 5. Verify
bash scripts/ops/health-check-and-rollback.sh
```

### Scenario C: Database or storage corruption

**Symptoms**:
- PostgreSQL refusing connections
- Qdrant vector DB errors
- Data inconsistencies

**Resolution**:

```bash
# ⚠️ CRITICAL: This will reset database connections but preserve data

ssh -i ~/.ssh/id_rsa_onprem_wsl akushnir@192.168.168.31
cd code-server-enterprise

# 1. Stop services gracefully (preserves volumes)
docker-compose down

# 2. Check data directory integrity
ls -la data/postgresql/
ls -la data/qdrant/

# 3. If data is corrupt, you may need to restore from NAS backup
# See: /mnt/nas/backups/postgresql-*.sql.gz

# 4. Restart services
docker-compose up -d

# 5. Monitor logs for recovery
docker-compose logs -f postgres

# 6. Validate health once recovered
bash scripts/ops/health-check-and-rollback.sh
```

## Health Check Deep-Dive

After any rollback, the system runs comprehensive health checks:

```
Health Check Endpoints:
✅ caddy        (HTTP 200 from /health)
✅ execution-scheduler (HTTP 200 from /health)
✅ opa          (TCP port 8181 open)
✅ oauth2-proxy (TCP port 4180 open)
✅ postgres     (TCP port 5432 open)
✅ redis        (TCP port 6379 open)

Dependency Validation:
✅ execution-scheduler requires: postgres, redis, redpanda
✅ opa requires: postgres
✅ caddy requires: execution-scheduler, opa
```

**If health check fails**, the system automatically:
1. Logs detailed failure information
2. Creates diagnostic checkpoint
3. Triggers another rollback attempt
4. Alerts operator if failure threshold exceeded

## Verifying Rollback Success

After rollback, verify using:

```bash
# 1. Container status (all should be "Up")
docker-compose ps

# 2. API health endpoint
curl -fsS http://localhost/health

# 3. Execution scheduler status
curl -fsS http://localhost:8080/health | jq .

# 4. View recent logs
docker-compose logs --tail=100

# 5. Check Git state (should be clean)
git status
git log --oneline -5
```

**Success indicators**:
- ✅ All services running without errors
- ✅ API endpoints responding with 200 OK
- ✅ No error messages in logs
- ✅ Git repository is clean

## Troubleshooting

### Rollback fails with "Docker not available"

```bash
# Verify Docker is running
docker ps

# If not running, start Docker
sudo systemctl start docker
systemctl status docker
```

### Rollback fails with "Permission denied"

```bash
# Check your user has docker group membership
id $USER
# Should show: ... groups=... docker(...)

# If not in docker group, add yourself
sudo usermod -aG docker $USER
newgrp docker
```

### Cannot restore from checkpoint

```bash
# Check checkpoint directory
ls -la .rollback-backups/

# If empty, checkpoints have expired (>7 day retention)
# Use Git to restore: git checkout HEAD -- [files]
```

### Services won't restart after rollback

```bash
# Check logs for errors
docker-compose logs -f

# Common issues:
# - Port already in use: docker-compose ps | grep 8080
# - Insufficient disk space: df -h
# - Corrupted configuration: docker-compose config
```

## Monitoring & Alerts

### Automated drift detection

GitHub Actions workflow runs daily at 2 AM UTC:
- Detects infrastructure drift automatically
- Creates issues for manual review
- Optional auto-remediation available

Workflow: `.github/workflows/drift-detection.yml`

### Health check monitoring

Health checks run:
- After every deployment
- Triggered automatically after rollback
- Via monitoring dashboard (Grafana)

Health check configuration (in `scripts/_common/_base-config.env`):
```bash
HEALTH_CHECK_INTERVAL=30        # seconds between checks
HEALTH_CHECK_TIMEOUT=5          # timeout per check
HEALTH_CHECK_RETRIES=3          # attempts before rollback
AUTO_ROLLBACK_ON_FAILURE=true   # enable automatic rollback
ROLLBACK_FAILURE_THRESHOLD=3    # consecutive failures to trigger rollback
```

## Rollback Audit Trail

All rollback operations are logged:

```bash
# View rollback history
cat .rollback-backups/latest-checkpoint.txt

# View checkpoint contents
ls -la .rollback-backups/checkpoint-TIMESTAMP/

# Restore from specific checkpoint
cp .rollback-backups/checkpoint-TIMESTAMP/docker-compose.yml .
cp .rollback-backups/checkpoint-TIMESTAMP/Caddyfile config/caddy/
```

## Testing Rollback Procedures

To test rollback without production impact:

```bash
# Test on development environment
export DEPLOYMENT_MODE=development
export PRIMARY_HOST=192.168.168.50  # dev host

# Create test checkpoint
bash scripts/ops/rollback.sh manual

# Verify checkpoint was created
bash scripts/ops/rollback.sh list
```

## Emergency Contacts

For infrastructure emergencies:
- **Operations Lead**: ops@kushnir.cloud
- **On-Call Engineer**: Check escalation policy
- **Incident Response**: #incident-response Slack channel

## Related Documentation

- [Infrastructure as Code (IaC) Guide](./IaC-GUIDE.md)
- [Deployment Procedures](./DEPLOYMENT.md)
- [Health Check Configuration](../scripts/ops/health-check-and-rollback.sh)
- [GitHub Issue #1531 - IaC Lifecycle Control](https://github.com/kushin77/code-server/issues/1531)

---

**Last Updated**: April 26, 2026  
**Version**: 1.0  
**Status**: Production Ready  
**Maintainer**: Infrastructure Team  
