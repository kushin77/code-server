/**
 * Review Agent - Code Quality and Security Auditor
 * 
 * Performs comprehensive code review including security audit,
 * best practices enforcement, and quality checks.
 */

import * as vscode from 'vscode';
import { Agent } from '../agent';
import { Recommendation, TaskType, AgentSpecialization } from '../types';

export class ReviewAgent extends Agent {
  constructor() {
    super(
      'ReviewAgent',
      AgentSpecialization.REVIEWER,
      [
        TaskType.CODE_REVIEW,
        TaskType.SECURITY,
      ]
    );
  }

  async analyze(
    documentUri: vscode.Uri,
    code: string,
    context?: Record<string, unknown>
  ): Promise<Recommendation[]> {
    const recommendations: Recommendation[] = [];

    // Perform code quality checks
    recommendations.push(...this.checkCodeQuality(code));

    // Perform security audit
    recommendations.push(...this.checkSecurity(code));

    // Enforce best practices
    recommendations.push(...this.checkBestPractices(code));

    return recommendations;
  }

  /**
   * Check code quality metrics
   */
  private checkCodeQuality(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check for inconsistent naming conventions
    const camelCaseCount = (code.match(/[a-z][a-zA-Z0-9]*[A-Z]/g) || []).length;
    const snakeCaseCount = (code.match(/_[a-z_]+/g) || []).length;

    if (camelCaseCount > 5 && snakeCaseCount > 5) {
      recommendations.push({
        id: 'naming-inconsistency',
        title: 'Inconsistent Naming Convention',
        description: 'Code mixes camelCase and snake_case naming. Maintain consistent naming conventions.',
        severity: 'info',
        actionable: true,
        suggestedFix: 'Choose one convention and apply consistently across the codebase (TypeScript convention: camelCase)',
      });
    }

    // Check code complexity (lines without comments)
    const lineCount = code.split('\n').length;
    const commentLineCount = (code.match(/\/\/|\/\*|\*\//g) || []).length;
    const commentRatio = commentLineCount / lineCount;

    if (commentRatio < 0.1 && lineCount > 50) {
      recommendations.push({
        id: 'insufficient-comments',
        title: 'Insufficient Code Documentation',
        description: `Code has ${lineCount} lines with less than 10% comment coverage. Add more documentation.`,
        severity: 'info',
        actionable: true,
        suggestedFix: 'Add JSDoc comments to functions and complex logic sections',
        codeSnippet: `/**
 * Analyzes code for quality metrics
 * @param code The source code to analyze
 * @returns Array of quality findings
 */`,
      });
    }

    // Check for TODO/FIXME comments
    const todoCount = (code.match(/TODO|FIXME|XXX|HACK/g) || []).length;
    if (todoCount > 0) {
      recommendations.push({
        id: 'unresolved-todos',
        title: `Found ${todoCount} unresolved TODO/FIXME comments`,
        description: 'Code contains unresolved TODOs. Ensure all are tracked in issues or resolved before merge.',
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Track unresolved tasks in GitHub issues or remove if no longer needed',
      });
    }

    return recommendations;
  }

  /**
   * Check for security vulnerabilities
   */
  private checkSecurity(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check for hardcoded credentials
    const credentialPatterns = [
      /password\s*[:=]\s*['"]/i,
      /api[_-]?key\s*[:=]\s*['"]/i,
      /secret\s*[:=]\s*['"]/i,
      /token\s*[:=]\s*['"]/i,
    ];

    const hasCredentials = credentialPatterns.some(pattern => pattern.test(code));
    if (hasCredentials) {
      recommendations.push({
        id: 'hardcoded-credentials',
        title: 'Hardcoded Credentials Detected',
        description: 'Code contains hardcoded credentials (password, API key, secret, or token). Never commit secrets!',
        severity: 'critical',
        actionable: true,
        suggestedFix: 'Use environment variables or secrets management system (e.g., process.env.API_KEY)',
      });
    }

    // Check for SQL injection vulnerabilities
    if (code.includes('query') || code.includes('sql')) {
      const hasUnsafeQuery = /query\s*\(/i.test(code) && !code.includes('parameterized') && !code.includes('$');
      if (hasUnsafeQuery) {
        recommendations.push({
          id: 'sql-injection-risk',
          title: 'Potential SQL Injection Vulnerability',
          description: 'Query construction detected without parameterization. Use prepared statements.',
          severity: 'critical',
          actionable: true,
          suggestedFix: 'Use parameterized queries: db.query("SELECT * FROM users WHERE id = ?", [userId])',
        });
      }
    }

    // Check for eval usage
    if (code.includes('eval(')) {
      recommendations.push({
        id: 'eval-usage',
        title: 'Use of eval() Detected',
        description: 'eval() is a severe security risk and performance problem. Never use it.',
        severity: 'critical',
        actionable: true,
        suggestedFix: 'Use JSON.parse(), Function(), or a safe expression parser instead',
      });
    }

    // Check for insecure regex (ReDoS)
    if (code.includes('+') && code.includes('*') && code.match(/\([^)]*[+*][^)]*\)+/)) {
      recommendations.push({
        id: 'complex-regex',
        title: 'Complex Regex Pattern (ReDoS Risk)',
        description: 'Complex regex with quantifiers can be vulnerable to ReDoS attacks.',
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Simplify regex or add input validation and timeout',
      });
    }

    // Check for insecure equality checks
    if (code.includes('==') && !code.includes('===')) {
      const eqCount = (code.match(/==/g) || []).length;
      recommendations.push({
        id: 'loose-equality',
        title: `Found ${eqCount} loose equality (==) checks`,
        description: 'Loose equality (==) can lead to unexpected type coercion. Use strict equality (===).',
        severity: 'warning',
        actionable: true,
        suggestedFix: 'Replace == with === for type-safe comparisons',
      });
    }

    return recommendations;
  }

  /**
   * Check for best practices
   */
  private checkBestPractices(code: string): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Check for proper error messages
    if (code.includes('throw new Error') && code.match(/throw new Error\(['"][^'"]*['"]\)/g)) {
      const vagueFallback = code.match(/throw new Error\(\s*['"]\s*['"]\)/);
      if (vagueFallback) {
        recommendations.push({
          id: 'vague-error-messages',
          title: 'Vague Error Messages',
          description: 'Error messages should be descriptive to aid debugging.',
          severity: 'info',
          actionable: true,
          suggestedFix: 'Use descriptive error messages: throw new Error(`Failed to fetch user ${userId}`)',
        });
      }
    }

    // Check for proper imports
    if (code.includes('require(') && code.includes('module.exports')) {
      recommendations.push({
        id: 'mixed-module-systems',
        title: 'Mixed CommonJS and ES6 Modules',
        description: 'Code mixes require() and module.exports. Use consistent module system.',
        severity: 'info',
        actionable: true,
        suggestedFix: 'Use ES6 modules consistently: import/export',
      });
    }

    // Check for unused variables
    const variableMatches = code.match(/(?:const|let|var)\s+(\w+)\s*=/g) || [];
    if (variableMatches.length > 5) {
      recommendations.push({
        id: 'check-unused-variables',
        title: 'Potential Unused Variables',
        description: 'Code declares multiple variables. Review for unused variables that should be removed.',
        severity: 'info',
        actionable: true,
        suggestedFix: 'Remove unused variable declarations and use ESLint to catch future occurrences',
      });
    }

    return recommendations;
  }
}
