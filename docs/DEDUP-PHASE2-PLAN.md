# Deduplication Framework - Phase 2 Implementation Plan

**Issue**: #625  
**Phase**: 2 of 5  
**Status**: READY FOR IMPLEMENTATION  
**Created**: April 17, 2026

---

## Overview

Phase 2 expands Phase 1 governance framework with:
1. Registry validation script (detect incomplete/incorrect documentation)
2. CI integration improvements
3. Real-world testing against codebase
4. Phase 2 → Phase 3 readiness preparation

---

## Deliverables

### 1. Registry Validation Script (`scripts/ci/validate-dedup-registry.sh`)

**Purpose**: Ensure canonical helper registry is complete and patterns match reality

**5 Validation Phases**:

| Phase | Name | Checks |
|---|---|---|
| 1 | Unregistered Helpers | Find function definitions not in registry |
| 2 | Pattern Violations | Detect deviations from documented patterns |
| 3 | Registry Completeness | Ensure all helpers have examples/docs |
| 4 | Policy Structure | Validate JSON schema/syntax |
| 5 | Report Generation | Output metrics and recommendations |

**Output**: `/tmp/dedup-registry-validation.txt` with detailed scoring

**Exit Codes**:
- `0` - All validations passed ✅
- `1` - Violations found ❌

---

### 2. Enhanced CI Workflow

**Workflow**: `.github/workflows/deduplication-guard-phase2.yml` (NEW)

**Jobs**:
1. `dedup-registry-check` - Run validation script on every PR
2. `registry-report` - Post summary to PR comments
3. `registry-metrics` - Upload metrics artifact

**Triggered On**:
- PR changes to `scripts/_common/`, `scripts/lib/`, `docs/DEDUPLICATION-POLICY.md`
- Manual trigger for on-demand validation

---

### 3. Real-World Test Results

**Scope**: Validate against 50+ existing shell scripts

**Test Coverage**:
- ✅ Check for undocumented helpers (Phase 1)
- ✅ Check for pattern deviations (Phase 2)
- ✅ Check for missing documentation (Phase 3)
- ✅ Measure registry completeness score

**Expected Results**: Document findings, update registry accordingly

---

### 4. Registry Gap Analysis Report

**Purpose**: Identify and prioritize updates needed in registry

**Report Includes**:
- Unregistered helper functions (with locations)
- Pattern violations (with examples)
- Documentation gaps (with helpers affected)
- Completeness metrics by category
- Prioritized remediation list

---

## Implementation Steps

### Step 1: Create Registry Validation Script ✅
- [ ] File created: `scripts/ci/validate-dedup-registry.sh`
- [ ] All 5 phases implemented
- [ ] Manual testing successful
- [ ] Bash syntax validated

### Step 2: Create Phase 2 CI Workflow
- [ ] Create `.github/workflows/deduplication-guard-phase2.yml`
- [ ] Integrate validation script
- [ ] Add PR comment reporting
- [ ] Add artifact uploads

### Step 3: Run Against Production Codebase
- [ ] Execute validation on 50+ scripts
- [ ] Collect findings in report
- [ ] Identify patterns to add to registry
- [ ] Prioritize by frequency/importance

### Step 4: Update Registry Based on Findings
- [ ] Add newly discovered helpers to registry
- [ ] Fix underdocumented patterns
- [ ] Update examples for clarity
- [ ] Document any exceptions

### Step 5: Create Phase 2 PR
- [ ] Commit validation script
- [ ] Commit updated registry
- [ ] Create PR with detailed findings
- [ ] Link to gap analysis report

---

## Success Criteria

| Criterion | Target | Status |
|---|---|---|
| Validation script passes manual tests | 100% | ⏳ In progress |
| CI workflow syntax valid | 100% | ⏳ Pending |
| Registry gaps identified | 50+ | ⏳ Pending |
| Gap analysis completeness | 90%+ | ⏳ Pending |
| Registry updated per findings | 95%+ | ⏳ Pending |
| Phase 2 PR created & mergeable | Y/N | ⏳ Pending |

---

## Timeline

| Task | Duration | Sequence |
|---|---|---|
| Create validation script | 1 hour | Step 1 ✅ |
| Create CI workflow | 30 min | Step 2 |
| Run validation tests | 1 hour | Step 3 |
| Update registry | 1 hour | Step 4 |
| Create PR & testing | 30 min | Step 5 |
| **Total** | **4 hours** | Parallel where possible |

---

## Acceptance Criteria (AC)

**AC1**: Validation script exists and runs without errors
- [ ] `scripts/ci/validate-dedup-registry.sh` exists
- [ ] Passes `bash -n` syntax check
- [ ] Executes successfully: `./scripts/ci/validate-dedup-registry.sh`
- [ ] Generates report: `/tmp/dedup-registry-validation.txt`

**AC2**: Validation detects real registry gaps
- [ ] Script identifies ≥5 unregistered patterns
- [ ] Script identifies ≥2 documentation gaps
- [ ] Script generates accurate completeness score

**AC3**: CI workflow integrated
- [ ] Workflow file created: `.github/workflows/deduplication-guard-phase2.yml`
- [ ] Workflow passes GitHub syntax validation
- [ ] Workflow comments on PRs with findings

**AC4**: Real-world validation completed
- [ ] Validation run on 50+ production scripts
- [ ] Report documented in PR body
- [ ] Findings categorized by severity

**AC5**: Registry updated
- [ ] All newly found helpers added to registry
- [ ] Documentation examples added where missing
- [ ] Registry completeness improved to 95%+

**AC6**: Phase 2 PR created
- [ ] PR created linking to #625
- [ ] PR body includes gap analysis
- [ ] All CI checks passing
- [ ] PR is mergeable

---

## Related Issues

- #625 - Deduplication framework (parent)
- #648 - Phase 1 deduplication PR (predecessor)
- #618 - Policy pack (complementary framework)

---

## Notes

- Phase 2 is prerequisite for Phase 3 (IDE hints require validated registry)
- Phase 2 findings will inform Phase 3 IDE integration priorities
- Gap analysis can be reused in Phase 4 (waiver system)

---

**Prepared By**: GitHub Copilot  
**Date**: April 17, 2026  
**Next Phase**: Phase 3 - IDE Hints & Copilot Integration
