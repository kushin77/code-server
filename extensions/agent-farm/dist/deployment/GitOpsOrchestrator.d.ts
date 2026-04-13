/**
 * GitOps Orchestrator
 * Git-based deployment orchestration with reconciliation loop
 */
export interface GitOpsConfig {
    repositoryUrl: string;
    branch: string;
    interval: number;
    retryAttempts: number;
    timeout: number;
    enableAutoSync: boolean;
    enablePruning: boolean;
    targets: DeploymentTarget[];
}
export interface RepositorySource {
    url: string;
    ref: string;
    secretRef?: string;
    username?: string;
    password?: string;
    sshKey?: Buffer;
}
export interface DeploymentTarget {
    name: string;
    namespace: string;
    cluster: string;
    region: string;
    path: string;
    kustomization?: string;
    helmRelease?: string;
    prune: boolean;
}
export interface SyncPolicy {
    automated: boolean;
    syncInterval: number;
    retryDeadline: number;
    selfHeal: boolean;
    prune: boolean;
}
export declare enum HealthStatus {
    HEALTHY = "Healthy",
    DEGRADED = "Degraded",
    PROGRESSING = "Progressing",
    UNKNOWN = "Unknown"
}
export interface ApplicationHealth {
    status: HealthStatus;
    lastUpdateTime: Date;
    resources: {
        healthy: number;
        progressing: number;
        degraded: number;
        unknown: number;
    };
    conditions: Array<{
        type: string;
        status: boolean;
        message: string;
        lastUpdateTime: Date;
    }>;
}
export interface SyncOperation {
    id: string;
    startedAt: Date;
    completedAt?: Date;
    phase: 'Pending' | 'Running' | 'Succeeded' | 'Failed' | 'Error';
    revision: string;
    message: string;
    result?: {
        resources: Array<{
            group: string;
            kind: string;
            namespace: string;
            name: string;
            status: 'Synced' | 'OutOfSync' | 'Unknown';
            message: string;
        }>;
    };
}
export interface GitOpsMetrics {
    lastSyncTime: Date;
    syncCount: number;
    failureCount: number;
    successRate: number;
    averageSyncDuration: number;
    lastHeartbeat: Date;
    health: ApplicationHealth;
    revision: string;
}
/**
 * GitOps Orchestrator - Manages Git-based deployments
 */
export declare class GitOpsOrchestrator {
    private config;
    private source;
    private syncPolicy;
    private metrics;
    private lastSyncOperation?;
    private reconciliationTimer?;
    constructor(config: GitOpsConfig, source: RepositorySource);
    /**
     * Start continuous reconciliation loop
     */
    startReconciliation(): void;
    /**
     * Stop reconciliation loop
     */
    stopReconciliation(): void;
    /**
     * Single reconciliation cycle
     */
    reconcile(): Promise<SyncOperation>;
    /**
     * Fetch latest revision from Git repository
     */
    private fetchLatestRevision;
    /**
     * Apply manifests to a deployment target
     */
    private applyToTarget;
    /**
     * Fetch manifests from Git
     */
    private fetchManifests;
    /**
     * Apply Kustomization
     */
    private applyKustomization;
    /**
     * Apply Helm Release
     */
    private applyHelmRelease;
    /**
     * Apply Kubernetes resources
     */
    private applyKubernetesResources;
    /**
     * Prune resources no longer in Git
     */
    private pruneResources;
    /**
     * Update application health status
     */
    private updateHealth;
    /**
     * Query health from all clusters
     */
    private queryClusterHealth;
    /**
     * Get current metrics
     */
    getMetrics(): GitOpsMetrics;
    /**
     * Get last sync operation
     */
    getLastSyncOperation(): SyncOperation | undefined;
    /**
     * Update Git repository source
     */
    updateSource(newSource: RepositorySource): void;
    /**
     * Check if currently in sync with Git
     */
    isInSync(): boolean;
    /**
     * Force immediate sync (ignoring interval)
     */
    forceSync(): Promise<SyncOperation>;
}
//# sourceMappingURL=GitOpsOrchestrator.d.ts.map
