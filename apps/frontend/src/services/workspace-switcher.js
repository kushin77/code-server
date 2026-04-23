/**
 * @file        apps/frontend/src/services/workspace-switcher.ts
 * @module      collaboration/workspace-switching
 * @description Hot workspace switching handler with < 200ms latency target
 */
import { getWorkspaceStateCache, } from './workspace-state-cache.js';
/**
 * Maximum concurrent active workspaces (SLA constraint)
 */
const MAX_CONCURRENT_WORKSPACES = 5;
/**
 * Target latency for workspace switch (SLA: < 200ms)
 */
const TARGET_LATENCY_MS = 200;
/**
 * WorkspaceSwitcher: Manages hot switching between workspaces
 */
export class WorkspaceSwitcher {
    constructor() {
        this.cache = null;
        this.activeWorkspaceIds = new Set();
        this.switchMetrics = new Map();
        this.onStateChange = null;
    }
    /**
     * Initialize switcher with state cache
     */
    async initialize() {
        this.cache = await getWorkspaceStateCache();
        console.log('[WorkspaceSwitcher] Initialized');
    }
    /**
     * Register state change listener
     */
    onWorkspaceStateChange(callback) {
        this.onStateChange = callback;
    }
    /**
     * Pause current workspace (save state)
     */
    async pauseWorkspace(workspaceId, state) {
        const startTime = performance.now();
        try {
            if (!this.cache)
                throw new Error('Cache not initialized');
            // Save to IndexedDB
            await this.cache.saveState(state);
            // Remove from active set
            this.activeWorkspaceIds.delete(workspaceId);
            const elapsed = performance.now() - startTime;
            console.log(`[WorkspaceSwitcher] Paused workspace ${workspaceId} (${elapsed.toFixed(1)}ms)`);
            return elapsed;
        }
        catch (error) {
            console.error('[WorkspaceSwitcher] Failed to pause workspace:', error);
            throw error;
        }
    }
    /**
     * Resume target workspace (load state)
     */
    async resumeWorkspace(workspaceId) {
        const startTime = performance.now();
        try {
            if (!this.cache)
                throw new Error('Cache not initialized');
            // Check concurrent workspace limit
            if (this.activeWorkspaceIds.size >= MAX_CONCURRENT_WORKSPACES &&
                !this.activeWorkspaceIds.has(workspaceId)) {
                console.warn(`[WorkspaceSwitcher] Reached max concurrent workspaces (${MAX_CONCURRENT_WORKSPACES})`);
                // Could implement LRU eviction here
            }
            // Load from IndexedDB
            const state = await this.cache.loadState(workspaceId);
            // Add to active set
            this.activeWorkspaceIds.add(workspaceId);
            const elapsed = performance.now() - startTime;
            console.log(`[WorkspaceSwitcher] Resumed workspace ${workspaceId} (${elapsed.toFixed(1)}ms, cached: ${state !== null})`);
            // Notify state change listeners
            if (state && this.onStateChange) {
                this.onStateChange(state);
            }
            return {
                state,
                elapsed,
            };
        }
        catch (error) {
            console.error('[WorkspaceSwitcher] Failed to resume workspace:', error);
            throw error;
        }
    }
    /**
     * Switch from one workspace to another
     * Target: < 200ms total latency
     */
    async switchWorkspace(fromId, fromState, toId) {
        const switchStartTime = performance.now();
        console.log(`[WorkspaceSwitcher] Switching from ${fromId} to ${toId}...`);
        try {
            // Step 1: Pause current workspace
            const pauseTime = await this.pauseWorkspace(fromId, fromState);
            // Step 2: Resume target workspace
            const { state, elapsed: resumeTime } = await this.resumeWorkspace(toId);
            const totalTime = performance.now() - switchStartTime;
            const cacheHit = state !== null;
            const metrics = {
                pauseTime,
                resumeTime,
                totalTime,
                cacheHit,
            };
            // Store metrics for monitoring
            this.switchMetrics.set(toId, metrics);
            // Warn if exceeds SLA
            if (totalTime > TARGET_LATENCY_MS) {
                console.warn(`[WorkspaceSwitcher] Switch latency exceeded SLA (${totalTime.toFixed(1)}ms > ${TARGET_LATENCY_MS}ms)`);
            }
            else {
                console.log(`[WorkspaceSwitcher] Switch completed within SLA (${totalTime.toFixed(1)}ms < ${TARGET_LATENCY_MS}ms)`);
            }
            return metrics;
        }
        catch (error) {
            console.error('[WorkspaceSwitcher] Switch failed:', error);
            throw error;
        }
    }
    /**
     * Get metrics for workspace
     */
    getMetrics(workspaceId) {
        return this.switchMetrics.get(workspaceId) || null;
    }
    /**
     * Get all active workspace IDs
     */
    getActiveWorkspaceIds() {
        return Array.from(this.activeWorkspaceIds);
    }
    /**
     * Check if workspace is active
     */
    isActive(workspaceId) {
        return this.activeWorkspaceIds.has(workspaceId);
    }
    /**
     * Get performance statistics
     */
    getPerformanceStats() {
        const metrics = Array.from(this.switchMetrics.values());
        if (metrics.length === 0) {
            return {
                avgSwitchTime: 0,
                maxSwitchTime: 0,
                cacheHitRate: 0,
                activeCount: this.activeWorkspaceIds.size,
            };
        }
        const times = metrics.map((m) => m.totalTime);
        const avgTime = times.reduce((a, b) => a + b) / times.length;
        const maxTime = Math.max(...times);
        const cacheHits = metrics.filter((m) => m.cacheHit).length;
        const cacheHitRate = cacheHits / metrics.length;
        return {
            avgSwitchTime: avgTime,
            maxSwitchTime: maxTime,
            cacheHitRate,
            activeCount: this.activeWorkspaceIds.size,
        };
    }
}
/**
 * Global workspace switcher instance
 */
let switcherInstance = null;
/**
 * Get global switcher instance
 */
export async function getWorkspaceSwitcher() {
    if (!switcherInstance) {
        switcherInstance = new WorkspaceSwitcher();
        await switcherInstance.initialize();
    }
    return switcherInstance;
}
//# sourceMappingURL=workspace-switcher.js.map