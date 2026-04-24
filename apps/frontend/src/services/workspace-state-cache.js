/**
 * @file        apps/frontend/src/services/workspace-state-cache.ts
 * @module      collaboration/workspace-switching
 * @description IndexedDB-backed workspace state persistence for hot switching
 */
/**
 * IndexedDB schema and operations
 */
export const WORKSPACE_STATE_DB = {
    name: 'code-server-workspaces',
    version: 1,
    stores: {
        states: {
            keyPath: 'workspaceId',
            indexes: [{ name: 'timestamp', keyPath: 'timestamp' }],
        },
    },
};
/**
 * WorkspaceStateCache: Manages IndexedDB storage for workspace state
 */
export class WorkspaceStateCache {
    constructor() {
        this.db = null;
        this.isInitialized = false;
    }
    /**
     * Initialize IndexedDB connection
     */
    async initialize() {
        if (this.isInitialized)
            return;
        return new Promise((resolve, reject) => {
            const request = indexedDB.open(WORKSPACE_STATE_DB.name, WORKSPACE_STATE_DB.version);
            request.onerror = () => {
                console.error('[WorkspaceStateCache] Failed to open IndexedDB:', request.error);
                reject(request.error);
            };
            request.onsuccess = () => {
                this.db = request.result;
                this.isInitialized = true;
                console.log('[WorkspaceStateCache] Initialized');
                resolve();
            };
            request.onupgradeneeded = (event) => {
                const db = event.target.result;
                // Create object stores
                if (!db.objectStoreNames.contains('states')) {
                    const store = db.createObjectStore('states', {
                        keyPath: WORKSPACE_STATE_DB.stores.states.keyPath,
                    });
                    // Create indexes
                    store.createIndex('timestamp', 'timestamp', { unique: false });
                }
            };
        });
    }
    /**
     * Save workspace state
     */
    async saveState(state) {
        if (!this.db)
            throw new Error('Cache not initialized');
        return new Promise((resolve, reject) => {
            const tx = this.db.transaction(['states'], 'readwrite');
            const store = tx.objectStore('states');
            const request = store.put({
                ...state,
                timestamp: Date.now(),
            });
            request.onerror = () => {
                console.error('[WorkspaceStateCache] Failed to save state:', request.error);
                reject(request.error);
            };
            request.onsuccess = () => {
                console.log(`[WorkspaceStateCache] Saved state for workspace ${state.workspaceId}`);
                resolve();
            };
        });
    }
    /**
     * Load workspace state
     */
    async loadState(workspaceId) {
        if (!this.db)
            throw new Error('Cache not initialized');
        return new Promise((resolve, reject) => {
            const tx = this.db.transaction(['states'], 'readonly');
            const store = tx.objectStore('states');
            const request = store.get(workspaceId);
            request.onerror = () => {
                console.error('[WorkspaceStateCache] Failed to load state:', request.error);
                reject(request.error);
            };
            request.onsuccess = () => {
                const state = request.result;
                if (state) {
                    console.log(`[WorkspaceStateCache] Loaded state for workspace ${workspaceId} (age: ${Date.now() - state.timestamp}ms)`);
                }
                resolve(state || null);
            };
        });
    }
    /**
     * Delete workspace state
     */
    async deleteState(workspaceId) {
        if (!this.db)
            throw new Error('Cache not initialized');
        return new Promise((resolve, reject) => {
            const tx = this.db.transaction(['states'], 'readwrite');
            const store = tx.objectStore('states');
            const request = store.delete(workspaceId);
            request.onerror = () => {
                console.error('[WorkspaceStateCache] Failed to delete state:', request.error);
                reject(request.error);
            };
            request.onsuccess = () => {
                console.log(`[WorkspaceStateCache] Deleted state for workspace ${workspaceId}`);
                resolve();
            };
        });
    }
    /**
     * Get all cached workspaces
     */
    async getAllCached() {
        if (!this.db)
            throw new Error('Cache not initialized');
        return new Promise((resolve, reject) => {
            const tx = this.db.transaction(['states'], 'readonly');
            const store = tx.objectStore('states');
            const request = store.getAll();
            request.onerror = () => {
                reject(request.error);
            };
            request.onsuccess = () => {
                resolve(request.result);
            };
        });
    }
    /**
     * Clear all cached states
     */
    async clear() {
        if (!this.db)
            throw new Error('Cache not initialized');
        return new Promise((resolve, reject) => {
            const tx = this.db.transaction(['states'], 'readwrite');
            const store = tx.objectStore('states');
            const request = store.clear();
            request.onerror = () => {
                reject(request.error);
            };
            request.onsuccess = () => {
                console.log('[WorkspaceStateCache] Cleared all states');
                resolve();
            };
        });
    }
    /**
     * Get cache size statistics
     */
    async getStats() {
        const states = await this.getAllCached();
        if (states.length === 0) {
            return {
                cachedCount: 0,
                oldestTimestamp: null,
                newestTimestamp: null,
            };
        }
        const timestamps = states.map((s) => s.timestamp).sort((a, b) => a - b);
        return {
            cachedCount: states.length,
            oldestTimestamp: timestamps[0],
            newestTimestamp: timestamps[timestamps.length - 1],
        };
    }
}
/**
 * Global workspace state cache instance
 */
let cacheInstance = null;
/**
 * Get global cache instance
 */
export async function getWorkspaceStateCache() {
    if (!cacheInstance) {
        cacheInstance = new WorkspaceStateCache();
        await cacheInstance.initialize();
    }
    return cacheInstance;
}
//# sourceMappingURL=workspace-state-cache.js.map