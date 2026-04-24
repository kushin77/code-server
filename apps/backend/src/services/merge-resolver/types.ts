#!/usr/bin/env node
/**
 * @file        apps/backend/src/services/merge-resolver/types.ts
 * @module      services/collaboration/merge-resolver
 * @description Type definitions for 3-way merge conflict resolver service
 */

/**
 * Conflict side type
 */
export type ConflictSide = 'ours' | 'theirs' | 'merged';

/**
 * Resolution strategy
 */
export type ResolutionStrategy = 'ours' | 'theirs' | 'manual' | 'smart-merge' | 'abort';

/**
 * Merge conflict
 */
export interface MergeConflict {
  id: string; // Unique conflict identifier
  filePath: string;
  lineStart: number;
  lineEnd: number;
  oursContent: string;
  theirsContent: string;
  baseContent: string;
  status: 'unresolved' | 'resolved' | 'rejected';
  resolvedAt?: number;
  resolvedBy?: string; // User email
  resolutionStrategy?: ResolutionStrategy;
  resolvedContent?: string;
}

/**
 * Merge diff entry
 */
export interface MergeDiff {
  filePath: string;
  action: 'added' | 'modified' | 'deleted';
  conflictCount: number;
  conflicts: MergeConflict[];
  isConflicted: boolean;
}

/**
 * Merge session
 */
export interface MergeSession {
  id: string;
  userId: string;
  userEmail: string;
  timestamp: number;
  sourceBranch: string;
  targetBranch: string;
  baseCommit: string;
  oursCommit: string;
  theirsCommit: string;
  status: 'in-progress' | 'completed' | 'aborted';
  completedAt?: number;
  diffs: MergeDiff[];
  conflictCount: number;
  resolvedCount: number;
  abortedCount: number;
}

/**
 * Merge conflict resolution request
 */
export interface ResolutionRequest {
  userId: string;
  userEmail: string;
  conflictId: string;
  strategy: ResolutionStrategy;
  customContent?: string; // For manual resolution
  autoResolve?: boolean; // Auto-resolve similar conflicts
}

/**
 * Merge conflict resolution result
 */
export interface ResolutionResult {
  success: boolean;
  conflictId: string;
  resolvedAt: number;
  strategy: ResolutionStrategy;
  resolvedCount?: number; // Number of similar conflicts resolved
  message?: string;
}

/**
 * Merge completion request
 */
export interface MergeCompletionRequest {
  userId: string;
  userEmail: string;
  mergeSessionId: string;
  commitMessage: string;
  autoCommit?: boolean;
}

/**
 * Merge completion result
 */
export interface MergeCompletionResult {
  success: boolean;
  mergeSessionId: string;
  completedAt: number;
  commitHash?: string;
  conflictStats: {
    total: number;
    resolved: number;
    unresolved: number;
  };
  message?: string;
}

/**
 * Merge resolver service configuration
 */
export interface MergeResolverServiceConfig {
  maxConcurrentSessions?: number; // Default 20
  maxConflictSize?: number; // Max bytes per conflict, default 10MB
  enableSmartMerge?: boolean; // Default true
  autoResolveThreshold?: number; // Confidence threshold (0-1), default 0.8
  maxHistorySize?: number; // Default 1000
  maxAuditLogSize?: number; // Default 10000
  enableDiffCache?: boolean; // Default true
  diffCacheTTL?: number; // Default 3600000 (1 hour)
}

/**
 * Diff statistics
 */
export interface DiffStatistics {
  filesChanged: number;
  filesAdded: number;
  filesDeleted: number;
  totalConflicts: number;
  resolvedConflicts: number;
  unresolvedConflicts: number;
  averageResolutionTime: number; // ms
  smartMergeSuccessRate: number; // 0-1
}

/**
 * Merge resolver audit entry
 */
export interface MergeResolverAuditEntry {
  userId: string;
  userEmail: string;
  operation: 'merge-session-created' | 'conflict-resolved' | 'merge-completed' | 'merge-aborted' | 'smart-merge-applied';
  status: 'success' | 'failure';
  mergeSessionId?: string;
  conflictId?: string;
  resolutionStrategy?: ResolutionStrategy;
  details?: Record<string, unknown>;
  ipAddress: string;
  userAgent: string;
  timestamp: number;
}

/**
 * Merge resolver statistics
 */
export interface MergeResolverStatistics {
  totalSessions: number;
  completedSessions: number;
  abortedSessions: number;
  totalConflicts: number;
  resolvedConflicts: number;
  totalResolutions: number;
  smartMergeResolutions: number;
  manualResolutions: number;
  averageSessionDuration: number; // ms
  averageConflictsPerSession: number;
  smartMergeSuccessRate: number; // 0-1
  lastSessionAt: number;
}
