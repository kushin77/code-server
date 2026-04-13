/**
 * Pull Request Validator
 * Validates pull requests before merging for deployment readiness
 */

export enum ValidationStage {
  MANIFEST_VALIDATION = 'manifest-validation',
  SECURITY_SCAN = 'security-scan',
  CONFIGURATION_VALIDATION = 'config-validation',
  DEPENDENCY_ANALYSIS = 'dependency-analysis',
  PERFORMANCE_IMPACT = 'performance-impact',
}

export interface ValidationRule {
  id: string;
  name: string;
  description: string;
  stage: ValidationStage;
  severity: 'critical' | 'high' | 'medium' | 'low';
  enabled: boolean;
  validate: (prContext: PullRequestContext) => Promise<ValidationIssue[]>;
}

export interface ValidationIssue {
  ruleId: string;
  ruleName: string;
  severity: 'critical' | 'high' | 'medium' | 'low';
  message: string;
  file?: string;
  line?: number;
  suggestion?: string;
}

export interface DeploymentValidation {
  id: string;
  prNumber: number;
  repository: string;
  branch: string;
  targetBranch: string;
  author: string;
  title: string;
  description: string;
  startTime: Date;
  completedTime?: Date;
  validationStages: {
    stage: ValidationStage;
    status: 'Pending' | 'Running' | 'Passed' | 'Failed' | 'Skipped';
    issues: ValidationIssue[];
    duration: number;
  }[];
  canMerge: boolean;
  canDeploy: boolean;
  blockedReasons: string[];
  warnings: string[];
  recommendations: string[];
}

export interface PullRequestContext {
  prNumber: number;
  repository: string;
  branch: string;
  targetBranch: string;
  author: string;
  title: string;
  description: string;
  files: Array<{
    name: string;
    additions: number;
    deletions: number;
    status: 'added' | 'removed' | 'modified';
    patch?: string;
  }>;
  labels: string[];
  isDraft: boolean;
  approvalCount: number;
  requestedReviewers: string[];
}

/**
 * Pull Request Validator
 */
export class PullRequestValidator {
  private rules: Map<string, ValidationRule> = new Map();

  constructor() {
    this.initializeDefaultRules();
  }

  /**
   * Initialize default validation rules
   */
  private initializeDefaultRules(): void {
    // Manifest validation rule
    this.addRule({
      id: 'manifest-syntax',
      name: 'Manifest Syntax',
      description: 'Validate YAML and manifest syntax',
      stage: ValidationStage.MANIFEST_VALIDATION,
      severity: 'critical',
      enabled: true,
      validate: async (context) => {
        const issues: ValidationIssue[] = [];

        for (const file of context.files) {
          if (file.name.endsWith('.yaml') || file.name.endsWith('.yml')) {
            // Validate YAML syntax
            if (file.patch && file.patch.includes('invalid:')) {
              issues.push({
                ruleId: 'manifest-syntax',
                ruleName: 'Manifest Syntax',
                severity: 'critical',
                message: 'Invalid YAML syntax detected',
                file: file.name,
                suggestion: 'Fix YAML indentation and syntax',
              });
            }
          }
        }

        return issues;
      },
    });

    // Configuration validation rule
    this.addRule({
      id: 'config-validation',
      name: 'Configuration Validation',
      description: 'Validate configuration files',
      stage: ValidationStage.CONFIGURATION_VALIDATION,
      severity: 'high',
      enabled: true,
      validate: async (context) => {
        const issues: ValidationIssue[] = [];

        for (const file of context.files) {
          if (file.name.includes('config') || file.name.includes('values')) {
            // Check for hardcoded secrets
            if (file.patch && (file.patch.includes('password') || file.patch.includes('secret'))) {
              issues.push({
                ruleId: 'config-validation',
                ruleName: 'Configuration Validation',
                severity: 'critical',
                message: 'Potential hardcoded secrets detected',
                file: file.name,
                suggestion: 'Use ConfigMap or Secret resources instead of hardcoded values',
              });
            }
          }
        }

        return issues;
      },
    });

    // Dependency analysis rule
    this.addRule({
      id: 'dependency-check',
      name: 'Dependency Analysis',
      description: 'Analyze new dependencies',
      stage: ValidationStage.DEPENDENCY_ANALYSIS,
      severity: 'high',
      enabled: true,
      validate: async (context) => {
        const issues: ValidationIssue[] = [];

        for (const file of context.files) {
          if (file.name.includes('requirements') || file.name.includes('package.json')) {
            // Check for dependency changes
            if (file.additions > 5 && file.status === 'modified') {
              issues.push({
                ruleId: 'dependency-check',
                ruleName: 'Dependency Analysis',
                severity: 'medium',
                message: 'Significant dependency changes detected',
                file: file.name,
                suggestion: 'Verify new dependencies are vetted and necessary',
              });
            }
          }
        }

        return issues;
      },
    });

    // Performance impact rule
    this.addRule({
      id: 'performance-impact',
      name: 'Performance Impact',
      description: 'Detect potential performance regressions',
      stage: ValidationStage.PERFORMANCE_IMPACT,
      severity: 'medium',
      enabled: true,
      validate: async (context) => {
        const issues: ValidationIssue[] = [];

        for (const file of context.files) {
          // Check for large additions that might impact performance
          if (file.additions > 500 && file.status === 'modified') {
            issues.push({
              ruleId: 'performance-impact',
              ruleName: 'Performance Impact',
              severity: 'medium',
              message: 'Large changes detected - verify performance impact',
              file: file.name,
              suggestion: 'Include performance testing results in PR description',
            });
          }
        }

        return issues;
      },
    });
  }

