# April 26, 2026 - Stage 2 Pre-Deployment Preparation

**Date Created**: April 24, 2026  
**Status**: IN PROGRESS  
**Target**: Complete all prep by April 25, 18:00 UTC  
**Deployment**: April 26, 08:00 UTC

---

## Immediate Action Items (April 24-25, 2026)

### ✅ COMPLETED IN PREVIOUS SESSION
- [x] IaC/Immutable/Idempotent compliance verified
- [x] All P0 security fixes (#968-#980) operational
- [x] Both production replicas healthy and synchronized
- [x] STAGE-2-APRIL-26-EXECUTION-CHECKLIST.md created
- [x] Feature flags prepared for Stage 2 canary deployment
- [x] Monitoring runbook documented (500+ lines)
- [x] Rollback procedures documented

### ⏳ BLOCKING ISSUE: Let's Encrypt Rate Limit
- **Current Status**: Rate limit ACTIVE (enforced 5 certs in 168h)
- **Rate Limit Expires**: April 25, 2026 at 11:29:47 UTC (31 hours from discovery)
- **Impact**: HTTPS endpoints not serving TLS (HTTP still working)
- **Mitigation**: Automatic resolution post-expiry
- **Timeline**:
  - April 25, 11:30 UTC: Rate limit expires → automatic renewal proceeds
  - April 25, 12:00 UTC: Restart Caddy on both replicas
  - April 25, 13:00 UTC: Verify HTTPS endpoints responding
  - April 25, 18:00 UTC: Final systems health check
  - April 26, 06:00 UTC: Pre-deployment validation
  - April 26, 08:00 UTC: Deploy Stage 2 canary

---

## Tasks for April 25, 2026

### Task 1: Post-Rate-Limit Certificate Renewal (11:30-13:00 UTC)

**Procedure**:
1. At 11:30 UTC, verify rate limit has expired:
   ```bash
   curl -i https://acme-v02.api.letsencrypt.org/acme/new-nonce
   ```
   (Should not show rate limit error)

2. Restart Caddy on both replicas to trigger renewal:
   ```bash
   ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose restart caddy"
   ssh akushnir@192.168.168.42 "cd code-server-enterprise && docker-compose restart caddy"
   ```

3. Monitor Caddy logs for successful renewal:
   ```bash
   ssh akushnir@192.168.168.31 "docker-compose logs -f caddy | grep -E 'issued|certificate'"
   ```

4. Wait 5 minutes for renewal to complete, then verify:
   ```bash
   curl -kv https://ide.kushnir.cloud/health
   ```
   Expected: HTTP 200 response with TLS handshake success

5. Verify both replicas have renewed certificates:
   ```bash
   for host in 192.168.168.31 192.168.168.42; do
     echo "=== $host ==="
     ssh akushnir@$host "curl -kv https://ide.kushnir.cloud/health 2>&1 | head -10"
   done
   ```

**Sign-off**: 
- [ ] Rate limit verified expired
- [ ] Caddy restarted on both replicas
- [ ] HTTPS renewal confirmed
- [ ] Both replicas serving TLS successfully

---

### Task 2: Systems Health Check (18:00 UTC, April 25)

**Procedure**:
1. Verify all services operational on R31:
   ```bash
   ssh akushnir@192.168.168.31 "docker-compose ps | grep -E 'UP|Exit' | wc -l"
   ```
   Expected: 23 services UP

2. Verify all services operational on R42:
   ```bash
   ssh akushnir@192.168.168.42 "docker-compose ps | grep -E 'UP|Exit' | wc -l"
   ```
   Expected: 22 services UP (Appsmith intentionally disabled)

3. Check health endpoints on both:
   ```bash
   for endpoint in http://ide.kushnir.cloud/health https://ide.kushnir.cloud/health; do
     echo "Testing: $endpoint"
     curl -s $endpoint | head -20
   done
   ```

4. Verify git status on both replicas:
   ```bash
   for host in 192.168.168.31 192.168.168.42; do
     echo "=== $host ==="
     ssh akushnir@$host "cd code-server-enterprise && git log --oneline -1 && git status --short"
   done
   ```
   Expected: Both on commit f65635db (or later), working directory clean

**Sign-off**:
- [ ] R31: 23 services UP
- [ ] R42: 22 services UP
- [ ] HTTP health endpoints responding
- [ ] HTTPS health endpoints responding (post-renewal)
- [ ] Both replicas at latest commit
- [ ] Working directory clean on both

---

## Tasks for April 26, 2026

### Task 3: Pre-Deployment Validation (06:00 UTC)

**Procedure**:
1. Run comprehensive validation:
   ```bash
   cd c:\code-server-enterprise
   bash scripts/ci/validate-stage-2-readiness.sh
   ```

2. Verify all 5 validation phases PASS:
   - Phase 1: SSH connectivity to both replicas
   - Phase 2: Docker daemon operational on both
   - Phase 3: HTTP health endpoints responding
   - Phase 4: Observability stack (Prometheus, Grafana, Loki, Jaeger) UP
   - Phase 5: Performance baseline SLOs MET (P99 latency <15ms, 100% success rate)

3. If any phase FAILS: STOP and troubleshoot before proceeding

**Sign-off**:
- [ ] Validation script executed
- [ ] All 5 phases PASSED
- [ ] No blocking issues identified

---

### Task 4: Deployment Execution (08:00 UTC)

**Phase 1: Deploy to Replica 1 (R31) - 08:00 UTC**
```bash
ssh akushnir@192.168.168.31 "cd code-server-enterprise && \
  COLLAB_9_STAGE_2_ENABLED=true \
  docker-compose up -d"
```

Monitoring: 10-minute intensive checks (08:00-08:10 UTC)
- Health endpoints responding
- P99 latency < 15ms
- Error rate < 1%
- All 23 services UP

**Phase 2: Deploy to Replica 2 (R42) - 08:15 UTC**
```bash
ssh akushnir@192.168.168.42 "cd code-server-enterprise && \
  COLLAB_9_STAGE_2_ENABLED=true \
  docker-compose up -d"
```

Monitoring: 10-minute intensive checks (08:15-08:25 UTC)
- Health endpoints responding
- P99 latency < 15ms
- Error rate < 1%
- All 22 services UP

**Sign-off**:
- [ ] R31 deployment successful
- [ ] R31 health checks all PASS
- [ ] R42 deployment successful
- [ ] R42 health checks all PASS
- [ ] Both replicas synchronized

---

## Monitoring Schedule (April 26, 08:00 UTC - 20:00 UTC)

| Time | Frequency | Action |
|------|-----------|--------|
| 08:00-08:15 | Every 1 min | Deploy R31, verify services UP |
| 08:15-08:25 | Every 1 min | Deploy R42, verify services UP |
| 08:25-09:00 | Every 5 min | Verify both replicas stable |
| 09:00-12:00 | Every 15 min | Health checks, latency, error rates |
| 12:00-16:00 | Every 30 min | Continued monitoring |
| 16:00-20:00 | Every 1 hour | Extended monitoring period |

---

## Decision Gates

### GO/NO-GO Decision Point 1: 20:00 UTC (12-hour checkpoint)

**Criteria for GO**:
- ✅ Both replicas running Stage 2 canary
- ✅ All 23/22 services UP on respective replicas
- ✅ P99 latency consistently < 15ms
- ✅ Error rate < 1% across 12-hour period
- ✅ Health endpoints responding
- ✅ No customer-facing issues reported

**Decision**:
- [ ] GO: Proceed to 24-hour monitoring
- [ ] NO-GO: Activate rollback procedures (see below)

### GO/NO-GO Decision Point 2: April 27, 08:00 UTC (24-hour checkpoint)

**Criteria for ACCEPT**:
- ✅ All GO criteria met for full 24-hour period
- ✅ Canary metrics exceed baseline SLOs
- ✅ Zero critical issues identified
- ✅ Customer feedback positive

**Decision**:
- [ ] ACCEPT: Canary successful, proceed to full production deployment
- [ ] EXTEND: Run canary for additional 24 hours with team review
- [ ] ROLLBACK: Deactivate canary and analyze issues

---

## Rollback Procedures

**If Issues Detected**:
1. Disable COLLAB_9_STAGE_2_ENABLED feature flag:
   ```bash
   ssh akushnir@192.168.168.31 "cd code-server-enterprise && \
     COLLAB_9_STAGE_2_ENABLED=false \
     docker-compose up -d"
   ssh akushnir@192.168.168.42 "cd code-server-enterprise && \
     COLLAB_9_STAGE_2_ENABLED=false \
     docker-compose up -d"
   ```

2. Verify rollback successful:
   ```bash
   for host in 192.168.168.31 192.168.168.42; do
     ssh akushnir@$host "docker-compose ps | tail -5"
   done
   ```

3. Document issue and prepare analysis for team

---

## Team Coordination Checkpoints

- [ ] April 25, 13:00 UTC: Certificate renewal verification (send update to team)
- [ ] April 25, 18:00 UTC: Systems health check complete (send status to team)
- [ ] April 26, 06:00 UTC: Pre-deployment validation complete (GO/NO-GO decision)
- [ ] April 26, 08:30 UTC: Both phases deployed, initial monitoring results
- [ ] April 26, 20:00 UTC: 12-hour checkpoint decision (GO/NO-GO for continued monitoring)
- [ ] April 27, 08:00 UTC: 24-hour checkpoint decision (ACCEPT/EXTEND/ROLLBACK)

---

## Risk Mitigation

| Risk | Mitigation | Owner |
|------|-----------|-------|
| Certificate renewal fails | Manual renewal via Let's Encrypt API | Infra team |
| Service degradation post-deployment | Immediate rollback to pre-canary state | On-call |
| Customer impact | Feature flag enables instant disable | Product team |
| Monitoring data loss | Separate alerting channel + local logs | Observability |

---

## Success Criteria

✅ **Pre-Deployment** (April 25):
- Rate limit expires successfully
- HTTPS endpoints renewed and serving TLS
- All services healthy on both replicas
- Git status clean and synchronized

✅ **Deployment** (April 26):
- Both replicas deploy successfully
- Health checks all pass immediately post-deploy
- Monitoring shows stable metrics

✅ **Post-Deployment** (April 26-27):
- 12-hour checkpoint: All GO criteria met
- 24-hour checkpoint: Ready for acceptance or rollback decision

---

## Files Reference

- **Checklist**: STAGE-2-APRIL-26-EXECUTION-CHECKLIST.md
- **Deployment**: scripts/ops/deploy-collab-9-production-canary.sh
- **Validation**: scripts/ci/validate-stage-2-readiness.sh
- **Rollback**: scripts/ops/rollback-stage-2-canary.sh
- **Monitoring**: Runbook in deployment-operations-complete-guide.md

---

## Status Summary

| Item | Status | Target Date |
|------|--------|-------------|
| Pre-deployment prep | ✅ READY | - |
| Certificate renewal | ⏳ WAITING | April 25, 11:30 UTC |
| Systems health check | ⏳ WAITING | April 25, 18:00 UTC |
| Pre-deployment validation | ⏳ WAITING | April 26, 06:00 UTC |
| Deployment execution | ⏳ WAITING | April 26, 08:00 UTC |
| 12-hour checkpoint | ⏳ WAITING | April 26, 20:00 UTC |
| 24-hour checkpoint | ⏳ WAITING | April 27, 08:00 UTC |

---

**Prepared By**: Copilot Agent  
**Date**: April 24, 2026  
**Status**: READY FOR EXECUTION  
**Next Action**: Monitor April 25, 11:30 UTC for rate limit expiry → proceed with certificate renewal
