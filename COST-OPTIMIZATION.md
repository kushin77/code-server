# GitHub Actions Cost Optimization - 14 Tactics for 70% Reduction

**Target Reduction**: Current spend → 30% of current (70% reduction)
**Implementation Period**: 30 days
**Owner**: DevOps + Engineering Team
**Priority**: P0

---

## Overview

GitHub Actions costs are driven by:
- **50%**: Compute time (runner minutes)
- **30%**: Artifact storage
- **15%**: Data transfer
- **5%**: Other (API calls, logs)

This guide provides 14 tactics to reduce each category.

---

## COMPUTE OPTIMIZATION (Reduce 40-50%)

### Tactic 1: Reduce Workflow Frequency

**Current State**: Every commit triggers CI/CD
**Target**: Selective triggers

```yaml
# BEFORE
on:
  push:  # Every push runs full CI

# AFTER
on:
  push:
    branches: [main]  # Only main branch
    paths:
      - 'src/**'      # Only source changes
      - '.github/workflows/**'  # And workflow changes
```

**Impact**: -30% of workflow runs
**Effort**: 2 hours (update 30 workflows)
**ROI**: High

---

### Tactic 2: Matrix Parallelization (Smart Parallelism)

**Current State**: Sequential tests (2 hours)
**Target**: Parallel via matrix (30 min)

```yaml
# BEFORE
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: npm test
      - run: npm run integration
      - run: npm run e2e

# AFTER - Runs in parallel
jobs:
  test:
    strategy:
      matrix:
        suite: [unit, integration, e2e]
    steps:
      - run: npm test:${{ matrix.suite }}
```

**Impact**: -70% runner minutes (faster completion)
**Effort**: 3 hours (refactor test automation)
**ROI**: Very High (also improves feedback time)

---

### Tactic 3: Caching Dependencies

**Current State**: Download npm packages every run (2 min)
**Target**: Cache dependencies (10 sec)

```yaml
- uses: actions/cache@v3
  with:
    path: node_modules
    key: node-${{ hashFiles('package-lock.json') }}
```

**Impact**: -90% of npm install time per workflow
**Effort**: 1 hour (add to all workflows)
**ROI**: Very High

---

### Tactic 4: Conditional Job Execution

**Current State**: All jobs run on every push
**Target**: Skip unnecessary jobs

```yaml
jobs:
  build:
    runs-on: ubuntu-latest

  deploy:
    runs-on: ubuntu-latest
    needs: build
    if: github.ref == 'refs/heads/main'  # Only on main
```

**Impact**: -40% of deploy job runs
**Effort**: 2 hours
**ROI**: High

---

### Tactic 5: Container Image Optimization

**Current State**: Build large container images (10 min)
**Target**: Use pre-built images (instant)

```yaml
# BEFORE
- name: Build Docker image
  run: docker build -t myapp .
- name: Push to registry
  run: docker push myapp

# AFTER - Use pre-built base image
container: ubuntu:22.04
```

**Impact**: -80% of Docker build time
**Effort**: 4 hours (create optimized base images)
**ROI**: Very High

---

## ARTIFACT OPTIMIZATION (Reduce 60-70%)

### Tactic 6: Shorter Artifact Retention

**Current State**: 90-day retention (standard GitHub default)
**Target**: 7-day retention (or 30-day for releases)

```yaml
- name: Upload artifacts
  uses: actions/upload-artifact@v3
  with:
    name: build-output
    path: dist/
    retention-days: 7  # Was: default 90
```

**Impact**: -85% of artifact storage
**Effort**: 1 hour (update all upload steps)
**ROI**: Very High

---

### Tactic 7: Compress Artifacts

**Current State**: Raw binaries (50 MB)
**Target**: Compressed archives (10 MB)

```yaml
- name: Compress artifacts
  run: tar -czf build.tar.gz dist/

- name: Upload
  uses: actions/upload-artifact@v3
  with:
    path: build.tar.gz  # Instead of dist/
```

**Impact**: -80% of artifact storage
**Effort**: 2 hours
**ROI**: High

---

### Tactic 8: Conditional Artifact Upload

**Current State**: Upload on every run
**Target**: Upload only on main branch or failures

