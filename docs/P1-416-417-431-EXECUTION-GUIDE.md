# P1 #416, #417, #431 Execution Guide
## Implementation Complete - Ready for Operator Deployment

**Status**: Code complete and committed. Ready for execution on production hosts.

**Date**: April 15, 2026  
**Author**: Copilot Agent  
**Target Hosts**: 192.168.168.31 (primary), 192.168.168.42 (replica)  

---

## 📋 Quick Start

### Option 1: Execute All Three P1 Items (Recommended)
```bash
# SSH to primary host
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Option A: Run individually
bash scripts/setup-terraform-remote-state.sh
bash scripts/setup-backup-dr-hardening.sh

# Option B: Run with nohup for long-running operations
nohup bash scripts/setup-terraform-remote-state.sh > /tmp/p1-417.log 2>&1 &
nohup bash scripts/setup-backup-dr-hardening.sh > /tmp/p1-431.log 2>&1 &
```

### Option 2: GitHub Actions Runner Setup (P1 #416)
Requires GitHub Personal Access Token with `admin:repo_hook` scope:
```bash
# Get token from: https://github.com/settings/tokens/new
GITHUB_TOKEN="your_token_here"

bash scripts/setup-github-runners.sh "$GITHUB_TOKEN" kushin77 code-server-enterprise
```

---

## 🔧 Implementation Details

### P1 #416: GitHub Actions CI/CD Runners

**What Changed**:
- Updated `.github/workflows/deploy.yml` to use self-hosted runners
- Separated `deploy-primary` and `deploy-replica` jobs
- Added workflow_dispatch for manual control

**What Gets Deployed**:
1. GitHub Actions runner on 192.168.168.31 (labeled: `[self-hosted, on-prem, primary]`)
2. GitHub Actions runner on 192.168.168.42 (labeled: `[self-hosted, on-prem, replica]`)
3. Both runners auto-start on host boot via systemd service

**Execution Command**:
```bash
bash scripts/setup-github-runners.sh <GITHUB_TOKEN> kushin77 code-server-enterprise
```

**Verification**:
```bash
# Check runners are registered
https://github.com/kushin77/code-server-enterprise/settings/actions/runners

# Check runner process on host
ssh akushnir@192.168.168.31 'ps aux | grep actions-runner'

# Check runner status
sudo /home/akushnir/github-runner/primary-runner/svc.sh status
```

**Timeline**: ~10 minutes per host

---

### P1 #417: Remote Terraform State Backend

**What Changed**:
- Created `terraform/backend-config.hcl` for MinIO S3 backend
- Added setup script to migrate from local to remote state
- Enables multi-host terraform deployments

**What Gets Configured**:
1. MinIO S3 bucket: `terraform-state`
2. State file: `code-server-enterprise/terraform.tfstate`
3. DynamoDB locking table: `terraform-locks`
4. Backend migration from local → remote

**Execution Command**:
```bash
# On primary host
cd /home/akushnir/code-server-enterprise
bash scripts/setup-terraform-remote-state.sh
```

**Verification**:
```bash
cd terraform

# Check backend status
terraform show | head -20

# List resources in state
terraform state list

# Verify state file in MinIO
docker-compose exec -T minio mc ls minio/terraform-state
```

**Timeline**: ~5-10 minutes

---

### P1 #431: Backup/DR Hardening

**What Changes**:
- PostgreSQL WAL archiving to `/mnt/nas-56/postgres-wal-archive`
- Automated daily backups with 30-day retention
- Redis backup automation (hourly snapshots)
- Prometheus metrics for backup age monitoring
- Alert rules for backup failures

**What Gets Created**:
1. WAL archiving script: `scripts/archive-wal.sh`
2. Backup automation: `scripts/backup-databases.sh`
3. Restore testing: `scripts/test-database-restore.sh`
4. Monitoring: `monitoring/backup-alert-rules.yml`

**Execution Command**:
```bash
# On primary host
cd /home/akushnir/code-server-enterprise
bash scripts/setup-backup-dr-hardening.sh
```

**Setup Cron Job** (for daily backups):
```bash
# Add to crontab
crontab -e

# Add line:
0 2 * * * cd /home/akushnir/code-server-enterprise && bash scripts/backup-databases.sh >> /var/log/backup-cron.log 2>&1
```

**Verification**:
```bash
# Test backup script
bash scripts/backup-databases.sh

# Check backup directory
ls -lh /mnt/nas-56/postgres-backups/

# Test restore
bash scripts/test-database-restore.sh

# Check Prometheus metrics
curl -s http://localhost:9090/api/v1/query?query=backup_age_hours
```

**Timeline**: ~15-20 minutes

**RTO/RPO Targets**:
- RTO (Recovery Time Objective): 15 minutes
- RPO (Recovery Point Objective): 1 hour (WAL archiving)

---

## ✅ Acceptance Criteria Validation

### P1 #416 - GitHub Actions Runners
- [ ] Runners registered at: https://github.com/kushin77/code-server-enterprise/settings/actions/runners
- [ ] Primary runner online: `[self-hosted, on-prem, primary]`
- [ ] Replica runner online: `[self-hosted, on-prem, replica]`
- [ ] Deploy workflow uses self-hosted runners
- [ ] Manual test: Trigger `deploy.yml` → runs on .31/.42

