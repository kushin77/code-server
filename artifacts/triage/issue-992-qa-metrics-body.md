## QA Metrics, Reporting, and CI Gate Integration

### Objective
Implement comprehensive QA metrics collection, reporting dashboard, and CI gates that prevent merges when tests fail.

### Problem Statement
Current state:
- No centralized test metrics
- No visibility into test coverage trends
- No CI gate blocks merges on test failure
- No reporting dashboard for QA status

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    QA Metrics & CI Pipeline                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐     ┌──────────────┐     ┌────────────────┐   │
│  │ Playwright   │────▶│ JUnit XML    │────▶│ GitHub Actions │   │
│  │ Test Runner  │     │ + JSON       │     │ CI Gate        │   │
│  └──────────────┘     └──────────────┘     └────────────────┘   │
│         │                    │                     │             │
│         │                    │                     │             │
│         ▼                    ▼                     ▼             │
│  ┌──────────────┐     ┌──────────────┐     ┌────────────────┐   │
│  │ Test         │     │ Prometheus   │     │ PR Status      │   │
│  │ Artifacts    │     │ Metrics      │     │ Check          │   │
│  │ (video/img)  │     │ (Grafana)    │     │ (Required)     │   │
│  └──────────────┘     └──────────────┘     └────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Implementation

#### 1. Test Reporter Configuration

**Update** `tests/e2e/playwright.config.ts`:

```typescript
import { defineConfig } from '@playwright/test';

export default defineConfig({
  // ... existing config ...
  
  reporter: [
    ['list'],
    ['html', { 
      outputFolder: '../artifacts/playwright-report',
      open: 'never' 
    }],
    ['json', { 
      outputFile: '../artifacts/playwright-results.json' 
    }],
    ['junit', { 
      outputFile: '../artifacts/playwright-junit.xml' 
    }],
    // Custom metrics reporter
    ['./reporters/metrics-reporter.ts', {
      outputFile: '../artifacts/test-metrics.json'
    }]
  ],
  
  // Fail fast on CI
  maxFailures: process.env.CI ? 5 : 0,
});
```

#### 2. Custom Metrics Reporter

**File**: `tests/e2e/reporters/metrics-reporter.ts`

```typescript
import type { Reporter, FullConfig, Suite, TestCase, TestResult, FullResult } from '@playwright/test/reporter';
import * as fs from 'fs';

interface TestMetrics {
  timestamp: string;
  totalTests: number;
  passed: number;
  failed: number;
  skipped: number;
  flaky: number;
  duration: number;
  passRate: number;
  categories: Record<string, {
    total: number;
    passed: number;
    failed: number;
  }>;
}

class MetricsReporter implements Reporter {
  private metrics: TestMetrics;
  private outputFile: string;
  
  constructor(options: { outputFile: string }) {
    this.outputFile = options.outputFile;
    this.metrics = {
      timestamp: new Date().toISOString(),
      totalTests: 0,
      passed: 0,
      failed: 0,
      skipped: 0,
      flaky: 0,
      duration: 0,
      passRate: 0,
      categories: {}
    };
  }

  onTestEnd(test: TestCase, result: TestResult) {
    this.metrics.totalTests++;
    this.metrics.duration += result.duration;
    
    // Track by category (test file)
    const category = test.parent.title || 'uncategorized';
    if (!this.metrics.categories[category]) {
      this.metrics.categories[category] = { total: 0, passed: 0, failed: 0 };
    }
    this.metrics.categories[category].total++;
    
    switch (result.status) {
      case 'passed':
        this.metrics.passed++;
        this.metrics.categories[category].passed++;
        break;
      case 'failed':
        this.metrics.failed++;
        this.metrics.categories[category].failed++;
        break;
      case 'skipped':
        this.metrics.skipped++;
        break;
    }
    
    if (result.retry > 0 && result.status === 'passed') {
      this.metrics.flaky++;
    }
  }

  onEnd(result: FullResult) {
    this.metrics.passRate = this.metrics.totalTests > 0 
      ? (this.metrics.passed / this.metrics.totalTests) * 100 
      : 0;
    
    fs.mkdirSync(require('path').dirname(this.outputFile), { recursive: true });
    fs.writeFileSync(this.outputFile, JSON.stringify(this.metrics, null, 2));
    
    console.log('\n📊 Test Metrics:');
    console.log(`   Total: ${this.metrics.totalTests}`);
    console.log(`   Passed: ${this.metrics.passed}`);
    console.log(`   Failed: ${this.metrics.failed}`);
    console.log(`   Pass Rate: ${this.metrics.passRate.toFixed(1)}%`);
    console.log(`   Duration: ${(this.metrics.duration / 1000).toFixed(1)}s`);
  }
}

export default MetricsReporter;
```

#### 3. GitHub Actions CI Gate

**File**: `.github/workflows/e2e-tests.yml`

