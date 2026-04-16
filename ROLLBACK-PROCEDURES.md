# Rollback Procedures — Comprehensive Guide

**Date**: April 16, 2026  
**Owner**: @operations-team  
**Purpose**: Enable safe, repeatable rollback of any code or infrastructure change  
**Testing**: Required before deploying to production  

---

## Quick Reference

| Scenario | Rollback Command | Time | Data Risk |
|----------|------------------|------|-----------|
| Last commit failed | `git revert HEAD` | <5 min | None |
| Last PR merged broken | `git revert -m 1 <merge-commit>` | <5 min | None |
| Docker container crashed | `docker-compose restart <service>` | <2 min | None |
| Database migration incompatible | `down` migration + `git revert` | 5-15 min | Review migration |
| Configuration changed | Restore `.env` file + container restart | <5 min | None |
| TLS certificate expired | Renew cert + caddy reload | <10 min | None |

---

## Level 1: Git Rollback (Application Code)

### Scenario: Last Commit Introduced Bug

```bash
# Identify the bad commit
git log --oneline -5
# e5ba4a36 feat(#404): Phase 2 automation    ← GOOD
# 4a3d2f1 docs(#404): Quality gates         ← GOOD
# abb5f8af docs: Consolidation strategy     ← BAD (broke something)

# Revert the bad commit
git revert abb5f8af

# Test locally
docker-compose up -d
docker-compose ps

# If verified good, push
git push origin main
```

**Time**: <5 minutes  
**Data Risk**: None (revert creates new commit, no data loss)  
**Testing**: Always test locally first

---

### Scenario: Last PR Merged Incompatible Changes

```bash
# Identify the merge commit
git log --oneline | grep -E "^[a-f0-9]{7} Merge pull request"
# e5ba4a36 Merge pull request #452 from branch-name
#          Phase 1: Error Fingerprinting, Appsmith, IAM

# Revert the merge (keep main branch parent)
git revert -m 1 e5ba4a36

# This creates a "Revert" commit, preserving history
git log --oneline -1
# ← new commit: Revert "Merge pull request #452..."

# Push
git push origin main

# Notify team of rollback
echo "PR #452 rolled back due to incompatibility with [reason]"
```

**Time**: <10 minutes  
**Data Risk**: None  
**Important**: Use `-m 1` flag (main branch is parent)  
**Effect**: Reverses all changes from the PR

---

### Scenario: Need to Go Back Multiple Commits

```bash
# Identify stable commit
git log --oneline | head -20
# e5ba4a36 feat: Something broken
# 4a3d2f1 docs: Also affected
# abb5f8af docs: Last good state ← STABLE

# Reset to stable commit (careful: loses uncommitted work)
git reset --hard abb5f8af

# Force push to main (only if authorized)
git push --force-with-lease origin main

# Alternative: Create revert commits instead
git revert e5ba4a36 4a3d2f1
git push origin main
```

**Time**: 5-15 minutes  
**Data Risk**: None if no data changes  
**Caution**: `--force-with-lease` overwrites history, use sparingly  
**Better**: Use `git revert` instead (preserves history)

---

## Level 2: Container Rollback (Runtime)

### Scenario: Service Container Crashed or Unresponsive

```bash
# Check service status
docker-compose ps
# code-server    Unhealthy
# caddy          Up (healthy)
# oauth2-proxy   Up (healthy)

# View logs to understand failure
docker logs code-server | tail -50

# Restart the service
docker-compose restart code-server

# Verify it's healthy
docker-compose ps
# code-server should now be "Up (healthy)"
```

**Time**: <2 minutes  
**Data Risk**: None (containers are stateless)  
**Testing**: Check logs first (may indicate deeper issue)

---

### Scenario: Config Change Broke Container Startup

```bash
# Check what changed
git diff docker-compose.yml
# Or check environment variables
docker exec code-server env | sort

# Restore from git if changed
git checkout -- docker-compose.yml

# Or restore .env files
git checkout -- .env.production

# Rebuild and restart
docker-compose build --no-cache code-server
docker-compose restart code-server

# Verify
docker-compose ps
docker logs code-server | tail -20
```

**Time**: 3-5 minutes  
**Data Risk**: None  
**Caution**: `git checkout` overwrites local changes

---

### Scenario: Need to Downgrade Service Version

```bash
# Edit docker-compose.yml to specify older version
# OLD: image: codercom/code-server:4.115.0
# NEW: image: codercom/code-server:4.113.0

vim docker-compose.yml  # or your editor

# Pull the older image
docker-compose pull code-server

# Restart with downgraded version
docker-compose down
docker-compose up -d code-server

# Verify version
docker inspect code-server | grep -i version
docker logs code-server | head -20
```

**Time**: 5-10 minutes  
**Data Risk**: Depends on version (check release notes)  
**Important**: Always have release notes for downgrades  
**Testing**: Test on staging first

---

## Level 3: Database Rollback (Stateful)

