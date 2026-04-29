# Phase 5: Extended Script Consolidation Plan

**Timeline**: Week 2-4 (Optional Enhancement Phase)  
**Priority**: Medium (Foundation complete, this phase adds polish)  
**Status**: Ready to Begin

---

## Phase 5 Overview

Phase 5 focuses on consolidating remaining script categories beyond the core 4 (ops, ci, _common, k8s). This is an enhancement phase that adds consistency and leverages the consolidated logging infrastructure established in Phases 1-4.

---

## Phase 5a: Specialized Script Categories (Week 1)

### 5a.1: Phase 5 Deployment Scripts (4 scripts)

**Scripts**: 
- performance-baseline.sh
- provision-edge-agents.sh
- setup-database-sharding.sh
- setup-global-load-balancing.sh

**Current State**: 
- All source init.sh ✅
- All define local logging functions ✅
- All use tee for dual output (console + log file)

**Consolidation Strategy**:
1. Remove local log_info(), log_success(), log_error() definitions
2. Keep log file output by using `tee` with init.sh logging
3. Maintain dual output pattern for consistency

**Example Transformation**:
```bash
# Before:
log_info() {
  echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

# After: Remove local definition, init.sh provides log_info
# Wrapper around init.sh to add log file:
log_info_tee() {
  log_info "$@" | tee -a "$LOG_FILE"
}
# Or just use: log_info "$@" | tee -a "$LOG_FILE"
```

**Effort**: ~30 minutes (4 scripts × 5-7 min each)  
**Risk**: Low (backward compatible, init.sh provides functions)  
**Validation**: Syntax check + dry-run execution

---

### 5a.2: Other Deployment Scripts (5+ scripts)

**Location**: scripts/deployment/  
**Scripts to Review**: deploy-final.sh, deploy-p3-services.sh, etc.

**Tasks**:
1. Check which source init.sh
2. Check which define local logging
3. Consolidate logging functions
4. Validate syntax

**Effort**: ~45 minutes  
**Status**: Ready to begin

---

### 5a.3: Maintenance & Operations (8 scripts)

**Location**: scripts/operations/, scripts/maintenance/  

**Tasks**:
1. Audit for local logging definitions
2. Update to use consolidated logging
3. Validate syntax and runtime

**Effort**: ~1 hour  
**Status**: Ready to begin

---

## Phase 5b: Testing & Utilities (Week 2)

### 5b.1: Chaos Engineering Scripts (5 scripts)

**Location**: scripts/chaos/  

**Approach**:
- Audit for consolidated logging usage
- Add assertions for test validation
- Enhance with structured output

**Effort**: ~1.5 hours  

---

### 5b.2: Integration Testing (4 scripts)

**Location**: scripts/integration/  

**Approach**:
- Consolidate logging
- Add test assertions
- Create integration test report framework

**Effort**: ~1 hour  

---

### 5b.3: High-Availability Scripts (3 scripts)

**Location**: scripts/ha/  

**Approach**:
- Consolidate logging
- Add health assertions
- Enhance validation reporting

**Effort**: ~45 minutes  

---

## Phase 5c: Remaining Categories (Week 3+)

### Low-Priority Categories
- scripts/governance/ (2 scripts)
- scripts/monitoring/ (3 scripts)
- scripts/perf/ (3 scripts)
- scripts/security/ (2 scripts)
- scripts/ide/ (3 scripts)
- scripts/extensions/ (9 scripts)
- scripts/observability/ (6 scripts)
- scripts/edge-agent/ (2 scripts)

**Combined Effort**: ~3-4 hours  
**Approach**: Batch consolidation using migration tool  

---

## Implementation Strategy

### Step 1: Quick Assessment (30 min)
For each script category:
1. Count total scripts
2. Check for local logging functions
3. Check for init.sh sourcing
4. Identify consolidation blockers

### Step 2: Systematic Consolidation (2-3 hours)
For high-priority categories:
1. Remove local logging definitions
2. Verify init.sh sourcing present
3. Syntax check with `bash -n`
4. Runtime test with sample execution

### Step 3: Validation (1 hour)
1. Full deployment test (dry-run)
2. Spot check key scripts
3. Document any issues

### Step 4: Documentation (30 min)
1. Update consolidation status
2. Create Phase 5 completion report
3. Identify any remaining work

---

## Success Criteria

### Phase 5a Success
✅ 4 Phase 5 deployment scripts consolidated  
✅ 5+ deployment scripts consolidated  
✅ 8 maintenance/operations scripts consolidated  
✅ All syntax validated (bash -n passes)  
✅ All functionality preserved (backward compatible)  

### Phase 5b Success
✅ 5 chaos engineering scripts consolidated  
✅ 4 integration test scripts consolidated  
✅ 3 HA scripts consolidated  
✅ No regressions in test output  

### Phase 5c Success
✅ 40+ remaining scripts consolidated  
✅ Consolidation coverage: 200+/205 scripts (97%)  
✅ Codebase-wide unified logging infrastructure  

---

## Expected Outcomes

### After Phase 5 Complete
- **Consolidation Coverage**: 97%+ of bash scripts
- **Unified Infrastructure**: Single source of truth for logging
- **Enhanced Diagnostics**: Consistent assertions and test reporting
- **Maintenance Burden**: Minimal (centralized functions)
- **Code Quality**: Significantly improved

### Statistics
| Metric | Before Phase 5 | After Phase 5 |
|--------|----------------|---------------|
| Scripts consolidated | 133 | 200+ |
| Local logging definitions | 130+ locations | 5-10 locations |
| Maintenance surface | 130+ locations | Centralized |
| Test assertion support | 0 | All scripts |
| Consolidation coverage | 65% | 97%+ |

---

## Timeline & Next Steps

**Week 1** (Phase 5a):
- [ ] Phase 5 deployment scripts (4) - ~30 min
- [ ] Other deployment scripts (5+) - ~45 min
- [ ] Operations/maintenance (8) - ~1 hour
- **Subtotal**: ~2.25 hours

**Week 2** (Phase 5b):
- [ ] Chaos engineering (5) - ~1.5 hours
- [ ] Integration testing (4) - ~1 hour
- [ ] High-availability (3) - ~45 min
- **Subtotal**: ~3.25 hours

**Week 3** (Phase 5c):
- [ ] Low-priority categories (40+) - ~3-4 hours
- [ ] Final validation and testing - ~1 hour
- [ ] Documentation and completion - ~1 hour
- **Subtotal**: ~5-6 hours

**Total Phase 5 Effort**: ~10-12 hours (spread over 3 weeks, ~3-4 hours/week)

---

## Risk Assessment

| Risk | Level | Mitigation |
|------|-------|-----------|
| Unintended script breakage | Low | Syntax validation + dry-run |
| Loss of logging output | Low | test.sh provides all functions |
| Performance regression | Minimal | No new overhead |
| Integration conflicts | Low | Color constants already resolved |

---

## Notes

- Phase 5 is optional but recommended for code consistency
- Foundation work (Phases 1-4) is complete and production-ready
- Phase 5 provides polish and enhances code quality
- Can be done incrementally without blocking production deployment