```yaml
name: E2E Tests

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  e2e-tests:
    runs-on: [self-hosted, vpn-connected]
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          
      - name: Install dependencies
        run: pnpm install
        
      - name: Fetch QA credentials from GSM
        id: secrets
        run: |
          echo "E2E_USER_EMAIL=$(gcloud secrets versions access latest --secret=qa-user-email)" >> $GITHUB_ENV
          echo "E2E_USER_PASSWORD=$(gcloud secrets versions access latest --secret=qa-user-password)" >> $GITHUB_ENV
          
      - name: Run E2E Tests
        id: e2e
        run: pnpm exec playwright test
        continue-on-error: true
        
      - name: Upload test artifacts
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: playwright-report
          path: |
            tests/artifacts/playwright-report/
            tests/artifacts/playwright-results.json
            tests/artifacts/playwright-junit.xml
            tests/artifacts/test-metrics.json
          retention-days: 30
          
      - name: Publish Test Results
        uses: dorny/test-reporter@v1
        if: always()
        with:
          name: E2E Test Results
          path: tests/artifacts/playwright-junit.xml
          reporter: java-junit
          fail-on-error: true
          
      - name: Comment on PR
        uses: actions/github-script@v7
        if: github.event_name == 'pull_request'
        with:
          script: |
            const fs = require('fs');
            const metrics = JSON.parse(fs.readFileSync('tests/artifacts/test-metrics.json'));
            
            const body = `## 🧪 E2E Test Results
            
            | Metric | Value |
            |--------|-------|
            | Total Tests | ${metrics.totalTests} |
            | ✅ Passed | ${metrics.passed} |
            | ❌ Failed | ${metrics.failed} |
            | ⏭️ Skipped | ${metrics.skipped} |
            | 🔄 Flaky | ${metrics.flaky} |
            | Pass Rate | ${metrics.passRate.toFixed(1)}% |
            | Duration | ${(metrics.duration / 1000).toFixed(1)}s |
            
            ${metrics.failed > 0 ? '⚠️ **This PR has failing tests. Please fix before merging.**' : '✅ **All tests passed!**'}
            `;
            
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body
            });
            
      - name: Fail on test failures
        if: steps.e2e.outcome == 'failure'
        run: exit 1

  # Block merge if tests fail
  e2e-gate:
    runs-on: ubuntu-latest
    needs: e2e-tests
    if: always()
    steps:
      - name: Check test results
        run: |
          if [ "${{ needs.e2e-tests.result }}" != "success" ]; then
            echo "❌ E2E tests failed - blocking merge"
            exit 1
          fi
          echo "✅ E2E tests passed - merge allowed"
```

#### 4. Branch Protection Rule

**GitHub Settings** → **Branches** → **main**:

```yaml
# Required status checks
- "e2e-gate"

# Require branches to be up to date
require_up_to_date: true

# Do not allow bypassing
enforce_admins: true
```

#### 5. Grafana Dashboard

**File**: `config/grafana/dashboards/qa-metrics.json`

```json
{
  "title": "QA Test Metrics",
  "panels": [
    {
      "title": "Test Pass Rate",
      "type": "gauge",
      "targets": [
        {
          "expr": "e2e_test_pass_rate",
          "legendFormat": "Pass Rate"
        }
      ],
      "thresholds": {
        "steps": [
          { "value": 0, "color": "red" },
          { "value": 80, "color": "yellow" },
          { "value": 95, "color": "green" }
        ]
      }
    },
    {
      "title": "Test Execution Trend",
      "type": "timeseries",
      "targets": [
        {
          "expr": "e2e_tests_total",
          "legendFormat": "Total"
        },
        {
          "expr": "e2e_tests_passed",
          "legendFormat": "Passed"
        },
        {
          "expr": "e2e_tests_failed",
          "legendFormat": "Failed"
        }
      ]
    },
    {
      "title": "Test Duration",
      "type": "stat",
      "targets": [
        {
          "expr": "e2e_test_duration_seconds",
          "legendFormat": "Duration"
        }
      ]
    }
  ]
}
```

#### 6. Prometheus Metrics Export

**File**: `scripts/ci/export-test-metrics.sh`

```bash
#!/usr/bin/env bash
# @file        scripts/ci/export-test-metrics.sh
# @module      ci/e2e
# @description Export E2E test metrics to Prometheus pushgateway

set -euo pipefail

METRICS_FILE="${1:-tests/artifacts/test-metrics.json}"
PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-http://pushgateway:9091}"

if [[ ! -f "${METRICS_FILE}" ]]; then
  echo "Metrics file not found: ${METRICS_FILE}"
  exit 1
fi

# Parse metrics
total=$(jq '.totalTests' "${METRICS_FILE}")
passed=$(jq '.passed' "${METRICS_FILE}")
failed=$(jq '.failed' "${METRICS_FILE}")
duration=$(jq '.duration' "${METRICS_FILE}")
passRate=$(jq '.passRate' "${METRICS_FILE}")

# Push to Prometheus
cat <<EOF | curl --data-binary @- "${PUSHGATEWAY_URL}/metrics/job/e2e_tests"
# TYPE e2e_tests_total gauge
e2e_tests_total ${total}
# TYPE e2e_tests_passed gauge
e2e_tests_passed ${passed}
# TYPE e2e_tests_failed gauge
e2e_tests_failed ${failed}
# TYPE e2e_test_duration_seconds gauge
e2e_test_duration_seconds ${duration}
# TYPE e2e_test_pass_rate gauge
e2e_test_pass_rate ${passRate}
EOF

echo "Metrics exported to Prometheus"
```

### Definition of Done

- [ ] Playwright reporters configured (JSON, JUnit, HTML, custom)
- [ ] Custom metrics reporter captures detailed stats
- [ ] CI workflow runs E2E tests on every PR
- [ ] PR comments show test results summary
- [ ] Branch protection requires E2E gate pass
- [ ] Grafana dashboard displays test trends
- [ ] Prometheus metrics exported for alerting
- [ ] Historical test data retained for 30+ days

### Metrics to Track

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `e2e_test_pass_rate` | % of tests passing | < 95% |
| `e2e_tests_failed` | Count of failed tests | > 0 |
| `e2e_test_duration_seconds` | Total test run time | > 300s |
| `e2e_tests_flaky` | Count of flaky tests | > 3 |

Parent: #982
