/**
 * Real-time Code Lens Provider Service
 * @file        apps/backend/src/services/code-lens-provider/code-lens-provider-service.ts
 * @module      services/code-lens-provider
 * @description Real-time code lens provider for integrated code intelligence
 */
import { EventEmitter } from 'events';
/**
 * Code Lens Provider Service
 * Provides real-time code lens integration with caching and performance tracking
 */
export class CodeLensProvider extends EventEmitter {
    constructor() {
        super();
        this.lenses = new Map();
        this.fileLenses = new Map(); // fileId -> lensIds
        this.references = new Map(); // lensId -> references
        this.cache = new Map(); // lensId -> cache
        this.commandHistory = new Map(); // lensId -> executions
        this.invalidations = new Map(); // fileId -> invalidations
        this.performanceMetrics = new Map(); // lensId -> metrics
        this.auditLog = new Map(); // userId -> entries
        this.stats = {
            totalLenses: 0,
            resolvedLenses: 0,
            unresolvedLenses: 0,
            totalReferences: 0,
            averageReferencesPerLens: 0,
            lensCount: {},
        };
        this.cacheHits = 0;
        this.cacheMisses = 0;
        this.config = {
            enableCodeLens: true,
            enableReferenceCounting: true,
            enableImplementationLens: true,
            cacheExpirationMs: 3600000, // 1 hour
            batchUpdateThreshold: 10,
            maxLensesPerFile: 1000,
            maxAuditEntries: 5000,
            performanceTrackingEnabled: true,
        };
        this.initialize();
    }
    /**
     * Get or create singleton instance
     */
    static getInstance(config) {
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
    static reset() {
        CodeLensProvider.instance = undefined;
    }
    /**
     * Initialize service
     */
    initialize() {
        this.emit('initialized', {
            data_object: { service: 'code-lens-provider', status: 'initialized' },
            timestamp: Date.now(),
        });
    }
    /**
     * Create code lens
     */
    createCodeLens(metadata, userId, ipAddress, userAgent) {
        try {
            if (!this.config.enableCodeLens) {
                return { success: false };
            }
            const lensId = `lens-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const lens = {
                ...metadata,
                lensId,
                isResolved: false,
            };
            this.lenses.set(lensId, lens);
            if (!this.fileLenses.has(metadata.fileId)) {
                this.fileLenses.set(metadata.fileId, new Set());
            }
            this.fileLenses.get(metadata.fileId).add(lensId);
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
        }
        catch (error) {
            this.logAudit(userId, 'create-code-lens', '', 'failure', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Update code lens
     */
    updateCodeLens(lensId, updates, userId, ipAddress, userAgent) {
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
        }
        catch (error) {
            this.logAudit(userId, 'update-code-lens', '', 'failure', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Delete code lens
     */
    deleteCodeLens(lensId, userId, ipAddress, userAgent) {
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
            }
            else {
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
        }
        catch (error) {
            this.logAudit(userId, 'delete-code-lens', '', 'failure', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get code lens
     */
    getCodeLens(lensId) {
        return this.lenses.get(lensId);
    }
    /**
     * Resolve code lens
     */
    resolveCodeLens(lensId, userId, ipAddress, userAgent) {
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
            const cacheEntry = {
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
        }
        catch (error) {
            this.logAudit(userId, 'resolve-code-lens', '', 'failure', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Resolve lenses in file
     */
    resolveLensesInFile(fileId, userId, ipAddress, userAgent) {
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
        }
        catch (error) {
            this.logAudit(userId, 'resolve-lenses-in-file', fileId, 'failure', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Unresolve code lens
     */
    unresolveCodeLens(lensId, userId, ipAddress, userAgent) {
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
        }
        catch (error) {
            this.logAudit(userId, 'unresolve-code-lens', '', 'failure', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get code lenses in file
     */
    getCodeLensesInFile(fileId) {
        const lensIds = this.fileLenses.get(fileId) || new Set();
        const lenses = [];
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
    getCodeLensesInRange(fileId, range) {
        const lenses = this.getCodeLensesInFile(fileId);
        return lenses.filter((lens) => lens.position.line >= range.startLine && lens.position.line <= range.endLine);
    }
    /**
     * Get unresolved lenses
     */
    getUnresolvedLenses(fileId) {
        let lenses = Array.from(this.lenses.values()).filter((l) => !l.isResolved);
        if (fileId) {
            lenses = lenses.filter((l) => l.fileId === fileId);
        }
        return lenses;
    }
    /**
     * Add reference
     */
    addReference(reference, userId, ipAddress, userAgent) {
        try {
            const referenceId = `ref-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const ref = {
                ...reference,
                referenceId,
            };
            if (!this.references.has(reference.lensId)) {
                this.references.set(reference.lensId, []);
            }
            this.references.get(reference.lensId).push(ref);
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
        }
        catch (error) {
            this.logAudit(userId, 'add-reference', '', 'failure', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get references for lens
     */
    getReferencesForLens(lensId) {
        return this.references.get(lensId) || [];
    }
    /**
     * Update reference counts
     */
    updateReferenceCounts(lensId, userId, ipAddress, userAgent) {
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
        }
        catch (error) {
            this.logAudit(userId, 'update-reference-counts', '', 'failure', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Remove reference
     */
    removeReference(referenceId, userId, ipAddress, userAgent) {
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
        }
        catch (error) {
            this.logAudit(userId, 'remove-reference', '', 'failure', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Batch update
     */
    batchUpdate(update, userId, ipAddress, userAgent) {
        try {
            const updateId = `update-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            // Add lenses
            for (const lens of update.addedLenses) {
                this.lenses.set(lens.lensId, lens);
                if (!this.fileLenses.has(update.fileId)) {
                    this.fileLenses.set(update.fileId, new Set());
                }
                this.fileLenses.get(update.fileId).add(lens.lensId);
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
        }
        catch (error) {
            this.logAudit(userId, 'batch-update', update.fileId, 'failure', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get file lenses
     */
    getFileLenses(fileId) {
        return this.getCodeLensesInFile(fileId);
    }
    /**
     * Execute command
     */
    executeCommand(lensId, command, args, userId, ipAddress, userAgent) {
        try {
            const lens = this.lenses.get(lensId);
            if (!lens) {
                return { success: false };
            }
            const executionId = `exec-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const execution = {
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
            this.commandHistory.get(lensId).push(execution);
            this.logAudit(userId, 'execute-command', lens.fileId, 'success', {
                executionId,
                command,
            });
            this.emit('command-executed', {
                data_object: { executionId, lensId, command },
                timestamp: Date.now(),
            });
            return { success: true, executionId, result: { status: 'executed' } };
        }
        catch (error) {
            this.logAudit(userId, 'execute-command', '', 'failure', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get command history
     */
    getCommandHistory(lensId, limit) {
        let executions = [];
        if (lensId) {
            executions = this.commandHistory.get(lensId) || [];
        }
        else {
            for (const [, cmds] of this.commandHistory) {
                executions.push(...cmds);
            }
        }
        return executions.slice(0, limit || 100);
    }
    /**
     * Invalidate cache
     */
    invalidateCache(fileId, reason, userId, ipAddress) {
        try {
            const invalidationId = `inv-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const lensIds = Array.from(this.fileLenses.get(fileId) || []);
            const invalidation = {
                invalidationId,
                fileId,
                reason: reason || 'manual',
                affectedLenses: lensIds,
                invalidatedAt: Date.now(),
            };
            if (!this.invalidations.has(fileId)) {
                this.invalidations.set(fileId, []);
            }
            this.invalidations.get(fileId).push(invalidation);
            // Clear cache for affected lenses
            for (const lensId of lensIds) {
                this.cache.delete(lensId);
            }
            this.emit('cache-invalidated', {
                data_object: { invalidationId, fileId, affectedCount: lensIds.length },
                timestamp: Date.now(),
            });
            return { success: true };
        }
        catch (error) {
            return { success: false };
        }
    }
    /**
     * Get cache hit rate
     */
    getCacheHitRate() {
        const total = this.cacheHits + this.cacheMisses;
        return total > 0 ? this.cacheHits / total : 0;
    }
    /**
     * Clear cache
     */
    clearCache(userId, ipAddress, userAgent) {
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
        }
        catch (error) {
            this.logAudit(userId, 'clear-cache', '', 'failure', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get performance metrics
     */
    getPerformanceMetrics(lensId) {
        if (!lensId) {
            const metrics = [];
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
    recordPerformanceMetric(metric) {
        if (!this.config.performanceTrackingEnabled) {
            return;
        }
        if (!this.performanceMetrics.has(metric.lensId)) {
            this.performanceMetrics.set(metric.lensId, []);
        }
        this.performanceMetrics.get(metric.lensId).push(metric);
    }
    /**
     * Get statistics
     */
    getStatistics(fileId) {
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
    getAuditLog(limit) {
        const entries = [];
        for (const [, userEntries] of this.auditLog) {
            entries.push(...userEntries);
        }
        entries.sort((a, b) => b.timestamp - a.timestamp);
        return entries.slice(0, limit || 100);
    }
    /**
     * Update configuration
     */
    updateConfig(config) {
        this.config = { ...this.config, ...config };
        this.emit('config-updated', {
            data_object: { config: this.config },
            timestamp: Date.now(),
        });
    }
    /**
     * Get configuration
     */
    getConfig() {
        return { ...this.config };
    }
    /**
     * Log audit entry
     */
    logAudit(userId, action, fileId, status, details) {
        if (!this.auditLog.has(userId)) {
            this.auditLog.set(userId, []);
        }
        const entry = {
            timestamp: Date.now(),
            userId,
            userEmail: `user-${userId}@example.com`,
            action,
            fileId,
            details: details || {},
        };
        const logs = this.auditLog.get(userId);
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
    shutdown() {
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
//# sourceMappingURL=code-lens-provider-service.js.map