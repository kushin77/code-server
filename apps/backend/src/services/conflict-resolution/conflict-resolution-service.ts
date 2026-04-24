/**
 * Workspace Conflict Resolution Service
 * @file        apps/backend/src/services/conflict-resolution/conflict-resolution-service.ts
 * @module      services/conflict-resolution
 * @description Detect and resolve workspace file/state conflicts in collaborative editing
 */

import { EventEmitter } from 'events';
import {
  FileConflict,
  StateConflict,
  ConflictResolution,
  StateResolution,
  ConflictDetectionResult,
  ConflictResolutionResult,
  BatchResolutionResult,
  ConflictHistoryEntry,
  ConflictAuditEntry,
  ConflictStatistics,
  ConflictSettings,
  IConflictResolutionService,
  FileVersion,
  WorkspaceState,
  ResolutionStrategy,
  ConflictType,
  ConflictSeverity,
} from './types.js';

/**
 * Conflict Resolution Service
 */
export class ConflictResolutionService extends EventEmitter implements IConflictResolutionService {
  private static instance: ConflictResolutionService;

  private conflicts: Map<string, FileConflict>;
  private stateConflicts: Map<string, StateConflict>;
  private resolutions: Map<string, ConflictResolution>;
  private stateResolutions: Map<string, StateResolution>;
  private conflictHistory: Map<string, ConflictHistoryEntry[]>;
  private auditLogs: Map<string, ConflictAuditEntry[]>;
  private settings: ConflictSettings;
  private statistics: ConflictStatistics;

  private constructor() {
    super();
    this.conflicts = new Map();
    this.stateConflicts = new Map();
    this.resolutions = new Map();
    this.stateResolutions = new Map();
    this.conflictHistory = new Map();
    this.auditLogs = new Map();

    this.settings = {
      autoResolveEnabled: false,
      autoResolutionStrategy: 'timestamp-based',
      conflictDetectionInterval: 5000,
      maxConflictHistorySize: 10000,
      maxAuditLogSize: 10000,
      enableMergeConflictAnalysis: true,
      enableStateConflictDetection: true,
      preserveConflictMarkers: false,
      retentionDays: 365,
    };

    this.statistics = {
      totalConflicts: 0,
      resolvedConflicts: 0,
      unresolvedConflicts: 0,
      conflictsByType: new Map(),
      conflictsBySeverity: new Map(),
      mostCommonConflictType: null,
      averageResolutionTime: 0,
      successRate: 0,
      mostActiveUsers: [],
      mostConflictedFiles: [],
    };

    this.initialize();
  }

  /**
   * Get or create service instance
   */
  static getInstance(settings?: Partial<ConflictSettings>): ConflictResolutionService {
    if (!ConflictResolutionService.instance) {
      ConflictResolutionService.instance = new ConflictResolutionService();
    }
    if (settings) {
      ConflictResolutionService.instance.updateSettings(settings, 'system', '127.0.0.1', 'node');
    }
    return ConflictResolutionService.instance;
  }

  /**
   * Reset instance for testing
   */
  static reset(): void {
    if (ConflictResolutionService.instance) {
      ConflictResolutionService.instance.shutdown();
    }
    ConflictResolutionService.instance = null as any;
  }

  /**
   * Initialize service
   */
  private initialize(): void {
    this.emit('initialized', {
      data_object: { service: 'conflict-resolution', status: 'initialized' },
      timestamp: Date.now(),
    });
  }