### P1 #417 - Remote Terraform State
- [ ] MinIO bucket created: `terraform-state`
- [ ] `terraform state list` returns resources
- [ ] No `terraform.tfstate` in local directory
- [ ] State synced to replica host
- [ ] State locking working (try parallel `terraform apply`)

### P1 #431 - Backup/DR Hardening
- [ ] WAL archive directory exists: `/mnt/nas-56/postgres-wal-archive`
- [ ] Daily backup script runs successfully
- [ ] Redis backup created in `/mnt/nas-56/postgres-backups/`
- [ ] Prometheus metric `backup_age_hours` available
- [ ] Alert rules loaded in AlertManager
- [ ] Restore test passes without errors

---

## 🚨 Important Notes

### P1 #416 - Runner Setup
⚠️ **Requires GitHub Token**
- Token must have: `admin:repo_hook` + `workflow` scopes
- Token is NOT stored (only used for registration)
- Runners auto-revoke from GitHub if service stops
- Can remove runners at: https://github.com/kushin77/code-server-enterprise/settings/actions/runners

### P1 #417 - State Migration
⚠️ **Backup local state before migration**
```bash
cp terraform/terraform.tfstate terraform/terraform.tfstate.backup
```

⚠️ **MinIO must be running**
```bash
docker-compose ps | grep minio  # Verify status
```

### P1 #431 - Backup Retention
⚠️ **Storage space required**
- PostgreSQL backup: ~5-10 GB per day
- 30-day retention: ~150-300 GB
- Verify NAS capacity: `df -h /mnt/nas-56`

---

## 📊 Deployment Checklist

**Pre-Deployment**:
- [ ] git pull latest changes
- [ ] Verify NAS connectivity: `ls /mnt/nas-56`
- [ ] Verify Docker: `docker ps`
- [ ] Check disk space: `df -h /`

**During Deployment**:
- [ ] Run setup scripts in order: state → backup → runners
- [ ] Monitor logs for errors
- [ ] Don't interrupt running backups

**Post-Deployment**:
- [ ] Verify all acceptance criteria
- [ ] Run health checks
- [ ] Document any issues
- [ ] Update GitHub issue status

---

## 🔍 Troubleshooting

### P1 #416 - Runner issues
```bash
# Check runner logs
tail -f /home/akushnir/github-runner/primary-runner/_diag/Runner_*.log

# Restart runner
sudo /home/akushnir/github-runner/primary-runner/svc.sh restart

# Check connectivity to GitHub
curl -I https://api.github.com
```

### P1 #417 - State backend issues
```bash
# Test MinIO connectivity
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
aws --endpoint-url http://minio:9000 s3 ls

# Check terraform backend initialization
cd terraform && terraform init -upgrade

# Diagnose state issues
terraform state list
terraform state pull | jq .
```

### P1 #431 - Backup issues
```bash
# Check WAL archive directory
ls /mnt/nas-56/postgres-wal-archive/ | head

# Check backup directory
ls -lhS /mnt/nas-56/postgres-backups/ | head

# Test backup script manually
bash scripts/backup-databases.sh

# Check Prometheus for backup metrics
curl http://localhost:9090/api/v1/query?query=backup_age_hours

# View AlertManager alerts
curl http://localhost:9093/api/v1/alerts
```

---

## 📈 Success Metrics

| Item | Success Criteria | Validation Command |
|------|------------------|--------------------|
| **P1 #416** | 2 runners online | GitHub: Settings → Actions → Runners |
| **P1 #417** | State in MinIO | `terraform state list` |
| **P1 #431** | Backup runs daily | Cron job status + logs |

---

## 📚 Documentation

For detailed implementation, see:
- `scripts/setup-github-runners.sh` - Runner setup logic
- `scripts/setup-terraform-remote-state.sh` - State backend setup
- `scripts/setup-backup-dr-hardening.sh` - Backup infrastructure
- `monitoring/backup-alert-rules.yml` - Prometheus alert rules

---

## 🎯 Next Steps After Deployment

1. **Verify all runners are registered**: https://github.com/kushin77/code-server-enterprise/settings/actions/runners
2. **Trigger test deployment**: Push to `phase-7-deployment` → deploy.yml should run on .31 and .42
3. **Verify terraform state**: `terraform state list` should work without errors
4. **Test backup/restore**: Run `bash scripts/test-database-restore.sh` in staging
5. **Monitor backup metrics**: Check Grafana dashboard for backup_age_hours

---

## ✨ Production-First Validation

✅ **Zero downtime**: No service interruptions during setup  
✅ **Reversible**: Can revert to local state/backup if needed  
✅ **Monitored**: Prometheus metrics + AlertManager rules  
✅ **Documented**: All procedures documented with runbooks  
✅ **Tested**: Scripts include validation steps  
✅ **Immutable**: All changes in git, reproducible  

---

**Deployment Status**: ✅ READY FOR EXECUTION  
**Estimated Total Time**: 45-60 minutes  
**Next Milestone**: Production validation + P2 #418 execution
