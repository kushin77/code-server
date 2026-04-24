# April 25, 2026 - Pre-Deployment Validation Procedure

**Date:** April 24, 2026 (preparation for April 25)  
**Event:** Final validation before April 26 09:00 UTC deployment  
**Status:** Ready to execute tomorrow (April 25)

---

## Overview

This procedure ensures all systems are operational and ready for production canary deployment on April 26 at 09:00 UTC. Execute this checklist on April 25 at any time (recommended: morning or early afternoon UTC).

---

## Phase 1: Let's Encrypt Rate Limit Recovery (Automated)

**Expected Status:** RESOLVED (rate limit expires ~01:48 UTC April 24)

### Verification Steps

1. **Check Caddy Certificate Status on Replica 1**
   ```bash
   ssh akushnir@192.168.168.31 'docker logs caddy --since 12h | grep -i "certificate\|renew\|obtain" | tail -20'
   ```
   **Expected Output:** Should show "certificate obtained" or similar renewal message  
   **What to do if FAILED:** Contact security lead — certificate may not have renewed

2. **Check Caddy Certificate Status on Replica 2**
   ```bash
   ssh akushnir@192.168.168.42 'docker logs caddy --since 12h | grep -i "certificate\|renew\|obtain" | tail -20'
   ```
   **Expected Output:** Same as Replica 1  
   **What to do if FAILED:** Contact security lead — consistency issue

3. **Verify HTTPS Endpoint Accessibility**
   ```bash
   curl -I https://ide.kushnir.cloud/health 2>&1 | head -5
   ```
   **Expected Output:**
   ```
   HTTP/2 200 
   ```
   **What to do if FAILED:** SSL certificate not installed; do not proceed with deployment

---

## Phase 2: Infrastructure Verification

### SSH Access & Git Status

Execute on local dev machine:

```bash
echo "=== Replica 1 Status ==="
ssh akushnir@192.168.168.31 'cd code-server-enterprise && git log --oneline -1 && git status --short'

echo "=== Replica 2 Status ==="
ssh akushnir@192.168.168.42 'cd code-server-enterprise && git log --oneline -1 && git status --short'
```

**Expected Output:**
- Both replicas: Git commit `c974d7c4` (or later if updates merged)
- Both replicas: `nothing to commit, working tree clean`

**What to do if FAILED:**
- Commit mismatch: Run sync script — `bash scripts/ops/sync-replicas.sh`
- Uncommitted changes: Stash and pull latest — `git stash && git pull origin main`

---

## Phase 3: Docker Services Health Check

### Replica 1 (Primary)

```bash
ssh akushnir@192.168.168.31 'docker-compose -f code-server-enterprise/docker-compose.yml ps | grep -E "^code-server|^caddy|^oauth2|^postgres|^redis|^prometheus|^grafana" | grep -c "Up"'
```

**Expected Output:** 21 (or higher if new services added)  
**What to do if FAILED:** Fewer than 20 services running
- Check logs: `ssh akushnir@192.168.168.31 'docker-compose -f code-server-enterprise/docker-compose.yml ps'`
- Restart failed service: `ssh akushnir@192.168.168.31 'docker-compose -f code-server-enterprise/docker-compose.yml restart <service>'`

### Replica 2 (Secondary)

```bash
ssh akushnir@192.168.168.42 'docker-compose -f code-server-enterprise/docker-compose.yml ps | grep -v "port.*allocated" | grep -c "Up"'
```