  /**
   * Detect conflicts
   */
  detectConflicts(
    workspaceId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): ConflictDetectionResult {
    try {
      const fileConflicts = Array.from(this.conflicts.values()).filter(
        (c) => !c.resolvedAt
      );
      const stateConflicts = Array.from(this.stateConflicts.values()).filter(
        (c) => !c.resolvedAt
      );

      const criticalCount = fileConflicts.filter((c) => c.severity === 'critical').length;
      const warningCount = fileConflicts.filter((c) => c.severity === 'high').length;

      this.emit('conflict-detection-completed', {
        data_object: {
          workspaceId,
          fileConflictCount: fileConflicts.length,
          stateConflictCount: stateConflicts.length,
        },
        timestamp: Date.now(),
      });

      this.logAudit(
        userId,
        `${userId}@example.com`,
        ipAddress,
        userAgent,
        'conflict-detected',
        '',
        '',
        { workspaceId, fileConflictCount: fileConflicts.length }
      );

      return {
        success: true,
        conflicts: fileConflicts,
        stateConflicts,
        totalConflicts: fileConflicts.length + stateConflicts.length,
        criticalCount,
        warningCount,
      };
    } catch (error) {
      return {
        success: false,
        conflicts: [],
        stateConflicts: [],
        totalConflicts: 0,
        criticalCount: 0,
        warningCount: 0,
        error: (error as Error).message,
      };
    }
  }

