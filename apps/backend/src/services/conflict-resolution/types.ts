/**
 * Workspace Conflict Resolution - Type Definitions
 * @file        apps/backend/src/services/conflict-resolution/types.ts
 * @module      services/conflict-resolution
 * @description Detect and resolve workspace file/state conflicts in collaborative editing
 */

import { EventEmitter } from 'events';

/**
 * Conflict type
 */
export type ConflictType =
  | 'file-content'
  | 'file-delete'
  | 'file-move'
  | 'file-rename'
  | 'file-permission'
  | 'state-merge'
  | 'symbolic-link'
  | 'git-merge-conflict';

/**
 * Conflict severity
 */
export type ConflictSeverity = 'low' | 'medium' | 'high' | 'critical';

/**
 * Resolution strategy
 */
export type ResolutionStrategy =
  | 'keep-local'
  | 'keep-remote'
  | 'merge'
  | 'manual'
  | 'version-control'
  | 'timestamp-based'
  | 'user-preference'
  | 'auto-merge';

/**
 * File conflict
 */
export interface FileConflict {
  id: string;
  filePath: string;
  conflictType: ConflictType;
  severity: ConflictSeverity;
  localVersion: FileVersion;
  remoteVersion: FileVersion;
  timestamp: number;
  resolvedAt?: number;
  resolution?: ConflictResolution;
  participants: string[];
  tags: string[];
}

/**
 * File version
 */
export interface FileVersion {
  userId: string;
  userEmail: string;
  content?: string;
  hash: string;
  size: number;
  timestamp: number;
  checksum: string;
  metadata?: Map<string, unknown>;
}

/**
 * Conflict resolution
 */
export interface ConflictResolution {
  id: string;
  conflictId: string;
  strategy: ResolutionStrategy;
  resolvedBy: string;
  resolvedAt: number;
  resultingContent?: string;
  mergeDetails?: MergeDetails;
  manualEdits?: boolean;
  confidence: number;
  metadata?: Map<string, unknown>;
}

/**
 * Merge details
 */
export interface MergeDetails {
  localLines: string[];
  remoteLines: string[];
  mergedLines: string[];
  conflictMarkers: ConflictMarker[];
  linesMerged: number;
  linesConflicting: number;
  mergeSuccessful: boolean;
}

/**
 * Conflict marker
 */
export interface ConflictMarker {
  startLine: number;
  endLine: number;
  type: 'local' | 'remote' | 'both';
  marker: string;
}

/**
 * State conflict
 */
export interface StateConflict {
  id: string;
  workspaceId: string;
  stateName: string;
  conflictType: ConflictType;
  severity: ConflictSeverity;
  localState: WorkspaceState;
  remoteState: WorkspaceState;
  timestamp: number;
  resolvedAt?: number;
  resolution?: StateResolution;
  participants: string[];
}

/**
 * Workspace state
 */
export interface WorkspaceState {
  userId: string;
  userEmail: string;
  openFiles: string[];
  selectedFile?: string;
  cursorPositions: Map<string, CursorPosition>;
  viewportState: Map<string, ViewportState>;
  timestamp: number;
}

/**
 * Cursor position
 */
export interface CursorPosition {
  line: number;
  column: number;
  selection?: {
    startLine: number;
    startColumn: number;
    endLine: number;
    endColumn: number;
  };
}

/**
 * Viewport state
 */
export interface ViewportState {
  scrollLine: number;
  scrollColumn: number;
  visibleRange: {
    startLine: number;
    endLine: number;
  };
}

/**
 * State resolution
 */
export interface StateResolution {
  id: string;
  stateConflictId: string;
  strategy: ResolutionStrategy;
  resolvedBy: string;
  resolvedAt: number;
  resultingState: WorkspaceState;
  confidence: number;
}

/**
 * Conflict detection result
 */
export interface ConflictDetectionResult {
  success: boolean;
  conflicts: FileConflict[];
  stateConflicts: StateConflict[];
  totalConflicts: number;
  criticalCount: number;
  warningCount: number;
  error?: string;
}

/**
 * Conflict resolution result
 */
