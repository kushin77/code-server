# Deduplication-as-Policy Framework - Phase 2 Implementation Plan

**Status**: Design & Specification (Awaiting Phase 1 PR Merge)  
**Target Issue**: #625  
**Timeline**: 2-3 weeks post Phase 1 merge  
**Owner**: @kushin77

---

## Executive Summary

Phase 1 established the canonical helper registry, detection scripts, and IDE hints. Phase 2 integrates these into the CI pipeline, validates the registry, and enforces deduplication as a quality gate.

**Phase 2 Scope**:
- ✅ Integrate detection into CI/CD workflow
- ✅ Create registry validation script
- ✅ Implement dedup scoring in PR checks
- ✅ Design waiver request/approval process
- ✅ Build metrics dashboard

---

## Detailed Phase 2 Deliverables

### 1. CI/CD Integration

#### 1.1 Detection Gate Integration

**File**: `.github/workflows/ci-deduplication-enforcement.yml`

**Purpose**: Run duplicate detection on every PR with script/compose/config changes

**Trigger**: 
```yaml
on:
  pull_request:
    paths:
      - 'scripts/**'
      - 'docker-compose*.yml'
      - 'scripts/_common/**'
      - '!**.md'  # Skip docs-only changes
```

**Jobs**:
1. **detect-duplicates** (runs scripts/ci/detect-duplicate-helpers.sh)
   - Outputs: Summary comment on PR
   - Decision: Pass/Warn/Block based on confidence level
   
2. **dedup-score** (runs scripts/ci/dedup-score-report.sh)
   - Outputs: Dedup score (0-100 scale)
   - Decision: Block if score < 60 (unless waivered)
   - Outputs: Scores to `/tmp/dedup-score.txt` for metrics

#### 1.2 PR Comment Format

**Template** (comment on each PR with changes):

```
## Deduplication Analysis

### Summary
- Detected Duplicates: N (HIGH: M, MEDIUM: K, LOW: J)
- Dedup Score: X/100
- Recommendation: [PASS | WARN | BLOCK]

### High-Confidence Issues
[List of HIGH confidence duplicates with line references]

### Medium-Confidence Issues
[List of MEDIUM confidence duplicates]

### How to Fix
1. Refactor into canonical helper from registry
2. Link to docs/DEDUPLICATION-POLICY.md#helpers
3. Re-run tests to verify

### Waiver Process
[Link to waiver process if applicable]
```

### 2. Registry Validation Script

**File**: `scripts/ci/validate-dedup-registry.sh`

**Purpose**: Ensure canonical registry is complete and helpers are actually available

**Validations**:
1. All helpers listed in registry actually exist
2. Helper canonical names don't conflict
3. Helper versions/tags are consistent
4. Dependencies between helpers are valid
5. Registry documentation is complete

**Output**: 
```bash
REGISTRY_STATUS=VALID|INVALID
REGISTRY_HELPERS_COUNT=N
REGISTRY_COVERAGE=X%
```

**Execution**: Runs as part of `validate` CI job before dedup detection

### 3. Waiver Request & Approval Process

#### 3.1 Waiver Issue Template

**Issue Title**: `waiver(dedup): [reason] for PR #N`

**Body Template**:
```markdown
## Waiver Request

**Related PR**: #N
**Duplicate Pattern**: [describe the duplicate]
**Reason**: [business justification]
**Proposed Refactor Timeline**: [future date if deferring]

## Acceptance Criteria
- [ ] Duplicate validated with reproducible steps
- [ ] Refactor complexity assessment completed
- [ ] Timeline documented (if deferring)
- [ ] Architecture review approved
- [ ] On-call engineer acknowledged

## Approval
- [ ] Architecture Owner (@kushnir)
- [ ] On-Call Reliability Engineer (@akushnir)
```

#### 3.2 Waiver Approval

**Workflow**: `Waiver issues → +1 from owner → Apply dedup-score override for PR`

**Override Mechanism**:
- Label: `dedup-waivered` on PR
- Score file override: `echo "DEDUP_WAIVERED=true" >> /tmp/dedup-score.txt`
- CI Result: ✅ PASS (with reason in logs)

### 4. Metrics Dashboard

#### 4.1 Metrics Collection

**Data Points** (collected per PR):
```
DEDUP_SCORE=X
DEDUP_LEVEL=[CRITICAL|HIGH|MEDIUM|LOW]
DUPLICATES_FOUND=N
HELPERS_REUSED=M
WAIVER_ISSUED=[true|false]
REFACTOR_COMPLEXITY=[simple|moderate|complex]
```

**Storage**: 
- GitHub Actions: `/tmp/dedup-score.txt`
- GitHub Issues: Metrics summary comment  
- Future: Time-series database (InfluxDB/Prometheus)

#### 4.2 Monthly Report

**File**: `docs/governance-reports/DEDUP-MONTHLY-REPORT-YYYY-MM.md`

**Contents**:
- Average dedup score (target: 80+)
- Most common duplicates (top 5)
- Waivers issued (with justifications)
- Refactor backlog (candidates for Phase 3-4)
- Trend analysis (improving/degrading)

