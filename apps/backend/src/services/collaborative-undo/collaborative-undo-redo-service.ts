/**
 * Collaborative Undo/Redo Service
 * Operational transformation-based undo/redo with multi-user support
 */

import { EventEmitter } from 'events';
import {
  Operation,
  OperationWithResolution,
  HistoryEntry,
  HistoryState,
  UndoRequest,
  RedoRequest,
  UndoResult,
  RedoResult,
  ConflictResolutionOptions,
  CollaborativeUndoRedoConfig,
  UndoRedoAuditEntry,
  UndoRedoStatistics,
} from './types.js';

/**
 * Collaborative Undo/Redo Service
 * Manages multi-user undo/redo with conflict detection and resolution
 */
export class CollaborativeUndoRedoService extends EventEmitter {
  private static instance: CollaborativeUndoRedoService;

  private history: Map<string, HistoryState> = new Map(); // Per document
  private operations: Map<string, Operation[]> = new Map(); // All operations per document
  private conflicts: Map<string, OperationWithResolution[]> = new Map(); // Detected conflicts
  private auditLog: Map<string, UndoRedoAuditEntry[]> = new Map(); // Per user
  private statistics: UndoRedoStatistics;
  private config: CollaborativeUndoRedoConfig;

  private constructor(config?: Partial<CollaborativeUndoRedoConfig>) {
    super();
    this.config = {
      maxHistorySize: 100,
      enableConflictDetection: true,
      conflictResolutionStrategy: 'merge',
      enableCompression: false,
      compressionThreshold: 1000,
      checkpointInterval: 60000,
      maxAuditLogSize: 10000,
      enableCrossUserUndo: false,
      ...config,
    };

    this.statistics = {
      totalOperations: 0,
      totalUndos: 0,
      totalRedos: 0,
      totalConflicts: 0,
      averageConflictResolutionTimeMs: 0,
      mostActiveUser: '',
      lastOperationAt: 0,
      historyDepth: 0,
    };
  }

  /**
   * Get or create singleton instance
   */
  static getInstance(config?: Partial<CollaborativeUndoRedoConfig>): CollaborativeUndoRedoService {
    if (!CollaborativeUndoRedoService.instance) {
      CollaborativeUndoRedoService.instance = new CollaborativeUndoRedoService(config);
      CollaborativeUndoRedoService.instance.initialize();
    }
    return CollaborativeUndoRedoService.instance;
  }

  /**
   * Initialize service
   */
  private initialize(): void {
    this.emit('initialized', { timestamp: Date.now() });
  }

  /**
   * Shutdown service
   */
  shutdown(): void {
    this.history.clear();
    this.operations.clear();
    this.conflicts.clear();
    this.auditLog.clear();
    this.emit('shutdown', { timestamp: Date.now() });
  }

  /**
   * Record an operation
   */
  recordOperation(
    operation: Operation,
    documentId: string,
    ipAddress: string,
    userAgent: string
  ): boolean {
    try {
      if (!this.history.has(documentId)) {
        this.history.set(documentId, {
          present: [],
          undo: [],
          redo: [],
          checkpoint: null,
        });
        this.operations.set(documentId, []);
      }

      const state = this.history.get(documentId)!;
      const allOps = this.operations.get(documentId)!;

      // Create history entry
      const entry: HistoryEntry = {
        id: `hist-${Date.now()}-${Math.random().toString(16).slice(2)}`,
        operations: [operation],
        timestamp: Date.now(),
        userId: operation.userId,
        userEmail: operation.userEmail,
        description: `${operation.type} at ${operation.position}`,
        reversible: this.isReversible(operation),
      };

      state.present.push(entry);
      allOps.push(operation);

      // Limit history size
      if (state.present.length > this.config.maxHistorySize) {
        state.present.shift();
      }

      // Clear redo on new operation
      state.redo = [];

      // Detect conflicts if enabled
      if (this.config.enableConflictDetection && allOps.length > 1) {
        this.detectConflicts(documentId, operation);
      }

      // Update statistics
      this.statistics.totalOperations++;
      this.statistics.lastOperationAt = Date.now();
      this.statistics.historyDepth = state.present.length;

      this.recordAudit({
        userId: operation.userId,
        userEmail: operation.userEmail,
        operation: 'operation-recorded',
        status: 'success',
        ipAddress,
        userAgent,
        details: {
          operationType: operation.type,
          path: operation.path,
          documentId,
        },
      });

      this.emit('operation-recorded', { operation, documentId, timestamp: Date.now() });
      return true;
    } catch (error) {
      this.recordAudit({
        userId: operation.userId,
        userEmail: operation.userEmail,
        operation: 'operation-recorded',
        status: 'failure',
        ipAddress,
        userAgent,
        details: { reason: error instanceof Error ? error.message : 'Unknown error' },
      });
      return false;
    }
  }

