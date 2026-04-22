/**
 * Real-time Code Lens Provider Service
 * @file        apps/backend/src/services/code-lens-provider/code-lens-provider-service.ts
 * @module      services/code-lens-provider
 * @description Real-time code lens provider for integrated code intelligence
 */

import { EventEmitter } from 'events';
import {
  CodeLensMetadata,
  CodeLensReference,
  CodeLensStatistics,
  CodeLensRange,
  CodeLensBatchUpdate,
  CodeLensCommandExecution,
  CodeLensPerformanceMetric,
  CodeLensInvalidation,
  CodeLensCacheEntry,
  CodeLensAuditEntry,
  CodeLensConfig,
  ICodeLensService,
} from './types.js';

/**
 * Code Lens Provider Service
 * Provides real-time code lens integration with caching and performance tracking
 */
export class CodeLensProvider extends EventEmitter implements ICodeLensService {
  private static instance: CodeLensProvider | undefined;
  private lenses: Map<string, CodeLensMetadata> = new Map();
  private fileLenses: Map<string, Set<string>> = new Map(); // fileId -> lensIds
  private references: Map<string, CodeLensReference[]> = new Map(); // lensId -> references
  private cache: Map<string, CodeLensCacheEntry> = new Map(); // lensId -> cache
  private commandHistory: Map<string, CodeLensCommandExecution[]> = new Map(); // lensId -> executions
  private invalidations: Map<string, CodeLensInvalidation[]> = new Map(); // fileId -> invalidations
  private performanceMetrics: Map<string, CodeLensPerformanceMetric[]> = new Map(); // lensId -> metrics
  private auditLog: Map<string, CodeLensAuditEntry[]> = new Map(); // userId -> entries
  private stats: CodeLensStatistics = {
    totalLenses: 0,
    resolvedLenses: 0,
    unresolvedLenses: 0,
    totalReferences: 0,
    averageReferencesPerLens: 0,
    lensCount: {},
  };
  private cacheHits = 0;
  private cacheMisses = 0;
  private config: CodeLensConfig = {
    enableCodeLens: true,
    enableReferenceCounting: true,
    enableImplementationLens: true,
    cacheExpirationMs: 3600000, // 1 hour
    batchUpdateThreshold: 10,
    maxLensesPerFile: 1000,
    maxAuditEntries: 5000,
    performanceTrackingEnabled: true,
  };

  private constructor() {
    super();
    this.initialize();
  }

  /**
   * Get or create singleton instance
   */
  public static getInstance(config?: Partial<CodeLensConfig>): CodeLensProvider {
    if (!CodeLensProvider.instance) {
      CodeLensProvider.instance = new CodeLensProvider();
    }
    if (config) {
      CodeLensProvider.instance.updateConfig(config);
    }
    return CodeLensProvider.instance;
  }

  /**
   * Reset singleton for testing
   */
  public static reset(): void {
    CodeLensProvider.instance = undefined;
  }

  /**
   * Initialize service
   */
  private initialize(): void {
    this.emit('initialized', {
      data_object: { service: 'code-lens-provider', status: 'initialized' },
      timestamp: Date.now(),
    });
  }

