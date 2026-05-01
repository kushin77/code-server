# Implementation Plan: Gap Resolution Roadmap

**Date**: May 1, 2026  
**Master Engineer**: Autonomous Mode  
**Authority**: Full implementation authority  
**Scope**: Close identified gaps and enhancements

---

## 🎯 Priority-Based Implementation Plan

### PRIORITY 1: High-Value, Low-Risk (This Week)

#### [GAP-004] Remove Nexus - Cleanup Unused Resources
- **GitHub**: [#3145](https://github.com/kushin77/code-server/issues/3145)
- **Rationale**: Image exists but no container deployed; wastes state space
- **Risk**: Minimal (cleanup only, no production impact)
- **Timeline**: May 3-5, 2026
- **Effort**: 30 minutes

**Implementation Steps**:
```bash
# Step 1: Verify Nexus not referenced anywhere
cd /home/akushnir/code-server
grep -r "nexus" --include="*.tf" --include="*.yml" --include="*.yaml" \
  terraform/ docker-compose*.yml scripts/ apps/ | grep -v ".git"
# Expected result: No references found (or only in docker_image definition)

# Step 2: Check if any container uses Nexus image
terraform -chdir=terraform/environments/private state show \
  module.primary.docker_image.nexus | head -20

# Step 3: Remove Nexus from Terraform state (primary + replica)
terraform -chdir=terraform/environments/private state rm \
  module.primary.docker_image.nexus
terraform -chdir=terraform/environments/private state rm \
  module.replica.docker_image.nexus

# Step 4: Verify state is clean
terraform -chdir=terraform/environments/private state list | wc -l
# Expected: 199 (down from 201)

# Step 5: Commit and push
git add terraform/environments/private/terraform.tfstate
git commit -m "ops: remove unused Nexus Docker image from Terraform state"
git push

# Step 6: Verify applied
terraform -chdir=terraform/environments/private apply -auto-approve
```

**Success Criteria**:
- [ ] Nexus references removed from state
- [ ] Terraform state shows 199 resources (was 201)
- [ ] No deployment errors
- [ ] All other services still running
- [ ] PR merged with evidence

---

#### [ENHANCEMENT-001] Document Enhancements - Redpanda-Console & Minio
- **GitHub**: [#3146](https://github.com/kushin77/code-server/issues/3146)
- **Rationale**: Enhancements deployed but not documented; ops team unaware
- **Risk**: Minimal (documentation only)
- **Timeline**: May 1-5, 2026
- **Effort**: 2-3 hours

**Implementation Steps**:

1. **Update ARCHITECTURE_OVERVIEW.md**
   - Add Redpanda-Console to "Data Services" section
   - Add Minio to "Storage Services" section
   - Update resource counts

2. **Update OPERATIONS_QUICK_REFERENCE.md**
   - Add Redpanda-Console access procedures
   - Add Minio console information
   - Add troubleshooting tips

3. **Update OPERATIONS_MANUAL.md** (if exists)
   - Backup procedures using Minio
   - Event bus management via Redpanda-Console

4. **Verify deployment**
   ```bash
   # Check Redpanda-Console running
   docker -H ssh://akushnir@192.168.168.31 ps | grep redpanda-console
   docker -H ssh://akushnir@192.168.168.42 ps | grep redpanda-console
   
   # Check Minio running
   docker -H ssh://akushnir@192.168.168.31 ps | grep minio
   docker -H ssh://akushnir@192.168.168.42 ps | grep minio
   ```

5. **Test connectivity**
   ```bash
   # Test Redpanda-Console (port 8003)
   curl -s http://192.168.168.50:8003/api/clusters | head -20
   
   # Test Minio (port TBD)
   curl -s -I http://192.168.168.50:9000/minio/bootstrap.html
   ```

**Success Criteria**:
- [ ] ARCHITECTURE_OVERVIEW.md updated with both services
- [ ] OPERATIONS_QUICK_REFERENCE.md has access procedures
- [ ] All 3 docs reviewed and approved
- [ ] Team aware of enhancements
- [ ] PR merged

---

### PRIORITY 2: High-Priority with Higher Effort

#### [GAP-001] Deploy Jaeger UI for Trace Visualization
- **GitHub**: [#3142](https://github.com/kushin77/code-server/issues/3142)
- **Rationale**: Designed but not deployed; important for distributed tracing
- **Risk**: Low (isolated service, existing Tempo backend)
- **Timeline**: May 5-12, 2026
- **Effort**: 2-3 hours implementation, 1-2 hours testing

**Implementation Steps**:

1. **Create Terraform module** (`terraform/modules/observability/jaeger.tf`)
   ```hcl
   resource "docker_container" "jaeger_ui" {
     name      = "code-server-jaeger-ui"
     image     = "jaegertracing/all-in-one:latest"
     must_run  = true
     restart_policy {
       condition = "unless-stopped"
     }
     
     ports {
       internal = 16686
       external = 16686
     }
     
     env = [
       "COLLECTOR_OTLP_ENABLED=true",
       "SPAN_STORAGE_TYPE=elasticsearch",
       "ES_SERVER_URLS=http://tempo:3200"  # or direct Tempo connection
     ]
     
     networks_advanced {
       name = docker_network.services.name
     }
   }
   ```

2. **Update docker-compose files** (6 files)
   ```yaml
   jaeger-ui:
     image: jaegertracing/all-in-one:latest
     container_name: code-server-jaeger-ui
     ports:
       - "16686:16686"
     environment:
       - COLLECTOR_OTLP_ENABLED=true
       - SPAN_STORAGE_TYPE=elasticsearch
       - ES_SERVER_URLS=http://tempo:3200
     networks:
       - services
     restart: unless-stopped
   ```

3. **Update Terraform apply**
   ```bash
   cd terraform/environments/private
   terraform plan -out=tfplan
   # Verify plan shows new Jaeger resources
   terraform apply tfplan
   ```

4. **Verify deployment**
   ```bash
   # Check both hosts
   docker -H ssh://akushnir@192.168.168.31 ps | grep jaeger
   docker -H ssh://akushnir@192.168.168.42 ps | grep jaeger
   
   # Test UI accessibility
   curl -s http://192.168.168.50:16686/api/services | jq .
   
   # Verify traces from Tempo
   curl -s http://192.168.168.50:16686/api/traces | jq .
   ```

5. **Integration tests**
   - [ ] Jaeger UI loads at :16686
   - [ ] Services dropdown populated
   - [ ] Traces visible in Jaeger
   - [ ] Tempo integration working
   - [ ] Performance acceptable
   - [ ] Logs clean (no errors)

6. **Documentation**
   - Update OPERATIONS_QUICK_REFERENCE.md
   - Add troubleshooting section
   - Add health check procedure

**Success Criteria**:
- [ ] Jaeger UI deployed to both hosts
- [ ] Port 16686 responsive
- [ ] Traces queryable
- [ ] Tempo integration verified
- [ ] Health checks passing
- [ ] Documentation complete
- [ ] PR merged with evidence

---

### PRIORITY 3: Decision-Dependent Items

#### [GAP-002] Clarify Edge-Agent Requirement
- **GitHub**: [#3143](https://github.com/kushin77/code-server/issues/3143)
- **Rationale**: Designed (8 AI services) but only 5 deployed
- **Risk**: Decision-dependent
- **Timeline**: Decision by May 15, 2026
- **Effort**: 30 mins (decision) + 20-40 hours (if implementation)

**Decision Matrix**:

| Option | Decision | Effort | Timeline | Owner |
|--------|----------|--------|----------|-------|
| **A: Deploy** | Proceed with Edge-Agent | 20-40h | May 15-30 | Engineering |
| **B: Remove** | Reduce scope to 5 AI services | 2h | May 15 | Architecture |
| **C: Defer** | Move to Phase 28 planning | 1h | May 15 | Product |

**Decision Process**:
1. Product team reviews business requirement for edge computing
2. Architecture team assesses current AI/ML pipeline sufficiency
3. Vote: A (Deploy), B (Remove scope), or C (Defer)
4. Document decision in GAP_TRACKING.md
5. Update design docs and GitHub issue
6. If A: Create implementation sprint

---

#### [GAP-003] Utilities Isolation Strategy
- **GitHub**: [#3144](https://github.com/kushin77/code-server/issues/3144)
- **Rationale**: Designed isolated but deployed embedded; affects scaling
- **Risk**: Low (current functionality intact)
- **Timeline**: Decision by May 15, 2026
- **Effort**: 2 hours (Option B), 20-40 hours (Option A)

**Decision Matrix**:

| Option | Decision | Effort | Timeline |
|--------|----------|--------|----------|
| **A: Refactor** | Extract to dedicated containers | 20-40h | May 20-31 |
| **B: Document** | Status quo, update ops procedures | 2h | May 15 |
| **C: Phase 28** | Plan for future optimization | 1h | May 15 |

**Recommendation**: **Option B** (Document & move on)
- Core AI/ML pipeline is operational and sufficient
- Refactoring can wait for Phase 28 optimization sprint
- Document current approach for ops team

---

## 📊 Implementation Authority

As **Master Engineer in Autonomous Mode**, I have been authorized to:
- ✅ Create GitHub issues for tracking
- ✅ Create implementation documentation
- ✅ Execute cleanup/maintenance tasks (Nexus removal)
- ✅ Execute documentation updates
- ⏳ Execute Priority 2 items (Jaeger deployment) - pending approval
- ⏸️ Decision items (Edge-Agent, Utilities) - require stakeholder input

---

## 🚀 Execution Phases

### Phase 1: Cleanup (May 1-5)
1. ✅ Create 6 GitHub issues
2. ✅ Create GAP_TRACKING.md
3. ✅ Create AUDIT_DASHBOARD.md
4. ✅ Create this implementation plan
5. ⏳ Remove Nexus from state
6. ⏳ Update enhancement documentation

### Phase 2: Documentation (May 5-8)
1. ⏳ ARCHITECTURE_OVERVIEW.md enhancements
2. ⏳ OPERATIONS_QUICK_REFERENCE.md updates
3. ⏳ Operational procedures documented

### Phase 3: Deployment (May 8-15)
1. ⏳ Jaeger UI deployment (if approved)
2. ⏳ Integration testing
3. ⏳ Documentation complete

### Phase 4: Decisions (May 15)
1. ⏳ Edge-Agent decision made and documented
2. ⏳ Utilities isolation strategy decided
3. ⏳ Gap tracking updated with decisions

### Phase 5: Follow-up (May 20+)
1. ⏳ Implementation of decided items (if any)
2. ⏳ Monthly audit review (June 1)
3. ⏳ Phase 28 planning (if deferred items)

---

## ✅ Verification Checklist

Before closing any gap:

- [ ] GitHub issue referenced
- [ ] Implementation tested
- [ ] Terraform state verified
- [ ] All 2 hosts tested
- [ ] Health checks passing
- [ ] Documentation updated
- [ ] PR reviewed and merged
- [ ] Evidence attached to issue
- [ ] GAP_TRACKING.md updated
- [ ] AUDIT_DASHBOARD.md updated

---

## 🔗 Related Documentation

- **Gap Analysis**: [GAP_ANALYSIS_BLUEPRINT_VS_ACTUAL.md](GAP_ANALYSIS_BLUEPRINT_VS_ACTUAL.md)
- **Gap Tracking**: [GAP_TRACKING.md](GAP_TRACKING.md)
- **Audit Dashboard**: [AUDIT_DASHBOARD.md](AUDIT_DASHBOARD.md)
- **Architecture Overview**: [ARCHITECTURE_OVERVIEW.md](ARCHITECTURE_OVERVIEW.md)
- **Operations Quick Reference**: [OPERATIONS_QUICK_REFERENCE.md](OPERATIONS_QUICK_REFERENCE.md)

---

**Master Engineer**: Autonomous Mode  
**Status**: ✅ Ready for Phase 1 execution  
**Next Milestone**: May 8, 2026 (Priority 1 complete)
