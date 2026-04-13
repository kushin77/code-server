/**
 * Phase 9: GitOps - Declarative Application Deployment
 *
 * Module exports and configuration for GitOps components
 */
export { ArgoCDApplicationManager, type ArgoCDApplication, type SyncPolicy, type ApplicationStatus, type SyncEvent } from './argocd-application-manager';
export { ApplicationSetManagerImpl, type ApplicationSetTemplate, type Generator, type ApplicationSetTarget, type GenerationResult } from './applicationset-manager';
export { GitOpsSyncStateManager, type SyncState, type ResourceStatus, type DriftEvent, type SyncAction, type GitOpsPolicy } from './gitops-sync-manager';
export declare const PHASE_9_CONFIG: {
    name: string;
    description: string;
    components: string[];
    capabilities: string[];
    metrics: {
        driftDetection: string;
        syncTime: string;
        reconciledApps: string;
        driftRate: string;
    };
};
//# sourceMappingURL=index.d.ts.map