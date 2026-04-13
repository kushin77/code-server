/**
 * Flux Configuration Builder
 * Generates Flux CD configurations for automated GitOps deployments
 */
export interface FluxHelmConfig {
    name: string;
    namespace: string;
    chart: string;
    chartVersion: string;
    targetNamespace: string;
    values: Record<string, unknown>;
    interval: string;
    timeout: string;
    releaseName: string;
    skipCrds?: boolean;
    install?: {
        crds: 'create' | 'skip' | 'none';
    };
    upgrade?: {
        crds: 'create' | 'skip' | 'none';
    };
}
export interface FluxImagePolicy {
    name: string;
    namespace: string;
    imageRepository: string;
    policy: {
        semver?: {
            range: string;
        };
        numeric?: {
            order: 'asc' | 'desc';
        };
        alphabetical?: {
            order: 'asc' | 'desc';
        };
    };
}
export interface FluxKustomization {
    name: string;
    namespace: string;
    sourceRef: {
        kind: 'GitRepository' | 'Bucket';
        name: string;
    };
    path: string;
    interval: string;
    timeout: string;
    prune: boolean;
    force: boolean;
    postBuild?: {
        substitute?: Record<string, string>;
        substituteFrom?: Array<{
            kind: 'ConfigMap' | 'Secret';
            name: string;
        }>;
    };
    patches?: Array<{
        target: {
            group?: string;
            version: string;
            kind: string;
            name: string;
            namespace?: string;
        };
        patch: string;
    }>;
    dependsOn?: Array<{
        name: string;
        namespace?: string;
    }>;
}
export interface FluxDeploymentConfig {
    gitRepository: {
        name: string;
        namespace: string;
        url: string;
        branch: string;
        interval: string;
        timeout: string;
        authentication?: {
            type: 'ssh' | 'https' | 'token';
            secretRef: string;
        };
    };
    helmRepositories: FluxHelmConfig[];
    imagePolicies: FluxImagePolicy[];
    kustomizations: FluxKustomization[];
    imageUpdateAutomation?: {
        name: string;
        namespace: string;
        checkInterval: string;
        updateStrategy: {
            strategy: 'Setters' | 'ChartVersion';
        };
        sourceRef: {
            kind: 'GitRepository';
            name: string;
        };
        gitCommitTemplate: {
            description: string;
            author: string;
        };
        push?: {
            branch: string;
        };
    };
}
/**
 * Flux Configuration Builder
 */
export declare class FluxConfigBuilder {
    private config;
    /**
     * Create new configuration
     */
    static create(): FluxConfigBuilder;
    /**
     * Set Git repository source
     */
    setGitRepository(name: string, url: string, branch: string, interval?: string): this;
    /**
     * Add Git authentication
     */
    setGitAuthentication(type: 'ssh' | 'https' | 'token', secretRef: string): this;
    /**
     * Add Helm repository configuration
     */
    addHelmRepository(config: FluxHelmConfig): this;
    /**
     * Add image policy for automated version detection
     */
    addImagePolicy(policy: FluxImagePolicy): this;
    /**
     * Add Kustomization target
     */
    addKustomization(kustomization: FluxKustomization): this;
    /**
     * Enable automated image updates
     */
    enableImageAutomation(gitBranch?: string): this;
    /**
     * Generate Flux HelmRepository YAML
     */
    generateHelmRepositoryYaml(name: string, url: string, interval?: string): string;
    /**
     * Generate Flux HelmRelease YAML
     */
    generateHelmReleaseYaml(helmConfig: FluxHelmConfig): string;
    /**
     * Generate Flux Kustomization YAML
     */
    generateKustomizationYaml(kustomization: FluxKustomization): string;
    /**
     * Generate Flux ImageRepository YAML
     */
    generateImageRepositoryYaml(policy: FluxImagePolicy): string;
    /**
     * Generate Flux ImagePolicy YAML
     */
    generateImagePolicyYaml(policy: FluxImagePolicy): string;
    /**
     * Generate complete Flux configuration YAML
     */
    generateCompleteConfig(): string;
    /**
     * Generate Git repository source YAML
     */
    private generateGitRepositoryYaml;
    /**
     * Generate image automation YAML
     */
    private generateImageUpdateAutomationYaml;
    /**
     * Helper: convert object to YAML indented format
     */
    private mapToYaml;
    /**
     * Helper: convert object to YAML format
     */
    private objectToYaml;
    /**
     * Helper: indent multi-line string
     */
    private indentString;
    /**
     * Build the final configuration object
     */
    build(): FluxDeploymentConfig;
}
//# sourceMappingURL=FluxConfigBuilder.d.ts.map