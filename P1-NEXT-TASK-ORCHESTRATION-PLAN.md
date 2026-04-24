# P1 NEXT TASK ORCHESTRATION PLAN

**Date**: April 23, 2026  
**Mandate**: "proceed now to next task — ensure IaC, immutable, idempotent"  
**Current Status**: P1 #1661 deployment initiated; next tasks identified

---

## Current State: P1 #1661 Health Monitoring

**Status**: ✅ DEPLOYMENT INITIATED  
**Action**: Prometheus health monitoring deployed to both replicas via parallel SSH  
**Remaining**:  
- [ ] Verify containers running on both replicas
- [ ] Verify health endpoints responding (200 OK)
- [ ] Verify Prometheus scrape targets UP
- [ ] Post evidence to GitHub #1661
- [ ] Mark issue complete

---

## Next P1 Tasks Identified (In Priority Order)

### IMMEDIATE: P1 #1661 Verification Tasks (complete ASAP)

**Task 1.1: Verify Deployment Completion**
```bash
# On both replicas:
docker-compose ps prometheus  # Should show "Up"
curl -k https://192.168.168.31/health  # 200 OK expected
curl -k https://192.168.168.42/health  # 200 OK expected

# Verify Prometheus targets
curl -s https://192.168.168.31:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.job | contains("cluster-health"))'
# Expected: Both with state="up"

# Verify alert rules loaded
curl -s https://192.168.168.31:9090/api/v1/rules | \
  jq '.data.groups[].rules[] | select(.name | contains("ClusterHealthCheck"))'
```

**Task 1.2: Post Completion Evidence**
```bash
gh issue comment 1661 --repo kushin77/code-server --body "
## Deployment Verification Complete ✅

- [x] Prometheus containers running on both replicas  
- [x] Health endpoints responding (200 OK)  
- [x] Scrape targets UP (cluster-health-replica-31, cluster-health-replica-42)  
- [x] Alert rules loaded (ClusterHealthCheckFailure, ClusterHealthCheckBothReplicasDown)  
- [x] Alerts routing to Slack configured  

Ready for 24/7 production monitoring.
"
```

---

## PRIORITY: Next High-Priority P1 Tasks After #1661

### P1 #1471: Post-Deployment Team Review & Retrospective
**Status**: OPEN  
**Objective**: Team retrospective after deployment completion  
**Scope**: Capture lessons learned, action items, runbook updates  
**Effort**: Medium (2-3 hours)  
**IaC Compliance**: Documentation only (no code changes)

---

## Alternative High-Priority P1 Tasks (Collaboration Features)

These collaboration EPICs are marked P1 but are feature-driven (not operational):

| Issue | Title | Effort | IaC Needed |
|-------|-------|--------|-----------|
| P1 #1071 | CRDT-based concurrent file editing | 16-20h | Minimal |
| P1 #1082 | Inline Code Comment Threads | 16-20h | Minimal |
| P1 #1093 | AI Conflict Prediction | 16-20h | Yes (LLM integration) |
| P1 #1103 | Rich Presence System | 16-20h | Yes (WebSocket cluster) |
| P1 #1113 | Session Recording & Playback | 16-20h | Yes (Storage, playback service) |
| P1 #1194 | Observability (Tracing, SLOs, health, funnels) | TBD | Yes (Tracing infrastructure) |
| P1 #1204 | Scale & Performance | TBD | Yes (WebSocket gateway, CRDT, delta sync) |
| P1 #1205 | WebSocket gateway cluster | TBD | Yes (3-node relay, hashing) |
| P1 #1206 | CRDT compaction | TBD | Yes (Snapshot + truncate) |
| P1 #1207 | Selective delta sync | TBD | Yes (State vectors) |

---

## RECOMMENDATION FOR IMMEDIATE EXECUTION

**Option 1: Complete P1 #1661 → Move to P1 #1471** (RECOMMENDED)
- ✅ Closes operational blocking task
- ✅ Captures team feedback
- ✅ Quick turnaround (no IaC complexity)
- ⏱️ Total effort: 1-2 hours

**Option 2: Complete P1 #1661 → Start P1 #1205 (WebSocket Gateway)**
- ⚠️ High complexity (infrastructure IaC required)
- ⚠️ Requires design phase first
- ⏱️ Total effort: 20+ hours
- ✅ High business impact (scale & performance)

