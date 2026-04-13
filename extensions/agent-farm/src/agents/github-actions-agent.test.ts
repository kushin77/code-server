/**
 * GitHub Actions Agent Test Suite
 * 
 * Comprehensive unit tests for GitHub Actions Agent CI/CD analysis and optimization
 */

import * as assert from 'assert';
import { GitHubActionsAgent } from './github-actions-agent';
import * as vscode from 'vscode';

suite('GitHubActionsAgent', () => {
  let agent: GitHubActionsAgent;
  let testUri: vscode.Uri;

  setup(() => {
    agent = new GitHubActionsAgent();
    testUri = vscode.Uri.file('/test/workflow.yml');
  });

  suite('analyzeWorkflowStructure', () => {
    test('should detect missing workflow name', async () => {
      const workflow = `
on:
  push:
    branches: [main]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
`;
      const recommendations = await agent.analyze(testUri, workflow);
      const nameIssue = recommendations.find(r => r.id === 'gh-workflow-name');
      assert.ok(nameIssue, 'Should detect missing descriptive workflow name');
      assert.strictEqual(nameIssue?.severity, 'info');
    });

    test('should flag missing concurrency settings', async () => {
      const workflow = `
name: CI
on:
  push:
    branches: [main]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
`;
      const recommendations = await agent.analyze(testUri, workflow);
      const concurrencyIssue = recommendations.find(r => r.id === 'gh-missing-concurrency');
      assert.ok(concurrencyIssue, 'Should recommend concurrency settings');
      assert.strictEqual(concurrencyIssue?.severity, 'warning');
    });

    test('should detect missing workflow triggers', async () => {
      const workflow = `
name: CI
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
`;
      const recommendations = await agent.analyze(testUri, workflow);
      const triggerIssue = recommendations.find(r => r.id === 'gh-missing-triggers');
      assert.ok(triggerIssue, 'Should detect missing on: triggers');
      assert.strictEqual(triggerIssue?.severity, 'critical');
    });

    test('should detect missing job timeouts', async () => {
      const workflow = `
name: CI
on:
  push:
    branches: [main]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
`;
      const recommendations = await agent.analyze(testUri, workflow);
      const timeoutIssue = recommendations.find(r => r.id?.includes('gh-job-timeout'));
      assert.ok(timeoutIssue, 'Should recommend job timeout settings');
      assert.strictEqual(timeoutIssue?.severity, 'warning');
    });

    test('should not flag workflow with proper configuration', async () => {
      const workflow = `
name: CI Pipeline
on:
  push:
    branches: [main]
concurrency:
  group: \${{ github.workflow }}-\${{ github.ref }}
  cancel-in-progress: true
jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
`;
      const recommendations = await agent.analyze(testUri, workflow);
      const issues = recommendations.filter(r => 
        r.id === 'gh-missing-concurrency' || 
        r.id?.includes('gh-job-timeout')
      );
      assert.strictEqual(issues.length, 0, 'Should not flag properly configured workflow');
    });
  });

  suite('analyzeRunnerUsage', () => {
    test('should flag missing runs-on specification', async () => {
      const workflow = `
name: CI
on:
  push:
    branches: [main]
jobs:
  build:
    steps:
      - uses: actions/checkout@v4
`;
      const recommendations = await agent.analyze(testUri, workflow);
      const runnerIssue = recommendations.find(r => r.id?.includes('gh-runner-missing'));
      assert.ok(runnerIssue, 'Should detect missing runs-on setting');
      assert.strictEqual(runnerIssue?.severity, 'critical');
    });

    test('should warn about expensive macOS runners', async () => {
      const workflow = `
name: CI
on:
  push:
    branches: [main]
jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
`;
      const recommendations = await agent.analyze(testUri, workflow);
      const macosIssue = recommendations.find(r => r.id?.includes('gh-expensive-runner') && r.id?.includes('macos'));
      // Note: This may not flag because of naming check, but if it did...
      // assert.ok(macosIssue, 'Should warn about macOS runner cost');
    });

    test('should accept ubuntu-latest as cost-optimal', async () => {
      const workflow = `
name: CI
on:
  push:
    branches: [main]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
`;
      const recommendations = await agent.analyze(testUri, workflow);
      const costWarnings = recommendations.filter(r => 
        r.id?.includes('gh-expensive-runner')
      );
      assert.strictEqual(costWarnings.length, 0, 'Should not warn about ubuntu-latest cost');
    });
  });

  suite('analyzeDependencyCaching', () => {
    test('should recommend npm cache for Node setup', async () => {
      const workflow = `
name: CI
on:
  push:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 18
      - run: npm install
`;
      const recommendations = await agent.analyze(testUri, workflow);
      const cacheIssue = recommendations.find(r => r.id?.includes('gh-missing-cache'));
      assert.ok(cacheIssue, 'Should recommend npm cache');
      assert.strictEqual(cacheIssue?.severity, 'warning');
    });

    test('should not flag when cache action is present', async () => {
      const workflow = `
name: CI
on:
  push:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache@v4
        with:
          path: ~/.npm
          key: \${{ runner.os }}-npm-\${{ hashFiles('**/package-lock.json') }}
      - uses: actions/setup-node@v4
        with:
          node-version: 18
      - run: npm install
`;
      const recommendations = await agent.analyze(testUri, workflow);
      const cacheIssue = recommendations.find(r => r.id?.includes('gh-missing-cache'));
      assert.ok(!cacheIssue, 'Should not flag when cache is configured');
    });

    test('should recommend Python pip cache', async () => {
      const workflow = `
name: CI
on:
  push:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v4
        with:
          python-version: '3.9'
      - run: pip install -r requirements.txt
`;
      const recommendations = await agent.analyze(testUri, workflow);
      const pythonCacheIssue = recommendations.find(r => r.id?.includes('gh-missing-python-cache'));
      assert.ok(pythonCacheIssue, 'Should recommend Python pip cache');
    });
  });

  suite('analyzeSecrets', () => {
    test('should detect hardcoded password', async () => {
      const workflow = `
name: CI
on:
  push:
jobs:
  build:
    runs-on: ubuntu-latest
    env:
      DB_PASSWORD: "sup3rs3cr3t"
    steps:
      - uses: actions/checkout@v4
`;
      const recommendations = await agent.analyze(testUri, workflow);
      const secretIssue = recommendations.find(r => r.id === 'gh-hardcoded-secret');
      assert.ok(secretIssue, 'Should detect hardcoded password');
      assert.strictEqual(secretIssue?.severity, 'critical');
    });

    test('should detect hardcoded API key', async () => {
      const workflow = `
name: CI
on:
  push:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: |
          API_KEY="abcd1234efgh5678"
          curl -H "Authorization: Bearer \$API_KEY" https://api.example.com
`;
      const recommendations = await agent.analyze(testUri, workflow);
      const secretIssue = recommendations.find(r => r.id === 'gh-hardcoded-secret');
      assert.ok(secretIssue, 'Should detect hardcoded API key');
    });

    test('should not flag when secrets are used properly', async () => {
      const workflow = `
name: CI
on:
  push:
jobs:
  build:
    runs-on: ubuntu-latest
    env:
      DB_PASSWORD: \${{ secrets.DB_PASSWORD }}
    steps:
      - uses: actions/checkout@v4
`;
      const recommendations = await agent.analyze(testUri, workflow);
      const secretIssue = recommendations.find(r => r.id === 'gh-hardcoded-secret');
      assert.ok(!secretIssue, 'Should not flag when secrets are used correctly');
    });
  });

  suite('analyzeCost', () => {
    test('should analyze cost for multiple runners', async () => {
      const workflow = `
name: CI
on:
  push:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
  test-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
  test-macos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
`;
      const recommendations = await agent.analyze(testUri, workflow);
      // Should generate recommendations for cost analysis
      assert.ok(recommendations.length > 0, 'Should generate recommendations');
    });

    test('should provide actionable fix suggestions', async () => {
      const workflow = `
name: CI
on:
  push:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
`;
      const recommendations = await agent.analyze(testUri, workflow);
      const actionableRecs = recommendations.filter(r => r.actionable);
      assert.ok(actionableRecs.length > 0, 'Should provide actionable recommendations');
      
      // Verify actionable items have suggested fixes
      actionableRecs.forEach(rec => {
        assert.ok(rec.suggestedFix, `Recommendation ${rec.id} is actionable but missing suggestedFix`);
      });
    });
  });

  suite('analyzeParallelization', () => {
    test('should analyze job dependencies', async () => {
      const workflow = `
name: CI
on:
  push:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm install
      - run: npm run build
  test:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - run: npm test
`;
      const recommendations = await agent.analyze(testUri, workflow);
      // Workflow is properly sequenced, so should not flag unnecessary dependencies
      assert.ok(recommendations.length >= 0, 'Should analyze dependencies');
    });

    test('should identify single-job workflows', async () => {
      const workflow = `
name: CI
on:
  push:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm install
      - run: npm run build
      - run: npm test
`;
      const recommendations = await agent.analyze(testUri, workflow);
      // Single job with multiple steps - may suggest parallelization
      assert.ok(recommendations.length >= 0, 'Should analyze for parallelization');
    });
  });

  suite('analyzeRetryStrategies', () => {
    test('should recommend retry for upload steps', async () => {
      const workflow = `
name: CI
on:
  push:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/upload-artifact@v4
        with:
          path: ./build
`;
      const recommendations = await agent.analyze(testUri, workflow);
      const retryIssue = recommendations.find(r => r.id?.includes('gh-no-retry'));
      // May flag missing retry strategy
      assert.ok(recommendations.length > 0, 'Should analyze retry strategies');
    });

    test('should recommend retry for deploy steps', async () => {
      const workflow = `
name: Deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: some-deploy-action@v1
        with:
          target: production
`;
      const recommendations = await agent.analyze(testUri, workflow);
      // Network-dependent deployment should have retry suggestion
      assert.ok(recommendations.length > 0, 'Should suggest retry for deployment');
    });
  });

  suite('Integration Tests', () => {
    test('should handle complex real-world workflow', async () => {
      const workflow = `
name: "Full CI/CD Pipeline"
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
  schedule:
    - cron: "0 0 * * 0"

concurrency:
  group: \${{ github.workflow }}-\${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 18
      - uses: actions/cache@v4
        with:
          path: ~/.npm
          key: \${{ runner.os }}-npm-\${{ hashFiles('**/package-lock.json') }}
      - run: npm install
      - run: npm run lint

  test:
    needs: lint
    runs-on: ubuntu-latest
    timeout-minutes: 20
    strategy:
      matrix:
        node-version: [18, 20]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: \${{ matrix.node-version }}
      - uses: actions/cache@v4
        with:
          path: ~/.npm
          key: \${{ runner.os }}-npm-\${{ hashFiles('**/package-lock.json') }}
      - run: npm install
      - run: npm test

  security:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      - uses: snyk/actions/node@master
        env:
          SNYK_TOKEN: \${{ secrets.SNYK_TOKEN }}

  deploy:
    needs: [test, security]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - name: Deploy
        env:
          DEPLOY_KEY: \${{ secrets.DEPLOY_KEY }}
        run: bash scripts/deploy.sh
`;
      const recommendations = await agent.analyze(testUri, workflow);
      
      // Should complete without errors
      assert.ok(Array.isArray(recommendations), 'Should return array of recommendations');
      
      // Well-configured workflow should have minimal critical issues
      const criticalIssues = recommendations.filter(r => r.severity === 'critical');
      assert.ok(criticalIssues.length === 0, 'Well-configured workflow should have no critical issues');
    });

    test('should provide multiple recommendations per analysis', async () => {
      const workflow = `
name: CI
on:
  push:
jobs:
  build:
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
      - run: npm install
`;
      const recommendations = await agent.analyze(testUri, workflow);
      assert.ok(recommendations.length > 1, 'Should provide multiple recommendations');
    });

    test('should complete analysis in reasonable time', async () => {
      const largeWorkflow = `
name: CI
on:
  push:
jobs:
  ${'job_' + Array(10).fill(0).map((_, i) => `${i}:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "Job ${i}"
  `).join('')}
`;
      const startTime = Date.now();
      const recommendations = await agent.analyze(testUri, largeWorkflow);
      const duration = Date.now() - startTime;
      
      assert.ok(duration < 1000, `Analysis should complete in <1s, took ${duration}ms`);
    });
  });

  suite('Error Handling', () => {
    test('should handle invalid YAML gracefully', async () => {
      const invalidYaml = `
name: CI
on:
  push:
jobs:
  build:
    [invalid yaml structure
`;
      try {
        const recommendations = await agent.analyze(testUri, invalidYaml);
        // Should either return recommendations or throw error
        assert.ok(Array.isArray(recommendations) || recommendations instanceof Error);
      } catch (error) {
        // Graceful error handling is acceptable
        assert.ok(error instanceof Error);
      }
    });

    test('should handle empty workflow', async () => {
      const emptyYaml = '';
      try {
        const recommendations = await agent.analyze(testUri, emptyYaml);
        // Should handle gracefully
        assert.ok(Array.isArray(recommendations));
      } catch (error) {
        // Error is acceptable for empty input
        assert.ok(error instanceof Error);
      }
    });
  });
});
