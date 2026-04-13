/**
 * GitHub Actions Agent - CI/CD Pipeline Analysis & Optimization
 * 
 * Specializes in analyzing GitHub Actions workflows, recommending optimizations for:
 * - Workflow structure and best practices
 * - Runner selection and resource efficiency
 * - Dependency caching strategies
 * - Secret management and security
 * - Cost optimization
 * - Parallelization opportunities
 * - Retry and resilience strategies
 */

import * as vscode from 'vscode';
import { Agent } from '../agent';
import { AgentSpecialization, TaskType, Recommendation } from '../types';
import * as yaml from 'yaml'; // Requires: npm install yaml

/**
 * GitHub Actions Agent - CI/CD Optimization Specialist
 */
export class GitHubActionsAgent extends Agent {
  constructor() {
    super(
      'GitHubActionsAgent',
      AgentSpecialization.CI_CD,
      [
        TaskType.CI_CD,
        TaskType.PERFORMANCE,
      ]
    );
  }

  /**
   * Analyze GitHub Actions workflow files for optimization opportunities
   */
  async analyze(
    documentUri: vscode.Uri,
    code: string,
    context?: Record<string, unknown>
  ): Promise<Recommendation[]> {
    const recommendations: Recommendation[] = [];

    try {
      // Parse YAML workflow file
      const workflow = yaml.parse(code) as Record<string, unknown>;

      // Check workflow structure and syntax
      const structureAnalysis = this.analyzeWorkflowStructure(workflow, code);
      recommendations.push(...structureAnalysis);

      // Analyze runner usage
      const runnerAnalysis = this.analyzeRunnerUsage(workflow);
      recommendations.push(...runnerAnalysis);

      // Check caching strategies
      const cachingAnalysis = this.analyzeDependencyCaching(workflow);
      recommendations.push(...cachingAnalysis);

      // Analyze secrets management
      const secretsAnalysis = this.analyzeSecrets(workflow, code);
      recommendations.push(...secretsAnalysis);

      // Analyze cost implications
      const costAnalysis = this.analyzeCost(workflow);
      recommendations.push(...costAnalysis);

      // Check parallelization opportunities
      const parallelAnalysis = this.analyzeParallelization(workflow);
      recommendations.push(...parallelAnalysis);

      // Analyze retry strategies
      const retryAnalysis = this.analyzeRetryStrategies(workflow);
      recommendations.push(...retryAnalysis);

      this.outputChannel.appendLine(`[${new Date().toLocaleTimeString()}] Analysis complete: ${recommendations.length} recommendations generated`);

    } catch (error) {
      this.outputChannel.appendLine(`[ERROR] Failed to analyze workflow: ${error instanceof Error ? error.message : String(error)}`);
      throw new Error(`Workflow analysis failed: ${error instanceof Error ? error.message : String(error)}`);
    }

    return recommendations;
  }

  /**
   * Analyze workflow structure and best practices
   */
  private analyzeWorkflowStructure(
    workflow: Record<string, unknown>,
    code: string
  ): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check if name is descriptive
    const name = workflow.name as string | undefined;
    if (!name || name.length < 5) {
      recommendations.push({
        id: 'gh-workflow-name',
        title: 'Workflow Name Not Descriptive',
        description: 'The workflow name should be descriptive (e.g., "CI: Build & Test" instead of "CI")',
        severity: 'info',
        actionable: true,
        suggestedFix: 'Update the workflow name to be more descriptive',
        codeSnippet: `name: "CI: Build, Test, and Deploy"`,
        documentationUrl: 'https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#name',
      });
    }

    // Check for missing concurrency settings (can cause resource waste)
    if (!workflow.concurrency) {
      recommendations.push({
        id: 'gh-missing-concurrency',
        title: 'Missing Concurrency Settings',
        description: 'Without concurrency controls, multiple workflow runs can execute simultaneously, wasting resources and CI/CD minutes.',
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Add concurrency to cancel in-progress runs when a new one starts',
        codeSnippet: `concurrency:
  group: \${{ github.workflow }}-\${{ github.ref }}
  cancel-in-progress: true`,
        documentationUrl: 'https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#concurrency',
      });
    }

    // Check trigger configuration
    const on = workflow.on as Record<string, unknown> | undefined;
    if (!on || Object.keys(on).length === 0) {
      recommendations.push({
        id: 'gh-missing-triggers',
        title: 'No Workflow Triggers Configured',
        description: 'The workflow has no triggers (on: section), so it will never run automatically.',
        severity: 'critical',
        actionable: true,
        suggestedFix: 'Add appropriate triggers (push, pull_request, schedule, etc.)',
        codeSnippet: `on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]`,
        documentationUrl: 'https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows',
      });
    }

