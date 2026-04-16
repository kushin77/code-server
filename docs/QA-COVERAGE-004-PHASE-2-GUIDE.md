# QA-COVERAGE-004 Phase 2: Coverage SLO Integration Guide

**Date**: April 15, 2026  
**Status**: Production Ready  
**Owner**: QA & Automation Team  
**Related Issues**: #338 (Phase 2), #316, #318, #325 (Phase 1)

---

## Overview

QA-COVERAGE-004 Phase 2 implements comprehensive test coverage SLO validation and CI/CD integration. Every PR and push must meet coverage thresholds before merge.

**What Changed**: Added automated SLO reporting, trend detection, and GitHub checks to enforce coverage gates.

---

## Architecture

```
Pull Request / Push to main
  ↓
VPN Endpoint Scan (generates coverage report)
  ↓
qa-coverage-gates.yml (triggered by workflow_run)
  ↓
├─ coverage-validation
│  └─ Run SLO reporter
│     └─ Validate metrics
│     └─ Track trends
│     └─ Comment on PR
│
├─ coverage-gates
│  └─ Create GitHub check
│
├─ coverage-trend-tracking
│  └─ Detect regressions
│  └─ Track improvements
│
└─ coverage-notification
   ├─ Slack alert on failure
   └─ Create issue (on main)
```

---

## SLO Targets

| Metric | Target | Purpose | Severity |
|--------|--------|---------|----------|
| Overall Coverage | 95% | Business logic + integration coverage | HIGH |
| Critical Path Coverage | 98% | Auth, core APIs, security-critical | CRITICAL |
| Networking Coverage | 96% | VPN, routing, proxy logic | HIGH |
| Security Coverage | 99% | Auth, crypto, secret handling | CRITICAL |
| Error Handling | 94% | Exception paths, edge cases | MEDIUM |

**Decision Gate**: If ANY metric below target → FAIL and block merge

---

## Implementation Details

### SLO Reporter (`tests/vpn-enterprise-endpoint-scan/slo-reporter.mjs`)

**Purpose**: Validate coverage against SLO targets, track trends, generate reports

**Input**: Coverage report (JSON from test suite)

**Output**:
1. Console report (colored for human readability)
2. `test-results/slo-report.json` (machine-readable)
3. `test-results/github-check.json` (GitHub API format)
4. Updated `coverage-history.json` (trend tracking)

**Key Functions**:

```javascript
validateCoverage(report)        // Check metrics against targets
analyzeTrends(metrics, history) // Detect improvements/regressions
generateReport(...)             // Create comprehensive report
```

**Trend Detection**:
- **Improving**: Coverage +1% or more
- **Declining**: Coverage -0.1% to -2%
- **Regression**: Coverage drops >2% (ALERT)
- **Stable**: Changes <1%

**Exit Codes**:
- `0` = All metrics pass SLOs
- `1` = Violations detected (merge blocked)

### Coverage Gates Workflow (`.github/workflows/qa-coverage-gates.yml`)

**Trigger**: Runs when `vpn-enterprise-endpoint-scan-enhanced.yml` completes

**Jobs**:

1. **coverage-validation**
   - Downloads coverage artifacts
   - Runs SLO reporter
   - Comments on PR with results
   - Exit code determines pass/fail

2. **coverage-gates**
   - Creates GitHub check (required status check)
   - Name: "QA Coverage SLO Gate"
   - Blocks merge if coverage fails

3. **coverage-trend-tracking**
   - Analyzes trends over time
   - Alerts on regressions
   - Tracks improvements

4. **coverage-notification**
   - Sends Slack alert on failure
   - Creates issue on main branch violations
   - Enables rapid incident response

5. **report-publishing**
   - Archives reports to artifacts
   - Publishes summary to GitHub Step Summary
   - 90-day retention for trend analysis

---

## Usage

### For PRs

1. **Create PR** with code changes
2. **VPN endpoint scan runs** automatically
3. **Coverage gates validates** results
4. **GitHub check blocks merge** if SLO failed
5. **Comment on PR** shows metrics + recommendations
6. **Fix code** and push (re-runs automatically)
7. **Merge** when all checks pass

### Viewing Results

**On GitHub**:
```
PR → Checks → QA Coverage SLO Gate → Details
```

**In PR Comment**: Scroll down to see coverage metrics table

**Locally**:
```bash
# Download artifacts
gh run download <RUN_ID> -n slo-report

# View report
cat test-results/slo-report.json | jq '.'
```

---

## Local Testing

### Run SLO Validation Locally

```bash
# 1. Generate coverage report (if not exists)
npm run test:coverage

# 2. Run SLO reporter
node tests/vpn-enterprise-endpoint-scan/slo-reporter.mjs coverage/coverage-final.json

# 3. View results
cat test-results/slo-report.json | jq '.summary'
```

### Expected Output

```
✅ PASS - All metrics above targets
or
❌ FAIL - security: 94% (target: 99%)
```

---

## Remediation Paths

### Scenario 1: Critical Path Coverage Below Target

**Symptom**: GitHub check fails, comment shows "critical: 95% (target: 98%)"

**Root Cause**: 
- New code without tests
- Deleted tests
- Test infrastructure issue

**Fix**:
```bash
# 1. Identify untested code
npm run test:coverage -- --reporter=lcov
open coverage/lcov-report/index.html  # View coverage map

# 2. Add tests for gaps
# Edit test file (tests/integration/*.test.js)
# Add test cases for untested paths

# 3. Verify locally
node tests/vpn-enterprise-endpoint-scan/slo-reporter.mjs coverage/coverage-final.json

# 4. Push and re-run
git push origin my-branch
# GitHub Actions re-runs automatically
```

### Scenario 2: Regression Detected

