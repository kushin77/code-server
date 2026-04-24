/**
 * Real-time Change Stream Service
 * @file        apps/backend/src/services/change-stream/change-stream-service.ts
 * @module      services/change-stream
 * @description Real-time change stream tracking and conflict detection
 */

import { EventEmitter } from 'events';
import {
  Change,
  ChangeStreamSubscription,
  ChangeMetadata,
  ConflictInfo,
  ChangeStatistics,
  ChangeAuditEntry,
  ChangeStreamConfig,
  IChangeStreamService,
  ChangeStatus,
  RollbackResult,
  EntityChangeTimeline,
  ChangeHistoryEntry,
  ChangeStreamEvent,
} from './types.js';

/**
 * Change Stream Service
 * Tracks changes, manages subscriptions, and detects conflicts
 */
export class ChangeStreamService extends EventEmitter implements IChangeStreamService {
  private static instance: ChangeStreamService | undefined;
  private changes: Map<string, Change> = new Map();
  private entityChanges: Map<string, Set<string>> = new Map(); // entityId -> changeIds
  private subscriptions: Map<string, ChangeStreamSubscription> = new Map();
  private userSubscriptions: Map<string, Set<string>> = new Map(); // userId -> subscriptionIds
  private conflicts: Map<string, ConflictInfo> = new Map();
  private timelines: Map<string, EntityChangeTimeline> = new Map(); // entityId -> timeline
  private auditLog: Map<string, ChangeAuditEntry[]> = new Map(); // userId -> entries
  private stats: ChangeStatistics = {
    totalChanges: 0,
    changesByOperation: {} as Record<string, number>,
    changesByEntityType: {} as Record<string, number>,
    changesByStatus: {} as Record<string, number>,
    changeBySeverity: {} as Record<string, number>,
    averageApplicationTimeMs: 0,
    conflictCount: 0,
    revertCount: 0,
  };
  private config: ChangeStreamConfig = {
    enableChangeTracking: true,
    maxChangesPerUser: 10000,
    maxSubscriptionsPerUser: 50,
    conflictDetectionEnabled: true,
    autoReplicateChanges: false,
    changeRetentionDays: 90,
    maxAuditEntries: 5000,
    batchProcessingIntervalMs: 5000,
    notificationEnabled: true,
    enableChangeCompression: true,
  };

  private constructor() {
    super();
    this.initialize();
  }

  /**
   * Get or create singleton instance
   */
  public static getInstance(config?: Partial<ChangeStreamConfig>): ChangeStreamService {
    if (!ChangeStreamService.instance) {
      ChangeStreamService.instance = new ChangeStreamService();
    }
    if (config) {
      ChangeStreamService.instance.updateConfig(config);
    }
    return ChangeStreamService.instance;
  }

  /**
   * Reset singleton for testing
   */
  public static reset(): void {
    ChangeStreamService.instance = undefined;
  }

  /**
   * Initialize service
   */
  private initialize(): void {
    this.emit('initialized', {
      data_object: { service: 'change-stream', status: 'initialized' },
      timestamp: Date.now(),
    });
  }

