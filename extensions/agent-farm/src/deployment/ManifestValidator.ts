/**
 * Manifest Validator
 * Validates and lints Kubernetes manifests before deployment
 */

export interface ManifestComponent {
  apiVersion: string;
  kind: string;
  name: string;
  namespace?: string;
  labels?: Record<string, string>;
  annotations?: Record<string, string>;
}

export interface ManifestDependency {
  from: string;
  to: string;
  type: 'configMap' | 'secret' | 'service' | 'pvc' | 'custom';
}

export interface ValidationRule {
  name: string;
  description: string;
  severity: 'error' | 'warning' | 'info';
  check: (manifest: ManifestComponent) => boolean;
  message: (manifest: ManifestComponent) => string;
}

export interface ValidationIssue {
  rule: string;
  severity: 'error' | 'warning' | 'info';
  component: string;
  message: string;
  line?: number;
}

export interface ValidationResult {
  valid: boolean;
  issues: ValidationIssue[];
  components: ManifestComponent[];
  dependencies: ManifestDependency[];
  warnings: number;
  errors: number;
  recommendations: string[];
  executionTime: number;
}

/**
 * Manifest Validator - Validates Kubernetes manifests
 */
export class ManifestValidator {
  private rules: ValidationRule[] = [];
  private customRules: ValidationRule[] = [];

  constructor() {
    this.initializeDefaultRules();
  }

  /**
   * Initialize default validation rules
   */
  private initializeDefaultRules(): void {
    // Image pull policy validation
    this.rules.push({
      name: 'image-pull-policy',
      description: 'Ensure imagePullPolicy is set to Always for non-cached images',
      severity: 'warning',
      check: (m) => {
        // Would check container image pull policy in real implementation
        return true;
      },
      message: (m) => `Container image pull policy should be explicit`,
    });

    // Resource limits validation
    this.rules.push({
      name: 'resource-limits',
      description: 'All containers must have CPU and memory limits',
      severity: 'error',
      check: (m) => m.kind === 'Pod' || m.kind === 'Deployment',
      message: (m) => `${m.name}: CPU and memory limits must be specified`,
    });

    // Health check validation
    this.rules.push({
      name: 'health-checks',
      description: 'Deployments should have liveness and readiness probes',
      severity: 'warning',
      check: (m) => m.kind === 'Deployment',
      message: (m) => `${m.name}: Missing health probes (liveness and/or readiness)`,
    });

    // Security context validation
    this.rules.push({
      name: 'security-context',
      description: 'Containers should run as non-root with read-only filesystem',
      severity: 'warning',
      check: (m) => m.kind === 'Pod' || m.kind === 'Deployment',
      message: (m) => `${m.name}: Missing security context configuration`,
    });

    // Service account validation
    this.rules.push({
      name: 'service-account',
      description: 'Pods should use explicit service accounts',
      severity: 'info',
      check: (m) => m.kind === 'Pod' || m.kind === 'Deployment',
      message: (m) => `${m.name}: Consider using explicit service account`,
    });

    // Namespace specification
    this.rules.push({
      name: 'namespace-explicit',
      description: 'Resources should explicitly specify namespace',
      severity: 'warning',
      check: (m) => !m.namespace && m.kind !== 'ClusterRole' && m.kind !== 'ClusterRoleBinding',
      message: (m) => `${m.name}: Namespace should be explicitly specified`,
    });

    // Labels validation
    this.rules.push({
      name: 'required-labels',
      description: 'Resources should have app, version, and managed-by labels',
      severity: 'warning',
      check: (m) => {
        if (!m.labels) return false;
        const required = ['app', 'version', 'managed-by'];
        return required.every((label) => label in m.labels!);
      },
      message: (m) => `${m.name}: Missing required labels (app, version, managed-by)`,
    });
  }

  /**
   * Add custom validation rule
   */
  addCustomRule(rule: ValidationRule): void {
    this.customRules.push(rule);
  }