```yaml
- name: Upload artifacts
  if: |
    failure() ||
    github.ref == 'refs/heads/main'
  uses: actions/upload-artifact@v3
  with:
    path: dist/
```

**Impact**: -70% of artifact uploads
**Effort**: 1 hour
**ROI**: High

---

## DATA TRANSFER OPTIMIZATION (Reduce 50-60%)

### Tactic 9: Region-Specific Runners

**Current State**: GitHub-hosted runners (default region)
**Target**: Region-closest runners

Using `runs-on: ubuntu-latest-arm` for supported actions reduces data transfer by using closer infrastructure.

**Impact**: -20% data transfer
**Effort**: 1 hour (testing)
**ROI**: Medium

---

### Tactic 10: Limit Logs Retention

**Current State**: Keep all logs indefinitely
**Target**: Delete after analysis period

```bash
# In enforce-governance.sh:
gh api repos/$REPO/actions/artifacts --delete \
  --jq '.artifacts[] | select(.expires_at < now) | .id'
```

**Impact**: -40% of log storage/transfer
**Effort**: 2 hours (automation script)
**ROI**: Medium

---

## WORKFLOW OPTIMIZATION (Reduce 30-40%)

### Tactic 11: Remove Redundant Checks

**Current State**: 5 linters running in sequence
**Target**: 1 combined linter

```yaml
# BEFORE - 5 separate jobs
jobs:
  eslint: ...
  prettier: ...
  stylelint: ...
  shellcheck: ...
  yaml-lint: ...

# AFTER - Combined linter
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: eslint . && prettier --check . && stylelint . && shellcheck scripts/* && yamllint config/
```

**Impact**: -60% of lint job runs
**Effort**: 3 hours (consolidate workflows)
**ROI**: High

---

### Tactic 12: On-Demand Workflows Only

**Current State**: Scheduled tasks run every night (waste)
**Target**: Manual trigger + metrics-based

```yaml
on:
  workflow_dispatch:  # Manual only
  # Remove: schedule:
```

For truly needed scheduled tasks:
```yaml
on:
  schedule:
    - cron: '0 2 * * 0'  # Once weekly, not daily
```

**Impact**: -80% of scheduled job runs
**Effort**: 1 hour
**ROI**: Very High

---

### Tactic 13: Fail Fast Strategies

**Current State**: Run all tests even if linting fails
**Target**: Fail immediately on lint/type errors

```yaml
jobs:
  lint:  # FIRST - fail fast
    runs-on: ubuntu-latest
    steps:
      - run: npm run lint
      - run: npm run type-check

  test:  # SECOND - only if lint passes
    needs: lint
    runs-on: ubuntu-latest
    steps:
      - run: npm test
```

**Impact**: -25% of test job runs (wasted effort)
**Effort**: 2 hours
**ROI**: High

---

### Tactic 14: Merge Duplicate Workflows

**Current State**: 40+ workflow files (many similar)
**Target**: 8-10 reusable workflow templates

**Current Duplication**:
- ci.yml, ci-pr.yml, ci-main.yml (3 similar files)
- deploy-staging, deploy-dev, deploy-prod (3 similar)
- test-unit, test-integration, test-e2e (3 similar)
- Total: 40 files with 60% duplication

**Solution - Reusable Workflows**:
```yaml
# workflows/ci.yml (single source)
on:
  workflow_call:
    inputs:
      test-suite:
        required: false
        default: 'all'

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: npm test -- --suite=${{ inputs.test-suite }}

# workflows/ci-main.yml (calls ci.yml)
on: [push]
jobs:
  call-ci:
    uses: ./.github/workflows/ci.yml
    with:
      test-suite: 'main'
```

**Impact**: -30% of workflow runs + easier maintenance
**Effort**: 6 hours (significant refactor)
**ROI**: Very High

---

## QUICK WIN PRIORITIZATION

### Phase 1: Immediate Wins (Days 1-3, 20-30% savings)
1. **Tactic 12**: Remove scheduled tasks (-20% runs, 0.5 hr)
2. **Tactic 3**: Add caching (-10% minutes, 1 hr)
3. **Tactic 6**: Reduce artifact retention (-15% storage, 1 hr)

