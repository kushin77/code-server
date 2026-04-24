/**
 * @file        apps/frontend/src/services/workspace-switcher.ts
 * @module      collaboration/workspace-switching
 * @description Hot workspace switching handler with < 200ms latency target
 */

import {
  WorkspaceStateCache,
  CachedWorkspaceState,
  getWorkspaceStateCache,
} from './workspace-state-cache.js';

/**
 * Workspace switching performance metrics
 */
export interface SwitchMetrics {
  pauseTime: number; // Time to pause current workspace
  resumeTime: number; // Time to resume target workspace
  totalTime: number; // Total switch time
  cacheHit: boolean; // Whether state was cached
}

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
  private cache: WorkspaceStateCache | null = null;
  private activeWorkspaceIds = new Set<string>();
  private switchMetrics: Map<string, SwitchMetrics> = new Map();
  private onStateChange: ((state: CachedWorkspaceState) => void) | null = null;

  /**
   * Initialize switcher with state cache
   */
  async initialize(): Promise<void> {
    this.cache = await getWorkspaceStateCache();
    console.log('[WorkspaceSwitcher] Initialized');
  }

  /**
   * Register state change listener
   */
  onWorkspaceStateChange(
    callback: (state: CachedWorkspaceState) => void
  ): void {
    this.onStateChange = callback;
  }

  /**
   * Pause current workspace (save state)
   */
  async pauseWorkspace(
    workspaceId: string,
    state: CachedWorkspaceState
  ): Promise<number> {
    const startTime = performance.now();

    try {
      if (!this.cache) throw new Error('Cache not initialized');

      // Save to IndexedDB
      await this.cache.saveState(state);

      // Remove from active set
      this.activeWorkspaceIds.delete(workspaceId);

      const elapsed = performance.now() - startTime;
      console.log(
        `[WorkspaceSwitcher] Paused workspace ${workspaceId} (${elapsed.toFixed(1)}ms)`
      );

      return elapsed;
    } catch (error) {
      console.error('[WorkspaceSwitcher] Failed to pause workspace:', error);
      throw error;
    }
  }

  /**
   * Resume target workspace (load state)
   */
  async resumeWorkspace(workspaceId: string): Promise<{
    state: CachedWorkspaceState | null;
    elapsed: number;
  }> {
    const startTime = performance.now();

    try {
      if (!this.cache) throw new Error('Cache not initialized');

      // Check concurrent workspace limit
      if (
        this.activeWorkspaceIds.size >= MAX_CONCURRENT_WORKSPACES &&
        !this.activeWorkspaceIds.has(workspaceId)
      ) {
        console.warn(
          `[WorkspaceSwitcher] Reached max concurrent workspaces (${MAX_CONCURRENT_WORKSPACES})`
        );
        // Could implement LRU eviction here
      }

      // Load from IndexedDB
      const state = await this.cache.loadState(workspaceId);

      // Add to active set
      this.activeWorkspaceIds.add(workspaceId);

      const elapsed = performance.now() - startTime;
      console.log(
        `[WorkspaceSwitcher] Resumed workspace ${workspaceId} (${elapsed.toFixed(1)}ms, cached: ${state !== null})`
      );

      // Notify state change listeners
      if (state && this.onStateChange) {
        this.onStateChange(state);
      }

      return {
        state,
        elapsed,
      };
    } catch (error) {
      console.error('[WorkspaceSwitcher] Failed to resume workspace:', error);
      throw error;
    }
  }

  /**
   * Switch from one workspace to another
   * Target: < 200ms total latency
   */
  async switchWorkspace(
    fromId: string,
    fromState: CachedWorkspaceState,
    toId: string
  ): Promise<SwitchMetrics> {
    const switchStartTime = performance.now();
    console.log(
      `[WorkspaceSwitcher] Switching from ${fromId} to ${toId}...`
    );

    try {
      // Step 1: Pause current workspace
      const pauseTime = await this.pauseWorkspace(fromId, fromState);

      // Step 2: Resume target workspace
      const { state, elapsed: resumeTime } = await this.resumeWorkspace(toId);

      const totalTime = performance.now() - switchStartTime;
      const cacheHit = state !== null;

      const metrics: SwitchMetrics = {
        pauseTime,
        resumeTime,
        totalTime,
        cacheHit,
      };

      // Store metrics for monitoring
      this.switchMetrics.set(toId, metrics);

      // Warn if exceeds SLA
      if (totalTime > TARGET_LATENCY_MS) {
        console.warn(
          `[WorkspaceSwitcher] Switch latency exceeded SLA (${totalTime.toFixed(1)}ms > ${TARGET_LATENCY_MS}ms)`
        );
      } else {
        console.log(
          `[WorkspaceSwitcher] Switch completed within SLA (${totalTime.toFixed(1)}ms < ${TARGET_LATENCY_MS}ms)`
        );
      }

      return metrics;
    } catch (error) {
      console.error('[WorkspaceSwitcher] Switch failed:', error);
      throw error;
    }
  }

  /**
   * Get metrics for workspace
   */
  getMetrics(workspaceId: string): SwitchMetrics | null {
    return this.switchMetrics.get(workspaceId) || null;
  }

  /**
   * Get all active workspace IDs
   */
  getActiveWorkspaceIds(): string[] {
    return Array.from(this.activeWorkspaceIds);
  }

  /**
   * Check if workspace is active
   */
  isActive(workspaceId: string): boolean {
    return this.activeWorkspaceIds.has(workspaceId);
  }

  /**
   * Get performance statistics
   */
  getPerformanceStats(): {
    avgSwitchTime: number;
    maxSwitchTime: number;
    cacheHitRate: number;
    activeCount: number;
  } {
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
let switcherInstance: WorkspaceSwitcher | null = null;

/**
 * Get global switcher instance
 */
export async function getWorkspaceSwitcher(): Promise<WorkspaceSwitcher> {
  if (!switcherInstance) {
    switcherInstance = new WorkspaceSwitcher();
    await switcherInstance.initialize();
  }
  return switcherInstance;
}
