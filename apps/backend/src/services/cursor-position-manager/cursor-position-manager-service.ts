/**
 * Real-time Cursor Position Manager Service
 * @file        apps/backend/src/services/cursor-position-manager/cursor-position-manager-service.ts
 * @module      services/cursor-position-manager
 * @description Real-time cursor position tracking for collaborative editing
 */

import { EventEmitter } from 'events';
import {
  CursorPosition,
  UserCursorState,
  CursorUpdate,
  CursorVisibilitySettings,
  CursorSyncState,
  CursorConflict,
  CursorPresence,
  CursorHistoryEntry,
  CursorStatistics,
  CursorJumpEvent,
  UserViewportState,
  ViewportFocusArea,
  CursorBroadcast,
  CursorAuditEntry,
  CursorPositionConfig,
  ICursorPositionService,
} from './types.js';

/**
 * Cursor Position Manager Service
 * Tracks and broadcasts real-time cursor positions for collaborative editing
 */
export class CursorPositionManager extends EventEmitter implements ICursorPositionService {
  private static instance: CursorPositionManager | undefined;
  private cursors: Map<string, UserCursorState> = new Map(); // userId:fileId -> state
  private fileCursors: Map<string, Set<string>> = new Map(); // fileId -> userIds
  private history: Map<string, CursorHistoryEntry[]> = new Map(); // fileId -> entries
  private conflicts: Map<string, CursorConflict[]> = new Map(); // fileId -> conflicts
  private jumps: Map<string, CursorJumpEvent[]> = new Map(); // userId -> jumps
  private viewports: Map<string, UserViewportState> = new Map(); // userId:fileId -> viewport
  private visibilitySettings: Map<string, CursorVisibilitySettings> = new Map(); // userId -> settings
  private auditLog: Map<string, CursorAuditEntry[]> = new Map(); // userId -> entries
  private stats: CursorStatistics = {
    totalCursorsTracked: 0,
    activeCursors: 0,
    inactiveCursors: 0,
    totalFiles: 0,
    averageCursorMovementPerSecond: 0,
    mostActiveCursor: null,
    conflictDetectionAccuracy: 0,
  };
  private config: CursorPositionConfig = {
    enableTracking: true,
    inactivityThreshold: 30000, // 30 seconds
    maxHistoryEntries: 10000,
    maxAuditEntries: 5000,
    conflictDetectionEnabled: true,
    broadcastInterval: 100, // 100ms
    broadcastBatchSize: 50,
  };

  private constructor() {
    super();
    this.initialize();
  }

  /**
   * Get or create singleton instance
   */
  public static getInstance(config?: Partial<CursorPositionConfig>): CursorPositionManager {
    if (!CursorPositionManager.instance) {
      CursorPositionManager.instance = new CursorPositionManager();
    }
    if (config) {
      CursorPositionManager.instance.updateConfig(config);
    }
    return CursorPositionManager.instance;
  }

  /**
   * Reset singleton for testing
   */
  public static reset(): void {
    CursorPositionManager.instance = undefined;
  }

  /**
   * Initialize service
   */
  private initialize(): void {
    this.emit('initialized', {
      data_object: { service: 'cursor-position-manager', status: 'initialized' },
      timestamp: Date.now(),
    });
  }

