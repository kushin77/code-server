// apps/backend/src/services/workspace/hot-switch-service.ts
// @file: Hot Workspace Switching Service
// @module: workspace-hot-switch
// @description: Fast workspace switching (<200ms) with IndexedDB state persistence and 5 concurrent limit
//
// Features:
// - Sub-200ms workspace switches
// - IndexedDB-backed state persistence
// - 5 concurrent workspace maximum
// - Performance tracking and metrics
// - State serialization and restoration
import { EventEmitter } from "events";
/**
 * Hot Workspace Switching Service
 */
export class HotWorkspaceSwitchService extends EventEmitter {
    constructor() {
        super();
        this.workspaces = new Map();
        this.activeWorkspace = null;
        this.maxConcurrentWorkspaces = 5;
        this.switchMetrics = [];
        this.lastSwitchTime = 0;
    }
    /**
     * Register a workspace for hot switching
     */
    registerWorkspace(state) {
        try {
            if (this.workspaces.size >= this.maxConcurrentWorkspaces) {
                return {
                    success: false,
                    error: `Maximum concurrent workspaces (${this.maxConcurrentWorkspaces}) reached. Close a workspace first.`,
                };
            }
            this.workspaces.set(state.id, { ...state, isActive: false });
            this.emit("workspace-registered", {
                workspaceId: state.id,
                name: state.name,
                timestamp: new Date(),
            });
            return { success: true, workspaceId: state.id };
        }
        catch (error) {
            const err = error;
            return { success: false, error: err.message };
        }
    }
    /**
     * Switch to a different workspace (<200ms requirement)
     */
    switchWorkspace(fromWorkspaceId, toWorkspaceId) {
        const startTime = Date.now();
        const metrics = {
            fromWorkspace: fromWorkspaceId || "none",
            toWorkspace: toWorkspaceId,
            startTime: new Date(startTime),
            success: false,
        };
        try {
            if (!this.workspaces.has(toWorkspaceId)) {
                metrics.error = "Target workspace not found";
                this.recordMetrics(metrics);
                return { success: false, error: "Target workspace not found" };
            }
            // Deactivate current workspace
            if (this.activeWorkspace) {
                const currentWorkspace = this.workspaces.get(this.activeWorkspace);
                if (currentWorkspace) {
                    currentWorkspace.isActive = false;
                }
            }
            // Activate new workspace
            const newWorkspace = this.workspaces.get(toWorkspaceId);
            if (newWorkspace) {
                newWorkspace.isActive = true;
                newWorkspace.timestamp = new Date();
            }
            this.activeWorkspace = toWorkspaceId;
            const endTime = Date.now();
            const duration = endTime - startTime;
            metrics.endTime = new Date(endTime);
            metrics.duration = duration;
            metrics.success = true;
            this.lastSwitchTime = endTime;
            this.recordMetrics(metrics);
            // Check if we met the <200ms requirement
            const withinRequirement = duration < 200;
            this.emit("workspace-switched", {
                fromWorkspace: fromWorkspaceId,
                toWorkspace: toWorkspaceId,
                duration,
                withinRequirement,
                timestamp: new Date(),
            });
            return { success: true, duration };
        }
        catch (error) {
            const err = error;
            metrics.error = err.message;
            metrics.success = false;
            this.recordMetrics(metrics);
            return { success: false, error: err.message };
        }
    }
    /**
     * Get current active workspace
     */
    getActiveWorkspace() {
        if (!this.activeWorkspace)
            return null;
        return this.workspaces.get(this.activeWorkspace) || null;
    }
    /**
     * Get all registered workspaces
     */
    getWorkspaces() {
        return Array.from(this.workspaces.values());
    }
    /**
     * Get workspace by ID
     */
    getWorkspace(workspaceId) {
        return this.workspaces.get(workspaceId) || null;
    }
    /**
     * Close and unregister a workspace
     */
    closeWorkspace(workspaceId) {
        try {
            if (!this.workspaces.has(workspaceId)) {
                return { success: false, error: "Workspace not found" };
            }
            const workspace = this.workspaces.get(workspaceId);
            // If closing active workspace, switch to another one
            if (this.activeWorkspace === workspaceId) {
                const otherWorkspace = Array.from(this.workspaces.values()).find((w) => w.id !== workspaceId);
                if (otherWorkspace) {
                    this.switchWorkspace(workspaceId, otherWorkspace.id);
                }
                else {
                    this.activeWorkspace = null;
                }
            }
            this.workspaces.delete(workspaceId);
            this.emit("workspace-closed", {
                workspaceId,
                timestamp: new Date(),
            });
            return { success: true };
        }
        catch (error) {
            const err = error;
            return { success: false, error: err.message };
        }
    }
    /**
     * Update workspace state (e.g., file changes, cursor position)
     */
    updateWorkspaceState(workspaceId, updates) {
        try {
            const workspace = this.workspaces.get(workspaceId);
            if (!workspace) {
                return { success: false, error: "Workspace not found" };
            }
            Object.assign(workspace, updates, { timestamp: new Date() });
            return { success: true };
        }
        catch (error) {
            const err = error;
            return { success: false, error: err.message };
        }
    }
    /**
     * Serialize workspace state for IndexedDB persistence
     */
    serializeWorkspace(workspaceId) {
        try {
            const workspace = this.workspaces.get(workspaceId);
            if (!workspace) {
                return { success: false, error: "Workspace not found" };
            }
            const serialized = JSON.stringify(workspace);
            return { success: true, data: serialized };
        }
        catch (error) {
            const err = error;
            return { success: false, error: err.message };
        }
    }
    /**
     * Deserialize workspace state from IndexedDB
     */
    deserializeWorkspace(data) {
        try {
            const state = JSON.parse(data);
            state.timestamp = new Date(state.timestamp);
            return { success: true, state };
        }
        catch (error) {
            const err = error;
            return { success: false, error: err.message };
        }
    }
    /**
     * Get performance metrics for workspace switches
     */
    getMetrics(limit = 100) {
        return this.switchMetrics.slice(-limit);
    }
    /**
     * Get average switch time
     */
    getAverageSwitchTime() {
        if (this.switchMetrics.length === 0)
            return 0;
        const totalTime = this.switchMetrics.reduce((sum, m) => sum + (m.duration || 0), 0);
        return Math.round((totalTime / this.switchMetrics.length) * 100) / 100;
    }
    /**
     * Get switch time percentile
     */
    getSwitchTimePercentile(percentile) {
        if (this.switchMetrics.length === 0)
            return 0;
        const sorted = this.switchMetrics
            .filter((m) => m.duration !== undefined)
            .map((m) => m.duration)
            .sort((a, b) => a - b);
        const index = Math.ceil((percentile / 100) * sorted.length) - 1;
        return sorted[Math.max(0, index)] || 0;
    }
    /**
     * Get percentage of switches meeting <200ms requirement
     */
    getPercentageWithinRequirement() {
        if (this.switchMetrics.length === 0)
            return 0;
        const withinRequirement = this.switchMetrics.filter((m) => m.duration !== undefined && m.duration < 200).length;
        return Math.round((withinRequirement / this.switchMetrics.length) * 10000) / 100;
    }
    /**
     * Get workspace count
     */
    getWorkspaceCount() {
        return this.workspaces.size;
    }
    /**
     * Get concurrent workspace limit
     */
    getConcurrentLimit() {
        return this.maxConcurrentWorkspaces;
    }
    /**
     * Get switching statistics
     */
    getStatistics() {
        const failedSwitches = this.switchMetrics.filter((m) => !m.success).length;
        return {
            totalWorkspaces: this.workspaces.size,
            activeWorkspace: this.activeWorkspace,
            maxConcurrent: this.maxConcurrentWorkspaces,
            totalSwitches: this.switchMetrics.length,
            averageSwitchTime: this.getAverageSwitchTime(),
            p95SwitchTime: this.getSwitchTimePercentile(95),
            p99SwitchTime: this.getSwitchTimePercentile(99),
            percentageWithinRequirement: this.getPercentageWithinRequirement(),
            failedSwitches,
        };
    }
    /**
     * Reset metrics (for testing)
     */
    resetMetrics() {
        this.switchMetrics = [];
    }
    /**
     * Get time since last switch
     */
    getTimeSinceLastSwitch() {
        if (this.lastSwitchTime === 0)
            return -1;
        return Date.now() - this.lastSwitchTime;
    }
    // ========== Private Methods ==========
    /**
     * Record metrics for a switch operation
     */
    recordMetrics(metrics) {
        this.switchMetrics.push(metrics);
        // Keep only last 1000 metrics
        if (this.switchMetrics.length > 1000) {
            this.switchMetrics = this.switchMetrics.slice(-1000);
        }
    }
}
// Singleton instance
let serviceInstance = null;
/**
 * Get or initialize the Hot Workspace Switch Service
 */
export function getHotWorkspaceSwitchService() {
    if (!serviceInstance) {
        serviceInstance = new HotWorkspaceSwitchService();
    }
    return serviceInstance;
}
/**
 * Initialize the service (for testing)
 */
export function initHotWorkspaceSwitchService() {
    serviceInstance = new HotWorkspaceSwitchService();
    return serviceInstance;
}
//# sourceMappingURL=hot-switch-service.js.map