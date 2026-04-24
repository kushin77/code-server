# P1 EXECUTION QUICK REFERENCE

**Status**: ✅ READY FOR IMMEDIATE EXECUTION  
**Date**: April 23, 2026  
**Governance**: IaC | Immutable | Idempotent | Deterministic | Reversible

---

## ONE-COMMAND EXECUTION (All Phases)

```bash
cd /mnt/c/code-server-enterprise && \
SSH_KEY=$HOME/.ssh/id_rsa_onprem bash scripts/ops/P1-1661-COMPLETION-EXECUTE.sh && \
SSH_KEY=$HOME/.ssh/id_rsa_onprem bash scripts/ops/P1-1466-STAGING-VALIDATION-EXECUTE.sh && \
SSH_KEY=$HOME/.ssh/id_rsa_onprem bash scripts/ops/P1-1467-GO-NO-GO-DECISION-EXECUTE.sh
```

**Total Duration**: 50-80 minutes  
**Expected Outcome**: GO decision posted to GitHub #1467

---

## INDIVIDUAL EXECUTION

### Phase 1: Deploy Health Monitoring (Non-Blocking)
```bash
cd /mnt/c/code-server-enterprise
SSH_KEY=$HOME/.ssh/id_rsa_onprem bash scripts/ops/P1-1661-COMPLETION-EXECUTE.sh
```
**Duration**: 15-20 min  
**Output**: 
- Prometheus deployed to 192.168.168.31 + 192.168.168.42
- AlertManager + alert rules configured
- Report: `/tmp/P1-1661-COMPLETION-REPORT.md`

### Phase 2: Staging Validation (Blocking)
```bash
cd /mnt/c/code-server-enterprise
SSH_KEY=$HOME/.ssh/id_rsa_onprem bash scripts/ops/P1-1466-STAGING-VALIDATION-EXECUTE.sh
```
**Duration**: 30-45 min  
**Output**:
- Full deployment runbook validated
- Rollback tested and verified
- Report: `/tmp/P1-1466-STAGING-VALIDATION-REPORT.md`
- Decision: READY/NOT READY

### Phase 3: GO/NO-GO Decision (Blocking)
```bash
cd /mnt/c/code-server-enterprise
SSH_KEY=$HOME/.ssh/id_rsa_onprem bash scripts/ops/P1-1467-GO-NO-GO-DECISION-EXECUTE.sh
```
**Duration**: 5-10 min  
**Output**:
- Evidence assessment completed
- Decision posted to GitHub #1467
- Authorization: GO or NO-GO

---

## WHAT EACH SCRIPT DOES

### P1-1661-COMPLETION-EXECUTE.sh
Deploys Prometheus + AlertManager health monitoring:
1. Verifies SSH connectivity (both replicas)
2. Syncs git repos (if needed)
3. Deploys containers (parallel)
4. Verifies scrape targets loaded
5. Confirms alert rules active
6. Generates completion report

**Prerequisites**:
- SSH key: `~/.ssh/id_rsa_onprem` available
- Git: Both replicas at origin/main

**Rollback**: `ssh akushnir@192.168.168.31 'docker-compose down prometheus alertmanager'`

---

### P1-1466-STAGING-VALIDATION-EXECUTE.sh
Executes full staging validation:
1. Pre-deployment: tooling checks
2. Deployment: docker-compose up -d
3. Health checks: verify endpoints
4. Performance: latency + resource measurement
5. Rollback test: down → up → verify
6. Gap analysis: identify any issues
7. Final report: ready/not ready

**Prerequisites**:
- Replica 1 (192.168.168.31) accessible
- Docker + docker-compose available

**Expected Result**: READY FOR PRODUCTION DEPLOYMENT

---

### P1-1467-GO-NO-GO-DECISION-EXECUTE.sh
Issues GO/NO-GO decision:
1. Collects evidence from all phases
2. Assesses 5 decision criteria
3. Calculates go/no-go score
4. Posts decision to GitHub
5. Documents risk assessment
6. Authorizes deployment path

**Prerequisites**:
- P1 #1661 complete (health monitoring)
- P1 #1466 complete (staging validation)

**Outcome**: 🟢 GO or 🔴 NO-GO

---

## SUCCESS CHECKLIST

After execution, verify:

- [ ] P1 #1661 report shows "✅ DEPLOYMENT COMPLETE"
- [ ] P1 #1466 report shows "✅ VALIDATION COMPLETE"
- [ ] P1 #1467 GitHub comment shows "🟢 GO DECISION"
- [ ] Both replicas health endpoints responding (HTTP 200)
- [ ] Prometheus scrape targets > 0
- [ ] AlertManager rules loaded > 0
- [ ] No ERROR entries in any script output

---

## ROLLBACK COMMANDS

If something goes wrong:

### Rollback P1 #1661 (remove monitoring)
```bash
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  'cd code-server-enterprise && docker-compose down prometheus alertmanager'
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 \
  'cd code-server-enterprise && docker-compose down prometheus alertmanager'
```

### Rollback P1 #1466 (reset replica to clean state)
```bash
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  'cd code-server-enterprise && git reset --hard origin/main && docker-compose down && docker-compose up -d'
```

### Rollback P1 #1467 (delete decision comment from GitHub)
```bash
gh issue comment delete <COMMENT_ID> --repo kushin77/code-server
```

---

## MONITORING DURING EXECUTION

### Watch P1 #1661 deployment
```bash
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'docker ps -a | grep prometheus'
```

### Watch P1 #1466 containers
```bash
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'watch docker ps'
```

### Watch P1 #1467 decision on GitHub
```bash
gh issue view 1467 --repo kushin77/code-server --comments
```

---

## TROUBLESHOOTING

**Script exits with SSH error**:
```bash
# Verify key access
ssh -i ~/.ssh/id_rsa_onprem -v akushnir@192.168.168.31 true
```

**Containers fail to start**:
```bash
# Check docker-compose syntax
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  'cd code-server-enterprise && docker-compose config | head -50'
```

**Health endpoints not responding**:
```bash
# Check container logs
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  'docker logs prometheus | tail -20'
```

**Performance metrics high**:
```bash
# Check resource utilization
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'docker stats'
```

---

## NEXT AFTER P1 #1467 GO

Once GO decision posted:

1. **Team Sign-Offs** (Issue #1464): Continue collection in parallel
2. **Production Deployment** (Issue #1468): Execute deployment to all replicas
3. **Post-Deployment Retrospective** (Issue #1471): Capture lessons learned

---

## GOVERNANCE COMPLIANCE ✅

- **IaC**: ✅ All config in git, no manual changes
- **Immutable**: ✅ Script-driven deployment only
- **Idempotent**: ✅ Safe to re-run multiple times
- **Deterministic**: ✅ Same input = same output
- **Reversible**: ✅ Full rollback capability via git

---

## CONTACT / ESCALATION

- **Infrastructure Issues**: Check ssh key + network connectivity
- **Deployment Issues**: Check docker-compose config + container logs
- **GitHub Issues**: Verify gh CLI authentication
- **Decision Blockers**: Review P1 #1661 + P1 #1466 reports

---

**Ready to execute?** Run Phase 1, then Phase 2, then Phase 3.  
**All governance standards maintained throughout.**

Proceed with: `cd /mnt/c/code-server-enterprise && SSH_KEY=$HOME/.ssh/id_rsa_onprem bash scripts/ops/P1-1661-COMPLETION-EXECUTE.sh`