  /**
   * Perform undo
   */
  undo(request: UndoRequest, documentId: string, ipAddress: string, userAgent: string): UndoResult {
    const state = this.history.get(documentId);
    if (!state || state.present.length === 0) {
      return {
        success: false,
        undoneOperations: [],
        reversedAt: Date.now(),
      };
    }

    try {
      const count = request.count || 1;
      const undoneOperations: Operation[] = [];

      for (let i = 0; i < count && state.present.length > 0; i++) {
        const entry = state.present.pop()!;
        state.redo.push(entry); // Push to REDO stack, not undo
        undoneOperations.push(...entry.operations);
      }

      this.statistics.totalUndos++;
      this.statistics.historyDepth = state.present.length;

      this.recordAudit({
        userId: request.userId,
        userEmail: request.userEmail,
        operation: 'undo',
        status: 'success',
        operationCount: undoneOperations.length,
        ipAddress,
        userAgent,
        details: { count },
      });

      this.emit('undo-performed', { undoneOperations, documentId, timestamp: Date.now() });

      return {
        success: true,
        undoneOperations,
        reversedAt: Date.now(),
      };
    } catch (error) {
      this.recordAudit({
        userId: request.userId,
        userEmail: request.userEmail,
        operation: 'undo',
        status: 'failure',
        ipAddress,
        userAgent,
        details: { reason: error instanceof Error ? error.message : 'Unknown error' },
      });

      return {
        success: false,
        undoneOperations: [],
        reversedAt: Date.now(),
      };
    }
  }

  /**
   * Perform redo
   */
  redo(request: RedoRequest, documentId: string, ipAddress: string, userAgent: string): RedoResult {
    const state = this.history.get(documentId);
    if (!state || state.redo.length === 0) {
      return {
        success: false,
        redoneOperations: [],
        redoneAt: Date.now(),
      };
    }

    try {
      const count = request.count || 1;
      const redoneOperations: Operation[] = [];

      for (let i = 0; i < count && state.redo.length > 0; i++) {
        const entry = state.redo.pop()!;
        state.present.push(entry); // Push back to present
        redoneOperations.push(...entry.operations);
      }

      this.statistics.totalRedos++;
      this.statistics.historyDepth = state.present.length;

      this.recordAudit({
        userId: request.userId,
        userEmail: request.userEmail,
        operation: 'redo',
        status: 'success',
        operationCount: redoneOperations.length,
        ipAddress,
        userAgent,
        details: { count },
      });

      this.emit('redo-performed', { redoneOperations, documentId, timestamp: Date.now() });

      return {
        success: true,
        redoneOperations,
        redoneAt: Date.now(),
      };
    } catch (error) {
      this.recordAudit({
        userId: request.userId,
        userEmail: request.userEmail,
        operation: 'redo',
        status: 'failure',
        ipAddress,
        userAgent,
        details: { reason: error instanceof Error ? error.message : 'Unknown error' },
      });

      return {
        success: false,
        redoneOperations: [],
        redoneAt: Date.now(),
      };
    }
  }

  /**
   * Get history state
   */
  getHistoryState(documentId: string): HistoryState | null {
    return this.history.get(documentId) || null;
  }

  /**
   * Can undo
   */
  canUndo(documentId: string): boolean {
    const state = this.history.get(documentId);
    return state ? state.present.length > 0 : false;
  }

  /**
   * Can redo
   */
  canRedo(documentId: string): boolean {
    const state = this.history.get(documentId);
    return state ? state.redo.length > 0 : false;
  }

  /**
   * Get undo count
   */
  getUndoCount(documentId: string): number {
    const state = this.history.get(documentId);
    return state ? state.present.length : 0;
  }

  /**
   * Get redo count
   */
  getRedoCount(documentId: string): number {
    const state = this.history.get(documentId);
    return state ? state.redo.length : 0;
  }

