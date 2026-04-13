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
export declare class ManifestValidator {
    private rules;
    private customRules;
    constructor();
    /**
     * Initialize default validation rules
     */
    private initializeDefaultRules;
    /**
     * Add custom validation rule
     */
    addCustomRule(rule: ValidationRule): void;
    /**
     * Validate manifest content
     */
    validateManifest(manifestYaml: string): Promise<ValidationResult>;
    /**
     * Parse YAML manifest into components
     */
    private parseManifest;
    /**
     * Validate individual component
     */
    private validateComponent;
    /**
     * Analyze dependencies between resources
     */
    private analyzeDependencies;
    /**
     * Validate dependencies
     */
    private validateDependencies;
    /**
     * Detect circular dependencies
     */
    private detectCircularDependencies;
    /**
     * Generate improvement recommendations
     */
    private generateRecommendations;
}
//# sourceMappingURL=ManifestValidator.d.ts.map