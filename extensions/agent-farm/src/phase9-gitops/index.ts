/**
 * Phase 9: GitOps - Declarative Application Deployment
 * 
 * Module exports and configuration for GitOps components
 */

export { ArgoCDApplicationManager, type ArgoCDApplication, type SyncPolicy, type ApplicationStatus, type SyncEvent } from './argocd-application-manager';
export { ApplicationSetManagerImpl, type ApplicationSetTemplate, type Generator, type ApplicationSetTarget, type GenerationResult } from './applicationset-manager';
export { GitOpsSyncStateManager, type SyncState, type ResourceStatus, type DriftEvent, type SyncAction, type GitOpsPolicy } from './gitops-sync-manager';

// Phase 9 configuration
export const PHASE_9_CONFIG = {
  name: 'GitOps',
  description: 'Declarative application deployment with ArgoCD',
  components: [
    'ArgoCDApplicationManager',
    'ApplicationSetManager',
    'GitOpsSyncStateManager'
  ],
  capabilities: [
    'Declarative application definitions',
    'Multi-cluster deployments via ApplicationSets',
    'Automatic drift detection and remediation',
    'Git-driven state synchronization',
    'Template-based application generation',
    'Policy-driven deployment automation',
    'Continuous reconciliation monitoring'
  ],
  metrics: {
    driftDetection: 'milliseconds to detect git/cluster divergence',
    syncTime: 'time to apply git state to cluster',
    reconciledApps: 'number of applications under GitOps control',
    driftRate: 'percentage of time cluster differs from git'
  }
};

// Initialize phase
console.log(`[Phase 9] ${PHASE_9_CONFIG.name}: ${PHASE_9_CONFIG.description}`);
console.log(`[Phase 9] Capabilities:`, PHASE_9_CONFIG.capabilities);