**Option 3: Complete P1 #1661 → Start P1 #1071 (CRDT)**
- ⚠️ Complex feature (16-20 hours)
- ⚠️ Foundational for collaboration
- ⏱️ Total effort: 20+ hours
- ✅ Enables all future collaboration features

---

## PROPOSED EXECUTION SEQUENCE (IaC Priority)

### Phase 1: Operational Readiness (THIS SPRINT)
1. ✅ P1 #1661 — Health Monitoring (in progress)
2. ⏳ P1 #1471 — Retrospective & Lessons Learned
3. ⏳ P1 #1194 — Observability Infrastructure (tracing, SLOs)

### Phase 2: Infrastructure Scale (NEXT SPRINT)
1. ⏳ P1 #1205 — WebSocket Gateway Cluster (3-node relay)
2. ⏳ P1 #1206 — CRDT Compaction (snapshot + truncate)
3. ⏳ P1 #1207 — Delta Sync (selective state vectors)

### Phase 3: Collaboration Features (AFTER PHASE 2)
1. ⏳ P1 #1071 — CRDT-based Concurrent Editing
2. ⏳ P1 #1082 — Inline Code Comment Threads
3. ⏳ P1 #1093 — AI Conflict Prediction
4. ⏳ P1 #1103 — Rich Presence System
5. ⏳ P1 #1113 — Session Recording & Playback

---

## GOVERNANCE COMPLIANCE MATRIX

All tasks MUST follow these standards:

| Standard | Requirement | Status |
|----------|-------------|--------|
| **IaC** | Configuration versioned in git | ✅ Required |
| **Immutable** | Script-driven deployment (no manual steps) | ✅ Required |
| **Idempotent** | Safe to run multiple times | ✅ Required |
| **Deterministic** | Same config → identical result | ✅ Required |
| **Reversible** | Instant rollback via git | ✅ Required |
| **Linux-Native** | Bash + Docker only | ✅ Required |
| **Metadata Headers** | GOV-002 compliant (@file, @module, @description) | ✅ Required |
| **No Duplication** | Use shared libraries (_common/) | ✅ Required |

---

## IMMEDIATE ACTION ITEMS

### ✅ STEP 1: Verify P1 #1661 Deployment (DO NOW)
```bash
# Run verification checklist documented in P1-1661-DEPLOYMENT-EXECUTION-RECORD.md
# Expected: All 5 verification steps pass within 5 minutes
```

### ✅ STEP 2: Post Evidence to GitHub (DO NOW)
```bash
# Comment on issue #1661 with deployment verification results
# Use unified issue creation script: source scripts/_common/issue-create-unified.sh
```

### ⏳ STEP 3: Choose Next Task (AFTER #1661 COMPLETE)
**Recommended**: P1 #1471 (Retrospective) — 2-3 hours, captures team feedback  
**Alternative**: P1 #1205 (WebSocket Gateway) — 20+ hours, infrastructure scale

### ⏳ STEP 4: Execute Next Task with Full IaC Governance
```bash
# For P1 #1471:
# - Organize team retrospective
# - Document lessons learned
# - Create action items
# - Update runbooks with improvements
# - Create follow-up issues for blockers

# For P1 #1205:
# - Design WebSocket gateway cluster architecture
# - Create IaC configuration (terraform + docker-compose)
# - Implement 3-node relay with consistent hashing
# - Deploy to staging first (non-prod test)
# - Verify with load testing
# - Deploy to production via standard deploy script
```

---

## SUCCESS CRITERIA

**P1 #1661 Complete** when:
- ✅ Prometheus running on both replicas
- ✅ Health endpoints responding
- ✅ Scrape targets UP
- ✅ Alerts configured and routed
- ✅ Evidence posted to GitHub
- ✅ Issue marked complete
- ⏱️ Expected: NOW (containers should be up by now)

**Next Task** (P1 #1471 or P1 #1205) when:
- ✅ All P1 #1661 success criteria met
- ✅ Evidence reviewed
- ✅ Retrospective or architectural planning complete
- ✅ IaC governance checklist passed
- ✅ Deployed to staging/production per standard process

---

**Status**: 🟢 READY FOR IMMEDIATE EXECUTION  
**Next Command**: Proceed with P1 #1661 verification, then execute chosen next P1 task

*Execution Framework: Full IaC/Immutable/Idempotent governance compliance*  
*Governance Verification: GOV-002 compliant scripts, shared library adoption, configuration separation*