    // Check for trigger + schedule best practices
    if (on?.push && on?.schedule) {
      recommendations.push({
        id: 'gh-redundant-triggers',
        title: 'Potentially Redundant Triggers',
        description: 'Workflow runs on both push and schedule. Consider if schedule is needed if run frequency is high.',
        severity: 'info',
        actionable: false,
        suggestedFix: 'Review trigger frequency to ensure schedule adds value',
        documentationUrl: 'https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows',
      });
    }

    // Check for timeout settings (prevent hanging jobs)
    const jobs = workflow.jobs as Record<string, Record<string, unknown>> | undefined;
    if (jobs) {
      Object.entries(jobs).forEach(([jobName, jobConfig]) => {
        if (!jobConfig['timeout-minutes']) {
          recommendations.push({
            id: `gh-job-timeout-${jobName}`,
            title: `Job "${jobName}" Missing Timeout`,
            description: `Job "${jobName}" has no timeout-minutes setting. Runaway jobs could consume CI/CD minutes.`,
            severity: 'warning',
            actionable: true,
            suggestedFix: `Set appropriate timeout for job: timeout-minutes: 30`,
            codeSnippet: `${jobName}:
  runs-on: ubuntu-latest
  timeout-minutes: 30  # Prevent runaway jobs`,
            documentationUrl: 'https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#jobsjob_idtimeout-minutes',
          });
        }
      });
    }

