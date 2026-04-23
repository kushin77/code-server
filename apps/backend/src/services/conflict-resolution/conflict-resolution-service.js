/**
 * Workspace Conflict Resolution Service
 * @file        apps/backend/src/services/conflict-resolution/conflict-resolution-service.ts
 * @module      services/conflict-resolution
 * @description Detect and resolve workspace file/state conflicts in collaborative editing
 */
import { EventEmitter } from 'events';
/**
 * Conflict Resolution Service
 */
export class ConflictResolutionService extends EventEmitter {
    constructor() {
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
    static getInstance(settings) {
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
    static reset() {
        if (ConflictResolutionService.instance) {
            ConflictResolutionService.instance.shutdown();
        }
        ConflictResolutionService.instance = null;
    }
    /**
     * Initialize service
     */
    initialize() {
        this.emit('initialized', {
            data_object: { service: 'conflict-resolution', status: 'initialized' },
            timestamp: Date.now(),
        });
    }
    /**
     * Detect conflicts
     */
    detectConflicts(workspaceId, userId, ipAddress, userAgent) {
        try {
            const fileConflicts = Array.from(this.conflicts.values()).filter((c) => !c.resolvedAt);
            const stateConflicts = Array.from(this.stateConflicts.values()).filter((c) => !c.resolvedAt);
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
            this.logAudit(userId, `${userId}@example.com`, ipAddress, userAgent, 'conflict-detected', '', '', { workspaceId, fileConflictCount: fileConflicts.length });
            return {
                success: true,
                conflicts: fileConflicts,
                stateConflicts,
                totalConflicts: fileConflicts.length + stateConflicts.length,
                criticalCount,
                warningCount,
            };
        }
        catch (error) {
            return {
                success: false,
                conflicts: [],
                stateConflicts: [],
                totalConflicts: 0,
                criticalCount: 0,
                warningCount: 0,
                error: error.message,
            };
        }
    }
    /**
     * Report conflict
     */
    reportConflict(conflict, userId, ipAddress, userAgent) {
        try {
            const conflictId = conflict.id || `conflict-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const newConflict = { ...conflict, id: conflictId };
            this.conflicts.set(conflictId, newConflict);
            this.statistics.totalConflicts++;
            if (!this.conflictHistory.has(conflictId)) {
                this.conflictHistory.set(conflictId, []);
            }
            const history = this.conflictHistory.get(conflictId);
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
            this.logAudit(userId, `${userId}@example.com`, ipAddress, userAgent, 'conflict-detected', conflict.filePath, conflictId, { type: conflict.conflictType, severity: conflict.severity });
            return { success: true, conflictId };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Resolve conflict
     */
    resolveConflict(conflictId, strategy, userId, ipAddress, userAgent) {
        try {
            const conflict = this.conflicts.get(conflictId);
            if (!conflict) {
                return { success: false, conflictId, errors: [], warnings: [] };
            }
            let resultingContent = '';
            if (strategy === 'keep-local') {
                resultingContent = conflict.localVersion.content || '';
            }
            else if (strategy === 'keep-remote') {
                resultingContent = conflict.remoteVersion.content || '';
            }
            else if (strategy === 'merge') {
                resultingContent = this.mergeContent(conflict.localVersion.content || '', conflict.remoteVersion.content || '');
            }
            const resolution = {
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
                const history = this.conflictHistory.get(conflictId);
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
            this.logAudit(userId, `${userId}@example.com`, ipAddress, userAgent, 'conflict-resolved', conflict.filePath, conflictId, { strategy, resultingContentLength: resultingContent.length });
            return { success: true, conflictId, resolution, newContent: resultingContent, warnings: [] };
        }
        catch (error) {
            return {
                success: false,
                conflictId,
                error: error.message,
                warnings: [],
            };
        }
    }
    /**
     * Get conflict
     */
    getConflict(conflictId) {
        try {
            const conflict = this.conflicts.get(conflictId);
            if (!conflict) {
                return { success: false, error: 'Conflict not found' };
            }
            return { success: true, conflict };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * List conflicts
     */
    listConflicts(workspaceId, status) {
        try {
            let conflicts = Array.from(this.conflicts.values());
            if (status === 'unresolved') {
                conflicts = conflicts.filter((c) => !c.resolvedAt);
            }
            else if (status === 'resolved') {
                conflicts = conflicts.filter((c) => c.resolvedAt);
            }
            return conflicts;
        }
        catch {
            return [];
        }
    }
    /**
     * Get conflict history
     */
    getConflictHistory(conflictId, limit) {
        try {
            const history = this.conflictHistory.get(conflictId) || [];
            return history.slice(-(limit || 50));
        }
        catch {
            return [];
        }
    }
    /**
     * Suggest resolution
     */
    suggestResolution(conflictId) {
        try {
            const conflict = this.conflicts.get(conflictId);
            if (!conflict) {
                return { success: false, error: 'Conflict not found' };
            }
            let suggestion = 'timestamp-based';
            let confidence = 0.7;
            if (conflict.localVersion.timestamp > conflict.remoteVersion.timestamp) {
                suggestion = 'keep-local';
                confidence = 0.85;
            }
            else {
                suggestion = 'keep-remote';
                confidence = 0.8;
            }
            this.emit('suggestion-generated', {
                data_object: { conflictId, suggestion, confidence },
                timestamp: Date.now(),
            });
            return { success: true, suggestion, confidence };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Merge conflict
     */
    mergeConflict(conflictId, localVersion, remoteVersion, userId, ipAddress, userAgent) {
        try {
            const conflict = this.conflicts.get(conflictId);
            if (!conflict) {
                return { success: false, conflictId, warnings: [] };
            }
            const mergedContent = this.mergeContent(localVersion.content || '', remoteVersion.content || '');
            const resolution = {
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
        }
        catch (error) {
            return {
                success: false,
                conflictId,
                error: error.message,
                warnings: [],
            };
        }
    }
    /**
     * Revert resolution
     */
    revertResolution(resolutionId, userId, ipAddress, userAgent) {
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
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Detect state conflicts
     */
    detectStateConflicts(workspaceId, userId, ipAddress, userAgent) {
        try {
            const stateConflicts = Array.from(this.stateConflicts.values()).filter((c) => !c.resolvedAt);
            this.emit('state-conflict-detection-completed', {
                data_object: { workspaceId, conflictCount: stateConflicts.length },
                timestamp: Date.now(),
            });
            return stateConflicts;
        }
        catch {
            return [];
        }
    }
    /**
     * Resolve state conflict
     */
    resolveStateConflict(stateConflictId, strategy, userId, ipAddress, userAgent) {
        try {
            const stateConflict = this.stateConflicts.get(stateConflictId);
            if (!stateConflict) {
                return { success: false, error: 'State conflict not found' };
            }
            let resultingState = stateConflict.localState;
            if (strategy === 'keep-remote') {
                resultingState = stateConflict.remoteState;
            }
            const resolution = {
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
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Batch resolve conflicts
     */
    batchResolveConflicts(conflictIds, strategy, userId, ipAddress, userAgent) {
        try {
            const results = [];
            let resolved = 0;
            let failed = 0;
            conflictIds.forEach((conflictId) => {
                const result = this.resolveConflict(conflictId, strategy, userId, ipAddress, userAgent);
                results.push(result);
                if (result.success) {
                    resolved++;
                }
                else {
                    failed++;
                }
            });
            this.emit('batch-resolution-completed', {
                data_object: { totalProcessed: conflictIds.length, resolved, failed },
                timestamp: Date.now(),
            });
            this.logAudit(userId, `${userId}@example.com`, ipAddress, userAgent, 'conflict-resolved', '', '', { totalProcessed: conflictIds.length, resolved, failed });
            return {
                success: failed === 0,
                totalProcessed: conflictIds.length,
                resolved,
                failed,
                skipped: 0,
                details: results,
            };
        }
        catch (error) {
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
    getStatistics() {
        const conflictsByType = new Map();
        const conflictsBySeverity = new Map();
        const userSet = new Set();
        const fileSet = new Set();
        Array.from(this.conflicts.values()).forEach((c) => {
            conflictsByType.set(c.conflictType, (conflictsByType.get(c.conflictType) || 0) + 1);
            conflictsBySeverity.set(c.severity, (conflictsBySeverity.get(c.severity) || 0) + 1);
            c.participants.forEach((p) => userSet.add(p));
            fileSet.add(c.filePath);
        });
        const unresolvedConflicts = Array.from(this.conflicts.values()).filter((c) => !c.resolvedAt).length;
        const successRate = this.statistics.totalConflicts > 0
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
    archiveConflict(conflictId, userId, ipAddress, userAgent) {
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
            this.logAudit(userId, `${userId}@example.com`, ipAddress, userAgent, 'conflict-detected', conflict.filePath, conflictId, { action: 'archived' });
            return { success: true };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Update settings
     */
    updateSettings(settings, userId, ipAddress, userAgent) {
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
    mergeContent(local, remote) {
        const localLines = local.split('\n');
        const remoteLines = remote.split('\n');
        const merged = [];
        const maxLength = Math.max(localLines.length, remoteLines.length);
        for (let i = 0; i < maxLength; i++) {
            const localLine = localLines[i] || '';
            const remoteLine = remoteLines[i] || '';
            if (localLine === remoteLine) {
                merged.push(localLine);
            }
            else if (localLine && !remoteLine) {
                merged.push(localLine);
            }
            else if (remoteLine && !localLine) {
                merged.push(remoteLine);
            }
            else {
                merged.push(`<<<<<<< local\n${localLine}\n=======\n${remoteLine}\n>>>>>>>`);
            }
        }
        return merged.join('\n');
    }
    /**
     * Log audit entry
     */
    logAudit(userId, userEmail, ipAddress, userAgent, operation, filePath, conflictId, details) {
        const entry = {
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
        const logs = this.auditLogs.get(userId);
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
    shutdown() {
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
//# sourceMappingURL=conflict-resolution-service.js.map