**Example**:
```markdown
# April 2026 Deduplication Report

## Summary
- Average Dedup Score: 82/100 ✅
- PRs Reviewed: 47
- Waivers Issued: 3
- Refactors Completed: 12

## Top Duplicates Detected
1. Port validation patterns (7 occurrences)
2. Config loading patterns (5 occurrences)
3. Error logging patterns (4 occurrences)

## Waivers
- #625: Docker compose services pattern (deferred to Phase 3)
- #630: Legacy RBAC integration (business justified)
- #635: Emergency hotfix (time-sensitive)
```

---

## Implementation Sequence

### Week 1: CI Integration & Registry Validation
- [ ] Create `.github/workflows/ci-deduplication-enforcement.yml`
- [ ] Create `scripts/ci/validate-dedup-registry.sh`
- [ ] Test on 3-5 sample PRs
- [ ] Document detection output format

### Week 2: Waiver System & Process
- [ ] Create waiver issue template
- [ ] Document approval workflow
- [ ] Implement waiver override in CI
- [ ] Create test cases for waiver process

### Week 3: Metrics & Reporting
- [ ] Create metrics collection in CI workflow
- [ ] Create monthly report template
- [ ] First report: Baseline metrics from Week 1-2
- [ ] Deploy to docs/governance-reports/

### Week 4: Integration & Hardening
- [ ] Full end-to-end test (new PR through waiver process)
- [ ] Performance testing (CI job runtime)
- [ ] Documentation updates
- [ ] Team training & rollout

---

## Technical Details

### Detection Confidence Levels

**HIGH Confidence** (Block merge without waiver):
- Identical function names/signatures across scripts
- Identical error handling patterns (identical if/while blocks)
- Identical logging calls with same parameters
- Identical config loading patterns

**MEDIUM Confidence** (Warn in PR):
- Similar function logic (>90% code similarity)
- Similar error patterns (different variables)
- Similar logging patterns (different messages)
- Similar config patterns (different keys)

**LOW Confidence** (Info only):
- Similar structure but different implementation
- Related patterns but independent purpose
- Edge cases or special scenarios

### Detection Algorithm (per check)

**Pattern Detection**:
```bash
for pattern in "${PATTERNS[@]}"; do
  matches=$(grep -r "$pattern" scripts/ | wc -l)
  if [[ $matches -gt 1 ]]; then
    confidence=$(calculate_similarity "$pattern")
    output_finding "$pattern" "$matches" "$confidence"
  fi
done
```

**Scoring Formula**:
```
score = 100 - (HIGH_count × 15 + MEDIUM_count × 5 + LOW_count × 1)
score = max(0, min(100, score))
```

---

## Integration with Phase 3-5

### Phase 3: Compliance Reporting
- Build analytics dashboard (Grafana/Prometheus)
- Create real-time dedup compliance view
- Automate monthly reports

### Phase 4: Enforcement & Automation
- Auto-suggest refactoring via Copilot
- Integrate waiver tracking into OKR metrics
- Create team scorecard (per-author dedup compliance)

### Phase 5: Governance Maturity
- Link dedup metrics to code quality metrics
- Create automated refactoring recommendations
- Build predictive analysis (future duplicates)
- Establish SLO for dedup score maintenance

---

## Success Criteria

**Phase 2 Completion Definition**:
- [ ] CI workflow integrated and tested on 10+ PRs
- [ ] Registry validation running without errors
- [ ] Waiver process executed at least once (end-to-end)
- [ ] First monthly report published
- [ ] Team trained on waiver request process
- [ ] Documentation complete and reviewed
- [ ] Zero false-positive blocks on PRs

**Quality Gates**:
- [ ] CI job runtime < 2 minutes
- [ ] False positive rate < 5%
- [ ] Waiver approval time < 4 hours
- [ ] Detection accuracy > 95% (vs manual review)

---

## Known Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| CI job timeout | Blocks all PRs | Set generous timeout, add early exit optimization |
| False positives | Team frustration | Calibrate confidence levels, add LOW tier for info-only |
| Waiver abuse | Defeats purpose | Require justification + architecture review |
| Performance degradation | Slower CI | Cache results, parallelize detection jobs |
| Outdated registry | Detection misses | Automate registry validation in Phase 2 |

---

## Testing Strategy

### Unit Tests (CI/CD scripts)
- Test detection on known duplicate patterns
- Test scoring calculation with various inputs
- Test waiver override logic

### Integration Tests
- Full PR workflow with duplicates
- Full PR workflow with waivers
- Registry validation on current state
- Metrics collection and reporting

### UAT (Team)
- Real PR with actual duplicates (team reviews)
- Waiver request through full workflow
- Monthly report generation and review

---

## Handoff Criteria (Phase 3 Ready)

Phase 2 is complete when:
1. ✅ CI enforcement working on main branch
2. ✅ At least 50 PRs processed through new workflow
3. ✅ Monthly metrics stable and understood
4. ✅ Waiver process executed at least 2 times
5. ✅ Team trained and comfortable with process
6. ✅ All known bugs fixed and tested

---

**Next Session**: Implement Phase 2 upon PR #648 merge
