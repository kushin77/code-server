/**
 * GitHub Actions Agent Test Suite - Jest Format
 */

import { GitHubActionsAgent } from './github-actions-agent';
import * as vscode from 'vscode';

describe('GitHubActionsAgent', () => {
  let agent: GitHubActionsAgent;
  let testUri: vscode.Uri;

  beforeEach(() => {
    agent = new GitHubActionsAgent();
    testUri = vscode.Uri.file('/test/workflow.yml');
  });

  describe('Workflow Structure Analysis', () => {
    it('should detect missing workflow name', async () => {
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
      expect(nameIssue).toBeDefined();
      expect(nameIssue?.severity).toBe('info');
    });

    it('should flag missing concurrency settings', async () => {
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
      expect(concurrencyIssue).toBeDefined();
      expect(concurrencyIssue?.severity).toBe('warning');
      expect(concurrencyIssue?.actionable).toBe(true);
    });

    it('should detect missing workflow triggers', async () => {
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
      expect(triggerIssue).toBeDefined();
      expect(triggerIssue?.severity).toBe('critical');
    });

    it('should detect missing job timeouts', async () => {
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
      expect(timeoutIssue).toBeDefined();
      expect(timeoutIssue?.severity).toBe('warning');
    });

    it('should not flag well-configured workflow', async () => {
      const workflow = `
name: CI Pipeline
on:
  push:
    branches: [main]
concurrency:
  group: workflow
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
      expect(issues.length).toBe(0);
    });
  });

  describe('Runner Analysis', () => {
    it('should flag missing runs-on specification', async () => {
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
      expect(runnerIssue).toBeDefined();
      expect(runnerIssue?.severity).toBe('critical');
    });

    it('should accept ubuntu-latest as cost-optimal', async () => {
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
      expect(costWarnings.length).toBe(0);
    });
  });

  describe('Caching Analysis', () => {
    it('should recommend npm cache for Node setup', async () => {
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
      expect(cacheIssue).toBeDefined();
      expect(cacheIssue?.severity).toBe('warning');
    });

    it('should not flag when cache action is present', async () => {
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
          key: npm-cache
      - uses: actions/setup-node@v4
        with:
          node-version: 18
      - run: npm install
`;
      const recommendations = await agent.analyze(testUri, workflow);
      const cacheIssue = recommendations.find(r => r.id?.includes('gh-missing-cache'));
      expect(cacheIssue).toBeUndefined();
    });

    it('should recommend Python pip cache', async () => {
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
      expect(pythonCacheIssue).toBeDefined();
    });
  });

  describe('Secrets Management', () => {
    it('should detect hardcoded password', async () => {
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
      expect(secretIssue).toBeDefined();
      expect(secretIssue?.severity).toBe('critical');
    });

    it('should detect hardcoded API key', async () => {
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
      expect(secretIssue).toBeDefined();
    });

    it('should not flag when secrets are used properly', async () => {
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
      expect(secretIssue).toBeUndefined();
    });
  });

  describe('Recommendations Quality', () => {
    it('should provide multiple recommendations per analysis', async () => {
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
      expect(recommendations.length).toBeGreaterThan(1);
    });

    it('should include actionable recommendations with fixes', async () => {
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
      
      actionableRecs.forEach(rec => {
        expect(rec.suggestedFix).toBeDefined();
      });
    });

    it('should include documentation URLs for reference', async () => {
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
      const withDocs = recommendations.filter(r => r.documentationUrl);
      
      expect(withDocs.length).toBeGreaterThan(0);
    });
  });

  describe('Complex Workflows', () => {
    it('should handle real-world CI/CD pipeline', async () => {
      const workflow = `
name: "Full CI/CD Pipeline"
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

concurrency:
  group: workflow
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
          key: npm-cache
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
          key: npm-cache
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
      
      expect(Array.isArray(recommendations)).toBe(true);
      expect(recommendations.length).toBeGreaterThanOrEqual(0);
      
      // Well-configured workflow should have minimal critical issues
      const criticalIssues = recommendations.filter(r => r.severity === 'critical');
      expect(criticalIssues.length).toBe(0);
    });

    it('should provide multiple recommendations per analysis', async () => {
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
      expect(recommendations.length).toBeGreaterThan(1);
    });

    it('should complete analysis in reasonable time', async () => {
      const workflow = `
name: CI
on:
  push:
jobs:
  job_1:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
  job_2:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
  job_3:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
`;
      const startTime = Date.now();
      const recommendations = await agent.analyze(testUri, workflow);
      const duration = Date.now() - startTime;
      
      expect(recommendations).toBeDefined();
      expect(duration).toBeLessThan(1000);
    });
  });

  describe('Error Handling', () => {
    it('should handle invalid YAML gracefully', async () => {
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
        expect(Array.isArray(recommendations) || recommendations instanceof Error).toBeTruthy();
      } catch (error) {
        expect(error instanceof Error).toBeTruthy();
      }
    });

    it('should handle empty workflow', async () => {
      const emptyYaml = '';
      try {
        const recommendations = await agent.analyze(testUri, emptyYaml);
        expect(Array.isArray(recommendations)).toBe(true);
      } catch (error) {
        expect(error instanceof Error).toBe(true);
      }
    });
  });
});
