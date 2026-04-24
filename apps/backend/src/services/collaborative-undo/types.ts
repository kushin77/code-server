/**
 * Collaborative Undo/Redo Service Types
 * Operational transformation-based undo/redo with multi-user support
 */

/**
 * Operation type
 */
export type OperationType = 'insert' | 'delete' | 'replace' | 'format' | 'metadata';

/**
 * Single operation
 */
export interface Operation {
  id: string;
  type: OperationType;
  userId: string;
  userEmail: string;
  timestamp: number;
  path: string; // file path or document identifier
  position: number; // cursor position
  content?: string; // for insert/replace
  oldContent?: string; // for delete/replace
  length?: number; // for delete
  metadata?: Record<string, unknown>;
}

/**
 * Operation with conflict resolution info
 */
export interface OperationWithResolution extends Operation {
  parentId: string; // ID of parent operation
  conflicts: string[]; // IDs of conflicting operations
  resolved: boolean;
  resolutionStrategy: 'local-first' | 'remote-first' | 'merge' | 'manual';
}

/**
 * Undo/Redo history entry
 */
export interface HistoryEntry {
  id: string;
  operations: Operation[];
  timestamp: number;
  userId: string;
  userEmail: string;
  description: string;
  reversible: boolean;
}

/**
 * History state
 */
export interface HistoryState {
  present: HistoryEntry[];
  undo: HistoryEntry[];
  redo: HistoryEntry[];
  checkpoint: HistoryEntry | null;
}

/**
 * Undo request
 */
export interface UndoRequest {
  userId: string;
  userEmail: string;
  count?: number; // number of actions to undo
  targetId?: string; // undo to specific history entry
}

/**
 * Redo request
 */
export interface RedoRequest {
  userId: string;
  userEmail: string;
  count?: number; // number of actions to redo
  targetId?: string; // redo to specific history entry
}

/**
 * Undo result
 */
export interface UndoResult {
  success: boolean;
  undoneOperations: Operation[];
  newState?: Record<string, unknown>;
  conflicts?: string[];
  reversedAt: number;
}

/**
 * Redo result
 */
export interface RedoResult {
  success: boolean;
  redoneOperations: Operation[];
  newState?: Record<string, unknown>;
  conflicts?: string[];
  redoneAt: number;
}

/**
 * Collaborative context for operation
 */
export interface CollaborativeContext {
  documentId: string;
  userId: string;
  userEmail: string;
  sessionId: string;
  cursorPosition: number;
  viewportStart: number;
  viewportEnd: number;
}

/**
 * Conflict resolution strategy options
 */
export interface ConflictResolutionOptions {
  strategy: 'local-first' | 'remote-first' | 'merge' | 'manual';
  mergeFunction?: (local: Operation, remote: Operation) => Operation;
  onManualResolution?: (conflict: ConflictInfo) => Promise<Operation>;
}

/**
 * Conflict information
 */
export interface ConflictInfo {
  operationId: string;
  conflictingOperationId: string;
  position: number;
  localContent: string;
  remoteContent: string;
  overlappingRange: [number, number];
}

/**
 * Service configuration
 */
export interface CollaborativeUndoRedoConfig {
  maxHistorySize: number;
  enableConflictDetection: boolean;
  conflictResolutionStrategy: 'local-first' | 'remote-first' | 'merge' | 'manual';
  enableCompression: boolean;
  compressionThreshold: number;
  checkpointInterval: number; // ms
  maxAuditLogSize: number;
  enableCrossUserUndo: boolean; // allow undoing other users' operations in collaborative mode
}

/**
 * Audit log entry
 */
export interface UndoRedoAuditEntry {
  id: string;
  userId: string;
  userEmail: string;
  operation: 'undo' | 'redo' | 'operation-recorded' | 'checkpoint-created' | 'history-cleared';
  status: 'success' | 'failure';
  operationCount?: number;
  conflictCount?: number;
  ipAddress: string;
  userAgent: string;
  timestamp: number;
  details: {
    reason?: string;
    affectedPaths?: string[];
    conflictsResolved?: number;
    [key: string]: unknown;
  };
}

/**
 * Statistics
 */
export interface UndoRedoStatistics {
  totalOperations: number;
  totalUndos: number;
  totalRedos: number;
  totalConflicts: number;
  averageConflictResolutionTimeMs: number;
  mostActiveUser: string;
  lastOperationAt: number;
  historyDepth: number;
}