**Expected Output:** 20 (1 intentionally disabled due to #1641)  
**What to do if FAILED:** Fewer than 20 services running
- Same recovery as Replica 1
- Confirm port binding workaround is still in place

---

## Phase 4: Monitoring Stack Verification

### Prometheus Metrics Collection

```bash
curl -s http://192.168.168.31:9090/api/v1/query?query=up | jq '.data.result | length'
```

**Expected Output:** 50+ (number of monitored targets)  
**What to do if FAILED:** Prometheus not scraping metrics
- Check Prometheus logs: `ssh akushnir@192.168.168.31 'docker logs prometheus'`
- Verify config: `ssh akushnir@192.168.168.31 'cat /path/to/prometheus.yml'`

### Grafana Dashboard Availability

```bash
curl -I http://192.168.168.31:3000/login 2>&1 | grep "HTTP"
```

**Expected Output:**
```
HTTP/1.1 200 OK
```

**What to do if FAILED:** Grafana not responding
- Restart Grafana: `ssh akushnir@192.168.168.31 'docker restart grafana'`
- Check logs: `ssh akushnir@192.168.168.31 'docker logs grafana'`

### Loki Log Aggregation

```bash
curl -s http://192.168.168.31:3100/loki/api/v1/label/__name__/values | jq '. | length'
```

**Expected Output:** 10+ (number of log streams)  
**What to do if FAILED:** Loki not collecting logs
- Restart Loki: `ssh akushnir@192.168.168.31 'docker restart loki'`
- Verify Promtail is running: `ssh akushnir@192.168.168.31 'docker ps | grep promtail'`

### Jaeger Distributed Tracing

```bash
curl -I http://192.168.168.31:16686/ 2>&1 | grep "HTTP"
```

**Expected Output:**
```
HTTP/1.1 200 OK
```

**What to do if FAILED:** Jaeger not responding
- Restart Jaeger: `ssh akushnir@192.168.168.31 'docker restart jaeger'`

---

## Phase 5: Cluster Parity Validation

### Run Cluster Parity Check

Execute on local dev machine:

```bash
bash scripts/ops/validate-cluster-parity.sh
```

**Expected Output:**
```
✅ Replica 1 & 2 at same commit
✅ 21 services on both replicas (accounting for #1641)
✅ Configuration synchronized
✅ Health checks passing on both replicas
✅ Cluster parity VERIFIED
```

**What to do if FAILED:**
- Commit mismatch: `bash scripts/ops/sync-replicas.sh`
- Service count mismatch: Review docker-compose differences
- Health check failure: Check Replica logs

---

## Phase 6: Deployment Script Validation

### Syntax Check

```bash
bash -n scripts/ops/parallel-deploy.sh
bash -n scripts/ops/validate-cluster-parity.sh
bash -n scripts/ci/validate-stage-2-readiness.sh
```

**Expected Output:** No output (clean syntax)  
**What to do if FAILED:** Syntax error in script
- Review error message
- Fix and commit: `git commit -am "fix: syntax error in deployment script"`

### Test Dry-Run (Optional but Recommended)

```bash
bash scripts/ops/parallel-deploy.sh --dry-run
```

**Expected Output:**
```
[DRY-RUN] Would deploy to Replica 1 (192.168.168.31)
[DRY-RUN] Would deploy to Replica 2 (192.168.168.42)
[DRY-RUN] Would validate cluster parity
```

---

## Phase 7: DAST Scan Recovery (Post Certificate Renewal)

### Run DAST Scan to Verify SSL Recovery

Once Let's Encrypt rate limit expires and certificate renews, run DAST scan:

```bash
curl -s http://192.168.168.31:8080/zap-cli scan -u https://ide.kushnir.cloud/health
```

**Expected Output:** Successful scan with no SSL errors  
**What to do if FAILED:** Certificate still not renewed
- Manual renewal: `ssh akushnir@192.168.168.31 'docker exec caddy caddy reload'`
- Check certificate: `ssh akushnir@192.168.168.31 'docker exec caddy caddy list-certificates'`

### Verify DAST Issue #1692 Resolution

Once scan succeeds:
```bash
gh issue comment 1692 --repo kushin77/code-server --body "✅ DAST scan successful post-certificate renewal. SSL/TLS issue resolved. Ready for production deployment April 26."
```

---

## Phase 8: Team Sign-Off Verification

### Confirm All 6 Approvals on Issue #1464

```bash
gh issue view 1464 --repo kushin77/code-server --json comments | jq '.[] | select(.body | contains("Approved")) | .author.login' | sort | uniq
```

**Expected Output:** 6 team leads with approval comments  
**What to do if FAILED:** Incomplete approvals
- Follow up with missing team leads
- Extend deployment date if needed for approvals

---

## Phase 9: Production Readiness Final Certification

### Run Full Validation Script

```bash
bash scripts/ci/validate-stage-2-readiness.sh
```

This validates:
- Phase 1: SSH & Git status ✅
- Phase 2: Docker services running ✅
- Phase 3: HTTP connectivity ✅
- Phase 4: Observability services ✅
- Phase 5: Performance & deployment scripts ✅

**Expected Output:**
```
[INFO] ==========================================
[INFO] Collab-9 Stage 2 Readiness Validation
[INFO] ==========================================
[SUCCESS] All 5 phases passed - deployment ready
```

---

## Summary Checklist (April 25)

### Morning/Afternoon (Any Time April 25)

- [ ] **Phase 1:** Let's Encrypt certificate renewed (check Caddy logs)
- [ ] **Phase 1:** HTTPS endpoint accessible (curl -I https://ide.kushnir.cloud/health)
- [ ] **Phase 2:** SSH access to both replicas working
- [ ] **Phase 2:** Git commits synchronized (c974d7c4)
- [ ] **Phase 3:** 21 services running on Replica 1
- [ ] **Phase 3:** 20 services running on Replica 2 (workaround #1641)
- [ ] **Phase 4:** Prometheus collecting metrics (50+ targets)
- [ ] **Phase 4:** Grafana accessible (HTTP 200)
- [ ] **Phase 4:** Loki collecting logs (10+ streams)
- [ ] **Phase 4:** Jaeger accessible (HTTP 200)
- [ ] **Phase 5:** Cluster parity validated
- [ ] **Phase 6:** Deployment scripts syntax valid
- [ ] **Phase 7:** DAST scan succeeds (SSL recovered)
- [ ] **Phase 8:** All 6 team sign-offs on Issue #1464
- [ ] **Phase 9:** Final validation script passes

---

## Approval & Readiness Sign-Off

Once all phases pass:

```bash
# Create sign-off document
cat > APRIL-25-VALIDATION-SIGN-OFF.md << 'EOF'
# April 25, 2026 - Pre-Deployment Validation Sign-Off

**Date:** April 25, 2026  
**Validated by:** [Team Lead Name]  
**Status:** ✅ READY FOR DEPLOYMENT

All 9 validation phases passed. Production canary deployment scheduled for April 26, 2026 at 09:00 UTC.

**Signature:** _________________ **Time:** _________
EOF

# Commit and push
git add APRIL-25-VALIDATION-SIGN-OFF.md
git commit -m "docs: April 25 pre-deployment validation sign-off - all systems ready"
git push origin main
```

---

## Troubleshooting Guide

### Issue: SSL Certificate Not Renewed
- **Cause:** Let's Encrypt rate limit still in effect or renewal failed
- **Fix:** Manual Caddy reload: `ssh akushnir@192.168.168.31 'docker exec caddy caddy reload'`
- **Timeline:** Rate limit expires ~01:48 UTC April 24; should be auto-renewed by April 25

### Issue: Service Count Mismatch
- **Cause:** Service startup failed or container crashed
- **Fix:** Check docker-compose: `docker-compose -f code-server-enterprise/docker-compose.yml up -d`
- **Verify:** `docker-compose ps` should show all services Up

### Issue: Cluster Parity Failed
- **Cause:** Git commits or config out of sync
- **Fix:** Run sync script: `bash scripts/ops/sync-replicas.sh`
- **Verify:** `bash scripts/ops/validate-cluster-parity.sh`

### Issue: Deployment Script Syntax Error
- **Cause:** Recent changes introduced syntax issue
- **Fix:** Fix and commit: `git commit -am "fix: script syntax"`
- **Verify:** `bash -n scripts/ops/parallel-deploy.sh`

### Issue: DAST Scan Still Fails
- **Cause:** Certificate renewal incomplete
- **Action:** Delay DAST until certificate successfully renewed
- **Escalate:** Contact security lead if not resolved by April 26 05:00 UTC

---

## April 26 Deployment Execution

Once April 25 validation completes successfully:

```bash
# Morning of April 26 (08:00 UTC)
echo "All validation complete. Deployment approved for 09:00 UTC"

# 09:00 UTC sharp
bash scripts/ops/parallel-deploy.sh
```

Deployment execution automatically:
1. Syncs config to both replicas
2. Pulls latest code
3. Deploys with health checks
4. Validates cluster parity
5. Activates monitoring for 48-hour canary window

---

**Status:** ✅ **READY FOR APRIL 25 VALIDATION**

Execute this checklist on April 25. If all phases pass, deployment is ready for April 26 09:00 UTC execution.
