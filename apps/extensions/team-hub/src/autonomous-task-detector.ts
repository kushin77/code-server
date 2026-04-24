// @file apps/extensions/team-hub/src/autonomous-task-detector.ts
// @module ide/copilot-autonomy
// @description P2-1539 Phase 2: Detect autonomous tasks from Copilot prompts
// @governance GOV-002: All task detection logged, with audit trail for all executions

import * as vscode from 'vscode';

export enum TaskSeverity {
  CRITICAL = 'critical',      // System modifications, destructive ops
  HIGH = 'high',               // Code changes, deployment
  MEDIUM = 'medium',           // Documentation, non-breaking changes
  LOW = 'low'                  // Queries, read-only operations
}

export enum TaskCategory {
  QUERY = 'query',             // Read-only information retrieval
  ANALYSIS = 'analysis',       // Code/config analysis
  DOCUMENTATION = 'documentation',  // Docs writing/updates
  CODE_CHANGE = 'code_change', // Modify source code
  INFRASTRUCTURE = 'infrastructure',  // IaC/deployment changes
  DEBUGGING = 'debugging',     // Debug and fix issues
  TESTING = 'testing'          // Run tests
}

export interface AutonomousTask {
  id: string;
  category: TaskCategory;
  severity: TaskSeverity;
  action: string;              // What the task does
  requiresApproval: boolean;   // Must user approve?
  estimatedDuration: number;   // Seconds
  confidence: number;          // 0-1 confidence score
  reasoning: string;           // Why this classification
}

export class AutonomousTaskDetector {
  private auditLog: AutonomousTask[] = [];

  /**
   * Analyze a prompt and detect if it represents an autonomous task
   */
  analyzePrompt(prompt: string): AutonomousTask | null {
    const normalized = prompt.toLowerCase().trim();

    // Query patterns - read-only, no approval needed
    if (this.matchesQueryPattern(normalized)) {
      return this.createTask(
        TaskCategory.QUERY,
        TaskSeverity.LOW,
        prompt,
        false,
        5,
        0.95,
        'Query pattern detected - read-only operation'
      );
    }

    // Analysis patterns - read-only code/config analysis
    if (this.matchesAnalysisPattern(normalized)) {
      return this.createTask(
        TaskCategory.ANALYSIS,
        TaskSeverity.LOW,
        prompt,
        false,
        30,
        0.9,
        'Analysis pattern detected - no code changes'
      );
    }

    // Documentation patterns - documentation updates
    if (this.matchesDocumentationPattern(normalized)) {
      return this.createTask(
        TaskCategory.DOCUMENTATION,
        TaskSeverity.MEDIUM,
        prompt,
        false,  // Non-breaking, but user may want to review
        60,
        0.85,
        'Documentation update detected'
      );
    }

    // Code change patterns - requires approval
    if (this.matchesCodeChangePattern(normalized)) {
      return this.createTask(
        TaskCategory.CODE_CHANGE,
        TaskSeverity.HIGH,
        prompt,
        true,  // REQUIRES APPROVAL
        300,
        0.8,
        'Code modification detected - user approval required'
      );
    }

    // Infrastructure patterns - requires approval
    if (this.matchesInfrastructurePattern(normalized)) {
      return this.createTask(
        TaskCategory.INFRASTRUCTURE,
        TaskSeverity.CRITICAL,
        prompt,
        true,  // REQUIRES APPROVAL
        600,
        0.85,
        'Infrastructure/deployment change detected - user approval required'
      );
    }

    // Debugging patterns
    if (this.matchesDebuggingPattern(normalized)) {
      return this.createTask(
        TaskCategory.DEBUGGING,
        TaskSeverity.HIGH,
        prompt,
        true,  // REQUIRES APPROVAL
        120,
        0.8,
        'Debugging task detected'
      );
    }

    // Testing patterns
    if (this.matchesTestingPattern(normalized)) {
      return this.createTask(
        TaskCategory.TESTING,
        TaskSeverity.MEDIUM,
        prompt,
        false,
        180,
        0.9,
        'Test execution detected'
      );
    }

    // Unknown pattern
    return null;
  }