**Symptom**: 
- Comment shows "Regressions: security: -3.5%"
- GitHub check fails

**Root Cause**: 
- Test deletion or modification
- Significant code refactor without test updates

**Fix**:
```bash
# 1. Review recent commits
git log --oneline -10 -- tests/

# 2. Check what changed
git diff HEAD~5 -- coverage/

# 3. Restore tests or add new ones
git checkout HEAD~1 -- tests/security.test.js  # If accidentally deleted
# OR
# Add new tests for refactored code

# 4. Verify improvement
npm run test:coverage
node tests/vpn-enterprise-endpoint-scan/slo-reporter.mjs coverage/coverage-final.json

# 5. Push
git push origin my-branch
```

### Scenario 3: Trend Analysis Shows Consistent Decline

**Symptom**: Last 3 PRs all show declining coverage trend

**Root Cause**:
- Team focusing on features over tests
- Test cleanup without parallel additions
- Coverage thresholds too high for current team velocity

**Fix**:
```bash
# Option A: Immediate fix (recommended)
1. Create issue: "Coverage Trend Declining"
2. Assign owner to increase coverage back
3. Add tests for new code

# Option B: Adjust thresholds (if justified)
1. Review SLO_TARGETS in slo-reporter.mjs
2. Document why thresholds are being reduced
3. Get team + security approval
4. Update file + commit

# Option C: Both
1. Add tests to restore coverage
2. Discuss realistic thresholds in retro
```

---

## Troubleshooting

### "No coverage report available"

**Problem**: Workflow says coverage report missing

**Solution**:
```bash
# Check if VPN scan generated report
ls -la test-results/vpn-endpoint-scan/

# If missing, re-run VPN endpoint scan
gh workflow run vpn-enterprise-endpoint-scan-enhanced.yml

# Wait for completion
gh run watch
```

### "SLO Reporter not found"

**Problem**: `slo-reporter.mjs` missing or wrong path

**Solution**:
```bash
# Verify file exists
ls -la tests/vpn-enterprise-endpoint-scan/slo-reporter.mjs

# If missing, create it from template
cp tests/vpn-enterprise-endpoint-scan/slo-reporter.mjs.template \
   tests/vpn-enterprise-endpoint-scan/slo-reporter.mjs
```

### "GitHub check stuck as pending"

**Problem**: Check not updating after re-run

**Solution**:
```bash
# Force re-run of coverage gates workflow
gh workflow run qa-coverage-gates.yml \
  --ref main \
  -f pr_number=<YOUR_PR_NUMBER>

# Monitor
gh run watch
```

---

## Monitoring & Alerts

### GitHub Checks (Automatic)

- **Status Check**: "QA Coverage SLO Gate" (required for merge)
- **Block Merge**: Fails if any metric below target
- **Comment**: Details + recommendations

### Slack Alerts (Optional)

```
🚨 Coverage SLO Failed
- Repository: kushin77/code-server
- Violation: security coverage below 99%
- Fix: See GitHub check for details
```

### Metrics Export (Prometheus)

Coverage metrics also exported to monitoring stack:
```
coverage_overall_percent{job="qa"} 96.3
coverage_critical_percent{job="qa"} 97.8
coverage_violations_total{job="qa"} 1
```

View in Grafana: Dashboard → QA Coverage → Trends

---

## Integration with Other Workflows

### Dependency Order

```
1. Unit/Integration Tests (must pass first)
   ↓
2. VPN Endpoint Scan (generates coverage)
   ↓
3. Coverage Gates (validates SLOs)  ← BLOCKS MERGE
   ↓
4. Security Scanning (SAST/DAST)
   ↓
5. Deploy (only if all gates pass)
```

### Required Checks for Merge

Before merging to main:
- ✅ All tests passing
- ✅ Coverage SLO Gate passing  ← Coverage must be good
- ✅ Security gates passing
- ✅ Code review approval

---

## Performance & Reliability

### Execution Time

| Step | Duration | Notes |
|------|----------|-------|
| Download artifacts | 15s | From GitHub Actions |
| Run SLO reporter | 2s | Node.js, no external calls |
| Generate PR comment | 5s | GitHub API |
| Create GitHub check | 3s | Quick API call |
| **Total** | ~30s | Quick feedback loop |

### Reliability

- **Retry Logic**: SLO reporter has no external dependencies (no retries needed)
- **Failure Tolerance**: If GitHub check fails, PR won't merge (correct behavior)
- **Data Retention**: Coverage history kept for 90 days (30-day trend window)

---

## Compliance & Audit Trail

### What's Recorded

- Coverage metrics at each commit
- Trend analysis over 30 days
- Violations and recommendations
- GitHub check status (immutable in GitHub)
- SLO reporter output (archived 90 days)

### For Audit Reviews

All reports available via:
```bash
# List all coverage reports
gh run list --workflow=qa-coverage-gates.yml --limit=100

# Download specific run
gh run download <RUN_ID> -n slo-report
```

---

## Future Enhancements

**Phase 3 Planned** (not yet implemented):
- [ ] Custom SLO targets per team/module
- [ ] Coverage target escalation rules (0% → 50% → 95%)
- [ ] A/B testing framework for experiments
- [ ] Integration with git blame to identify accountability
- [ ] Coverage trend predictions (ML)

---

## References

- [SLO Reporter Source](tests/vpn-enterprise-endpoint-scan/slo-reporter.mjs)
- [Coverage Gates Workflow](.github/workflows/qa-coverage-gates.yml)
- [VPN Endpoint Scan](.github/workflows/vpn-enterprise-endpoint-scan-enhanced.yml)
- Issue #338: QA-COVERAGE-004-PHASE-2

---

**Version**: 1.0  
**Last Updated**: April 15, 2026  
**Status**: Production Ready