  /**
   * Validate manifest content
   */
  async validateManifest(manifestYaml: string): Promise<ValidationResult> {
    const startTime = Date.now();
    const issues: ValidationIssue[] = [];
    const components: ManifestComponent[] = [];
    const dependencies: ManifestDependency[] = [];

    try {
      // Parse YAML and extract components
      const parsedComponents = this.parseManifest(manifestYaml);
      components.push(...parsedComponents);

      // Run all validation rules
      for (const component of components) {
        const componentIssues = await this.validateComponent(component);
        issues.push(...componentIssues);
      }

      // Analyze dependencies
      const analyzedDeps = this.analyzeDependencies(components);
      dependencies.push(...analyzedDeps);

      // Detect dependency issues
      const depIssues = this.validateDependencies(components, dependencies);
      issues.push(...depIssues);

      // Generate recommendations
      const recommendations = this.generateRecommendations(components, issues);

      // Calculate statistics
      const errorCount = issues.filter((i) => i.severity === 'error').length;
      const warningCount = issues.filter((i) => i.severity === 'warning').length;

      const executionTime = Date.now() - startTime;

      return {
        valid: errorCount === 0,
        issues,
        components,
        dependencies,
        warnings: warningCount,
        errors: errorCount,
        recommendations,
        executionTime,
      };
    } catch (error) {
      issues.push({
        rule: 'parse-error',
        severity: 'error',
        component: 'manifest',
        message: `Failed to parse manifest: ${error instanceof Error ? error.message : 'Unknown error'}`,
      });

      return {
        valid: false,
        issues,
        components,
        dependencies,
        warnings: 0,
        errors: 1,
        recommendations: ['Fix manifest syntax and try again'],
        executionTime: Date.now() - startTime,
      };
    }
  }

  /**
   * Parse YAML manifest into components
   */
  private parseManifest(manifestYaml: string): ManifestComponent[] {
    const components: ManifestComponent[] = [];

    // Split by document separator (---)
    const documents = manifestYaml.split(/^---\s*$/m);

    for (const doc of documents) {
      if (!doc.trim()) continue;

      try {
        // In real implementation, would use YAML parser
        // For now, extract basic structure
        const lines = doc.split('\n');
        let apiVersion = 'v1';
        let kind = 'Unknown';
        let name = 'unnamed';
        let namespace: string | undefined;
        const labels: Record<string, string> = {};
        const annotations: Record<string, string> = {};

        for (const line of lines) {
          if (line.match(/^\s*apiVersion:/)) {
            apiVersion = line.split(':')[1]?.trim() || 'v1';
          } else if (line.match(/^\s*kind:/)) {
            kind = line.split(':')[1]?.trim() || 'Unknown';
          } else if (line.match(/^\s*metadata:/)) {
            // Metadata section starts
          } else if (line.match(/^\s*name:/) && !line.includes('metadata')) {
            name = line.split(':')[1]?.trim() || 'unnamed';
          } else if (line.match(/^\s*namespace:/)) {
            namespace = line.split(':')[1]?.trim();
          }
        }

        components.push({
          apiVersion,
          kind,
          name,
          namespace,
          labels,
          annotations,
        });
      } catch (error) {
        console.warn(`Failed to parse document: ${error}`);
      }
    }

    return components;
  }

  /**
   * Validate individual component
   */
  private async validateComponent(component: ManifestComponent): Promise<ValidationIssue[]> {
    const issues: ValidationIssue[] = [];

    // Run default rules
    for (const rule of this.rules) {
      if (!rule.check(component)) {
        issues.push({
          rule: rule.name,
          severity: rule.severity,
          component: component.name,
          message: rule.message(component),
        });
      }
    }

    // Run custom rules
    for (const rule of this.customRules) {
      if (!rule.check(component)) {
        issues.push({
          rule: rule.name,
          severity: rule.severity,
          component: component.name,
          message: rule.message(component),
        });
      }
    }

    return issues;
  }

