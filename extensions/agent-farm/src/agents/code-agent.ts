/**
 * Code Agent - Implementation and Optimization Specialist
 * 
 * Analyzes code for implementation issues, refactoring opportunities,
 * and performance optimizations.
 */

import * as vscode from 'vscode';
import { Agent } from '../agent';
import { Recommendation, TaskType, AgentSpecialization } from '../types';

export class CodeAgent extends Agent {
  constructor() {
    super(
      'CodeAgent',
      AgentSpecialization.CODER,
      [
        TaskType.CODE_IMPLEMENTATION,
        TaskType.REFACTORING,
        TaskType.PERFORMANCE,
      ]
    );
  }

  async analyze(
    documentUri: vscode.Uri,
    code: string,
    context?: Record<string, unknown>
  ): Promise<Recommendation[]> {
    const recommendations: Recommendation[] = [];

    // Check for common implementation issues
    recommendations.push(...this.checkImplementationIssues(code));

    // Check for refactoring opportunities
    recommendations.push(...this.checkRefactoringOpportunities(code));

    // Check for performance problems
    recommendations.push(...this.checkPerformanceIssues(code));

    return recommendations;
  }

  /**
   * Check for common implementation antipatterns
   */
  private checkImplementationIssues(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check for missing error handling
    const asyncAwaitMatches = code.match(/await\s+\w+/g) || [];
    if (asyncAwaitMatches.length > 0) {
      const unhandledAsync = asyncAwaitMatches.filter(match => {
        const index = code.indexOf(match);
        const before = code.substring(Math.max(0, index - 10), index);
        return !before.includes('try') && !before.includes('catch');
      });

      if (unhandledAsync.length > 0) {
        recommendations.push({
          id: 'error-handling-async',
          title: 'Missing Error Handling for Async Calls',
          description: `Found ${unhandledAsync.length} async calls without try-catch error handling. This can lead to unhandled promise rejections.`,
          severity: 'warning',
          actionable: true,
          suggestedFix: 'Wrap async calls in try-catch blocks or add .catch() handlers',
          codeSnippet: `try {
  const result = await asyncFunction();
} catch (error) {
  // Handle error appropriately
  console.error('Failed to execute:', error);
}`,
          documentationUrl: 'https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/async_function',
        });
      }
    }

    // Check for console.log statements in production code
    const consoleLogCount = (code.match(/console\.(log|debug|info)/g) || []).length;
    if (consoleLogCount > 3) {
      recommendations.push({
        id: 'console-statements',
        title: 'Excessive Console Statements',
        description: `Found ${consoleLogCount} console.log/debug/info statements. Consider using a proper logging library instead.`,
        severity: 'info',
        actionable: true,
        suggestedFix: 'Replace console.log with structured logging (e.g., winston, pino)',
        documentationUrl: 'https://github.com/winstonjs/winston',
      });
    }

    // Check for magic numbers
    const magicNumberMatches = code.match(/\b(\d{3,}|[0-9]+\.[0-9]+)\b/g) || [];
    if (magicNumberMatches.length > 5) {
      recommendations.push({
        id: 'magic-numbers',
        title: 'Magic Numbers Without Constants',
        description: `Found ${magicNumberMatches.length} numeric literals. Consider extracting to named constants for clarity.`,
        severity: 'info',
        actionable: true,
        suggestedFix: `const TIMEOUT_MS = 5000;
const MAX_RETRIES = 3;`,
      });
    }

    return recommendations;
  }

  /**
   * Check for refactoring opportunities
   */
  private checkRefactoringOpportunities(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check for duplicate code (simple heuristic)
    const lines = code.split('\n');
    const lineMap = new Map<string, number>();
    let duplicateCount = 0;

    lines.forEach(line => {
      const trimmed = line.trim();
      if (trimmed.length > 20) {
        lineMap.set(trimmed, (lineMap.get(trimmed) || 0) + 1);
      }
    });

    duplicateCount = Array.from(lineMap.values()).filter(count => count > 1).length;

    if (duplicateCount > 0) {
      recommendations.push({
        id: 'code-duplication',
        title: 'Potential Code Duplication Detected',
        description: `Found ${duplicateCount} potentially duplicated code blocks. Consider extracting to reusable functions.`,
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Extract duplicated logic into helper functions or utilities',
      });
    }

    // Check for long functions
    const functionMatches = code.match(/(?:function|=>\s*\{|async\s+function)/g) || [];
    const avgLineCount = lines.length / (functionMatches.length || 1);

    if (avgLineCount > 30) {
      recommendations.push({
        id: 'long-functions',
        title: 'Long Functions',
        description: `Average function length is ${Math.round(avgLineCount)} lines. Functions should be focused and testable.`,
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Break down functions into smaller, single-responsibility functions',
      });
    }

    return recommendations;
  }

  /**
   * Check for performance issues
   */
  private checkPerformanceIssues(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check for nested loops
    const nestedLoopPattern = /for\s*\(.*\)[\s\S]*for\s*\(/;
    if (nestedLoopPattern.test(code)) {
      recommendations.push({
        id: 'nested-loops',
        title: 'Nested Loops Detected',
        description: 'Nested loops can have O(n²) complexity. Consider using efficient data structures or algorithms.',
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Use Set/Map for O(n) lookup instead of nested loops when possible',
      });
    }

    // Check for synchronous operations that should be async
    if (code.includes('readFileSync') || code.includes('readSync')) {
      recommendations.push({
        id: 'sync-operations',
        title: 'Synchronous File Operations',
        description: 'Synchronous operations block the event loop. Use async versions instead.',
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Replace readFileSync with promises.readFile or fs.readFile with callback',
      });
    }

    // Check for missing memoization in expensive operations
    if (code.includes('fibonacci') || code.includes('factorial')) {
      recommendations.push({
        id: 'expensive-recursion',
        title: 'Recursive Functions Without Memoization',
        description: 'Recursive functions without caching can have exponential time complexity.',
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Implement memoization or use caching to avoid redundant calculations',
        codeSnippet: `const memo = new Map();
function fibonacci(n) {
  if (memo.has(n)) return memo.get(n);
  // ... computation ...
  memo.set(n, result);
  return result;
}`,
      });
    }

    return recommendations;
  }
}