### Scenario: Database Migration Failed or Corrupted Data

```bash
# IMMEDIATE: Stop writes
docker-compose pause postgres redis

# Check backup status
ls -lah /var/backups/postgres/
# Or check automated backup:
aws s3 ls s3://backups/code-server/postgres/ | tail -5

# Restore from backup (PostgreSQL example)
# Option 1: Restore entire database from backup
psql -U code-server -d code_server_db < /var/backups/postgres/backup-2026-04-16.sql

# Option 2: Use pg_restore if backup is in custom format
pg_restore -U code-server -d code_server_db /var/backups/postgres/backup-2026-04-16.dump

# Option 3: Restore from cloud backup (AWS RDS, etc.)
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier code-server-restored \
  --db-snapshot-identifier code-server-2026-04-16

# Resume services
docker-compose unpause postgres redis

# Verify data consistency
docker exec postgres pg_dump -U code-server code_server_db | head -50

# Run tests to validate data
pytest tests/integration/test_database.py -v
```

**Time**: 15-30 minutes (depending on database size and backup location)  
**Data Risk**: SIGNIFICANT (data loss possible, must restore from backup)  
**Critical**: Always have automated backups before deploying migrations  
**Testing**: **NEVER deploy database changes without backup first**

---

### Scenario: Revert Database Migration

```bash
# If migration has a `down` step:
python manage.py migrate --backwards 1

# Or with Alembic (SQLAlchemy):
alembic downgrade -1

# Or manually:
psql -U code-server -d code_server_db < migration_down.sql

# Verify schema changed back
\d table_name  # PostgreSQL schema inspection

# Commit rollback decision
git log --oneline | grep migration
# Find the migration commit:
git revert <migration-commit-hash>

# Test application with old schema
docker-compose restart code-server
sleep 30
curl http://localhost:8080/healthz  # Check app health
```

**Time**: 5-15 minutes  
**Data Risk**: DEPENDS on migration (read migration code!)  
**Critical**: Down migrations MUST be tested in staging first  
**Rule**: No database migration to production without successful rollback test

---

## Level 4: Infrastructure Rollback (IaC/Terraform)

### Scenario: Terraform Apply Broke Infrastructure

```bash
# Check what changed
terraform plan -no-color > /tmp/plan.txt
cat /tmp/plan.txt | head -50

# If something looks wrong, don't apply:
# → git revert the terraform change instead

git log --oneline | grep terraform
# a1b2c3d4 feat(terraform): Add new monitoring

# Revert the terraform commit
git revert a1b2c3d4

# Verify reverted
git diff HEAD~1 HEAD | head -50

# Re-plan
terraform init  # If needed
terraform plan

# If plan looks correct, apply (or deploy via CI)
terraform apply -auto-approve  # Only if you're authorized
```

**Time**: 5-15 minutes  
**Data Risk**: DEPENDS on what infrastructure changed  
**Caution**: Terraform destroys resources on revert (must have backups)  
**Rule**: Always `terraform plan` before `terraform apply`

---

### Scenario: Kubernetes Deployment Failed

```bash
# Check deployment status
kubectl rollout status deployment/code-server -n default

# If failed, rollback to previous version
kubectl rollout undo deployment/code-server -n default

# Verify rollback
kubectl get pods -n default
kubectl logs -n default deployment/code-server

# If still broken, check events
kubectl describe deployment code-server -n default
```

**Time**: <5 minutes  
**Data Risk**: None (K8s handles versioning)  
**Advantage**: Kubernetes automatic rollback is fastest for container issues

---

## Level 5: Network & DNS Rollback

### Scenario: DNS Changed, Services Unreachable

```bash
# Check current DNS resolution
nslookup ide.kushnir.cloud
dig ide.kushnir.cloud +short

# If wrong, revert DNS change
# Check git for DNS terraform/config
git log --oneline | grep dns
# a1b2c3d4 feat(dns): Update CloudFlare records

git revert a1b2c3d4

# Terraform to apply DNS revert
terraform apply -auto-approve

# Verify DNS resolution
nslookup ide.kushnir.cloud
# Should resolve to correct IP

# Verify service is accessible
curl -I https://ide.kushnir.cloud
```

**Time**: 5-15 minutes  
**Data Risk**: None  
**Caution**: DNS changes take time to propagate (TTL delay)  
**Rule**: Lower TTL before making DNS changes (for faster rollback)

---

### Scenario: TLS Certificate Expired

```bash
# Check certificate status
docker exec caddy openssl s_client -connect localhost:443 -showcerts 2>/dev/null | grep -A5 "Issuer\|Validity"

# If expired, renew immediately
# Caddy should auto-renew, but manual option:
docker exec caddy curl -X POST http://localhost:2019/load

# If auto-renewal failed, check logs
docker logs caddy | grep -i "certificate\|tls"

# Manually request new cert
docker exec caddy caddy renew --force

# Reload configuration
docker exec caddy caddy reload --config /etc/caddy/Caddyfile

# Verify new cert
docker exec caddy openssl s_client -connect localhost:443 -showcerts 2>/dev/null | grep -A5 "Validity"
curl -I https://ide.kushnir.cloud
```