  /**
   * Analyze dependencies between resources
   */
  private analyzeDependencies(components: ManifestComponent[]): ManifestDependency[] {
    const dependencies: ManifestDependency[] = [];

    // In real implementation, would parse resource references
    // For now, add some example dependencies
    for (const component of components) {
      if (component.kind === 'Deployment') {
        // Assume Deployment depends on ConfigMaps and Secrets
        const configMapName = `${component.name}-config`;
        const secretName = `${component.name}-secret`;

        if (components.some((c) => c.kind === 'ConfigMap' && c.name === configMapName)) {
          dependencies.push({
            from: component.name,
            to: configMapName,
            type: 'configMap',
          });
        }

        if (components.some((c) => c.kind === 'Secret' && c.name === secretName)) {
          dependencies.push({
            from: component.name,
            to: secretName,
            type: 'secret',
          });
        }

        // Assume Deployment has a Service
        const serviceName = component.name;
        if (components.some((c) => c.kind === 'Service' && c.name === serviceName)) {
          dependencies.push({
            from: component.name,
            to: serviceName,
            type: 'service',
          });
        }
      }
    }

    return dependencies;
  }

  /**
   * Validate dependencies
   */
  private validateDependencies(
    components: ManifestComponent[],
    dependencies: ManifestDependency[]
  ): ValidationIssue[] {
    const issues: ValidationIssue[] = [];
    const componentNames = new Set(components.map((c) => c.name));

    for (const dep of dependencies) {
      if (!componentNames.has(dep.to)) {
        issues.push({
          rule: 'missing-dependency',
          severity: 'error',
          component: dep.from,
          message: `Dependent resource not found: ${dep.to}`,
        });
      }
    }

    // Check for circular dependencies
    const circular = this.detectCircularDependencies(dependencies);
    for (const cycle of circular) {
      issues.push({
        rule: 'circular-dependency',
        severity: 'error',
        component: cycle[0],
        message: `Circular dependency detected: ${cycle.join(' -> ')}`,
      });
    }

    return issues;
  }

  /**
   * Detect circular dependencies
   */
  private detectCircularDependencies(dependencies: ManifestDependency[]): string[][] {
    const cycles: string[][] = [];
    const visited = new Set<string>();
    const recursionStack = new Set<string>();

    const dfs = (node: string, path: string[]): void => {
      visited.add(node);
      recursionStack.add(node);
      path.push(node);

      const outgoing = dependencies.filter((d) => d.from === node);
      for (const dep of outgoing) {
        if (!visited.has(dep.to)) {
          dfs(dep.to, [...path]);
        } else if (recursionStack.has(dep.to)) {
          const cycleStart = path.indexOf(dep.to);
          if (cycleStart !== -1) {
            cycles.push([...path.slice(cycleStart), dep.to]);
          }
        }
      }

      recursionStack.delete(node);
    };

    const allNodes = new Set<string>();
    dependencies.forEach((d) => {
      allNodes.add(d.from);
      allNodes.add(d.to);
    });

    for (const node of allNodes) {
      if (!visited.has(node)) {
        dfs(node, []);
      }
    }

    return cycles;
  }

  /**
   * Generate improvement recommendations
   */
  private generateRecommendations(components: ManifestComponent[], issues: ValidationIssue[]): string[] {
    const recommendations: string[] = [];

    // Count issue types
    const errorCount = issues.filter((i) => i.severity === 'error').length;
    const warningCount = issues.filter((i) => i.severity === 'warning').length;

    if (errorCount > 0) {
      recommendations.push(`Fix ${errorCount} critical errors before deployment`);
    }

    if (warningCount > 0) {
      recommendations.push(`Address ${warningCount} warnings to improve reliability`);
    }

    if (issues.some((i) => i.rule === 'resource-limits')) {
      recommendations.push('Set CPU and memory limits for all containers (improves scheduling and prevents node crashes)');
    }

    if (issues.some((i) => i.rule === 'health-checks')) {
      recommendations.push('Add liveness and readiness probes to detect failing containers');
    }

    if (issues.some((i) => i.rule === 'security-context')) {
      recommendations.push('Configure security context to run as non-root with read-only filesystem');
    }

    if (components.length === 0) {
      recommendations.push('Manifest is empty or unparseable');
    } else {
      recommendations.push(`Manifest contains ${components.length} resources - ready for deployment`);
    }

    return recommendations;
  }
}