  /**
   * Record change
   */
  public recordChange(
    change: Omit<Change, 'changeId' | 'timestamp' | 'appliedAt'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; changeId?: string } {
    try {
      if (!this.config.enableChangeTracking) {
        return { success: false };
      }

      const changeId = `change-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const fullChange: Change = {
        ...change,
        changeId,
        timestamp: Date.now(),
        userId,
        userEmail: `user-${userId}@example.com`,
      };

      this.changes.set(changeId, fullChange);

      if (!this.entityChanges.has(change.entityId)) {
        this.entityChanges.set(change.entityId, new Set());
      }
      this.entityChanges.get(change.entityId)!.add(changeId);

      // Update timeline
      this.updateTimeline(change.entityId, fullChange);

      this.stats.totalChanges++;

      this.logAudit(userId, 'record-change', changeId, change.entityId, {
        operation: change.operation,
        entityType: change.entityType,
      });

      this.emit('change-recorded', {
        data_object: { changeId, entityId: change.entityId, operation: change.operation },
        timestamp: Date.now(),
      });

      return { success: true, changeId };
    } catch (error) {
      this.logAudit(userId, 'record-change', '', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get change
   */
  public getChange(changeId: string): Change | undefined {
    return this.changes.get(changeId);
  }

  /**
   * Get entity changes
   */
  public getEntityChanges(entityId: string, limit?: number): Change[] {
    const changeIds = this.entityChanges.get(entityId) || new Set();
    const changes: Change[] = [];

    for (const id of changeIds) {
      const change = this.changes.get(id);
      if (change) {
        changes.push(change);
      }
    }

    changes.sort((a, b) => b.timestamp - a.timestamp);
    return changes.slice(0, limit || 100);
  }

  /**
   * Create subscription
   */
  public createSubscription(
    subscription: Omit<ChangeStreamSubscription, 'subscriptionId' | 'createdAt'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; subscriptionId?: string } {
    try {
      const subscriptionId = `sub-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const fullSubscription: ChangeStreamSubscription = {
        ...subscription,
        subscriptionId,
        createdAt: Date.now(),
      };

      this.subscriptions.set(subscriptionId, fullSubscription);

      if (!this.userSubscriptions.has(userId)) {
        this.userSubscriptions.set(userId, new Set());
      }
      this.userSubscriptions.get(userId)!.add(subscriptionId);

      this.logAudit(userId, 'create-subscription', '', '', {
        subscriptionId,
        entityId: subscription.entityId,
      });

      this.emit('subscription-created', {
        data_object: { subscriptionId, userId, entityId: subscription.entityId },
        timestamp: Date.now(),
      });

      return { success: true, subscriptionId };
    } catch (error) {
      this.logAudit(userId, 'create-subscription', '', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Update subscription
   */
  public updateSubscription(
    subscriptionId: string,
    updates: Partial<ChangeStreamSubscription>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const subscription = this.subscriptions.get(subscriptionId);
      if (!subscription) {
        return { success: false };
      }

      Object.assign(subscription, updates);

      this.logAudit(userId, 'update-subscription', '', '', {
        subscriptionId,
      });

      this.emit('subscription-updated', {
        data_object: { subscriptionId, userId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'update-subscription', '', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Delete subscription
   */
  public deleteSubscription(
    subscriptionId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      this.subscriptions.delete(subscriptionId);
      this.userSubscriptions.get(userId)?.delete(subscriptionId);

      this.logAudit(userId, 'delete-subscription', '', '', {
        subscriptionId,
      });

      this.emit('subscription-deleted', {
        data_object: { subscriptionId, userId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'delete-subscription', '', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get subscriptions
   */
  public getSubscriptions(userId: string): ChangeStreamSubscription[] {
    const subscriptionIds = this.userSubscriptions.get(userId) || new Set();
    const subscriptions: ChangeStreamSubscription[] = [];

    for (const id of subscriptionIds) {
      const sub = this.subscriptions.get(id);
      if (sub) {
        subscriptions.push(sub);
      }
    }

    return subscriptions;
  }

  /**
   * Publish change
   */
  public publishChange(
    change: Change,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; affectedSubscriptions?: number } {
    try {
      let affectedCount = 0;

      for (const [, subscription] of this.subscriptions) {
        if (subscription.status !== 'active') {
          continue;
        }

        const matches =
          (!subscription.entityId || subscription.entityId === change.entityId) &&
          (!subscription.entityType || subscription.entityType === change.entityType) &&
          (!subscription.operations || subscription.operations.includes(change.operation));

        if (matches) {
          affectedCount++;
          this.emit('change-published-to-subscription', {
            data_object: { subscriptionId: subscription.subscriptionId, changeId: change.changeId },
            timestamp: Date.now(),
          });
        }
      }

      this.logAudit(userId, 'publish-change', change.changeId, change.entityId, {
        affectedSubscriptions: affectedCount,
      });

      this.emit('change-published', {
        data_object: { changeId: change.changeId, entityId: change.entityId, affectedCount },
        timestamp: Date.now(),
      });

      return { success: true, affectedSubscriptions: affectedCount };
    } catch (error) {
      this.logAudit(userId, 'publish-change', change.changeId, change.entityId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Detect conflicts
   */
  public detectConflicts(
    changeId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; conflicts?: ConflictInfo[] } {
    try {
      if (!this.config.conflictDetectionEnabled) {
        return { success: true, conflicts: [] };
      }

      const change = this.changes.get(changeId);
      if (!change) {
        return { success: false };
      }

      const detectedConflicts: ConflictInfo[] = [];

      // Check for conflicts with other recent changes to same entity
      const entityChangeIds = this.entityChanges.get(change.entityId) || new Set();
      const recentChanges = Array.from(entityChangeIds)
        .map((id) => this.changes.get(id))
        .filter((c) => c && c.timestamp > change.timestamp - 60000); // Last minute

      for (const otherChange of recentChanges) {
        if (otherChange && otherChange.changeId !== changeId) {
          // Simple conflict detection: concurrent operations on same entity
          const conflict: ConflictInfo = {
            conflictId: `conflict-${Date.now()}-${Math.random().toString(16).slice(2)}`,
            conflictingChangeId: otherChange.changeId,
            conflictType: 'content',
            severity: 'medium',
            detectedAt: Date.now(),
            resolutionStatus: 'pending',
          };

          this.conflicts.set(conflict.conflictId, conflict);
          detectedConflicts.push(conflict);
          this.stats.conflictCount++;
        }
      }

      if (detectedConflicts.length > 0) {
        change.conflictInfo = detectedConflicts[0];
        change.status = 'conflicted';
      }

      this.logAudit(userId, 'detect-conflicts', changeId, change.entityId, {
        conflictCount: detectedConflicts.length,
      });

      this.emit('conflicts-detected', {
        data_object: { changeId, conflictCount: detectedConflicts.length },
        timestamp: Date.now(),
      });

      return { success: true, conflicts: detectedConflicts };
    } catch (error) {
      this.logAudit(userId, 'detect-conflicts', changeId, '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Resolve conflict
   */
  public resolveConflict(
    conflictId: string,
    resolution: 'accept' | 'reject' | 'merge',
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const conflict = this.conflicts.get(conflictId);
      if (!conflict) {
        return { success: false };
      }

      conflict.resolutionStatus = 'resolved';

      this.logAudit(userId, 'resolve-conflict', '', '', {
        conflictId,
        resolution,
      });

      this.emit('conflict-resolved', {
        data_object: { conflictId, resolution },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'resolve-conflict', '', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Apply change
   */
  public applyChange(
    changeId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; applicationTimeMs?: number } {
    try {
      const change = this.changes.get(changeId);
      if (!change) {
        return { success: false };
      }

      const startTime = Date.now();
      change.status = 'applied';
      change.appliedAt = startTime;

      this.logAudit(userId, 'apply-change', changeId, change.entityId, {});

      this.emit('change-applied', {
        data_object: { changeId, entityId: change.entityId, applicationTimeMs: 0 },
        timestamp: Date.now(),
      });

      return { success: true, applicationTimeMs: 0 };
    } catch (error) {
      this.logAudit(userId, 'apply-change', changeId, '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Batch apply changes
   */
  public batchApplyChanges(
    changeIds: string[],
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; appliedCount?: number; batchId?: string } {
    try {
      const batchId = `batch-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      let appliedCount = 0;

      for (const id of changeIds) {
        const result = this.applyChange(id, userId, ipAddress, userAgent);
        if (result.success) {
          appliedCount++;
        }
      }

      this.logAudit(userId, 'batch-apply-changes', '', '', {
        batchId,
        appliedCount,
        totalCount: changeIds.length,
      });

      this.emit('batch-apply-completed', {
        data_object: { batchId, userId, appliedCount },
        timestamp: Date.now(),
      });

      return { success: true, appliedCount, batchId };
    } catch (error) {
      this.logAudit(userId, 'batch-apply-changes', '', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Revert change
   */
  public revertChange(
    changeId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const change = this.changes.get(changeId);
      if (!change) {
        return { success: false };
      }

      change.status = 'reverted';
      change.revertedAt = Date.now();
      this.stats.revertCount++;

      this.logAudit(userId, 'revert-change', changeId, change.entityId, {});

      this.emit('change-reverted', {
        data_object: { changeId, entityId: change.entityId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'revert-change', changeId, '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Rollback changes
   */
  public rollbackChanges(
    changeIds: string[],
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; rollbackId?: string; revertedCount?: number } {
    try {
      const rollbackId = `rollback-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      let revertedCount = 0;

      for (const id of changeIds) {
        const result = this.revertChange(id, userId, ipAddress, userAgent);
        if (result.success) {
          revertedCount++;
        }
      }

      this.logAudit(userId, 'rollback-changes', '', '', {
        rollbackId,
        revertedCount,
        totalCount: changeIds.length,
      });

      this.emit('rollback-completed', {
        data_object: { rollbackId, userId, revertedCount },
        timestamp: Date.now(),
      });

      return { success: true, rollbackId, revertedCount };
    } catch (error) {
      this.logAudit(userId, 'rollback-changes', '', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get change timeline
   */
  public getChangeTimeline(entityId: string): EntityChangeTimeline | undefined {
    return this.timelines.get(entityId);
  }

  /**
   * Get statistics
   */
  public getStatistics(userId?: string): ChangeStatistics {
    if (!userId) {
      return { ...this.stats };
    }

    // User-specific statistics
    const userChanges = Array.from(this.changes.values()).filter((c) => c.userId === userId);

    return {
      totalChanges: userChanges.length,
      changesByOperation: {} as Record<string, number>,
      changesByEntityType: {} as Record<string, number>,
      changesByStatus: {} as Record<string, number>,
      changeBySeverity: {} as Record<string, number>,
      averageApplicationTimeMs: 0,
      conflictCount: userChanges.filter((c) => c.status === 'conflicted').length,
      revertCount: userChanges.filter((c) => c.status === 'reverted').length,
    };
  }

  /**
   * Get audit log
   */
  public getAuditLog(limit?: number): ChangeAuditEntry[] {
    const entries: ChangeAuditEntry[] = [];
    for (const [, userEntries] of this.auditLog) {
      entries.push(...userEntries);
    }
    entries.sort((a, b) => b.timestamp - a.timestamp);
    return entries.slice(0, limit || 100);
  }

  /**
   * Archive old changes
   */
  public archiveOldChanges(
    daysOld: number,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; archivedCount?: number } {
    try {
      const cutoffTime = Date.now() - daysOld * 86400000;
      let archivedCount = 0;

      for (const [, change] of this.changes) {
        if (change.timestamp < cutoffTime && change.status !== 'archived') {
          change.status = 'archived';
          archivedCount++;
        }
      }

      this.logAudit(userId, 'archive-old-changes', '', '', {
        daysOld,
        archivedCount,
      });

      this.emit('archive-completed', {
        data_object: { userId, archivedCount },
        timestamp: Date.now(),
      });

      return { success: true, archivedCount };
    } catch (error) {
      this.logAudit(userId, 'archive-old-changes', '', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Export changes
   */
  public exportChanges(
    entityId: string,
    format: 'json' | 'csv',
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; data?: string } {
    try {
      const changes = this.getEntityChanges(entityId);

      let data: string;
      if (format === 'json') {
        data = JSON.stringify(changes, null, 2);
      } else {
        // CSV format
        const headers = ['changeId', 'operation', 'timestamp', 'status', 'severity'];
        const rows = changes.map((c) => [c.changeId, c.operation, c.timestamp, c.status, c.severity].join(','));
        data = [headers.join(','), ...rows].join('\n');
      }

      this.logAudit(userId, 'export-changes', '', entityId, {
        format,
        changeCount: changes.length,
      });

      this.emit('changes-exported', {
        data_object: { entityId, format, changeCount: changes.length },
        timestamp: Date.now(),
      });

      return { success: true, data };
    } catch (error) {
      this.logAudit(userId, 'export-changes', '', entityId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Replicate changes
   */
  public replicateChanges(
    changeIds: string[],
    targetUserIds: string[],
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; replicationId?: string } {
    try {
      const replicationId = `repl-${Date.now()}-${Math.random().toString(16).slice(2)}`;

      this.logAudit(userId, 'replicate-changes', '', '', {
        replicationId,
        changeCount: changeIds.length,
        targetUserCount: targetUserIds.length,
      });

      this.emit('replication-started', {
        data_object: { replicationId, userId, targetCount: targetUserIds.length },
        timestamp: Date.now(),
      });

      return { success: true, replicationId };
    } catch (error) {
      this.logAudit(userId, 'replicate-changes', '', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Update timeline
   */
  private updateTimeline(entityId: string, change: Change): void {
    if (!this.timelines.has(entityId)) {
      this.timelines.set(entityId, {
        entityId,
        entityType: change.entityType,
        changeHistory: [],
        firstChangeAt: change.timestamp,
        lastChangeAt: change.timestamp,
        totalChangeCount: 0,
        currentStatus: change.status,
      });
    }

    const timeline = this.timelines.get(entityId)!;
    const historyEntry: ChangeHistoryEntry = {
      changeId: change.changeId,
      entityId,
      operation: change.operation,
      userId: change.userId,
      timestamp: change.timestamp,
      status: change.status,
      description: change.description,
    };

    timeline.changeHistory.push(historyEntry);
    timeline.lastChangeAt = change.timestamp;
    timeline.totalChangeCount++;
    timeline.currentStatus = change.status;
  }

  /**
   * Log audit entry
   */
  private logAudit(
    userId: string,
    action: string,
    changeId: string,
    entityId: string,
    details?: Record<string, unknown>
  ): void {
    if (!this.auditLog.has(userId)) {
      this.auditLog.set(userId, []);
    }

    const entry: ChangeAuditEntry = {
      timestamp: Date.now(),
      userId,
      userEmail: `user-${userId}@example.com`,
      action,
      changeId: changeId || undefined,
      entityId: entityId || undefined,
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
   * Update configuration
   */
  public updateConfig(config: Partial<ChangeStreamConfig>): void {
    this.config = { ...this.config, ...config };

    this.emit('config-updated', {
      data_object: { config: this.config },
      timestamp: Date.now(),
    });
  }

  /**
   * Shutdown service
   */
  public shutdown(): void {
    this.changes.clear();
    this.entityChanges.clear();
    this.subscriptions.clear();
    this.userSubscriptions.clear();
    this.conflicts.clear();
    this.timelines.clear();
    this.auditLog.clear();

    this.emit('shutdown', {
      data_object: { service: 'change-stream', status: 'shutdown' },
      timestamp: Date.now(),
    });
  }
}
