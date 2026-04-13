"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.GitOpsSyncStateManager = void 0;
const events_1 = require("events");
class GitOpsSyncStateManager extends events_1.EventEmitter {
    constructor() {
        super();
        this.syncStates = new Map();
        this.policies = new Map();
        this.monitors = new Map();
        this.driftHistory = new Map();
    }
    /**
     * Register application for GitOps sync management
     */
    registerApplication(appName, gitSource) {
        if (this.syncStates.has(appName)) {
            throw new Error(`Application ${appName} already registered for sync management`);
        }
        const syncState = {
            applicationName: appName,
            desiredState: {
                repository: gitSource.repo,
                revision: gitSource.revision,
                path: gitSource.path,
                hash: this.computeHash(gitSource)
            },
            actualState: {
                cluster: 'primary',
                namespace: 'default',
                resources: [],
                hash: ''
            },
            inSync: false,
            lastSyncTime: new Date()
        };
        this.syncStates.set(appName, syncState);
        this.policies.set(appName, this.getDefaultPolicy());
        this.driftHistory.set(appName, []);
        this.emit('app-registered', { appName, timestamp: new Date() });
        console.log(`[GitOps] Registered application: ${appName} for sync management`);
    }
    /**
     * Get default GitOps policy
     */
    getDefaultPolicy() {
        return {
            autoSync: true,
            autoPrune: true,
            selfHeal: true,
            syncInterval: 30000, // 30 seconds
            driftThreshold: 0.05, // 5% drift tolerance
            enforcePolicy: 'strict'
        };
    }
    /**
     * Detect drift between git and cluster state
     */
    async detectDrift(appName) {
        const state = this.syncStates.get(appName);
        if (!state) {
            throw new Error(`Application ${appName} not found`);
        }
        console.log(`[GitOps] Detecting drift for: ${appName}`);
        // Simulate drift detection
        const currentHash = this.generateRandomHash();
        const hasDrift = currentHash !== state.desiredState.hash;
        if (hasDrift) {
            state.driftDetectedTime = new Date();
            state.inSync = false;
            const driftEvent = {
                applicationName: appName,
                changedResources: state.actualState.resources,
                desiredHash: state.desiredState.hash,
                actualHash: currentHash,
                timestamp: new Date()
            };
            const history = this.driftHistory.get(appName) || [];
            history.push(driftEvent);
            this.driftHistory.set(appName, history);
            this.emit('drift-detected', driftEvent);
            console.log(`[GitOps] Drift detected in ${appName}: ${currentHash}`);
            // Auto-sync if policy permits
            const policy = this.policies.get(appName);
            if (policy.autoSync) {
                await this.syncApplication(appName);
            }
        }
        else {
            state.inSync = true;
            state.lastSyncTime = new Date();
            this.emit('in-sync', { appName, timestamp: new Date() });
        }
        return hasDrift;
    }
    /**
     * Sync application (reconcile git state with cluster)
     */
    async syncApplication(appName) {
        const state = this.syncStates.get(appName);
        if (!state) {
            throw new Error(`Application ${appName} not found`);
        }
        console.log(`[GitOps] Syncing application: ${appName}`);
        const syncAction = {
            applicationName: appName,
            action: 'sync',
            reason: 'Manual or auto-triggered sync',
            timestamp: new Date()
        };
        try {
            // Simulate apply of git state to cluster
            await new Promise(resolve => setTimeout(resolve, 1000));
            state.actualState.hash = state.desiredState.hash;
            state.inSync = true;
            state.lastSyncTime = new Date();
            this.emit('sync-succeeded', syncAction);
            console.log(`[GitOps] Sync completed for: ${appName}`);
        }
        catch (error) {
            this.emit('sync-failed', {
                ...syncAction,
                error: error.message
            });
            throw error;
        }
        return syncAction;
    }
    /**
     * Force sync (ignore safety checks)
     */
    async forceSyncApplication(appName) {
        console.log(`[GitOps] Force syncing application: ${appName}`);
        const syncAction = {
            applicationName: appName,
            action: 'force-sync',
            reason: 'Manual force sync requested',
            timestamp: new Date()
        };
        try {
            // Simulate force apply of git state
            await new Promise(resolve => setTimeout(resolve, 1500));
            const state = this.syncStates.get(appName);
            if (state) {
                state.actualState.hash = state.desiredState.hash;
                state.inSync = true;
                state.lastSyncTime = new Date();
            }
            this.emit('force-sync-succeeded', syncAction);
        }
        catch (error) {
            this.emit('force-sync-failed', { ...syncAction, error: error.message });
            throw error;
        }
        return syncAction;
    }
    /**
     * Prune orphaned resources
     */
    async pruneOrphans(appName) {
        console.log(`[GitOps] Pruning orphaned resources for: ${appName}`);
        const policy = this.policies.get(appName);
        if (policy && !policy.autoPrune) {
            console.log(`[GitOps] Pruning disabled for ${appName}`);
            return;
        }
        // Simulate pruning
        await new Promise(resolve => setTimeout(resolve, 500));
        this.emit('prune-completed', { appName, timestamp: new Date() });
    }
    /**
     * Start continuous drift monitoring
     */
    startMonitoring(appName, intervalMs) {
        if (this.monitors.has(appName)) {
            console.log(`[GitOps] Monitoring already started for ${appName}`);
            return;
        }
        const policy = this.policies.get(appName);
        const interval = intervalMs || policy?.syncInterval || 30000;
        console.log(`[GitOps] Started monitoring ${appName} every ${interval}ms`);
        const monitor = setInterval(async () => {
            try {
                await this.detectDrift(appName);
                const state = this.syncStates.get(appName);
                if (state && !state.inSync && policy?.autoSync) {
                    await this.syncApplication(appName);
                }
            }
            catch (error) {
                this.emit('monitor-error', {
                    appName,
                    error: error.message,
                    timestamp: new Date()
                });
            }
        }, interval);
        this.monitors.set(appName, monitor);
    }
    /**
     * Stop monitoring
     */
    stopMonitoring(appName) {
        const monitor = this.monitors.get(appName);
        if (monitor) {
            clearInterval(monitor);
            this.monitors.delete(appName);
            console.log(`[GitOps] Stopped monitoring ${appName}`);
        }
    }
    /**
     * Set GitOps policy
     */
    setPolicy(appName, policy) {
        const existing = this.policies.get(appName);
        if (!existing) {
            throw new Error(`Application ${appName} not found`);
        }
        const updated = { ...existing, ...policy };
        this.policies.set(appName, updated);
        this.emit('policy-updated', { appName, policy: updated, timestamp: new Date() });
        console.log(`[GitOps] Updated policy for ${appName}`);
    }
    /**
     * Get sync state
     */
    getSyncState(appName) {
        return this.syncStates.get(appName);
    }
    /**
     * Get all sync states
     */
    getAllSyncStates() {
        return Array.from(this.syncStates.values());
    }
    /**
     * Get drift history
     */
    getDriftHistory(appName) {
        return this.driftHistory.get(appName) || [];
    }
    /**
     * Helper: compute hash of git source
     */
    computeHash(source) {
        // Simulated hash computation
        return `hash-${source.repo}-${source.revision}`.slice(0, 16);
    }
    /**
     * Helper: generate random hash
     */
    generateRandomHash() {
        return `hash-${Math.random().toString(36).substring(7)}`;
    }
    /**
     * Cleanup resources
     */
    destroy() {
        for (const [appName, monitor] of this.monitors) {
            clearInterval(monitor);
        }
        this.monitors.clear();
        console.log('[GitOps] Cleanup completed');
    }
}
exports.GitOpsSyncStateManager = GitOpsSyncStateManager;
exports.default = GitOpsSyncStateManager;
//# sourceMappingURL=gitops-sync-manager.js.map