  /**
   * Create code lens
   */
  public createCodeLens(
    metadata: Omit<CodeLensMetadata, 'lensId' | 'isResolved'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; lensId?: string } {
    try {
      if (!this.config.enableCodeLens) {
        return { success: false };
      }

      const lensId = `lens-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const lens: CodeLensMetadata = {
        ...metadata,
        lensId,
        isResolved: false,
      };

      this.lenses.set(lensId, lens);

      if (!this.fileLenses.has(metadata.fileId)) {
        this.fileLenses.set(metadata.fileId, new Set());
      }
      this.fileLenses.get(metadata.fileId)!.add(lensId);

      this.stats.totalLenses++;
      this.stats.unresolvedLenses++;

      this.logAudit(userId, 'create-code-lens', metadata.fileId, 'success', {
        lensId,
        title: metadata.title,
      });

      this.emit('code-lens-created', {
        data_object: { lensId, fileId: metadata.fileId, title: metadata.title },
        timestamp: Date.now(),
      });

      return { success: true, lensId };
    } catch (error) {
      this.logAudit(userId, 'create-code-lens', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Update code lens
   */
  public updateCodeLens(
    lensId: string,
    updates: Partial<CodeLensMetadata>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const lens = this.lenses.get(lensId);
      if (!lens) {
        return { success: false };
      }

      Object.assign(lens, updates);
      this.invalidateCache(lens.fileId, 'lens-updated', userId, ipAddress);

      this.logAudit(userId, 'update-code-lens', lens.fileId, 'success', {
        lensId,
      });

      this.emit('code-lens-updated', {
        data_object: { lensId, fileId: lens.fileId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'update-code-lens', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Delete code lens
   */
  public deleteCodeLens(lensId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean } {
    try {
      const lens = this.lenses.get(lensId);
      if (!lens) {
        return { success: false };
      }

      this.lenses.delete(lensId);
      this.fileLenses.get(lens.fileId)?.delete(lensId);
      this.references.delete(lensId);
      this.cache.delete(lensId);
      this.commandHistory.delete(lensId);

      this.stats.totalLenses--;
      if (lens.isResolved) {
        this.stats.resolvedLenses--;
      } else {
        this.stats.unresolvedLenses--;
      }

      this.logAudit(userId, 'delete-code-lens', lens.fileId, 'success', {
        lensId,
      });

      this.emit('code-lens-deleted', {
        data_object: { lensId, fileId: lens.fileId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'delete-code-lens', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get code lens
   */
  public getCodeLens(lensId: string): CodeLensMetadata | undefined {
    return this.lenses.get(lensId);
  }

  /**
   * Resolve code lens
   */
  public resolveCodeLens(lensId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean; metadata?: CodeLensMetadata } {
    try {
      const lens = this.lenses.get(lensId);
      if (!lens) {
        return { success: false };
      }

      if (!lens.isResolved) {
        lens.isResolved = true;
        lens.resolvedAt = Date.now();
        this.stats.unresolvedLenses--;
        this.stats.resolvedLenses++;
      }

      // Add to cache
      const cacheEntry: CodeLensCacheEntry = {
        lensId,
        lensMetadata: lens,
        references: this.references.get(lensId) || [],
        computedAt: Date.now(),
        expiresAt: Date.now() + this.config.cacheExpirationMs,
        hitCount: 0,
      };
      this.cache.set(lensId, cacheEntry);

      this.logAudit(userId, 'resolve-code-lens', lens.fileId, 'success', {
        lensId,
      });

      this.emit('code-lens-resolved', {
        data_object: { lensId, fileId: lens.fileId },
        timestamp: Date.now(),
      });

      return { success: true, metadata: lens };
    } catch (error) {
      this.logAudit(userId, 'resolve-code-lens', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Resolve lenses in file
   */
  public resolveLensesInFile(fileId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean; resolvedCount?: number } {
    try {
      const lensIds = this.fileLenses.get(fileId) || new Set();
      let resolvedCount = 0;

      for (const lensId of lensIds) {
        const lens = this.lenses.get(lensId);
        if (lens && !lens.isResolved) {
          lens.isResolved = true;
          lens.resolvedAt = Date.now();
          this.stats.unresolvedLenses--;
          this.stats.resolvedLenses++;
          resolvedCount++;
        }
      }

      this.logAudit(userId, 'resolve-lenses-in-file', fileId, 'success', {
        resolvedCount,
      });

      this.emit('file-lenses-resolved', {
        data_object: { fileId, resolvedCount },
        timestamp: Date.now(),
      });

      return { success: true, resolvedCount };
    } catch (error) {
      this.logAudit(userId, 'resolve-lenses-in-file', fileId, 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Unresolve code lens
   */
  public unresolveCodeLens(lensId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean } {
    try {
      const lens = this.lenses.get(lensId);
      if (!lens) {
        return { success: false };
      }

      if (lens.isResolved) {
        lens.isResolved = false;
        lens.resolvedAt = undefined;
        this.stats.resolvedLenses--;
        this.stats.unresolvedLenses++;
      }

      this.cache.delete(lensId);

      this.logAudit(userId, 'unresolve-code-lens', lens.fileId, 'success', {
        lensId,
      });

      this.emit('code-lens-unresolved', {
        data_object: { lensId, fileId: lens.fileId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'unresolve-code-lens', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get code lenses in file
   */
  public getCodeLensesInFile(fileId: string): CodeLensMetadata[] {
    const lensIds = this.fileLenses.get(fileId) || new Set();
    const lenses: CodeLensMetadata[] = [];

    for (const lensId of lensIds) {
      const lens = this.lenses.get(lensId);
      if (lens) {
        lenses.push(lens);
      }
    }

    return lenses;
  }

  /**
   * Get code lenses in range
   */
  public getCodeLensesInRange(fileId: string, range: CodeLensRange): CodeLensMetadata[] {
    const lenses = this.getCodeLensesInFile(fileId);

    return lenses.filter((lens) => lens.position.line >= range.startLine && lens.position.line <= range.endLine);
  }

  /**
   * Get unresolved lenses
   */
  public getUnresolvedLenses(fileId?: string): CodeLensMetadata[] {
    let lenses = Array.from(this.lenses.values()).filter((l) => !l.isResolved);

    if (fileId) {
      lenses = lenses.filter((l) => l.fileId === fileId);
    }

    return lenses;
  }

  /**
   * Add reference
   */
  public addReference(
    reference: Omit<CodeLensReference, 'referenceId'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; referenceId?: string } {
    try {
      const referenceId = `ref-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const ref: CodeLensReference = {
        ...reference,
        referenceId,
      };

      if (!this.references.has(reference.lensId)) {
        this.references.set(reference.lensId, []);
      }
      this.references.get(reference.lensId)!.push(ref);
      this.stats.totalReferences++;

      this.logAudit(userId, 'add-reference', reference.referencingFile, 'success', {
        referenceId,
        lensId: reference.lensId,
      });

      this.emit('reference-added', {
        data_object: { referenceId, lensId: reference.lensId },
        timestamp: Date.now(),
      });

      return { success: true, referenceId };
    } catch (error) {
      this.logAudit(userId, 'add-reference', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get references for lens
   */
  public getReferencesForLens(lensId: string): CodeLensReference[] {
    return this.references.get(lensId) || [];
  }

  /**
   * Update reference counts
   */
  public updateReferenceCounts(lensId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean; count?: number } {
    try {
      const refs = this.references.get(lensId) || [];
      const count = refs.length;

      this.logAudit(userId, 'update-reference-counts', '', 'success', {
        lensId,
        count,
      });

      this.emit('reference-counts-updated', {
        data_object: { lensId, referenceCount: count },
        timestamp: Date.now(),
      });

      return { success: true, count };
    } catch (error) {
      this.logAudit(userId, 'update-reference-counts', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Remove reference
   */
  public removeReference(referenceId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean } {
    try {
      for (const [lensId, refs] of this.references) {
        const index = refs.findIndex((r) => r.referenceId === referenceId);
        if (index >= 0) {
          refs.splice(index, 1);
          this.stats.totalReferences--;

          this.logAudit(userId, 'remove-reference', '', 'success', {
            referenceId,
            lensId,
          });

          this.emit('reference-removed', {
            data_object: { referenceId, lensId },
            timestamp: Date.now(),
          });

          return { success: true };
        }
      }

      return { success: false };
    } catch (error) {
      this.logAudit(userId, 'remove-reference', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Batch update
   */
  public batchUpdate(
    update: Omit<CodeLensBatchUpdate, 'updateId' | 'timestamp'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; updateId?: string } {
    try {
      const updateId = `update-${Date.now()}-${Math.random().toString(16).slice(2)}`;

      // Add lenses
      for (const lens of update.addedLenses) {
        this.lenses.set(lens.lensId, lens);
        if (!this.fileLenses.has(update.fileId)) {
          this.fileLenses.set(update.fileId, new Set());
        }
        this.fileLenses.get(update.fileId)!.add(lens.lensId);
      }

      // Remove lenses
      for (const lensId of update.removedLenses) {
        this.lenses.delete(lensId);
        this.fileLenses.get(update.fileId)?.delete(lensId);
      }

      // Update lenses
      for (const lens of update.updatedLenses) {
        const existing = this.lenses.get(lens.lensId);
        if (existing) {
          Object.assign(existing, lens);
        }
      }

      this.logAudit(userId, 'batch-update', update.fileId, 'success', {
        updateId,
        addedCount: update.addedLenses.length,
        removedCount: update.removedLenses.length,
        updatedCount: update.updatedLenses.length,
      });

      this.emit('batch-update-completed', {
        data_object: { updateId, fileId: update.fileId },
        timestamp: Date.now(),
      });

      return { success: true, updateId };
    } catch (error) {
      this.logAudit(userId, 'batch-update', update.fileId, 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get file lenses
   */
  public getFileLenses(fileId: string): CodeLensMetadata[] {
    return this.getCodeLensesInFile(fileId);
  }

  /**
   * Execute command
   */
  public executeCommand(
    lensId: string,
    command: string,
    args: unknown[],
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; executionId?: string; result?: unknown } {
    try {
      const lens = this.lenses.get(lensId);
      if (!lens) {
        return { success: false };
      }

      const executionId = `exec-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const execution: CodeLensCommandExecution = {
        executionId,
        lensId,
        command,
        arguments: args,
        executedBy: userId,
        executedAt: Date.now(),
      };

      if (!this.commandHistory.has(lensId)) {
        this.commandHistory.set(lensId, []);
      }
      this.commandHistory.get(lensId)!.push(execution);

      this.logAudit(userId, 'execute-command', lens.fileId, 'success', {
        executionId,
        command,
      });

      this.emit('command-executed', {
        data_object: { executionId, lensId, command },
        timestamp: Date.now(),
      });

      return { success: true, executionId, result: { status: 'executed' } };
    } catch (error) {
      this.logAudit(userId, 'execute-command', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get command history
   */
  public getCommandHistory(lensId?: string, limit?: number): CodeLensCommandExecution[] {
    let executions: CodeLensCommandExecution[] = [];

    if (lensId) {
      executions = this.commandHistory.get(lensId) || [];
    } else {
      for (const [, cmds] of this.commandHistory) {
        executions.push(...cmds);
      }
    }

    return executions.slice(0, limit || 100);
  }

  /**
   * Invalidate cache
   */
  public invalidateCache(fileId: string, reason: string, userId: string, ipAddress: string): { success: boolean } {
    try {
      const invalidationId = `inv-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const lensIds = Array.from(this.fileLenses.get(fileId) || []);

      const invalidation: CodeLensInvalidation = {
        invalidationId,
        fileId,
        reason: (reason as any) || 'manual',
        affectedLenses: lensIds,
        invalidatedAt: Date.now(),
      };

      if (!this.invalidations.has(fileId)) {
        this.invalidations.set(fileId, []);
      }
      this.invalidations.get(fileId)!.push(invalidation);

      // Clear cache for affected lenses
      for (const lensId of lensIds) {
        this.cache.delete(lensId);
      }

      this.emit('cache-invalidated', {
        data_object: { invalidationId, fileId, affectedCount: lensIds.length },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      return { success: false };
    }
  }

  /**
   * Get cache hit rate
   */
  public getCacheHitRate(): number {
    const total = this.cacheHits + this.cacheMisses;
    return total > 0 ? this.cacheHits / total : 0;
  }

  /**
   * Clear cache
   */
  public clearCache(userId: string, ipAddress: string, userAgent: string): { success: boolean } {
    try {
      this.cache.clear();
      this.cacheHits = 0;
      this.cacheMisses = 0;

      this.logAudit(userId, 'clear-cache', '', 'success', {});

      this.emit('cache-cleared', {
        data_object: { clearedEntries: 0 },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'clear-cache', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get performance metrics
   */
  public getPerformanceMetrics(lensId?: string): CodeLensPerformanceMetric[] {
    if (!lensId) {
      const metrics: CodeLensPerformanceMetric[] = [];
      for (const [, lensMetrics] of this.performanceMetrics) {
        metrics.push(...lensMetrics);
      }
      return metrics;
    }

    return this.performanceMetrics.get(lensId) || [];
  }

  /**
   * Record performance metric
   */
  public recordPerformanceMetric(metric: CodeLensPerformanceMetric): void {
    if (!this.config.performanceTrackingEnabled) {
      return;
    }

    if (!this.performanceMetrics.has(metric.lensId)) {
      this.performanceMetrics.set(metric.lensId, []);
    }

    this.performanceMetrics.get(metric.lensId)!.push(metric);
  }

  /**
   * Get statistics
   */
  public getStatistics(fileId?: string): CodeLensStatistics {
    if (!fileId) {
      return { ...this.stats };
    }

    const lenses = this.getCodeLensesInFile(fileId);
    const resolved = lenses.filter((l) => l.isResolved).length;
    const references = lenses.reduce((sum, l) => sum + (this.references.get(l.lensId) || []).length, 0);

    return {
      totalLenses: lenses.length,
      resolvedLenses: resolved,
      unresolvedLenses: lenses.length - resolved,
      totalReferences: references,
      averageReferencesPerLens: lenses.length > 0 ? references / lenses.length : 0,
      lensCount: { [fileId]: lenses.length },
    };
  }

  /**
   * Get audit log
   */
  public getAuditLog(limit?: number): CodeLensAuditEntry[] {
    const entries: CodeLensAuditEntry[] = [];
    for (const [, userEntries] of this.auditLog) {
      entries.push(...userEntries);
    }
    entries.sort((a, b) => b.timestamp - a.timestamp);
    return entries.slice(0, limit || 100);
  }

  /**
   * Update configuration
   */
  public updateConfig(config: Partial<CodeLensConfig>): void {
    this.config = { ...this.config, ...config };

    this.emit('config-updated', {
      data_object: { config: this.config },
      timestamp: Date.now(),
    });
  }

  /**
   * Get configuration
   */
  public getConfig(): CodeLensConfig {
    return { ...this.config };
  }

  /**
   * Log audit entry
   */
  private logAudit(userId: string, action: string, fileId: string, status: 'success' | 'failure', details?: Record<string, unknown>): void {
    if (!this.auditLog.has(userId)) {
      this.auditLog.set(userId, []);
    }

    const entry: CodeLensAuditEntry = {
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
    this.lenses.clear();
    this.fileLenses.clear();
    this.references.clear();
    this.cache.clear();
    this.commandHistory.clear();
    this.invalidations.clear();
    this.performanceMetrics.clear();
    this.auditLog.clear();

    this.emit('shutdown', {
      data_object: { service: 'code-lens-provider', status: 'shutdown' },
      timestamp: Date.now(),
    });
  }
}
