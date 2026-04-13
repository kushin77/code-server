"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ArgoCDApplicationManager = void 0;
const events_1 = require("events");
class ArgoCDApplicationManager extends events_1.EventEmitter {
    constructor() {
        super();
        this.syncInterval = null;
        this.applications = new Map();
        this.statusCache = new Map();
    }
    /**
     * Register application for GitOps management
     */
    registerApplication(app) {
        if (this.applications.has(app.name)) {
            throw new Error(`Application ${app.name} already registered`);
        }
        // Validate application configuration
        this.validateApplicationConfig(app);
        this.applications.set(app.name, app);
        this.emit('application-registered', { appName: app.name, timestamp: new Date() });
        console.log(`[ArgoCD] Registered application: ${app.name} in namespace: ${app.namespace}`);
    }
    /**
     * Validate application configuration
     */
    validateApplicationConfig(app) {
        const errors = [];
        if (!app.name || app.name.length === 0) {
            errors.push('Application name is required');
        }
        if (!app.repoUrl || app.repoUrl.length === 0) {
            errors.push('Repository URL is required');
        }
        if (!app.destServer) {
            errors.push('Destination server is required');
        }
        if (!app.destNamespace) {
            errors.push('Destination namespace is required');
        }
        if (!app.syncPolicy) {
            errors.push('Sync policy is required');
        }
        if (errors.length > 0) {
            throw new Error(`Invalid application config: ${errors.join(', ')}`);
        }
    }
    /**
     * Trigger sync for application
     */
    async syncApplication(appName, force = false) {
        const app = this.applications.get(appName);
        if (!app) {
            throw new Error(`Application ${appName} not found`);
        }
        const syncEvent = {
            applicationName: appName,
            timestamp: new Date(),
            syncStatus: 'Syncing',
            syncResult: 'In Progress',
            message: `Triggering sync for ${appName}` + (force ? ' (force)' : '')
        };
        try {
            // Trigger ArgoCD sync (simulated)
            console.log(`[ArgoCD] Syncing application: ${appName}${force ? ' (force)' : ''}`);
            // In real implementation, would call ArgoCD API:
            // await argoCDClient.sync(appName, { force });
            // Simulate sync completion
            await new Promise(resolve => setTimeout(resolve, 2000));
            syncEvent.syncStatus = 'Complete';
            syncEvent.syncResult = 'Succeeded';
            syncEvent.message = `Application ${appName} synced successfully`;
            this.emit('application-synced', syncEvent);
        }
        catch (error) {
            syncEvent.syncStatus = 'Failed';
            syncEvent.syncResult = 'Failed';
            syncEvent.message = `Sync failed: ${error.message}`;
            this.emit('sync-error', syncEvent);
            throw error;
        }
        return syncEvent;
    }
    /**
     * Get application status
     */
    async getApplicationStatus(appName) {
        const app = this.applications.get(appName);
        if (!app) {
            throw new Error(`Application ${appName} not found`);
        }
        // Check cache first
        const cached = this.statusCache.get(appName);
        if (cached && new Date().getTime() - cached.lastSyncTime.getTime() < 30000) {
            return cached;
        }
        // Fetch fresh status (simulated)
        const status = {
            name: appName,
            syncStatus: 'Synced',
            healthStatus: 'Healthy',
            lastSyncTime: new Date(),
            lastSyncStatus: 'Succeeded',
            operationInProgress: false
        };
        this.statusCache.set(appName, status);
        return status;
    }
    /**
     * Get status of all applications
     */
    async getAllApplicationStatus() {
        const statuses = [];
        for (const appName of this.applications.keys()) {
            const status = await this.getApplicationStatus(appName);
            statuses.push(status);
        }
        return statuses;
    }
    /**
     * Wait for application to be healthy
     */
    async waitForHealthy(appName, timeoutMs = 300000) {
        const startTime = Date.now();
        while (Date.now() - startTime < timeoutMs) {
            const status = await this.getApplicationStatus(appName);
            if (status.healthStatus === 'Healthy' && status.syncStatus === 'Synced') {
                return true;
            }
            // Exponential backoff
            await new Promise(resolve => setTimeout(resolve, 2000));
        }
        return false;
    }
    /**
     * Start continuous status monitoring
     */
    startMonitoring(intervalMs = 30000) {
        if (this.syncInterval) {
            console.log('[ArgoCD] Monitoring already started');
            return;
        }
        console.log(`[ArgoCD] Starting monitoring with ${intervalMs}ms interval`);
        this.syncInterval = setInterval(async () => {
            try {
                const statuses = await this.getAllApplicationStatus();
                for (const status of statuses) {
                    if (status.healthStatus !== 'Healthy') {
                        this.emit('health-degraded', {
                            applicationName: status.name,
                            healthStatus: status.healthStatus,
                            timestamp: new Date()
                        });
                        // Trigger auto-remediation if sync policy permits
                        const app = this.applications.get(status.name);
                        if (app?.syncPolicy?.automated?.selfHeal) {
                            console.log(`[ArgoCD] Auto-healing ${status.name}`);
                            await this.syncApplication(status.name);
                        }
                    }
                    if (status.syncStatus === 'OutOfSync') {
                        this.emit('drift-detected', {
                            applicationName: status.name,
                            timestamp: new Date()
                        });
                        // Auto-sync if policy permits
                        if (app?.syncPolicy?.automated) {
                            console.log(`[ArgoCD] Auto-syncing ${status.name}`);
                            await this.syncApplication(status.name);
                        }
                    }
                }
            }
            catch (error) {
                this.emit('monitoring-error', {
                    error: error.message,
                    timestamp: new Date()
                });
            }
        }, intervalMs);
    }
    /**
     * Stop monitoring
     */
    stopMonitoring() {
        if (this.syncInterval) {
            clearInterval(this.syncInterval);
            this.syncInterval = null;
            console.log('[ArgoCD] Monitoring stopped');
        }
    }
    /**
     * Delete application
     */
    async deleteApplication(appName) {
        const app = this.applications.get(appName);
        if (!app) {
            throw new Error(`Application ${appName} not found`);
        }
        this.applications.delete(appName);
        this.statusCache.delete(appName);
        this.emit('application-deleted', { appName, timestamp: new Date() });
        console.log(`[ArgoCD] Deleted application: ${appName}`);
    }
    /**
     * List all registered applications
     */
    listApplications() {
        return Array.from(this.applications.values());
    }
    /**
     * Get application config
     */
    getApplication(appName) {
        return this.applications.get(appName);
    }
    /**
     * Update application configuration
     */
    updateApplication(appName, updates) {
        const app = this.applications.get(appName);
        if (!app) {
            throw new Error(`Application ${appName} not found`);
        }
        const updated = { ...app, ...updates };
        this.validateApplicationConfig(updated);
        this.applications.set(appName, updated);
        this.emit('application-updated', { appName, timestamp: new Date() });
        console.log(`[ArgoCD] Updated application: ${appName}`);
    }
}
exports.ArgoCDApplicationManager = ArgoCDApplicationManager;
exports.default = ArgoCDApplicationManager;
//# sourceMappingURL=argocd-application-manager.js.map