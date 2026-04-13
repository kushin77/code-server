import { EventEmitter } from 'events';
/**
 * GitOps Sync State Manager
 *
 * Monitors and enforces git-driven state in Kubernetes cluster.
 * Reconciles desired (git) vs actual (cluster) state.
 *
 * ~380 lines
 */
export interface SyncState {
    applicationName: string;
    desiredState: {
        repository: string;
        revision: string;
        path: string;
        hash: string;
    };
    actualState: {
        cluster: string;
        namespace: string;
        resources: ResourceStatus[];
        hash: string;
    };
    inSync: boolean;
    lastSyncTime: Date;
    driftDetectedTime?: Date;
}
export interface ResourceStatus {
    kind: string;
    name: string;
    namespace: string;
    syncStatus: 'Synced' | 'OutOfSync' | 'Unknown';
    healthStatus: 'Healthy' | 'Progressing' | 'Degraded' | 'Missing';
}
export interface DriftEvent {
    applicationName: string;
    changedResources: ResourceStatus[];
    desiredHash: string;
    actualHash: string;
    timestamp: Date;
}
export interface SyncAction {
    applicationName: string;
    action: 'sync' | 'prune' | 'force-sync';
    reason: string;
    dryRun?: boolean;
    timestamp: Date;
}
export interface GitOpsPolicy {
    autoSync: boolean;
    autoPrune: boolean;
    selfHeal: boolean;
    syncInterval: number;
    driftThreshold: number;
    enforcePolicy: 'strict' | 'lenient';
}
export declare class GitOpsSyncStateManager extends EventEmitter {
    private syncStates;
    private policies;
    private monitors;
    private driftHistory;
    constructor();
    /**
     * Register application for GitOps sync management
     */
    registerApplication(appName: string, gitSource: {
        repo: string;
        revision: string;
        path: string;
    }): void;
    /**
     * Get default GitOps policy
     */
    private getDefaultPolicy;
    /**
     * Detect drift between git and cluster state
     */
    detectDrift(appName: string): Promise<boolean>;
    /**
     * Sync application (reconcile git state with cluster)
     */
    syncApplication(appName: string): Promise<SyncAction>;
    /**
     * Force sync (ignore safety checks)
     */
    forceSyncApplication(appName: string): Promise<SyncAction>;
    /**
     * Prune orphaned resources
     */
    pruneOrphans(appName: string): Promise<void>;
    /**
     * Start continuous drift monitoring
     */
    startMonitoring(appName: string, intervalMs?: number): void;
    /**
     * Stop monitoring
     */
    stopMonitoring(appName: string): void;
    /**
     * Set GitOps policy
     */
    setPolicy(appName: string, policy: Partial<GitOpsPolicy>): void;
    /**
     * Get sync state
     */
    getSyncState(appName: string): SyncState | undefined;
    /**
     * Get all sync states
     */
    getAllSyncStates(): SyncState[];
    /**
     * Get drift history
     */
    getDriftHistory(appName: string): DriftEvent[];
    /**
     * Helper: compute hash of git source
     */
    private computeHash;
    /**
     * Helper: generate random hash
     */
    private generateRandomHash;
    /**
     * Cleanup resources
     */
    destroy(): void;
}
export default GitOpsSyncStateManager;
//# sourceMappingURL=gitops-sync-manager.d.ts.map
