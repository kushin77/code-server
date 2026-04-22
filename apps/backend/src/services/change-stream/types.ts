/**
 * Real-time Change Stream Service Types
 * @file        apps/backend/src/services/change-stream/types.ts
 * @module      services/change-stream
 * @description Type definitions for change stream functionality
 */

/**
 * Change operation types
 */
export type ChangeOperation = 'create' | 'update' | 'delete' | 'replace' | 'move';

/**
 * Change entity type
 */
export type ChangeEntityType = 'file' | 'directory' | 'workspace' | 'project' | 'document';

/**
 * Change severity level
 */
export type ChangeSeverity = 'low' | 'medium' | 'high' | 'critical';

/**
 * Change status
 */
export type ChangeStatus = 'pending' | 'applied' | 'reverted' | 'conflicted' | 'archived';

/**
 * Basic change metadata
 */
export interface ChangeMetadata {
  changeId: string;
  entityId: string;
  entityType: ChangeEntityType;
  operation: ChangeOperation;
  userId: string;
  userEmail: string;
  timestamp: number;
  status: ChangeStatus;
  severity: ChangeSeverity;
}

/**
 * Detailed change information
 */
export interface Change extends ChangeMetadata {
  previousValue?: unknown;
  newValue: unknown;
  parentEntityId?: string;
  tags: string[];
  description: string;
  appliedAt?: number;
  revertedAt?: number;
  conflictInfo?: ConflictInfo;
  metadata: Record<string, unknown>;
}

/**
 * Change conflict information
 */
export interface ConflictInfo {
  conflictId: string;
  conflictingChangeId: string;
  conflictType: 'content' | 'position' | 'state' | 'permission';
  severity: ChangeSeverity;
  detectedAt: number;
  resolutionStatus: 'pending' | 'resolved' | 'abandoned';
}

/**
 * Change stream subscription
 */
export interface ChangeStreamSubscription {
  subscriptionId: string;
  userId: string;
  entityId?: string;
  entityType?: ChangeEntityType;
  operations?: ChangeOperation[];
  status: 'active' | 'paused' | 'cancelled';
  createdAt: number;
  filters?: {
    minSeverity?: ChangeSeverity;
    maxResults?: number;
    includeArchived?: boolean;
  };
}

/**
 * Change stream event
 */
export interface ChangeStreamEvent {
  eventId: string;
  subscriptionId: string;
  change: Change;
  timestamp: number;
  deliveryAttempts: number;
}

/**
 * Change history entry
 */
export interface ChangeHistoryEntry {
  changeId: string;
  entityId: string;
  operation: ChangeOperation;
  userId: string;
  timestamp: number;
  status: ChangeStatus;
  description: string;
}

/**
 * Change statistics
 */
export interface ChangeStatistics {
  totalChanges: number;
  changesByOperation: Record<ChangeOperation, number>;
  changesByEntityType: Record<ChangeEntityType, number>;
  changesByStatus: Record<ChangeStatus, number>;
  changeBySeverity: Record<ChangeSeverity, number>;
  averageApplicationTimeMs: number;
  conflictCount: number;
  revertCount: number;
}

/**
 * Change batch operation
 */
export interface ChangeBatch {
  batchId: string;
  userId: string;
  changes: Change[];
  createdAt: number;
  appliedAt?: number;
  status: 'pending' | 'applied' | 'reverted' | 'partially-applied';
  description: string;
}

/**
 * Change rollback result
 */
export interface RollbackResult {
  rollbackId: string;
  affectedChangeIds: string[];
  rollbackStatus: 'success' | 'partial' | 'failed';
  revertsCount: number;
  timestamp: number;
  errors?: string[];
}

/**
 * Change notification
 */
export interface ChangeNotification {
  notificationId: string;
  userId: string;
  change: Change;
  notificationType: 'creation' | 'update' | 'deletion' | 'conflict';
  sentAt: number;
  readAt?: number;
}

/**
 * Entity change timeline
 */
export interface EntityChangeTimeline {
  entityId: string;
  entityType: ChangeEntityType;
  changeHistory: ChangeHistoryEntry[];
  firstChangeAt: number;
  lastChangeAt: number;
  totalChangeCount: number;
  currentStatus: ChangeStatus;
}

/**
 * Change replication state
 */
export interface ReplicationState {
  entityId: string;
  sourceUserId: string;
  targetUserIds: string[];
  lastReplicatedAt: number;
  replicationStatus: 'pending' | 'in-progress' | 'completed' | 'failed';
  errorDetails?: string;
}

/**
 * Change collaboration context
 */
export interface CollaborationContext {
  changeId: string;
  collaborators: string[];
  commentThread?: {
    threadId: string;
    comments: Array<{
      commentId: string;
      userId: string;
      text: string;
      createdAt: number;
    }>;
  };
  reviewStatus?: 'pending' | 'approved' | 'rejected';
}

/**
 * Audit entry for changes
 */
export interface ChangeAuditEntry {
  timestamp: number;
  userId: string;
  userEmail: string;
  action: string;
  changeId?: string;
  entityId?: string;
  details: Record<string, unknown>;
}

/**
 * Service configuration
 */
export interface ChangeStreamConfig {
  enableChangeTracking: boolean;
  maxChangesPerUser: number;
  maxSubscriptionsPerUser: number;
  conflictDetectionEnabled: boolean;
  autoReplicateChanges: boolean;
  changeRetentionDays: number;
  maxAuditEntries: number;
  batchProcessingIntervalMs: number;
  notificationEnabled: boolean;
  enableChangeCompression: boolean;
}

/**
 * Change stream service interface
 */
export interface IChangeStreamService {
  recordChange(
    change: Omit<Change, 'changeId' | 'timestamp' | 'appliedAt'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; changeId?: string };

  getChange(changeId: string): Change | undefined;

  getEntityChanges(entityId: string, limit?: number): Change[];

  createSubscription(
    subscription: Omit<ChangeStreamSubscription, 'subscriptionId' | 'createdAt'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; subscriptionId?: string };

  updateSubscription(
    subscriptionId: string,
    updates: Partial<ChangeStreamSubscription>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  deleteSubscription(
    subscriptionId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  getSubscriptions(userId: string): ChangeStreamSubscription[];

  publishChange(
    change: Change,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; affectedSubscriptions?: number };

  detectConflicts(
    changeId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; conflicts?: ConflictInfo[] };

  resolveConflict(
    conflictId: string,
    resolution: 'accept' | 'reject' | 'merge',
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  applyChange(
    changeId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; applicationTimeMs?: number };

  batchApplyChanges(
    changeIds: string[],
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; appliedCount?: number; batchId?: string };

  revertChange(
    changeId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  rollbackChanges(
    changeIds: string[],
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; rollbackId?: string; revertedCount?: number };

  getChangeTimeline(entityId: string): EntityChangeTimeline | undefined;

  getStatistics(userId?: string): ChangeStatistics;

  getAuditLog(limit?: number): ChangeAuditEntry[];

  archiveOldChanges(
    daysOld: number,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; archivedCount?: number };

  exportChanges(
    entityId: string,
    format: 'json' | 'csv',
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; data?: string };

  replicateChanges(
    changeIds: string[],
    targetUserIds: string[],
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; replicationId?: string };

  updateConfig(config: Partial<ChangeStreamConfig>): void;

  shutdown(): void;
}