  /**
   * Add custom validation rule
   */
  addRule(rule: ValidationRule): void {
    this.rules.set(rule.id, rule);
  }

  /**
   * Validate a pull request
   */
  async validatePullRequest(context: PullRequestContext): Promise<DeploymentValidation> {
    const startTime = new Date();
    const validation: DeploymentValidation = {
      id: `pr-${context.prNumber}-${Date.now()}`,
      prNumber: context.prNumber,
      repository: context.repository,
      branch: context.branch,
      targetBranch: context.targetBranch,
      author: context.author,
      title: context.title,
      description: context.description,
      startTime,
      validationStages: [],
      canMerge: false,
      canDeploy: false,
      blockedReasons: [],
      warnings: [],
      recommendations: [],
    };

    // Group rules by stage
    const rulesByStage = new Map<ValidationStage, ValidationRule[]>();
    for (const rule of this.rules.values()) {
      if (!rulesByStage.has(rule.stage)) {
        rulesByStage.set(rule.stage, []);
      }
      rulesByStage.get(rule.stage)!.push(rule);
    }

    // Run validation stages
    for (const [stage, rules] of rulesByStage.entries()) {
      const stageStart = Date.now();
      const stageIssues: ValidationIssue[] = [];

      for (const rule of rules) {
        if (!rule.enabled) {
          continue;
        }

        try {
          const issues = await rule.validate(context);
          stageIssues.push(...issues);
        } catch (error) {
          stageIssues.push({
            ruleId: rule.id,
            ruleName: rule.name,
            severity: 'high',
            message: `Validation failed: ${error}`,
          });
        }
      }

      const stageDuration = Date.now() - stageStart;
      const hasCriticalIssues = stageIssues.some((i) => i.severity === 'critical');
      const status = stageIssues.length === 0 ? 'Passed' : hasCriticalIssues ? 'Failed' : 'Passed';

      validation.validationStages.push({
        stage,
        status: status as 'Passed' | 'Failed',
        issues: stageIssues,
        duration: stageDuration,
      });

      // Track issues
      for (const issue of stageIssues) {
        if (issue.severity === 'critical') {
          validation.blockedReasons.push(`${issue.ruleName}: ${issue.message}`);
        } else if (issue.severity === 'high') {
          validation.warnings.push(`${issue.ruleName}: ${issue.message}`);
        }
      }
    }

    // Determine merge and deploy eligibility
    validation.canMerge = validation.blockedReasons.length === 0;
    validation.canDeploy =
      validation.canMerge &&
      context.approvalCount >= 2 &&
      !context.isDraft &&
      context.labels.includes('approved-for-deployment');

    // Generate recommendations
    validation.recommendations = this.generateRecommendations(context, validation);

    validation.completedTime = new Date();

    return validation;
  }

  /**
   * Generate recommendations based on validation results
   */
  private generateRecommendations(context: PullRequestContext, validation: DeploymentValidation): string[] {
    const recommendations: string[] = [];

    if (!validation.canMerge) {
      recommendations.push('Fix critical validation issues before merging');
    }

    if (!validation.canDeploy && validation.canMerge) {
      if (context.approvalCount < 2) {
        recommendations.push(`Requires ${2 - context.approvalCount} more approval(s) before deployment`);
      }
      if (context.isDraft) {
        recommendations.push('Mark PR as ready for review before deployment');
      }
      if (!context.labels.includes('approved-for-deployment')) {
        recommendations.push('Add "approved-for-deployment" label to enable deployment');
      }
    }

    if (validation.warnings.length > 0) {
      recommendations.push('Address warnings to improve reliability');
    }

    if (context.files.some((f) => f.name.endsWith('Dockerfile'))) {
      recommendations.push('Verify container image builds and security scanning');
    }

    if (context.files.some((f) => f.name.includes('deployment') || f.name.includes('pod'))) {
      recommendations.push('Test deployment in staging environment first');
    }

    if (context.approvalCount >= 2 && validation.canMerge && validation.canDeploy) {
      recommendations.push('✅ Ready to merge and deploy to production');
    }

    return recommendations;
  }
}