  /**
   * Check if prompt is a query
   */
  private matchesQueryPattern(prompt: string): boolean {
    const queryKeywords = [
      'what is', 'how do', 'find', 'search', 'list', 'show',
      'get', 'retrieve', 'look up', 'check', 'verify', 'explain',
      'tell me', 'describe', 'what are', 'where is'
    ];
    return queryKeywords.some(kw => prompt.includes(kw));
  }

  /**
   * Check if prompt is analysis
   */
  private matchesAnalysisPattern(prompt: string): boolean {
    const analysisKeywords = [
      'analyze', 'review', 'audit', 'check', 'scan', 'inspect',
      'compare', 'diff', 'metrics', 'complexity', 'performance',
      'security scan', 'lint'
    ];
    return analysisKeywords.some(kw => prompt.includes(kw));
  }

  /**
   * Check if prompt is documentation
   */
  private matchesDocumentationPattern(prompt: string): boolean {
    const docKeywords = [
      'document', 'write docs', 'create readme', 'add comments',
      'update documentation', 'generate docs', 'write guide',
      'create runbook', 'add examples'
    ];
    return docKeywords.some(kw => prompt.includes(kw));
  }

  /**
   * Check if prompt involves code changes
   */
  private matchesCodeChangePattern(prompt: string): boolean {
    const codeKeywords = [
      'fix bug', 'implement', 'add feature', 'refactor', 'rewrite',
      'modify', 'change', 'update code', 'edit', 'implement feature',
      'add function', 'create class', 'fix error'
    ];
    return codeKeywords.some(kw => prompt.includes(kw));
  }

  /**
   * Check if prompt involves infrastructure/deployment
   */
  private matchesInfrastructurePattern(prompt: string): boolean {
    const infraKeywords = [
      'deploy', 'terraform', 'docker', 'kubernetes', 'helm',
      'infrastructure', 'provision', 'setup service', 'configure',
      'create database', 'migrate', 'scale', 'update config'
    ];
    return infraKeywords.some(kw => prompt.includes(kw));
  }

  /**
   * Check if prompt involves debugging
   */
  private matchesDebuggingPattern(prompt: string): boolean {
    const debugKeywords = [
      'debug', 'troubleshoot', 'fix', 'error', 'issue', 'problem',
      'why', 'investigate', 'root cause', 'trace'
    ];
    return debugKeywords.some(kw => prompt.includes(kw));
  }

  /**
   * Check if prompt involves testing
   */
  private matchesTestingPattern(prompt: string): boolean {
    const testKeywords = [
      'run test', 'test', 'execute test', 'test suite', 'vitest',
      'jest', 'unit test', 'integration test', 'e2e test'
    ];
    return testKeywords.some(kw => prompt.includes(kw));
  }

  /**
   * Create a task with ID and timestamp
   */
  private createTask(
    category: TaskCategory,
    severity: TaskSeverity,
    action: string,
    requiresApproval: boolean,
    estimatedDuration: number,
    confidence: number,
    reasoning: string
  ): AutonomousTask {
    const task: AutonomousTask = {
      id: `task-${Date.now()}-${Math.random().toString(36).substring(7)}`,
      category,
      severity,
      action,
      requiresApproval,
      estimatedDuration,
      confidence,
      reasoning
    };

    this.auditLog.push(task);
    return task;
  }

  /**
   * Get audit log of all detected tasks
   */
  getAuditLog(): AutonomousTask[] {
    return [...this.auditLog];
  }

  /**
   * Clear audit log (for tests)
   */
  clearAuditLog(): void {
    this.auditLog = [];
  }
}

export function createAutonomousTaskDetector(): AutonomousTaskDetector {
  return new AutonomousTaskDetector();
}