  /**
   * Report conflict
   */
  reportConflict(
    conflict: FileConflict,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; conflictId?: string; error?: string } {
    try {
      const conflictId = conflict.id || `conflict-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const newConflict: FileConflict = { ...conflict, id: conflictId };

      this.conflicts.set(conflictId, newConflict);
      this.statistics.totalConflicts++;

      if (!this.conflictHistory.has(conflictId)) {
        this.conflictHistory.set(conflictId, []);
      }

      const history = this.conflictHistory.get(conflictId)!;
      history.push({
        id: `hist-${Date.now()}`,
        conflictId,
        timestamp: Date.now(),
        action: 'conflict-detected',
        userId,
        userEmail: `${userId}@example.com`,
        details: new Map({ type: conflict.conflictType }),
      });

      this.emit('conflict-reported', {
        data_object: { conflictId, filePath: conflict.filePath, severity: conflict.severity },
        timestamp: Date.now(),
      });

      this.logAudit(
        userId,
        `${userId}@example.com`,
        ipAddress,
        userAgent,
        'conflict-detected',
        conflict.filePath,
        conflictId,
        { type: conflict.conflictType, severity: conflict.severity }
      );

      return { success: true, conflictId };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  /**
   * Resolve conflict
   */
  resolveConflict(
    conflictId: string,
    strategy: ResolutionStrategy,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): ConflictResolutionResult {
    try {
      const conflict = this.conflicts.get(conflictId);
      if (!conflict) {
        return { success: false, conflictId, errors: [], warnings: [] };
      }

      let resultingContent = '';

      if (strategy === 'keep-local') {
        resultingContent = conflict.localVersion.content || '';
      } else if (strategy === 'keep-remote') {
        resultingContent = conflict.remoteVersion.content || '';
      } else if (strategy === 'merge') {
        resultingContent = this.mergeContent(
          conflict.localVersion.content || '',
          conflict.remoteVersion.content || ''
        );
      }

      const resolution: ConflictResolution = {
        id: `res-${Date.now()}-${Math.random().toString(16).slice(2)}`,
        conflictId,
        strategy,
        resolvedBy: userId,
        resolvedAt: Date.now(),
        resultingContent,
        confidence: 0.85,
      };

      this.resolutions.set(resolution.id, resolution);
      conflict.resolution = resolution;
      conflict.resolvedAt = Date.now();
      this.statistics.resolvedConflicts++;

      if (this.conflictHistory.has(conflictId)) {
        const history = this.conflictHistory.get(conflictId)!;
        history.push({
          id: `hist-${Date.now()}`,
          conflictId,
          timestamp: Date.now(),
          action: 'resolution-successful',
          userId,
          userEmail: `${userId}@example.com`,
          details: new Map({ strategy }),
        });
      }

      this.emit('conflict-resolved', {
        data_object: { conflictId, strategy, resultingContent: resultingContent.length },
        timestamp: Date.now(),
      });

      this.logAudit(
        userId,
        `${userId}@example.com`,
        ipAddress,
        userAgent,
        'conflict-resolved',
        conflict.filePath,
        conflictId,
        { strategy, resultingContentLength: resultingContent.length }
      );

      return { success: true, conflictId, resolution, newContent: resultingContent, warnings: [] };
    } catch (error) {
      return {
        success: false,
        conflictId,
        error: (error as Error).message,
        warnings: [],
      };
    }
  }

  /**
   * Get conflict
   */
  getConflict(conflictId: string): { success: boolean; conflict?: FileConflict; error?: string } {
    try {
      const conflict = this.conflicts.get(conflictId);
      if (!conflict) {
        return { success: false, error: 'Conflict not found' };
      }
      return { success: true, conflict };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  /**
   * List conflicts
   */
  listConflicts(
    workspaceId?: string,
    status?: 'unresolved' | 'resolved' | 'all'
  ): FileConflict[] {
    try {
      let conflicts = Array.from(this.conflicts.values());

      if (status === 'unresolved') {
        conflicts = conflicts.filter((c) => !c.resolvedAt);
      } else if (status === 'resolved') {
        conflicts = conflicts.filter((c) => c.resolvedAt);
      }

      return conflicts;
    } catch {
      return [];
    }
  }

  /**
   * Get conflict history
   */
  getConflictHistory(conflictId: string, limit?: number): ConflictHistoryEntry[] {
    try {
      const history = this.conflictHistory.get(conflictId) || [];
      return history.slice(-(limit || 50));
    } catch {
      return [];
    }
  }

  /**
   * Suggest resolution
   */
  suggestResolution(
    conflictId: string
  ): { success: boolean; suggestion?: ResolutionStrategy; confidence?: number; error?: string } {
    try {
      const conflict = this.conflicts.get(conflictId);
      if (!conflict) {
        return { success: false, error: 'Conflict not found' };
      }

      let suggestion: ResolutionStrategy = 'timestamp-based';
      let confidence = 0.7;

      if (conflict.localVersion.timestamp > conflict.remoteVersion.timestamp) {
        suggestion = 'keep-local';
        confidence = 0.85;
      } else {
        suggestion = 'keep-remote';
        confidence = 0.8;
      }

      this.emit('suggestion-generated', {
        data_object: { conflictId, suggestion, confidence },
        timestamp: Date.now(),
      });

      return { success: true, suggestion, confidence };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  /**
   * Merge conflict
   */
  mergeConflict(
    conflictId: string,
    localVersion: FileVersion,
    remoteVersion: FileVersion,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): ConflictResolutionResult {
    try {
      const conflict = this.conflicts.get(conflictId);
      if (!conflict) {
        return { success: false, conflictId, warnings: [] };
      }

      const mergedContent = this.mergeContent(
        localVersion.content || '',
        remoteVersion.content || ''
      );

      const resolution: ConflictResolution = {
        id: `res-${Date.now()}-${Math.random().toString(16).slice(2)}`,
        conflictId,
        strategy: 'merge',
        resolvedBy: userId,
        resolvedAt: Date.now(),
        resultingContent: mergedContent,
        confidence: 0.75,
      };

      this.resolutions.set(resolution.id, resolution);
      conflict.resolution = resolution;
      conflict.resolvedAt = Date.now();
      this.statistics.resolvedConflicts++;

      this.emit('merge-executed', {
        data_object: { conflictId, mergedLength: mergedContent.length },
        timestamp: Date.now(),
      });

      return { success: true, conflictId, resolution, newContent: mergedContent, warnings: [] };
    } catch (error) {
      return {
        success: false,
        conflictId,
        error: (error as Error).message,
        warnings: [],
      };
    }
  }

  /**
   * Revert resolution
   */
  revertResolution(
    resolutionId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; error?: string } {
    try {
      const resolution = this.resolutions.get(resolutionId);
      if (!resolution) {
        return { success: false, error: 'Resolution not found' };
      }

      const conflict = this.conflicts.get(resolution.conflictId);
      if (conflict) {
        conflict.resolvedAt = undefined;
        conflict.resolution = undefined;
        this.statistics.resolvedConflicts--;
      }

      this.resolutions.delete(resolutionId);

      this.emit('resolution-reverted', {
        data_object: { resolutionId, conflictId: resolution.conflictId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  /**
   * Detect state conflicts
   */
  detectStateConflicts(
    workspaceId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): StateConflict[] {
    try {
      const stateConflicts = Array.from(this.stateConflicts.values()).filter(
        (c) => !c.resolvedAt
      );

      this.emit('state-conflict-detection-completed', {
        data_object: { workspaceId, conflictCount: stateConflicts.length },
        timestamp: Date.now(),
      });

      return stateConflicts;
    } catch {
      return [];
    }
  }

  /**
   * Resolve state conflict
   */
  resolveStateConflict(
    stateConflictId: string,
    strategy: ResolutionStrategy,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; resolution?: StateResolution; error?: string } {
    try {
      const stateConflict = this.stateConflicts.get(stateConflictId);
      if (!stateConflict) {
        return { success: false, error: 'State conflict not found' };
      }

      let resultingState = stateConflict.localState;

      if (strategy === 'keep-remote') {
        resultingState = stateConflict.remoteState;
      }

      const resolution: StateResolution = {
        id: `res-${Date.now()}-${Math.random().toString(16).slice(2)}`,
        stateConflictId,
        strategy,
        resolvedBy: userId,
        resolvedAt: Date.now(),
        resultingState,
        confidence: 0.8,
      };

      this.stateResolutions.set(resolution.id, resolution);
      stateConflict.resolvedAt = Date.now();
      stateConflict.resolution = resolution;

      this.emit('state-conflict-resolved', {
        data_object: { stateConflictId, strategy },
        timestamp: Date.now(),
      });

      return { success: true, resolution };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  /**
   * Batch resolve conflicts
   */
  batchResolveConflicts(
    conflictIds: string[],
    strategy: ResolutionStrategy,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): BatchResolutionResult {
    try {
      const results: ConflictResolutionResult[] = [];
      let resolved = 0;
      let failed = 0;

      conflictIds.forEach((conflictId) => {
        const result = this.resolveConflict(conflictId, strategy, userId, ipAddress, userAgent);
        results.push(result);
        if (result.success) {
          resolved++;
        } else {
          failed++;
        }
      });

      this.emit('batch-resolution-completed', {
        data_object: { totalProcessed: conflictIds.length, resolved, failed },
        timestamp: Date.now(),
      });

      this.logAudit(
        userId,
        `${userId}@example.com`,
        ipAddress,
        userAgent,
        'conflict-resolved',
        '',
        '',
        { totalProcessed: conflictIds.length, resolved, failed }
      );

      return {
        success: failed === 0,
        totalProcessed: conflictIds.length,
        resolved,
        failed,
        skipped: 0,
        details: results,
      };
    } catch (error) {
      return {
        success: false,
        totalProcessed: 0,
        resolved: 0,
        failed: conflictIds.length,
        skipped: 0,
        details: [],
      };
    }
  }

  /**
   * Get statistics
   */
  getStatistics(): ConflictStatistics {
    const conflictsByType = new Map<ConflictType, number>();
    const conflictsBySeverity = new Map<ConflictSeverity, number>();
    const userSet = new Set<string>();
    const fileSet = new Set<string>();

    Array.from(this.conflicts.values()).forEach((c) => {
      conflictsByType.set(c.conflictType, (conflictsByType.get(c.conflictType) || 0) + 1);
      conflictsBySeverity.set(c.severity, (conflictsBySeverity.get(c.severity) || 0) + 1);
      c.participants.forEach((p) => userSet.add(p));
      fileSet.add(c.filePath);
    });

    const unresolvedConflicts = Array.from(this.conflicts.values()).filter(
      (c) => !c.resolvedAt
    ).length;

    const successRate =
      this.statistics.totalConflicts > 0
        ? (this.statistics.resolvedConflicts / this.statistics.totalConflicts) * 100
        : 0;

    return {
      totalConflicts: this.statistics.totalConflicts,
      resolvedConflicts: this.statistics.resolvedConflicts,
      unresolvedConflicts,
      conflictsByType,
      conflictsBySeverity,
      mostCommonConflictType: null,
      averageResolutionTime: 0,
      successRate,
      mostActiveUsers: Array.from(userSet).slice(0, 5),
      mostConflictedFiles: Array.from(fileSet).slice(0, 5),
    };
  }

  /**
   * Archive conflict
   */
  archiveConflict(
    conflictId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; error?: string } {
    try {
      const conflict = this.conflicts.get(conflictId);
      if (!conflict) {
        return { success: false, error: 'Conflict not found' };
      }

      if (!conflict.tags) {
        conflict.tags = [];
      }
      conflict.tags.push('archived');

      this.emit('conflict-archived', {
        data_object: { conflictId },
        timestamp: Date.now(),
      });

      this.logAudit(
        userId,
        `${userId}@example.com`,
        ipAddress,
        userAgent,
        'conflict-detected',
        conflict.filePath,
        conflictId,
        { action: 'archived' }
      );

      return { success: true };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  /**
   * Update settings
   */
  updateSettings(
    settings: Partial<ConflictSettings>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): void {
    this.settings = { ...this.settings, ...settings };

    this.emit('settings-updated', {
      data_object: { userId, settings },
      timestamp: Date.now(),
    });

    this.logAudit(userId, `${userId}@example.com`, ipAddress, userAgent, 'conflict-detected', '', '', {
      settingsUpdate: settings,
    });
  }

  /**
   * Merge content
   */
  private mergeContent(local: string, remote: string): string {
    const localLines = local.split('\n');
    const remoteLines = remote.split('\n');
    const merged: string[] = [];

    const maxLength = Math.max(localLines.length, remoteLines.length);

    for (let i = 0; i < maxLength; i++) {
      const localLine = localLines[i] || '';
      const remoteLine = remoteLines[i] || '';

      if (localLine === remoteLine) {
        merged.push(localLine);
      } else if (localLine && !remoteLine) {
        merged.push(localLine);
      } else if (remoteLine && !localLine) {
        merged.push(remoteLine);
      } else {
        merged.push(`<<<<<<< local\n${localLine}\n=======\n${remoteLine}\n>>>>>>>`);
      }
    }

    return merged.join('\n');
  }

  /**
   * Log audit entry
   */
  private logAudit(
    userId: string,
    userEmail: string,
    ipAddress: string,
    userAgent: string,
    operation: any,
    filePath: string,
    conflictId: string,
    details: any
  ): void {
    const entry: ConflictAuditEntry = {
      timestamp: Date.now(),
      userId,
      userEmail,
      ipAddress,
      userAgent,
      operation,
      conflictId: conflictId || undefined,
      filePath: filePath || undefined,
      status: 'success',
      details: new Map(Object.entries(details)),
    };

    if (!this.auditLogs.has(userId)) {
      this.auditLogs.set(userId, []);
    }

    const logs = this.auditLogs.get(userId)!;
    logs.push(entry);

    if (logs.length > this.settings.maxAuditLogSize) {
      logs.splice(0, logs.length - this.settings.maxAuditLogSize);
    }

    this.emit('audit-logged', {
      data_object: { userId, operation, status: 'success' },
      timestamp: Date.now(),
    });
  }

  /**
   * Shutdown service
   */
  shutdown(): void {
    this.conflicts.clear();
    this.stateConflicts.clear();
    this.resolutions.clear();
    this.stateResolutions.clear();
    this.conflictHistory.clear();
    this.auditLogs.clear();

    this.emit('shutdown', {
      data_object: { service: 'conflict-resolution', status: 'shutdown' },
      timestamp: Date.now(),
    });

    this.removeAllListeners();
  }
}