**Time**: <5 minutes  
**Data Risk**: None  
**Prevention**: Set alert for certs expiring in 30 days

---

## Level 6: Complete Environment Rollback

### Scenario: Multiple Services Broken After Deployment

```bash
# EMERGENCY PROCEDURE:
# 1. Stop everything
docker-compose down

# 2. Check git status
git status
git log --oneline -5

# 3. Identify last good state
# Good: e5ba4a36 ✅ All services healthy
# Bad:  4a3d2f1 ❌ Services failing

# 4. Revert
git revert 4a3d2f1

# 5. Pull and restart
git pull origin main
docker-compose build --no-cache
docker-compose up -d

# 6. Verify
sleep 30  # Let services start
docker-compose ps
docker-compose logs | grep -i error

# 7. Run health checks
curl http://localhost:8080/healthz
curl http://localhost:4180/ping
curl http://localhost:9090/-/healthy
```

**Time**: 10-20 minutes  
**Data Risk**: DEPENDS on what was deployed  
**Testing**: Run health checks before declaring success  
**Communication**: Notify stakeholders immediately

---

## Rollback Testing Checklist

**Before deploying any change, verify rollback works:**

- [ ] Have identified the rollback command
- [ ] Tested rollback on staging environment
- [ ] Documented rollback steps in PR description
- [ ] Verified health check passes after rollback
- [ ] Confirmed data consistency after rollback
- [ ] Notified on-call engineer of rollback procedure
- [ ] Set alert threshold to detect if rollback is needed

---

## Automated Rollback (Production Safety)

### GitHub Actions Automatic Rollback

```yaml
# .github/workflows/deploy.yml (example)
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy
        run: terraform apply -auto-approve
        
      - name: Run health checks
        run: bash scripts/health-check.sh
        
      - name: Auto-rollback on failure
        if: failure()
        run: |
          echo "Health check failed, rolling back..."
          git revert HEAD --no-edit
          git push
          echo "Rollback complete"
```

**Benefit**: Automatic rollback if health checks fail  
**Risk**: May mask underlying issue (investigate logs first)  
**Rule**: Always check logs before re-deploying

---

## Rollback Decision Tree

```
Is service down?
├─ YES → docker-compose restart <service> (quick fix)
├─ NO → Check logs first
   ├─ Is it a recent code change?
   │  └─ YES → git revert <commit>
   ├─ Is it a config change?
   │  └─ YES → git checkout -- .env* docker-compose.yml
   ├─ Is it a database issue?
   │  └─ YES → Restore from backup (CRITICAL)
   └─ Is it infrastructure?
      └─ YES → terraform apply after git revert
```

---

## Escalation Path

**If unsure about rollback:**

1. **Ask**: Post in #incidents Slack channel with what broke
2. **Wait**: Get approval from on-call engineer (@kushin77, @PureBlissAK)
3. **Document**: Explain the issue, expected rollback, expected impact
4. **Execute**: Follow rollback procedure above with approval
5. **Verify**: Run health checks after rollback
6. **Post-Mortem**: What caused the break? How to prevent?

**DO NOT GUESS** — Rollback can have unintended consequences. Always get approval first.

---

## Rollback Procedures by Role

### Software Engineer (Code Changes)

```bash
# If your PR caused issues:
git revert -m 1 <merge-commit-from-PR>
git push origin main
# NOTIFY: Post comment in PR + Slack alert
```

### DevOps Engineer (Infrastructure Changes)

```bash
# If terraform broke something:
git revert <terraform-commit>
terraform apply -auto-approve
# NOTIFY: Post incident ticket + team Slack
```

### On-Call Engineer (Emergency Response)

```bash
# FIRST: Assess damage
docker-compose ps
docker logs <failing-service> | tail -100

# SECOND: Execute rollback (if clear)
git revert <bad-commit>
docker-compose restart <service>

# THIRD: Verify health
curl http://localhost:8080/healthz
docker-compose ps

# FOURTH: Notify
echo "Rolled back <commit>. Reason: <why>. Impact: <what changed>"
```

---

## Prevention

**To avoid needing rollbacks:**

1. ✅ **Test locally** before pushing
2. ✅ **Run tests** in CI before merging
3. ✅ **Code review** catches errors early
4. ✅ **Staged deployments** (staging → canary → production)
5. ✅ **Health checks** detect issues immediately
6. ✅ **Automated backups** for data recovery
7. ✅ **Monitoring & alerting** catch degradation

**Goal**: Make rollbacks rare and fast.

---

**Owner**: @operations-team  
**Last Updated**: April 16, 2026  
**Status**: Ready for production use  
**Review Frequency**: Quarterly or after each incident
