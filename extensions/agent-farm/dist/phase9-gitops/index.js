"use strict";
/**
 * Phase 9: GitOps - Declarative Application Deployment
 *
 * Module exports and configuration for GitOps components
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.PHASE_9_CONFIG = exports.GitOpsSyncStateManager = exports.ApplicationSetManagerImpl = exports.ArgoCDApplicationManager = void 0;
var argocd_application_manager_1 = require("./argocd-application-manager");
Object.defineProperty(exports, "ArgoCDApplicationManager", { enumerable: true, get: function () { return argocd_application_manager_1.ArgoCDApplicationManager; } });
var applicationset_manager_1 = require("./applicationset-manager");
Object.defineProperty(exports, "ApplicationSetManagerImpl", { enumerable: true, get: function () { return applicationset_manager_1.ApplicationSetManagerImpl; } });
var gitops_sync_manager_1 = require("./gitops-sync-manager");
Object.defineProperty(exports, "GitOpsSyncStateManager", { enumerable: true, get: function () { return gitops_sync_manager_1.GitOpsSyncStateManager; } });
// Phase 9 configuration
exports.PHASE_9_CONFIG = {
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
console.log(`[Phase 9] ${exports.PHASE_9_CONFIG.name}: ${exports.PHASE_9_CONFIG.description}`);
console.log(`[Phase 9] Capabilities:`, exports.PHASE_9_CONFIG.capabilities);
//# sourceMappingURL=index.js.map