export interface ConflictResolutionResult {
  success: boolean;
  conflictId: string;
  resolution?: ConflictResolution;
  newContent?: string;
  error?: string;
  warnings: string[];
}

/**
 * Batch resolution result
 */
export interface BatchResolutionResult {
  success: boolean;
  totalProcessed: number;
  resolved: number;
  failed: number;
  skipped: number;
  details: ConflictResolutionResult[];
}

/**
 * Conflict history
 */
export interface ConflictHistoryEntry {
  id: string;
  conflictId: string;
  timestamp: number;
  action: ConflictAction;
  userId: string;
  userEmail: string;
  details: Map<string, unknown>;
}

/**
 * Conflict action
 */
export type ConflictAction =
  | 'conflict-detected'
  | 'resolution-attempted'
  | 'resolution-successful'
  | 'resolution-failed'
  | 'resolution-reviewed'
  | 'resolution-reverted'
  | 'conflict-archived';

/**
 * Audit entry for conflict operations
 */
export interface ConflictAuditEntry {
  timestamp: number;
  userId: string;
  userEmail: string;
  ipAddress: string;
  userAgent: string;
  operation: ConflictOperation;
  conflictId?: string;
  filePath?: string;
  status: 'success' | 'failure';
  details: Map<string, unknown>;
}

/**
 * Conflict operation type
 */
export type ConflictOperation =
  | 'conflict-detected'
  | 'conflict-resolved'
  | 'conflict-reviewed'
  | 'state-synced'
  | 'merge-executed'
  | 'resolution-reverted';

/**
 * Conflict statistics
 */
export interface ConflictStatistics {
  totalConflicts: number;
  resolvedConflicts: number;
  unresolvedConflicts: number;
  conflictsByType: Map<ConflictType, number>;
  conflictsBySeverity: Map<ConflictSeverity, number>;
  mostCommonConflictType: ConflictType | null;
  averageResolutionTime: number;
  successRate: number;
  mostActiveUsers: string[];
  mostConflictedFiles: string[];
}

/**
 * Conflict settings
 */
export interface ConflictSettings {
  autoResolveEnabled: boolean;
  autoResolutionStrategy: ResolutionStrategy;
  conflictDetectionInterval: number;
  maxConflictHistorySize: number;
  maxAuditLogSize: number;
  enableMergeConflictAnalysis: boolean;
  enableStateConflictDetection: boolean;
  preserveConflictMarkers: boolean;
  retentionDays: number;
}

/**
 * Service interface
 */
export interface IConflictResolutionService extends EventEmitter {
  detectConflicts(
    workspaceId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): ConflictDetectionResult;

  reportConflict(
    conflict: FileConflict,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; conflictId?: string; error?: string };

  resolveConflict(
    conflictId: string,
    strategy: ResolutionStrategy,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): ConflictResolutionResult;

  getConflict(conflictId: string): { success: boolean; conflict?: FileConflict; error?: string };

  listConflicts(
    workspaceId?: string,
    status?: 'unresolved' | 'resolved' | 'all'
  ): FileConflict[];

  getConflictHistory(
    conflictId: string,
    limit?: number
  ): ConflictHistoryEntry[];

  suggestResolution(
    conflictId: string
  ): { success: boolean; suggestion?: ResolutionStrategy; confidence?: number; error?: string };

  mergeConflict(
    conflictId: string,
    localVersion: FileVersion,
    remoteVersion: FileVersion,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): ConflictResolutionResult;

  revertResolution(
    resolutionId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; error?: string };

  detectStateConflicts(
    workspaceId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): StateConflict[];

  resolveStateConflict(
    stateConflictId: string,
    strategy: ResolutionStrategy,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; resolution?: StateResolution; error?: string };

  batchResolveConflicts(
    conflictIds: string[],
    strategy: ResolutionStrategy,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): BatchResolutionResult;

  getStatistics(): ConflictStatistics;

  archiveConflict(
    conflictId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; error?: string };

  updateSettings(
    settings: Partial<ConflictSettings>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): void;

  shutdown(): void;
}