    return recommendations;
  }

  /**
   * Analyze runner selection and resource usage
   */
  private analyzeRunnerUsage(workflow: Record<string, unknown>): Recommendation[] {
    const recommendations: Recommendation[] = [];

    const jobs = workflow.jobs as Record<string, Record<string, unknown>> | undefined;
    if (!jobs) {
      return recommendations;
    }

    Object.entries(jobs).forEach(([jobName, jobConfig]) => {
      const runsOn = jobConfig['runs-on'] as string | string[] | undefined;

      // Check if using appropriate runners
      if (!runsOn) {
        recommendations.push({
          id: `gh-runner-missing-${jobName}`,
          title: `Job "${jobName}" Missing runs-on Setting`,
          description: `Job "${jobName}" doesn't specify which runner to use.`,
          severity: 'critical',
          actionable: true,
          suggestedFix: 'Specify a runner: ubuntu-latest, windows-latest, macos-latest',
          codeSnippet: `${jobName}:
  runs-on: ubuntu-latest`,
        });
      } else if (typeof runsOn === 'string') {
        // Check for unnecessary expensive runners
        const jobName_lower = jobName.toLowerCase();
        if (runsOn.includes('macos') && !(/darwin|mac|ios/i.test(jobName_lower))) {
          recommendations.push({
            id: `gh-expensive-runner-${jobName}`,
            title: `Job "${jobName}" Using Expensive macOS Runner`,
            description: 'macOS runners cost 10x more than Linux. Consider if macOS is truly required.',
            severity: 'warning',
            actionable: true,
            suggestedFix: 'Use ubuntu-latest unless macOS/iOS specific testing is truly needed',
            codeSnippet: `# Change from:
  runs-on: macos-latest
# To:
  runs-on: ubuntu-latest`,
          });
        }

        if (runsOn.includes('windows') && !(/windows|win/i.test(jobName_lower))) {
          recommendations.push({
            id: `gh-expensive-runner-windows-${jobName}`,
            title: `Job "${jobName}" Using Expensive Windows Runner`,
            description: 'Windows runners cost more than Linux. Consider if Windows-specific testing is needed.',
            severity: 'warning',
            actionable: true,
            suggestedFix: 'Use ubuntu-latest for cross-platform testing unless Windows-specific',
            documentationUrl: 'https://docs.github.com/en/billing/managing-billing-for-github-actions/about-billing-for-github-actions#per-minute-rates',
          });
        }
      }

      // Check for self-hosted runners (security consideration)
      if (typeof runsOn === 'string' && runsOn.includes('self-hosted')) {
        recommendations.push({
          id: `gh-self-hosted-${jobName}`,
          title: `Job "${jobName}" Uses Self-Hosted Runner`,
          description: 'Self-hosted runners require maintenance and security hardening. Ensure they are properly configured.',
          severity: 'info',
          actionable: false,
          suggestedFix: 'Verify self-hosted runner security configuration and maintenance plan',
          documentationUrl: 'https://docs.github.com/en/actions/hosting-your-own-runners',
        });
      }
    });

    return recommendations;
  }

  /**
   * Analyze dependency caching strategies
   */
  private analyzeDependencyCaching(workflow: Record<string, unknown>): Recommendation[] {
    const recommendations: Recommendation[] = [];

    const jobs = workflow.jobs as Record<string, Record<string, unknown>> | undefined;
    if (!jobs) {
      return recommendations;
    }

    Object.entries(jobs).forEach(([jobName, jobConfig]) => {
      const steps = jobConfig.steps as Array<Record<string, unknown>> | undefined;
      if (!steps) {
        return;
      }

      const hasNodeSetup = steps.some(s => 
        s.uses?.toString().includes('setup-node') ||
        s.uses?.toString().includes('setup-python')
      );

      const hasCache = steps.some(s => s.uses?.toString().includes('cache'));

      // If using Node/Python but no cache, recommend caching
      if (hasNodeSetup && !hasCache) {
        const setupStep = steps.find(s => s.uses?.toString().includes('setup-node'));
        const with_ = (setupStep?.with as Record<string, unknown> | undefined) || {};
        const packageManager = with_['package-manager'] === 'pnpm' ? 'pnpm' : with_['package-manager'] === 'yarn' ? 'yarn' : 'npm';

        recommendations.push({
          id: `gh-missing-cache-${jobName}`,
          title: `Job "${jobName}" Missing Dependency Cache`,
          description: `Job runs with ${packageManager} but has no cache configured. Dependencies are downloaded fresh each run.`,
          severity: 'warning',
          actionable: true,
          suggestedFix: `Add dependency caching to speed up ${packageManager} installs`,
          codeSnippet: `- uses: actions/cache@v4
  with:
    path: |
      ~/.${packageManager}
      ./node_modules
    key: \${{ runner.os }}-${packageManager}-\${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      \${{ runner.os }}-${packageManager}-`,
          documentationUrl: 'https://github.com/actions/cache',
        });
      }

      // Check for Python package caching
      const hasPythonSetup = steps.some(s => s.uses?.toString().includes('setup-python'));
      if (hasPythonSetup && !hasCache) {
        recommendations.push({
          id: `gh-missing-python-cache-${jobName}`,
          title: `Job "${jobName}" Missing Python Package Cache`,
          description: 'Job uses Python but has no pip package cache configured.',
          severity: 'warning',
          actionable: true,
          suggestedFix: 'Add pip cache action for faster dependency installation',
          codeSnippet: `- uses: actions/cache@v4
  with:
    path: ~/.cache/pip
    key: \${{ runner.os }}-pip-\${{ hashFiles('**/requirements.txt') }}
    restore-keys: |
      \${{ runner.os }}-pip-`,
        });
      }
    });

    return recommendations;
  }

  /**
   * Analyze secrets management and security
   */
  private analyzeSecrets(
    workflow: Record<string, unknown>,
    code: string
  ): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check for hardcoded secrets - but exclude proper ${{ secrets.XXXXX }} references
    const lines = code.split('\n');
    const secretPatterns = [
      /password['\s]*[:=]\s*["'](?!\{)/gi,
      /token['\s]*[:=]\s*["'](?!\{)/gi,
      /api[_-]?key['\s]*[:=]\s*["'](?!\{)/gi,
      /secret['\s]*[:=]\s*["'][^}]/gi,
      /credentials['\s]*[:=]\s*["'](?!\{)/gi,
    ];

    let foundHardcodedSecret = false;
    lines.forEach(line => {
      // Skip lines that properly use ${{ secrets. }}
      if (line.includes('${{ secrets.')) {
        return;
      }

      secretPatterns.forEach(pattern => {
        if (pattern.test(line)) {
          foundHardcodedSecret = true;
        }
      });
    });

    if (foundHardcodedSecret) {
      recommendations.push({
        id: 'gh-hardcoded-secret',
        title: 'Hardcoded Secret/Credential Detected',
        description: 'Potential hardcoded secret, password, or API key found in workflow.',
        severity: 'critical',
        actionable: true,
        suggestedFix: 'Move secrets to GitHub Secrets and reference with ${{ secrets.SECRET_NAME }}',
        codeSnippet: `# Instead of:
env:
  API_KEY: "abc123def456"

# Use:
env:
  API_KEY: \${{ secrets.API_KEY }}`,
        documentationUrl: 'https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions',
      });
    }

    // Check if using secrets properly
    const hasSecretsUsage = code.includes('secrets.');
    if (!hasSecretsUsage && code.includes('password') && code.includes('login')) {
      recommendations.push({
        id: 'gh-secrets-not-used',
        title: 'Credentials Not Stored in Secrets',
        description: 'Workflow appears to need credentials but doesn\'t use GitHub Secrets.',
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Use GitHub Secrets for all sensitive credentials',
        documentationUrl: 'https://docs.github.com/en/actions/security-guides/encrypted-secrets',
      });
    }

    return recommendations;
  }

  /**
   * Analyze cost implications and optimization opportunities
   */
  private analyzeCost(workflow: Record<string, unknown>): Recommendation[] {
    const recommendations: Recommendation[] = [];

    const jobs = workflow.jobs as Record<string, Record<string, unknown>> | undefined;
    if (!jobs) {
      return recommendations;
    }

    let estimatedMonthlyCost = 0;
    let costSavings = 0;

    Object.entries(jobs).forEach(([jobName, jobConfig]) => {
      const runsOn = jobConfig['runs-on'] as string | undefined;

      // Estimate cost (simplified - GitHub rates vary)
      if (runsOn?.includes('ubuntu')) {
        // Ubuntu: $0.008 per minute
        estimatedMonthlyCost += 0.008 * 60 * 20; // Assume 1 run per day, 1 hour per run
      } else if (runsOn?.includes('windows')) {
        // Windows: $0.016 per minute
        estimatedMonthlyCost += 0.016 * 60 * 20;
      } else if (runsOn?.includes('macos')) {
        // macOS: $0.08 per minute
        estimatedMonthlyCost += 0.08 * 60 * 20;
      }
    });

    if (estimatedMonthlyCost > 100) {
      recommendations.push({
        id: 'gh-cost-high',
        title: 'High Estimated CI/CD Costs',
        description: `Estimated monthly CI/CD cost: $${estimatedMonthlyCost.toFixed(2)}. Consider optimizations.`,
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Review job parallelization, cache dependencies, use efficient runners',
        documentationUrl: 'https://docs.github.com/en/billing/managing-billing-for-github-actions',
      });
    }

    return recommendations;
  }

  /**
   * Analyze parallelization opportunities
   */
  private analyzeParallelization(workflow: Record<string, unknown>): Recommendation[] {
    const recommendations: Recommendation[] = [];

    const jobs = workflow.jobs as Record<string, Record<string, unknown>> | undefined;
    if (!jobs) {
      return recommendations;
    }

    // Check if jobs have unnecessary dependencies
    Object.entries(jobs).forEach(([jobName, jobConfig]) => {
      const needs = jobConfig.needs as string | string[] | undefined;

      if (!needs && jobName !== 'build') {
        // Check if job could run in parallel
        const steps = jobConfig.steps as Array<Record<string, unknown>> | undefined;
        if (steps && steps.length > 1) {
          // Multiple steps suggest potential parallelization
          recommendations.push({
            id: `gh-parallelization-${jobName}`,
            title: `Job "${jobName}" Could Be Parallelized`,
            description: `Job has multiple steps that could potentially run in parallel jobs for faster overall completion.`,
            severity: 'info',
            actionable: false,
            suggestedFix: 'Consider splitting into multiple parallel jobs if steps are independent',
            documentationUrl: 'https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#jobsjob_idneeds',
          });
        }
      }
    });

    return recommendations;
  }

  /**
   * Analyze retry strategies and resilience
   */
  private analyzeRetryStrategies(workflow: Record<string, unknown>): Recommendation[] {
    const recommendations: Recommendation[] = [];

    const jobs = workflow.jobs as Record<string, Record<string, unknown>> | undefined;
    if (!jobs) {
      return recommendations;
    }

    Object.entries(jobs).forEach(([jobName, jobConfig]) => {
      const steps = jobConfig.steps as Array<Record<string, unknown>> | undefined;
      if (!steps) {
        return;
      }

      // Check for unstable steps without retry
      steps.forEach((step, i) => {
        const uses = step.uses?.toString() || '';
        
        // Network-dependent steps should have retry
        if ((uses.includes('upload') || uses.includes('download') || uses.includes('deploy')) && !step['continue-on-error']) {
          const with_ = (step.with as Record<string, unknown> | undefined) || {};
          const hasRetry = with_['max-retry'] || with_['retry-count'];
           
          if (!hasRetry) {
            recommendations.push({
              id: `gh-no-retry-${jobName}-${i}`,
              title: `Step "${step.name || uses}" Could Benefit From Retry`,
              description: 'Network-dependent steps (upload, download, deploy) often benefit from automatic retries.',
              severity: 'info',
              actionable: true,
              suggestedFix: 'Add retry strategy for resilience',
              codeSnippet: `- name: Upload artifacts
  uses: actions/upload-artifact@v4
  with:
    path: ./build
    retry-count: 3  # Retry up to 3 times on transient failures`,
            });
          }
        }
      });
    });

    return recommendations;
  }


}