  /**
   * Update cursor position
   */
  public updateCursorPosition(
    userId: string,
    userEmail: string,
    userName: string,
    fileId: string,
    position: CursorPosition,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      if (!this.config.enableTracking) {
        return { success: false };
      }

      const key = `${userId}:${fileId}`;
      const oldState = this.cursors.get(key);
      const movementDistance = oldState ? this.calculateDistance(oldState.position, position) : 0;

      const newState: UserCursorState = {
        userId,
        userEmail,
        userName,
        fileId,
        position,
        lastUpdated: Date.now(),
        isActive: true,
        color: this.generateUserColor(userId),
      };

      this.cursors.set(key, newState);

      if (!this.fileCursors.has(fileId)) {
        this.fileCursors.set(fileId, new Set());
      }
      this.fileCursors.get(fileId)!.add(userId);

      // Record in history
      if (oldState) {
        this.recordHistory(fileId, userId, oldState.position, position, movementDistance);
      }

      this.logAudit(userId, 'update-cursor-position', fileId, 'success', {
        position,
        movementDistance,
      });

      this.emit('cursor-position-updated', {
        data_object: { userId, fileId, position },
        timestamp: Date.now(),
      });

      // Check for conflicts
      if (this.config.conflictDetectionEnabled) {
        this.detectConflicts(fileId);
      }

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'update-cursor-position', fileId, 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Update cursor selection
   */
  public updateCursorSelection(
    userId: string,
    fileId: string,
    selectionStart: CursorPosition,
    selectionEnd: CursorPosition,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const key = `${userId}:${fileId}`;
      const state = this.cursors.get(key);

      if (!state) {
        return { success: false };
      }

      state.selectionStart = selectionStart;
      state.selectionEnd = selectionEnd;
      state.lastUpdated = Date.now();

      this.logAudit(userId, 'update-selection', fileId, 'success', {
        selectionStart,
        selectionEnd,
      });

      this.emit('cursor-selection-updated', {
        data_object: { userId, fileId, selectionStart, selectionEnd },
        timestamp: Date.now(),
      });

      // Check for conflicts
      if (this.config.conflictDetectionEnabled) {
        this.detectConflicts(fileId);
      }

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'update-selection', fileId, 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get cursor position
   */
  public getCursorPosition(userId: string, fileId: string): CursorPosition | undefined {
    const key = `${userId}:${fileId}`;
    return this.cursors.get(key)?.position;
  }

  /**
   * Get cursors in file
   */
  public getCursorsInFile(fileId: string): UserCursorState[] {
    const userIds = this.fileCursors.get(fileId) || new Set();
    const cursors: UserCursorState[] = [];

    for (const userId of userIds) {
      const key = `${userId}:${fileId}`;
      const state = this.cursors.get(key);
      if (state) {
        cursors.push(state);
      }
    }

    return cursors;
  }

  /**
   * Get cursors by user
   */
  public getCursorsByUser(userId: string): UserCursorState[] {
    const cursors: UserCursorState[] = [];

    for (const [key, state] of this.cursors) {
      if (state.userId === userId) {
        cursors.push(state);
      }
    }

    return cursors;
  }

  /**
   * Get active cursors
   */
  public getActiveCursors(fileId?: string): UserCursorState[] {
    const now = Date.now();
    const threshold = now - this.config.inactivityThreshold;

    let cursors = Array.from(this.cursors.values()).filter((c) => c.lastUpdated > threshold && c.isActive);

    if (fileId) {
      cursors = cursors.filter((c) => c.fileId === fileId);
    }

    return cursors;
  }

  /**
   * Get inactive cursors
   */
  public getInactiveCursors(fileId?: string): UserCursorState[] {
    const now = Date.now();
    const threshold = now - this.config.inactivityThreshold;

    let cursors = Array.from(this.cursors.values()).filter((c) => c.lastUpdated <= threshold || !c.isActive);

    if (fileId) {
      cursors = cursors.filter((c) => c.fileId === fileId);
    }

    return cursors;
  }

  /**
   * Get synchronization state
   */
  public getSyncState(fileId: string): CursorSyncState {
    return {
      fileId,
      timestamp: Date.now(),
      activeCursors: this.getActiveCursors(fileId),
      inactiveCursors: this.getInactiveCursors(fileId),
      conflictingPositions: this.conflicts.get(fileId) || [],
    };
  }

  /**
   * Broadcast cursor update
   */
  public broadcastCursorUpdate(
    fileId: string,
    updates: CursorUpdate[],
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; broadcastId?: string } {
    try {
      const broadcastId = `broadcast-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const userIds = Array.from(new Set(updates.map((u) => u.userId)));

      const broadcast: CursorBroadcast = {
        broadcastId,
        fileId,
        cursorUpdates: updates,
        includedUsers: userIds,
        timestamp: Date.now(),
        priority: 'normal',
      };

      this.logAudit(userId, 'broadcast-cursor-update', fileId, 'success', {
        broadcastId,
        updateCount: updates.length,
      });

      this.emit('cursor-broadcast', {
        data_object: broadcast,
        timestamp: Date.now(),
      });

      return { success: true, broadcastId };
    } catch (error) {
      this.logAudit(userId, 'broadcast-cursor-update', fileId, 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get presence
   */
  public getPresence(fileId: string): CursorPresence {
    const active = this.getActiveCursors(fileId);
    const inactive = this.getInactiveCursors(fileId);

    return {
      fileId,
      activeCursorCount: active.length,
      inactiveCursorCount: inactive.length,
      totalParticipants: new Set([...active, ...inactive].map((c) => c.userId)).size,
      lastSyncTime: Date.now(),
    };
  }

  /**
   * Get user presence
   */
  public getUserPresence(userId: string): CursorPresence[] {
    const cursors = this.getCursorsByUser(userId);
    const fileIds = new Set(cursors.map((c) => c.fileId));

    return Array.from(fileIds).map((fileId) => this.getPresence(fileId));
  }

  /**
   * Detect conflicts
   */
  public detectConflicts(fileId: string): CursorConflict[] {
    const cursors = this.getCursorsInFile(fileId);
    const detected: CursorConflict[] = [];
    const positionMap = new Map<string, string[]>();

    // Group cursors by position
    for (const cursor of cursors) {
      const key = `${cursor.position.line},${cursor.position.column}`;
      if (!positionMap.has(key)) {
        positionMap.set(key, []);
      }
      positionMap.get(key)!.push(cursor.userId);
    }

    // Check for conflicts
    for (const [key, userIds] of positionMap) {
      if (userIds.length > 1) {
        const [line, column] = key.split(',').map(Number);
        const conflictId = `conflict-${Date.now()}-${Math.random().toString(16).slice(2)}`;

        detected.push({
          conflictId,
          fileId,
          position: { line, column },
          involvedUsers: userIds,
          conflictType: 'same-position',
          detectedAt: Date.now(),
          resolved: false,
        });
      }
    }

    if (detected.length > 0) {
      if (!this.conflicts.has(fileId)) {
        this.conflicts.set(fileId, []);
      }
      this.conflicts.get(fileId)!.push(...detected);

      this.emit('cursor-conflicts-detected', {
        data_object: { fileId, conflictCount: detected.length },
        timestamp: Date.now(),
      });
    }

    return detected;
  }

  /**
   * Resolve conflict
   */
  public resolveConflict(
    conflictId: string,
    resolutionStrategy: 'none' | 'merge' | 'separate',
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      for (const [fileId, conflicts] of this.conflicts) {
        const conflict = conflicts.find((c) => c.conflictId === conflictId);
        if (conflict) {
          conflict.resolved = true;

          this.logAudit(userId, 'resolve-conflict', fileId, 'success', {
            conflictId,
            strategy: resolutionStrategy,
          });

          this.emit('cursor-conflict-resolved', {
            data_object: { conflictId, fileId, strategy: resolutionStrategy },
            timestamp: Date.now(),
          });

          return { success: true };
        }
      }

      return { success: false };
    } catch (error) {
      this.logAudit(userId, 'resolve-conflict', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Record cursor jump
   */
  public recordCursorJump(
    jump: Omit<CursorJumpEvent, 'jumpId' | 'timestamp'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; jumpId?: string } {
    try {
      const jumpId = `jump-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const event: CursorJumpEvent = {
        ...jump,
        jumpId,
        timestamp: Date.now(),
      };

      if (!this.jumps.has(userId)) {
        this.jumps.set(userId, []);
      }

      this.jumps.get(userId)!.push(event);

      this.logAudit(userId, 'record-cursor-jump', jump.fileId, 'success', {
        jumpId,
        reason: jump.reason,
      });

      this.emit('cursor-jump-recorded', {
        data_object: { jumpId, userId, reason: jump.reason },
        timestamp: Date.now(),
      });

      return { success: true, jumpId };
    } catch (error) {
      this.logAudit(userId, 'record-cursor-jump', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get cursor jumps
   */
  public getCursorJumps(userId: string, fileId?: string, limit?: number): CursorJumpEvent[] {
    let jumps = this.jumps.get(userId) || [];

    if (fileId) {
      jumps = jumps.filter((j) => j.fileId === fileId);
    }

    return jumps.slice(0, limit || 100);
  }

  /**
   * Update viewport
   */
  public updateViewport(
    userId: string,
    fileId: string,
    focusArea: ViewportFocusArea,
    zoom: number,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const key = `${userId}:${fileId}`;
      const viewport: UserViewportState = {
        userId,
        fileId,
        focusArea,
        zoom,
        lastUpdated: Date.now(),
      };

      this.viewports.set(key, viewport);

      this.logAudit(userId, 'update-viewport', fileId, 'success', {
        focusArea,
        zoom,
      });

      this.emit('viewport-updated', {
        data_object: { userId, fileId, zoom },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'update-viewport', fileId, 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get viewport
   */
  public getViewport(userId: string, fileId: string): UserViewportState | undefined {
    const key = `${userId}:${fileId}`;
    return this.viewports.get(key);
  }

  /**
   * Update visibility settings
   */
  public updateVisibilitySettings(settings: CursorVisibilitySettings, userId: string, ipAddress: string, userAgent: string): { success: boolean } {
    try {
      this.visibilitySettings.set(userId, settings);

      this.logAudit(userId, 'update-visibility-settings', '', 'success', {
        settings,
      });

      this.emit('visibility-settings-updated', {
        data_object: { userId, settings },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'update-visibility-settings', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get visibility settings
   */
  public getVisibilitySettings(userId: string): CursorVisibilitySettings {
    return (
      this.visibilitySettings.get(userId) || {
        showOtherCursors: true,
        showSelections: true,
        showInactiveAfterMs: 30000,
        colorScheme: 'auto',
        cursorSize: 'medium',
      }
    );
  }

  /**
   * Get cursor history
   */
  public getCursorHistory(fileId: string, userId?: string, limit?: number): CursorHistoryEntry[] {
    let entries = this.history.get(fileId) || [];

    if (userId) {
      entries = entries.filter((e) => e.userId === userId);
    }

    return entries.slice(0, limit || 100);
  }

  /**
   * Clear cursor history
   */
  public clearCursorHistory(fileId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean } {
    try {
      this.history.delete(fileId);

      this.logAudit(userId, 'clear-cursor-history', fileId, 'success', {});

      this.emit('cursor-history-cleared', {
        data_object: { fileId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'clear-cursor-history', fileId, 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get statistics
   */
  public getStatistics(fileId?: string): CursorStatistics {
    const activeCursors = this.getActiveCursors(fileId);
    const inactiveCursors = this.getInactiveCursors(fileId);

    return {
      totalCursorsTracked: this.cursors.size,
      activeCursors: activeCursors.length,
      inactiveCursors: inactiveCursors.length,
      totalFiles: this.fileCursors.size,
      averageCursorMovementPerSecond: this.calculateAverageMovement(),
      mostActiveCursor: this.findMostActiveCursor(),
      conflictDetectionAccuracy: 0.95,
    };
  }

  /**
   * Get audit log
   */
  public getAuditLog(limit?: number): CursorAuditEntry[] {
    const entries: CursorAuditEntry[] = [];
    for (const [, userEntries] of this.auditLog) {
      entries.push(...userEntries);
    }
    entries.sort((a, b) => b.timestamp - a.timestamp);
    return entries.slice(0, limit || 100);
  }

  /**
   * Remove cursor
   */
  public removeCursor(userId: string, fileId: string, ipAddress: string, userAgent: string): { success: boolean } {
    try {
      const key = `${userId}:${fileId}`;
      this.cursors.delete(key);

      const userIds = this.fileCursors.get(fileId);
      if (userIds) {
        userIds.delete(userId);
      }

      this.logAudit(userId, 'remove-cursor', fileId, 'success', {});

      this.emit('cursor-removed', {
        data_object: { userId, fileId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'remove-cursor', fileId, 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Remove user from file
   */
  public removeUserFromFile(userId: string, fileId: string, ipAddress: string, userAgent: string): { success: boolean } {
    try {
      // Remove cursor
      const key = `${userId}:${fileId}`;
      this.cursors.delete(key);

      // Remove from file cursors
      const userIds = this.fileCursors.get(fileId);
      if (userIds) {
        userIds.delete(userId);
      }

      // Remove viewport
      this.viewports.delete(key);

      this.logAudit(userId, 'remove-user-from-file', fileId, 'success', {});

      this.emit('user-removed-from-file', {
        data_object: { userId, fileId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'remove-user-from-file', fileId, 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Update configuration
   */
  public updateConfig(config: Partial<CursorPositionConfig>): void {
    this.config = { ...this.config, ...config };

    this.emit('config-updated', {
      data_object: { config: this.config },
      timestamp: Date.now(),
    });
  }

  /**
   * Get configuration
   */
  public getConfig(): CursorPositionConfig {
    return { ...this.config };
  }

  /**
   * Calculate distance between two positions
   */
  private calculateDistance(from: CursorPosition, to: CursorPosition): number {
    return Math.abs(to.line - from.line) + Math.abs(to.column - from.column);
  }

  /**
   * Record history entry
   */
  private recordHistory(fileId: string, userId: string, fromPosition: CursorPosition, toPosition: CursorPosition, distance: number): void {
    if (!this.history.has(fileId)) {
      this.history.set(fileId, []);
    }

    const entry: CursorHistoryEntry = {
      timestamp: Date.now(),
      userId,
      fileId,
      fromPosition,
      toPosition,
      movementDistance: distance,
    };

    const entries = this.history.get(fileId)!;
    entries.push(entry);

    if (entries.length > this.config.maxHistoryEntries) {
      entries.splice(0, entries.length - this.config.maxHistoryEntries);
    }
  }

  /**
   * Generate user color
   */
  private generateUserColor(userId: string): string {
    const colors = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#FFA07A', '#98D8C8', '#F7DC6F'];
    const hash = userId.split('').reduce((acc, char) => acc + char.charCodeAt(0), 0);
    return colors[hash % colors.length];
  }

  /**
   * Calculate average movement
   */
  private calculateAverageMovement(): number {
    let totalDistance = 0;
    let entryCount = 0;

    for (const [, entries] of this.history) {
      totalDistance += entries.reduce((sum, e) => sum + e.movementDistance, 0);
      entryCount += entries.length;
    }

    return entryCount > 0 ? totalDistance / entryCount : 0;
  }

  /**
   * Find most active cursor
   */
  private findMostActiveCursor(): { userId: string; moveCount: number } | null {
    let maxMoves = 0;
    let mostActive: { userId: string; moveCount: number } | null = null;

    const moveMap = new Map<string, number>();
    for (const [, entries] of this.history) {
      for (const entry of entries) {
        const count = (moveMap.get(entry.userId) || 0) + 1;
        moveMap.set(entry.userId, count);
      }
    }

    for (const [userId, count] of moveMap) {
      if (count > maxMoves) {
        maxMoves = count;
        mostActive = { userId, moveCount: count };
      }
    }

    return mostActive;
  }

  /**
   * Log audit entry
   */
  private logAudit(userId: string, action: string, fileId: string, status: 'success' | 'failure', details?: Record<string, unknown>): void {
    if (!this.auditLog.has(userId)) {
      this.auditLog.set(userId, []);
    }

    const entry: CursorAuditEntry = {
      timestamp: Date.now(),
      userId,
      userEmail: `user-${userId}@example.com`,
      action,
      fileId,
      details: details || {},
    };

    const logs = this.auditLog.get(userId)!;
    logs.push(entry);

    if (logs.length > this.config.maxAuditEntries) {
      logs.splice(0, logs.length - this.config.maxAuditEntries);
    }

    this.emit('audit-logged', {
      data_object: entry,
      timestamp: Date.now(),
    });
  }

  /**
   * Shutdown service
   */
  public shutdown(): void {
    this.cursors.clear();
    this.fileCursors.clear();
    this.history.clear();
    this.conflicts.clear();
    this.jumps.clear();
    this.viewports.clear();
    this.visibilitySettings.clear();
    this.auditLog.clear();

    this.emit('shutdown', {
      data_object: { service: 'cursor-position-manager', status: 'shutdown' },
      timestamp: Date.now(),
    });
  }
}
