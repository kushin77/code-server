import { EventEmitter } from 'events';
/**
 * ArgoCD Application Manager
 *
 * Manages ArgoCD Application resources for declarative application deployment.
 * Handles syncing, health assessment, and automatic remediation.
 *
 * ~380 lines
 */
export interface ArgoCDApplication {
    name: string;
    namespace: string;
    repoUrl: string;
    targetRevision: string;
    path: string;
    destServer: string;
    destNamespace: string;
    syncPolicy: SyncPolicy;
    project: string;
    labels?: Record<string, string>;
    annotations?: Record<string, string>;
}
export interface SyncPolicy {
    automated?: {
        prune: boolean;
        selfHeal: boolean;
        allowEmpty: boolean;
    };
    syncOptions?: string[];
    retry?: {
        limit: number;
        backoff: {
            duration: string;
            factor: number;
            maxDuration: string;
        };
    };
}
export interface ApplicationStatus {
    name: string;
    syncStatus: 'Synced' | 'OutOfSync' | 'Unknown';
    healthStatus: 'Healthy' | 'Progressing' | 'Degraded' | 'Unknown';
    lastSyncTime: Date;
    lastSyncStatus: 'Succeeded' | 'Failed' | 'Unknown';
    operationInProgress: boolean;
}
export interface SyncEvent {
    applicationName: string;
    timestamp: Date;
    syncStatus: string;
    syncResult: string;
    message: string;
}
export declare class ArgoCDApplicationManager extends EventEmitter {
    private applications;
    private statusCache;
    private syncInterval;
    private kubeClient;
    constructor();
    /**
     * Register application for GitOps management
     */
    registerApplication(app: ArgoCDApplication): void;
    /**
     * Validate application configuration
     */
    private validateApplicationConfig;
    /**
     * Trigger sync for application
     */
    syncApplication(appName: string, force?: boolean): Promise<SyncEvent>;
    /**
     * Get application status
     */
    getApplicationStatus(appName: string): Promise<ApplicationStatus>;
    /**
     * Get status of all applications
     */
    getAllApplicationStatus(): Promise<ApplicationStatus[]>;
    /**
     * Wait for application to be healthy
     */
    waitForHealthy(appName: string, timeoutMs?: number): Promise<boolean>;
    /**
     * Start continuous status monitoring
     */
    startMonitoring(intervalMs?: number): void;
    /**
     * Stop monitoring
     */
    stopMonitoring(): void;
    /**
     * Delete application
     */
    deleteApplication(appName: string): Promise<void>;
    /**
     * List all registered applications
     */
    listApplications(): ArgoCDApplication[];
    /**
     * Get application config
     */
    getApplication(appName: string): ArgoCDApplication | undefined;
    /**
     * Update application configuration
     */
    updateApplication(appName: string, updates: Partial<ArgoCDApplication>): void;
}
export default ArgoCDApplicationManager;
//# sourceMappingURL=argocd-application-manager.d.ts.map