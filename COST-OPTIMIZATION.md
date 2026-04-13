# GitHub Actions Cost Optimization Guide

**Goal**: Reduce Actions spend by 25-40% within 30 days while maintaining reliability.

---

## Quick Wins (Implement Today)

### 1. Disable Unused Workflows

**Savings**: 15-20% (typical: $75-100/month)

```bash
# Find workflows with zero runs in last 90 days
for repo in $(gh repo list kushin77 --json name -q); do
  gh api repos/$repo/actions/workflows --jq '.workflows[] | 
    select(.state == "active") | 
    {name, total_runs}'
done | grep '"total_runs": 0' | wc -l
```

**Action**: Delete unused workflows, archive in git history.

**Examples**:
- Experimental/POC workflows
- Deprecated CI systems
- Migrated-away builds

---

### 2. Cancel Stale Workflow Runs

**Savings**: 10-15% ($50-75/month)

GitHub Actions continues running failed tests — cancel early.

```yaml
# Add to every test job
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

**Impact**:
```
Before: PR triggers test → Push again → Old test still running (wasted 10 min)
After:  Old test cancelled automatically, new one runs

Savings: ~1 cancelled test per PR = 10 min/PR × 50 PRs = 8 hours/month = ~$10
```

---

### 3. Use Caching Aggressively

**Savings**: 20-30% in build workflows ($100-150/month)

```yaml
- uses: actions/cache@v3
  with:
    path: |
      ~/.npm
      ~/.cargo
      ~/.gradle
    key: ${{ runner.os }}-${{ hashFiles('package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-

- run: npm ci  # Fast with cache hit
```

**Typical gains**:
- npm dependencies: 5→2 min per run
- Java gradle: 8→3 min per run
- Python pip: 4→1 min per run

**Cost**: $5/month (cache storage)  
**Savings**: $50-100/month  
**ROI**: 10:1

---

### 4. Consolidate Matrix Jobs

**Savings**: 15% ($75/month)

```yaml
# ❌ BEFORE: 6 separate workflows, 9 min each = 54 min total
jobs:
  test-ubuntu: { runs-on: ubuntu-latest }
  test-macos: { runs-on: macos-latest }
  test-windows: { runs-on: windows-latest }

# ✅ AFTER: 1 matrix workflow, 3 parallel = 9 min total
jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}
```

**Trade-off**: Set `max-parallel: 3` to avoid hitting concurrent job limits.

---

### 5. Turn Off Debug Logging

**Savings**: 5% ($25/month) + faster runs

```bash
# Remove these secrets if present:
# - ACTIONS_STEP_DEBUG: true
# - ACTIONS_RUNNER_DEBUG: true
```

Debug logging:
- Increases log volume by 10x
- Slows down logging upload
- Stored for 90 days
- No operational benefit in production

---

## Medium-Term Optimizations (Weeks 1-2)

### 6. Parallelize Build Dependencies

**Savings**: 10% ($50/month)

```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps: [checkout, setup-node, lint]

  test:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps: [checkout, setup-node, test]

  security:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps: [checkout, setup-node, security-scan]

  # All in parallel = 15 min (not 30)
```

**Before**: lint → test → security (sequential, 30 min)  
**After**: Parallel (15 min)  
**Savings**: 15 min per run × 100 runs/month = 25 hours = $33/month

---

### 7. Reduce Workflow Frequency

**Savings**: 20% ($100/month)

```yaml
# ❌ BEFORE: On every push
on:
  push:

# ✅ AFTER: Only on PR and main
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
```

**Savings**:
- Dev branches: 50 pushes/month → CI runs = 50 × 10 min = 500 min = $66
- Move to: "only run on PR" = 20 PRs × 10 min = 200 min = $26
- **Savings**: $40/month

---

### 8. Replace Heavy Linters with Lightweight Alternatives

**Savings**: 15-20% ($75-100/month)

```yaml
# ❌ BEFORE: ESLint full project scan (5 min)
- run: npm run lint

# ✅ AFTER: Pre-commit hook + GitHub's super-linter (2 min)
- uses: github/super-linter@v4
  env:
    DEFAULT_BRANCH: main
    VALIDATE_ALL_CODEBASE: false  # Only changed files
```

**Cost comparison**:
```
ESLint: 5 min × 100 runs = 500 min/month = $66
GitHub Super-Linter: 2 min × 100 runs = 200 min/month = $26
Savings: $40/month
```

---

### 9. Batch Scheduled Workflows

**Savings**: 30% of scheduled jobs ($15/month)

```yaml
# ❌ BEFORE: 4 separate schedules
jobs:
  backup:
    on:
      schedule: ['0 2 * * *']  # 2 AM
  metrics:
    on:
      schedule: ['0 3 * * *']  # 3 AM
  cleanup:
    on:
      schedule: ['0 4 * * *']  # 4 AM
  report:
    on:
      schedule: ['0 5 * * *']  # 5 AM

# ✅ AFTER: Single scheduled trigger, conditional jobs
on:
  schedule: ['0 2 * * *']

jobs:
  batch:
    runs-on: ubuntu-latest
    steps:
      - run: ./backup.sh && ./metrics.sh && ./cleanup.sh && ./report.sh
      # All in 1 runner = 10 min (vs 4 × 10 min = 40 min)
```

**Savings**: 30 min/month per scheduled job × 10 jobs = 300 min = $40/month

---

### 10. Use Artifacts Efficiently

**Savings**: 5-10% ($25-50/month)

```yaml
# ❌ BEFORE: Store all artifacts forever
- uses: actions/upload-artifact@v3
  with:
    name: coverage
    path: coverage/

# ✅ AFTER: Only retain recent artifacts
- uses: actions/upload-artifact@v3
  with:
    name: coverage
    path: coverage/
    retention-days: 7  # Auto-delete after 7 days
```

**Impact**:
- Default: 30-day retention
- Recommended: 7 days for CI artifacts, 90 days for builds
- Saves on storage and transfer

---

## Advanced Optimizations (Weeks 2-4)

### 11. Use Smaller Runners for Non-Critical Jobs

**Savings**: 20-30% ($100-150/month)

```yaml
jobs:
  test:
    runs-on: ubuntu-latest        # 2 CPU, $0.008/min
    timeout-minutes: 15

  lint:
    runs-on: ubuntu-latest        # Switch to smaller?
    timeout-minutes: 5            # No, standard is fine

  docs:
    runs-on: ubuntu-latest        # Could use smaller
    timeout-minutes: 3
```

**GitHub Pricing** (per minute):
```
ubuntu-latest:  $0.008/min (2 CPU)
macos-latest:   $0.016/min (4 CPU)
windows-latest: $0.016/min (2 CPU)
```

**Create custom runners** (self-hosted):
- 1 CPU: $0.0038/min (50% savings)
- 4 CPU: $0.0152/min (5% increase, but 2x throughput)

**Decision**: 
- Lint, docs, test → standard ubuntu
- Heavy builds → custom 4-CPU runner

---

### 12. Implement Smart Skipping

**Savings**: 10-20% ($50-100/month)

Only run workflows when files actually change:

```yaml
# Only run tests if code changed
on:
  push:
    paths:
      - 'src/**'
      - 'package.json'
      - '.github/workflows/test.yml'

# Don't run if only docs updated
paths-ignore:
  - 'docs/**'
  - '*.md'
```

---

### 13. Profile and Optimize Hot Paths

**Savings**: 15% ($75/month)

Identify bottlenecks in top 5 workflows:

```bash
# Find slowest workflows
gh api repos/my-org/my-repo/actions/runs \
  -F per_page=100 \
  --jq '.workflow_runs[] | 
    select(.status == "completed") | 
    {name, duration: (.run_number * 10)} |
    sort_by(.duration) | reverse | .[0:5]'
```

**Common bottlenecks**:
1. Node modules installation (fix: use cache)
2. Docker image build (fix: use pre-built images)
3. Large test suites (fix: parallelize or split)
4. Slow OIDC token generation (fix: batch operations)

---

### 14. Replace Secret Token Generation

**Savings**: $10/month

```yaml
# ❌ BEFORE: OIDC token per step = overhead
- uses: aws-actions/configure-aws-credentials@v2
  with:
    role-to-assume: arn:aws:iam::...
    
- run: aws s3 cp ...

# ✅ AFTER: Single token, reuse
jobs:
  deploy:
    permissions:
      id-token: write
    steps:
      - uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: arn:aws:iam::...
          
      - run: aws s3 cp ...
      - run: aws cloudformation deploy ...
      # Reuse same token
```

---

## Monitoring & Ongoing Optimization

### Cost Dashboard

Track weekly:
```bash
# Weekly cost summary
gh api repos/$REPO/actions/runs \
  -F per_page=100 \
  --jq '[.workflow_runs[] | 
    select(.updated_at > (now - 7*24*60*60 | todate)) | 
    .run_time] | 
    reduce .[] as $x (0; . + $x) / 60 as $hours |
    $hours * 0.008 as $cost |
    "\($cost | floor) cost, \($hours | floor) hours"'
```

### Success Metrics

Track monthly improvements:

| Metric | Baseline | Target | Owner |
|--------|----------|--------|-------|
| Monthly cost | $500 | $300 | Finance |
| Avg run time | 20 min | 12 min | DevOps |
| Success rate | 90% | 95% | QA |
| P95 latency | 2 hrs | <1 hr | DevOps |
| Cache hit rate | 40% | 80% | Backend Lead |

---

## Implementation Checkmate

**Week 1 (Quick Wins)**:
- [ ] Disable unused workflows
- [ ] Add concurrency + cancel-in-progress
- [ ] Implement basic caching
- [ ] Turn off debug logging

**Expected savings**: 40% reduction (~$200/month)

**Week 2 (Medium-Term)**:
- [ ] Parallelize jobs
- [ ] Reduce workflow frequency
- [ ] Replace/optimize linters
- [ ] Batch scheduled jobs

**Expected additional savings**: 20% (~$100/month)

**Week 3-4 (Advanced)**:
- [ ] Implement smart skipping
- [ ] Profile hot paths
- [ ] Optimize custom runners
- [ ] Monitor and adjust

**Expected additional savings**: 10% (~$50/month)

---

## Total Expected Outcome

```
Current spend:         $500/month
After Week 1:          $300/month (40% reduction)
After Week 2:          $200/month (60% reduction)
After Week 4:          $150/month (70% reduction)

Annual savings:        $4,200
Payback period:        1-2 weeks (implementation vs savings)
Effort:                2-3 engineer-days
```

---

## FAQs

**Q: Won't all these optimizations make things slower for developers?**  
A: No — parallelization and caching often make builds faster.

**Q: What if my build legitimately takes 1 hour?**  
A: Document it and request quota exemption with business justification. Can be approved.

**Q: Can we run on cheaper infrastructure?**  
A: Yes — self-hosted runners cost 1/2, but require maintenance effort.

**Q: How do we prevent cost creep later?**  
A: Governance framework auto-disables workflows exceeding quotas, with approval gates for overrides.
