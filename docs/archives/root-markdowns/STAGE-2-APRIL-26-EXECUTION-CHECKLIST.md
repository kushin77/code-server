# Collab-9 Stage 2 Canary - April 26, 2026 Execution Checklist

**Status**: Ready for Execution  
**Date**: April 24, 2026  
**Scheduled Deployment**: April 26, 2026 (post-LetsEncrypt rate limit expiry)  
**Last Updated**: April 24, 2026 04:52 UTC

---

## Pre-Deployment (April 25, 2026 - Post Rate Limit Expiry)

### 1. Certificate Verification (Required before deployment)
- [ ] Verify Let's Encrypt rate limit expires April 25 at 11:29:47 UTC
- [ ] After 11:30 UTC, SSH to each replica and restart caddy:
  ```bash
  ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose restart caddy"
  ssh akushnir@192.168.168.42 "cd code-server-enterprise && docker-compose restart caddy"
  ```
- [ ] Verify HTTPS responding: `curl -k https://ide.kushnir.cloud/health`
- [ ] Verify both replicas serving TLS successfully (no SSL alert errors)

### 2. Systems Health Check (April 25, 18:00 UTC)
- [ ] Replica 1 (192.168.168.31): 23 services UP
- [ ] Replica 2 (192.168.168.42): 22 services UP
- [ ] All health endpoints responding (HTTP and HTTPS)
- [ ] Observability stack operational (Prometheus, Grafana, Loki, Jaeger)

### 3. Git and Code Status
- [ ] Latest commit on both replicas: a456d4fb (or later)
- [ ] Working directory clean on local machine
- [ ] No uncommitted changes blocking deployment

### 4. Deployment Scripts Validation
- [ ] Verify `scripts/ops/deploy-collab-9-production-canary.sh` present and executable
- [ ] Verify feature flags in place (COLLAB_9_STAGE_2_ENABLED=true)
- [ ] Verify rollback procedures documented in runbook

---

## Deployment Day (April 26, 2026 Morning)

### 5. Final Pre-Deployment Verification (06:00 UTC)
- [ ] Run pre-deployment validation: `bash scripts/ci/validate-stage-2-readiness.sh`
- [ ] All 5 validation phases PASS (SSH, Docker, HTTP, Observability, Performance)
- [ ] No blocking issues identified

### 6. Deployment Execution (08:00 UTC - Scheduled Time)

**Phase 1: Replica 1 (R31)**
```bash
ssh akushnir@192.168.168.31 "cd code-server-enterprise && \
  bash scripts/ops/deploy-collab-9-production-canary.sh --phase 1"
```
- [ ] Deployment initiated
- [ ] Docker compose up -d succeeds
- [ ] 23 services healthy
- [ ] Health checks passing

**Phase 2: Replica 2 (R42)**
```bash
ssh akushnir@192.168.168.42 "cd code-server-enterprise && \
  bash scripts/ops/deploy-collab-9-production-canary.sh --phase 1"
```
- [ ] Deployment initiated
- [ ] Docker compose up -d succeeds
- [ ] 22 services healthy
- [ ] Health checks passing

### 7. First 1-Hour Monitoring (08:00-09:00 UTC)
- [ ] Every 10 minutes: Verify both replicas operational
- [ ] Check container status: `docker-compose ps`
- [ ] Verify no crash loops or restarts
- [ ] Review Caddy logs for errors
- [ ] Confirm feature flag is active
- [ ] Monitor CPU/memory usage (<80%)

### 8. First 8-Hour Monitoring (09:00-16:00 UTC)
- [ ] Hourly health checks per runbook section 3.1
- [ ] Prometheus metrics collecting correctly
- [ ] Grafana dashboards showing data
- [ ] No errors in application logs
- [ ] No performance degradation observed

### 9. 12-Hour Checkpoint (20:00 UTC - GO/NO-GO Decision)
- [ ] Run full validation: `bash scripts/ci/validate-stage-2-readiness.sh`
- [ ] All SLOs met (P99 latency <100ms, success rate >99%)
- [ ] No critical issues observed
- [ ] **Decision**: Continue or rollback?
- [ ] Document decision in GitHub issue #1467

### 10. 24-Hour Checkpoint (April 27, 08:00 UTC - Final Decision)
- [ ] All monitoring metrics stable
- [ ] No incidents or issues
- [ ] Performance baseline maintained
- [ ] **Decision**: Keep deployed or rollback?
- [ ] Document final status in GitHub issue #1467

---

## Rollback Procedures (If Needed at Any Point)

```bash
# Both replicas simultaneously
ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose down && git checkout HEAD~1 && docker-compose up -d"
ssh akushnir@192.168.168.42 "cd code-server-enterprise && docker-compose down && git checkout HEAD~1 && docker-compose up -d"
```

- [ ] Rollback time: <5 minutes both replicas
- [ ] Revert to commit b1343ecb (last known good)
- [ ] Verify all 23/22 services healthy post-rollback
- [ ] Document rollback reason in GitHub issue

---

## Contacts & Escalation

**On-Call Engineer**: [Team Name]  
**Escalation Path**: Team Lead → Manager → CTO  
**Incident Channel**: #production-incidents (Slack)  
**Status Page**: https://status.kushnir.cloud

---

## Sign-Offs

- [ ] Technical Lead: _____________________ Date: _______
- [ ] DevOps: _____________________ Date: _______
- [ ] Product Manager: _____________________ Date: _______

---

## Success Criteria

✅ **Deployment Successful When:**
1. Both replicas healthy and synchronized
2. All services passing health checks
3. No critical errors in logs
4. Performance metrics within SLOs (P99 <100ms, success >99%)
5. Feature flag working and engaged
6. Monitoring data collected and visible

---

## Appendix: Quick Command Reference

```bash
# SSH to replicas
ssh akushnir@192.168.168.31  # Replica 1
ssh akushnir@192.168.168.42  # Replica 2

# Check service status
docker-compose ps

# View logs
docker-compose logs -f [service-name]

# Restart Caddy (post-cert renewal)
docker-compose restart caddy

# View health endpoint
curl -k https://ide.kushnir.cloud/health

# Full deployment
bash scripts/ops/deploy-collab-9-production-canary.sh --phase 1
```

---

**Prepared By**: Copilot Agent  
**Date**: April 24, 2026  
**Version**: 1.0  
**Status**: Ready for Execution  
