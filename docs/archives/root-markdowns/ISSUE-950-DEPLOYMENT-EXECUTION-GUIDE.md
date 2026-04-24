# Issue #950 Deployment Execution Guide
## How to Deploy sanitized/redeploy-pr to Production

---

## Prerequisites

- [ ] SSH access to primary host: `ssh akushnir@192.168.168.31` (key-based auth)
- [ ] Git access to repository
- [ ] Docker running on 192.168.168.31
- [ ] Write access to close GitHub issue #950

---

## Deployment Steps

### Step 1: Merge Branch to Main (Requires GitHub Admin/Maintainer Access)

**Option A: Via GitHub Web UI**
1. Go to https://github.com/kushin77/code-server
2. Click "Pull requests" tab
3. Create new PR:
   - Head: `sanitized/redeploy-pr`
   - Base: `main`
   - Title: "fix: merge Issue #950 deployment with documentation"
4. Click "Create pull request"
5. Review and approve (1-2 hours)
6. Click "Merge pull request"
7. Confirm merge

**Option B: Via Command Line (if you have admin access)**
```bash
cd /path/to/code-server-enterprise
git checkout main
git pull origin main
git merge origin/sanitized/redeploy-pr
git push origin main
```

### Step 2: Execute Production Deployment Script

Once merged to main, run the deployment script on the primary host:

```bash
ssh akushnir@192.168.168.31 'bash -s' < DEPLOY-ISSUE-950-TO-PRODUCTION.sh
```

**What this script does:**
1. ✓ Verifies we're on host 192.168.168.31
2. ✓ Creates deployment backup
3. ✓ Pulls latest code from main
4. ✓ Validates docker-compose.yml
5. ✓ Stops services gracefully (30 second timeout)
6. ✓ Starts services with latest code
7. ✓ Waits 10 seconds for services to stabilize
8. ✓ Performs health checks
9. ✓ Reports deployment status

### Step 3: Verify Deployment Success

```bash
# Option 1: Check output from deployment script (above)
# Look for: "✓ Issue #950 Deployment SUCCESSFUL"

# Option 2: Manual verification
ssh akushnir@192.168.168.31 'docker compose ps'

# All services should show status: Up or healthy
```

### Step 4: Run Post-Deployment Validation

If you want comprehensive validation beyond the basic health checks:

```bash
ssh akushnir@192.168.168.31 'cd code-server-enterprise && bash scripts/ci/check-deployment-health.sh'
```

This runs the full validation from the POST-DEPLOYMENT-VALIDATION-APRIL-2026.md guide.

### Step 5: Close Issue #950

Once deployment is verified successful:

```bash
gh issue close 950 --repo kushin77/code-server --comment "✓ Deployment successful. Branch merged to main, all services operational on 192.168.168.31."
```

Or via GitHub web UI:
1. Go to https://github.com/kushin77/code-server/issues/950
2. Click "Close issue"
3. Select reason: "Completed"
4. Add comment summarizing deployment

---

## Expected Outputs

### Successful Deployment

```
========================================
Issue #950 Production Deployment
========================================

Step 1: Verifying host...
Current host IP: 192.168.168.31
✓ Correct host

Step 2: Navigating to repository...
✓ In repository

Step 3: Checking current branch...
Current branch: main
✓ Branch checked

[... steps 4-12 ...]

Step 13: Performing health checks...
✓ code-server responding
✓ oauth2-proxy health check passed
✓ Prometheus healthy

Step 14: Current service status...
NAME                COMMAND                  SERVICE             STATUS
code_server_prod    "/docker-entrypoint…"   code-server         Up (healthy)
caddy_prod          "caddy run --config …"  caddy               Up
oauth2_proxy_prod   "oauth2-proxy --conf…"  oauth2-proxy        Up (healthy)
postgres_prod       "docker-entrypoint…"   postgres            Up (healthy)
...

========================================
Deployment Summary
========================================
Health checks passed: 3/3
Backup location: /home/akushnir/code-server-enterprise/backups/deployment-20260422-120000
Deployment ID: 1713787200

✓ Issue #950 Deployment SUCCESSFUL
All services operational and health checks passing
```

### If There Are Issues

```
⚠ Issue #950 Deployment PARTIAL
Some services may still be starting. Check logs:
  docker compose logs --tail=50 <service-name>
```