**Total Effort**: 2.5 hours
**Immediate Impact**: 20-30% cost reduction

### Phase 2: Medium Wins (Days 4-10, additional 20% savings)
4. **Tactic 1**: Selective triggers (-30% runs, 2 hr)
5. **Tactic 8**: Conditional uploads (-20% storage, 1 hr)
6. **Tactic 13**: Fail fast (-10% minutes, 2 hr)

**Total Effort**: 5 hours
**Additional Impact**: 20% more reduction (cumulative ~45%)

### Phase 3: Major Refactors (Days 11-30, additional 25% savings)
7. **Tactic 2**: Parallelization (-50% minutes, 3 hr)
8. **Tactic 5**: Container images (-40% build time, 4 hr)
9. **Tactic 14**: Merge workflows (-30% runs, 6 hr)

**Total Effort**: 13 hours
**Additional Impact**: 25% more reduction (cumulative ~70%)

---

## ROI Breakdown

| Tactic | Effort | Savings | ROI | Priority |
|--------|--------|---------|-----|----------|
| 12: On-demand only | 0.5 hr | 20% | 40x | P0 |
| 3: Caching | 1 hr | 10% | 10x | P0 |
| 6: Retention | 1 hr | 15% | 15x | P0 |
| 1: Triggers | 2 hr | 30% | 15x | P1 |
| 8: Conditional | 1 hr | 20% | 20x | P1 |
| 13: Fail fast | 2 hr | 10% | 5x | P1 |
| 2: Parallelism | 3 hr | 50% | 16x | P1 |
| 5: Containers | 4 hr | 40% | 10x | P1 |
| 14: Merge | 6 hr | 30% | 5x | P2 |
| 4: Conditionals | 2 hr | 40% | 20x | P1 |
| 7: Compress | 2 hr | 80% | 40x | P1 |
| 9: Region | 1 hr | 20% | 20x | P2 |
| 10: Logs | 2 hr | 40% | 20x | P1 |
| 11: Linters | 3 hr | 60% | 20x | P1 |

**Average ROI**: 15x-20x improvement per hour invested

---

## Implementation Checklist

**P1 — Ship now (quick wins)**:
- [ ] Disable unused scheduled workflows
- [ ] Add caching to workflows
- [ ] Reduce artifact retention to 7 days
- [ ] **Estimated savings: 20-30%**

**P2 — Next batch**:
- [ ] Add path triggers to workflows
- [ ] Add conditional artifact uploads
- [ ] Implement fail-fast strategies
- [ ] **Estimated savings: +20%** (total 40-50%)

**P3 — Ongoing**:
- [ ] Refactor test matrix for parallelism
- [ ] Optimize container images
- [ ] Consolidate workflows
- [ ] Monitor, adjust, document

---

## Measuring Success

**Baseline vs. Target**:
| Period | Compute | Storage | Transfer | Total |
|--------|---------|---------|----------|-------|
| Baseline (90 days) | $5,000 | $1,500 | $500 | $7,000 |
| 2 weeks in | $4,200 | $1,200 | $400 | $5,800 |
| 4 weeks in | $2,800 | $800 | $250 | $3,850 |
| Target | $2,500 | $450 | $150 | $3,100 |
| **Savings** | -50% | -70% | -70% | **-56% → target -60%** |

---

## Long-Term Maintenance

**Monthly Review**:
- [ ] Compare actual vs. budget
- [ ] Identify new cost drivers
- [ ] Refine workflows if needed

**Ongoing**:
- [ ] Full cost analysis when needed
- [ ] New optimization tactics
- [ ] Share learnings across teams
- [ ] Adjust quotas

---

## Resources

**Docs**:
- GitHub Actions Pricing: https://github.com/pricing/actions
- Actions Best Practices: https://docs.github.com/en/actions
- Our GOVERNANCE.md: Framework overview

**Tools**:
- `scripts/cost-report.sh` - Generate cost reports
- `scripts/enforce-governance.sh` - Apply policies
- GitHub Billing API - Real-time cost tracking

---

**Status**: Active — implement ASAP, no schedule
**Owner**: DevOps Team + Engineering Representatives