  /**
   * Create checkpoint
   */
  createCheckpoint(
    documentId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): boolean {
    const state = this.history.get(documentId);
    if (!state || state.present.length === 0) {
      return false;
    }

    try {
      const checkpoint = state.present[state.present.length - 1];
      state.checkpoint = checkpoint;

      this.recordAudit({
        userId,
        userEmail: '',
        operation: 'checkpoint-created',
        status: 'success',
        ipAddress,
        userAgent,
        details: { checkpointId: checkpoint.id },
      });

      this.emit('checkpoint-created', { documentId, checkpointId: checkpoint.id, timestamp: Date.now() });
      return true;
    } catch (error) {
      this.recordAudit({
        userId,
        userEmail: '',
        operation: 'checkpoint-created',
        status: 'failure',
        ipAddress,
        userAgent,
        details: { reason: error instanceof Error ? error.message : 'Unknown error' },
      });
      return false;
    }
  }

  /**
   * Get audit log
   */
  getAuditLog(userId: string): UndoRedoAuditEntry[] {
    return (this.auditLog.get(userId) || []).slice(-100);
  }

  /**
   * Get statistics
   */
  getStatistics(): UndoRedoStatistics {
    return { ...this.statistics };
  }

  /**
   * Update configuration
   */
  updateConfig(
    config: Partial<CollaborativeUndoRedoConfig>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): void {
    this.config = { ...this.config, ...config };
    this.emit('config-updated', { config: this.config, timestamp: Date.now() });
  }

  /**
   * Clear history for document
   */
  clearHistory(documentId: string, userId: string, ipAddress: string, userAgent: string): boolean {
    try {
      this.history.delete(documentId);
      this.operations.delete(documentId);
      this.conflicts.delete(documentId);

      this.recordAudit({
        userId,
        userEmail: '',
        operation: 'history-cleared',
        status: 'success',
        ipAddress,
        userAgent,
        details: { documentId },
      });

      this.emit('history-cleared', { documentId, timestamp: Date.now() });
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * Static reset for testing
   */
  static reset(): void {
    if (CollaborativeUndoRedoService.instance) {
      CollaborativeUndoRedoService.instance.shutdown();
    }
    CollaborativeUndoRedoService.instance = undefined as any;
  }

  /**
   * Private helper: Detect conflicts
   */
  private detectConflicts(documentId: string, operation: Operation): void {
    const allOps = this.operations.get(documentId) || [];
    const docConflicts = this.conflicts.get(documentId) || [];

    for (const op of allOps) {
      if (op.id === operation.id) continue;

      // Check for overlapping positions
      if (
        (operation.position >= op.position && operation.position < (op.position + (op.length || 1))) ||
        (op.position >= operation.position && op.position < (operation.position + (operation.length || 1)))
      ) {
        // Conflict detected
        const conflictOp: OperationWithResolution = {
          ...operation,
          parentId: op.id,
          conflicts: [op.id],
          resolved: false,
          resolutionStrategy: this.config.conflictResolutionStrategy,
        };

        docConflicts.push(conflictOp);
        this.statistics.totalConflicts++;

        if (!this.conflicts.has(documentId)) {
          this.conflicts.set(documentId, []);
        }
        this.conflicts.get(documentId)!.push(conflictOp);

        this.emit('conflict-detected', { operation, conflictingOp: op, documentId, timestamp: Date.now() });
      }
    }
  }

  /**
   * Private helper: Check if operation is reversible
   */
  private isReversible(operation: Operation): boolean {
    return operation.type !== 'metadata';
  }

  /**
   * Private helper: Record audit entry
   */
  private recordAudit(entry: {
    userId: string;
    userEmail: string;
    operation: 'undo' | 'redo' | 'operation-recorded' | 'checkpoint-created' | 'history-cleared';
    status: 'success' | 'failure';
    operationCount?: number;
    conflictCount?: number;
    ipAddress: string;
    userAgent: string;
    details?: Record<string, unknown>;
  }): void {
    const auditEntry: UndoRedoAuditEntry = {
      id: `audit-${Date.now()}-${Math.random().toString(16).slice(2)}`,
      userId: entry.userId,
      userEmail: entry.userEmail,
      operation: entry.operation,
      status: entry.status,
      operationCount: entry.operationCount,
      conflictCount: entry.conflictCount,
      ipAddress: entry.ipAddress,
      userAgent: entry.userAgent,
      timestamp: Date.now(),
      details: entry.details || {},
    };

    if (!this.auditLog.has(entry.userId)) {
      this.auditLog.set(entry.userId, []);
    }

    const userLog = this.auditLog.get(entry.userId)!;
    userLog.push(auditEntry);

    if (userLog.length > this.config.maxAuditLogSize) {
      userLog.splice(0, userLog.length - this.config.maxAuditLogSize);
    }

    this.emit('audit-logged', { entry: auditEntry, timestamp: Date.now() });
  }
}