**Troubleshooting**:
- Check specific service logs: `docker compose logs --tail=100 oauth2_proxy_prod`
- Check system resources: `free -h && df -h`
- Check network: `curl -v http://localhost:8080`
- See QUICK-REFERENCE-OPERATIONS-GUIDE.md for more troubleshooting

---

## Rollback (If Needed)

If deployment fails and you need to rollback:

```bash
ssh akushnir@192.168.168.31

# 1. List available backups
ls -la code-server-enterprise/backups/

# 2. Restore docker-compose from backup
cp code-server-enterprise/backups/deployment-20260422-120000/docker-compose-backup.yml \
   code-server-enterprise/docker-compose.yml

# 3. Restart services
cd code-server-enterprise
docker compose down --timeout=30
docker compose up -d

# 4. Verify services
docker compose ps
```

---

## Documentation References

**Before Deploying**: Read
- [ISSUE-950-READY-FOR-MERGE.md](docs/ISSUE-950-READY-FOR-MERGE.md) - Merge checklist
- [DEPLOYMENT-EPIC-950-SUMMARY-APRIL-2026.md](docs/DEPLOYMENT-EPIC-950-SUMMARY-APRIL-2026.md) - Architecture overview

**During/After Deployment**: Use
- [POST-DEPLOYMENT-VALIDATION-APRIL-2026.md](docs/POST-DEPLOYMENT-VALIDATION-APRIL-2026.md) - Full validation procedures
- [QUICK-REFERENCE-OPERATIONS-GUIDE.md](docs/QUICK-REFERENCE-OPERATIONS-GUIDE.md) - Quick troubleshooting

**For Operations**: Keep
- [OPERATIONS-CHECKLIST-DAILY-WEEKLY-MONTHLY.md](docs/OPERATIONS-CHECKLIST-DAILY-WEEKLY-MONTHLY.md) - Routine checks

---

## Timeline

| Step | Estimate | Notes |
|------|----------|-------|
| Create PR (Step 1A) | 5 min | Via GitHub web UI |
| Code review (Step 1) | 1-2 hours | Team review required |
| Merge PR (Step 1) | 10 min | Via GitHub web UI |
| Run deployment script (Step 2) | 3-5 min | Automatic execution |
| Verify (Step 3) | 2 min | Check docker ps output |
| Close issue (Step 5) | 2 min | Via GitHub |
| **Total** | **2-3 hours** | **Most is waiting for review** |

---

## Pre-Deployment Checklist

Before running the deployment script:

- [ ] Branch is merged to main (or pending merge)
- [ ] Current branch is `main`
- [ ] Latest code is pulled: `git pull origin main`
- [ ] All 10 services are defined in docker-compose.yml
- [ ] No local uncommitted changes: `git status` shows clean
- [ ] Sufficient disk space: `df -h` shows >50% free
- [ ] Sufficient memory: `free -h` shows >50 GB available
- [ ] SSH key configured for passwordless access
- [ ] Backup destination has space: `/home/akushnir/code-server-enterprise/backups/`

---

## Post-Deployment Checklist

After successful deployment:

- [ ] All services running: `docker compose ps` shows all Up/healthy
- [ ] Health checks passed: Deployment script showed 3/3 checks passed
- [ ] Code-server accessible: Browser can reach http://code-server.kushnir.cloud:8080
- [ ] OAuth login works: Can authenticate with Google account
- [ ] Monitoring active: Prometheus shows metrics collecting
- [ ] Alerts configured: AlertManager shows rules loaded
- [ ] Backups working: New backup file created in `/backups/`
- [ ] Issue #950 closed: GitHub issue marked completed

---

## Support

**If deployment fails:**
1. Check deployment script output for specific error
2. Review troubleshooting section in QUICK-REFERENCE-OPERATIONS-GUIDE.md
3. Check service logs: `docker compose logs --tail=100 <service>`
4. Rollback if needed (see Rollback section above)
5. Open new GitHub issue if problem persists

**Questions?**
- See `/docs/` for comprehensive guides
- Check `/docs/QUICK-REFERENCE-OPERATIONS-GUIDE.md` for command reference
- Review `/docs/OPERATIONS-CHECKLIST-DAILY-WEEKLY-MONTHLY.md` for procedures

---

**Issue #950 Deployment Ready**  
Created: April 22, 2026  
Status: ✅ Ready for Execution
