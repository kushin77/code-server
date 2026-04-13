import { EventEmitter } from 'events';
/**
 * ApplicationSet Manager for ArgoCD
 *
 * Manages ApplicationSets for multi-application and multi-cluster deployments.
 * Supports templating, parameter substitution, and dynamic target generation.
 *
 * ~400 lines
 */
export interface ApplicationSetTemplate {
    apiVersion: string;
    kind: string;
    metadata: {
        name: string;
        namespace: string;
    };
    spec: {
        generators: Generator[];
        template: {
            metadata: Record<string, any>;
            spec: Record<string, any>;
        };
        syncPolicy?: Record<string, any>;
    };
}
export interface Generator {
    type: 'list' | 'cluster' | 'git' | 'matrix' | 'merge';
    selector?: Record<string, string>;
    repositories?: string[];
    template?: Record<string, any>;
}
export interface ApplicationSetTarget {
    appName: string;
    cluster: string;
    namespace: string;
    repoUrl: string;
    targetRevision: string;
    path: string;
}
export interface GenerationResult {
    appsetName: string;
    generatedCount: number;
    targets: ApplicationSetTarget[];
    timestamp: Date;
}
export declare class ApplicationSetManager extends EventEmitter {
    private appSets;
    private generatedApps;
    private clusterRegistry;
    constructor();
}
export interface ClusterInfo {
    name: string;
    server: string;
    caData: string;
    authToken: string;
    labels?: Record<string, string>;
    region?: string;
}
/**
 * ApplicationSet Manager - manages declarative multi-app deployments
 */
export declare class ApplicationSetManagerImpl extends ApplicationSetManager {
    /**
     * Register cluster for ApplicationSet generation
     */
    registerCluster(cluster: ClusterInfo): void;
    /**
     * Create ApplicationSet
     */
    createApplicationSet(template: ApplicationSetTemplate): void;
    /**
     * Validate ApplicationSet template
     */
    private validateApplicationSetTemplate;
    /**
     * Generate applications from ApplicationSet
     */
    generateApplications(appsetName: string): Promise<GenerationResult>;
    /**
     * Generate apps from cluster selector
     */
    private generateFromClusterSelector;
    /**
     * Generate apps from static list
     */
    private generateFromList;
    /**
     * Generate apps from Git directories
     */
    private generateFromGit;
    /**
     * Generate apps from matrix (cross-product)
     */
    private generateFromMatrix;
    /**
     * Get generated applications
     */
    getGeneratedApplications(appsetName: string): ApplicationSetTarget[] | undefined;
    /**
     * Update ApplicationSet
     */
    updateApplicationSet(appsetName: string, template: ApplicationSetTemplate): void;
    /**
     * Delete ApplicationSet
     */
    deleteApplicationSet(appsetName: string): void;
    /**
     * List all ApplicationSets
     */
    listApplicationSets(): ApplicationSetTemplate[];
    /**
     * List registered clusters
     */
    listClusters(): ClusterInfo[];
}
export default ApplicationSetManagerImpl;
//# sourceMappingURL=applicationset-manager.d.ts.map
