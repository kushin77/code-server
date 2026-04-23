#!/usr/bin/env node
/**
 * @file        apps/backend/src/services/merge-resolver/merge-resolver-service.ts
 * @module      services/collaboration/merge-resolver
 * @description 3-way merge conflict resolver with interactive diff editor
 */
import { EventEmitter } from 'events';
/**
 * 3-way merge conflict resolver service
 */
export class MergeResolverService extends EventEmitter {
    /**
     * Get singleton instance
     */
    static getInstance(config) {
        if (!this.instance) {
            this.instance = new MergeResolverService(config);
        }
        return this.instance;
    }
    /**
     * Reset singleton for testing
     */
    static reset() {
        this.instance = undefined;
    }
    /**
     * Constructor
     */
    constructor(config) {
        super();
        this.config = {
            maxConcurrentSessions: config?.maxConcurrentSessions ?? 20,
            maxConflictSize: config?.maxConflictSize ?? 10 * 1024 * 1024,
            enableSmartMerge: config?.enableSmartMerge ?? true,
            autoResolveThreshold: config?.autoResolveThreshold ?? 0.8,
            maxHistorySize: config?.maxHistorySize ?? 1000,
            maxAuditLogSize: config?.maxAuditLogSize ?? 10000,
            enableDiffCache: config?.enableDiffCache ?? true,
            diffCacheTTL: config?.diffCacheTTL ?? 3600000,
        };
        this.sessions = new Map();
        this.auditLog = new Map();
        this.statistics = {
            totalSessions: 0,
            completedSessions: 0,
            abortedSessions: 0,
            totalConflicts: 0,
            resolvedConflicts: 0,
            totalResolutions: 0,
            smartMergeResolutions: 0,
            manualResolutions: 0,
            averageSessionDuration: 0,
            averageConflictsPerSession: 0,
            smartMergeSuccessRate: 0,
            lastSessionAt: 0,
        };
        this.resolutionHistory = [];
        this.emit('initialized', { timestamp: Date.now() });
    }
    /**
     * Create merge session
     */
    createMergeSession(userId, userEmail, sourceBranch, targetBranch, baseCommit, oursCommit, theirsCommit, diffs, ipAddress, userAgent) {
        const conflictCount = diffs.reduce((sum, d) => sum + d.conflictCount, 0);
        const session = {
            id: `merge-${Date.now()}-${Math.random().toString(16).slice(2)}`,
            userId,
            userEmail,
            timestamp: Date.now(),
            sourceBranch,
            targetBranch,
            baseCommit,
            oursCommit,
            theirsCommit,
            status: 'in-progress',
            diffs,
            conflictCount,
            resolvedCount: 0,
            abortedCount: 0,
        };
        this.sessions.set(session.id, session);
        this.statistics.totalSessions++;
        this.statistics.totalConflicts += conflictCount;
        this.statistics.lastSessionAt = Date.now();
        this.recordAudit({
            userId,
            userEmail,
            operation: 'merge-session-created',
            status: 'success',
            mergeSessionId: session.id,
            details: { sourceBranch, targetBranch, conflictCount },
            ipAddress,
            userAgent,
            timestamp: Date.now(),
        });
        this.emit('merge-session-created', {
            session,
            timestamp: Date.now(),
        });
        return session;
    }
    /**
     * Get merge session
     */
    getMergeSession(sessionId) {
        return this.sessions.get(sessionId) ?? null;
    }
    /**
     * Resolve conflict
     */
    resolveConflict(request, sessionId, ipAddress, userAgent) {
        const session = this.sessions.get(sessionId);
        if (!session) {
            return {
                success: false,
                conflictId: request.conflictId,
                resolvedAt: Date.now(),
                strategy: request.strategy,
                message: 'Session not found',
            };
        }
        try {
            let conflict = null;
            for (const diff of session.diffs) {
                conflict = diff.conflicts.find((c) => c.id === request.conflictId) ?? null;
                if (conflict)
                    break;
            }
            if (!conflict) {
                return {
                    success: false,
                    conflictId: request.conflictId,
                    resolvedAt: Date.now(),
                    strategy: request.strategy,
                    message: 'Conflict not found',
                };
            }
            // Apply resolution
            if (request.strategy === 'ours') {
                conflict.resolvedContent = conflict.oursContent;
            }
            else if (request.strategy === 'theirs') {
                conflict.resolvedContent = conflict.theirsContent;
            }
            else if (request.strategy === 'manual' && request.customContent) {
                conflict.resolvedContent = request.customContent;
            }
            else if (request.strategy === 'smart-merge') {
                conflict.resolvedContent = this.performSmartMerge(conflict);
                this.statistics.smartMergeResolutions++;
            }
            conflict.status = 'resolved';
            conflict.resolvedAt = Date.now();
            conflict.resolvedBy = request.userEmail;
            conflict.resolutionStrategy = request.strategy;
            session.resolvedCount++;
            this.statistics.resolvedConflicts++;
            this.statistics.totalResolutions++;
            if (request.strategy === 'manual') {
                this.statistics.manualResolutions++;
            }
            // Auto-resolve similar conflicts
            let resolvedCount = 1;
            if (request.autoResolve && request.strategy !== 'manual') {
                for (const diff of session.diffs) {
                    for (const c of diff.conflicts) {
                        if (c.id !== conflict.id && c.status === 'unresolved' && this.isSimilar(conflict, c)) {
                            c.status = 'resolved';
                            c.resolvedAt = Date.now();
                            c.resolvedBy = request.userEmail;
                            c.resolutionStrategy = request.strategy;
                            if (request.strategy === 'ours') {
                                c.resolvedContent = c.oursContent;
                            }
                            else if (request.strategy === 'theirs') {
                                c.resolvedContent = c.theirsContent;
                            }
                            else if (request.strategy === 'smart-merge') {
                                c.resolvedContent = this.performSmartMerge(c);
                            }
                            session.resolvedCount++;
                            this.statistics.resolvedConflicts++;
                            this.statistics.totalResolutions++;
                            resolvedCount++;
                        }
                    }
                }
            }
            this.resolutionHistory.push({
                sessionId,
                conflictId: request.conflictId,
                timestamp: Date.now(),
            });
            if (this.resolutionHistory.length > this.config.maxHistorySize) {
                this.resolutionHistory.splice(0, this.resolutionHistory.length - this.config.maxHistorySize);
            }
            this.recordAudit({
                userId: request.userId,
                userEmail: request.userEmail,
                operation: 'conflict-resolved',
                status: 'success',
                mergeSessionId: sessionId,
                conflictId: request.conflictId,
                resolutionStrategy: request.strategy,
                details: { resolvedCount, autoResolveApplied: resolvedCount > 1 },
                ipAddress,
                userAgent,
                timestamp: Date.now(),
            });
            this.emit('conflict-resolved', {
                sessionId,
                conflictId: request.conflictId,
                strategy: request.strategy,
                resolvedCount,
                timestamp: Date.now(),
            });
            return {
                success: true,
                conflictId: request.conflictId,
                resolvedAt: Date.now(),
                strategy: request.strategy,
                resolvedCount,
            };
        }
        catch (error) {
            this.recordAudit({
                userId: request.userId,
                userEmail: request.userEmail,
                operation: 'conflict-resolved',
                status: 'failure',
                mergeSessionId: sessionId,
                conflictId: request.conflictId,
                resolutionStrategy: request.strategy,
                details: { reason: error instanceof Error ? error.message : 'Unknown error' },
                ipAddress,
                userAgent,
                timestamp: Date.now(),
            });
            return {
                success: false,
                conflictId: request.conflictId,
                resolvedAt: Date.now(),
                strategy: request.strategy,
                message: error instanceof Error ? error.message : 'Resolution failed',
            };
        }
    }
    /**
     * Complete merge
     */
    completeMerge(request, ipAddress, userAgent) {
        const session = this.sessions.get(request.mergeSessionId);
        if (!session) {
            return {
                success: false,
                mergeSessionId: request.mergeSessionId,
                completedAt: Date.now(),
                conflictStats: { total: 0, resolved: 0, unresolved: 0 },
                message: 'Session not found',
            };
        }
        try {
            const unresolvedCount = session.diffs.reduce((sum, d) => {
                return sum + d.conflicts.filter((c) => c.status === 'unresolved').length;
            }, 0);
            if (unresolvedCount > 0) {
                return {
                    success: false,
                    mergeSessionId: request.mergeSessionId,
                    completedAt: Date.now(),
                    conflictStats: {
                        total: session.conflictCount,
                        resolved: session.resolvedCount,
                        unresolved: unresolvedCount,
                    },
                    message: 'Cannot complete merge with unresolved conflicts',
                };
            }
            session.status = 'completed';
            session.completedAt = Date.now();
            this.statistics.completedSessions++;
            const duration = session.completedAt - session.timestamp;
            this.statistics.averageSessionDuration =
                (this.statistics.averageSessionDuration * (this.statistics.completedSessions - 1) + duration) /
                    this.statistics.completedSessions;
            this.recordAudit({
                userId: request.userId,
                userEmail: request.userEmail,
                operation: 'merge-completed',
                status: 'success',
                mergeSessionId: request.mergeSessionId,
                details: { conflictCount: session.conflictCount, commitMessage: request.commitMessage },
                ipAddress,
                userAgent,
                timestamp: Date.now(),
            });
            this.emit('merge-completed', {
                sessionId: request.mergeSessionId,
                commitMessage: request.commitMessage,
                conflictStats: {
                    total: session.conflictCount,
                    resolved: session.resolvedCount,
                    unresolved: 0,
                },
                timestamp: Date.now(),
            });
            return {
                success: true,
                mergeSessionId: request.mergeSessionId,
                completedAt: Date.now(),
                commitHash: `commit-${Date.now().toString(16)}`,
                conflictStats: {
                    total: session.conflictCount,
                    resolved: session.resolvedCount,
                    unresolved: 0,
                },
            };
        }
        catch (error) {
            this.recordAudit({
                userId: request.userId,
                userEmail: request.userEmail,
                operation: 'merge-completed',
                status: 'failure',
                mergeSessionId: request.mergeSessionId,
                details: { reason: error instanceof Error ? error.message : 'Unknown error' },
                ipAddress,
                userAgent,
                timestamp: Date.now(),
            });
            return {
                success: false,
                mergeSessionId: request.mergeSessionId,
                completedAt: Date.now(),
                conflictStats: { total: 0, resolved: 0, unresolved: 0 },
                message: error instanceof Error ? error.message : 'Merge completion failed',
            };
        }
    }
    /**
     * Abort merge
     */
    abortMerge(sessionId, userId, userEmail, ipAddress, userAgent) {
        const session = this.sessions.get(sessionId);
        if (!session) {
            return false;
        }
        session.status = 'aborted';
        this.statistics.abortedSessions++;
        this.recordAudit({
            userId,
            userEmail,
            operation: 'merge-aborted',
            status: 'success',
            mergeSessionId: sessionId,
            ipAddress,
            userAgent,
            timestamp: Date.now(),
        });
        this.emit('merge-aborted', { sessionId, timestamp: Date.now() });
        return true;
    }
    /**
     * Get diff statistics
     */
    getDiffStatistics(sessionId) {
        const session = this.sessions.get(sessionId);
        if (!session) {
            return {
                filesChanged: 0,
                filesAdded: 0,
                filesDeleted: 0,
                totalConflicts: 0,
                resolvedConflicts: 0,
                unresolvedConflicts: 0,
                averageResolutionTime: 0,
                smartMergeSuccessRate: 0,
            };
        }
        const filesAdded = session.diffs.filter((d) => d.action === 'added').length;
        const filesDeleted = session.diffs.filter((d) => d.action === 'deleted').length;
        const filesModified = session.diffs.filter((d) => d.action === 'modified').length;
        const unresolvedConflicts = session.diffs.reduce((sum, d) => {
            return sum + d.conflicts.filter((c) => c.status === 'unresolved').length;
        }, 0);
        return {
            filesChanged: session.diffs.length,
            filesAdded,
            filesDeleted,
            totalConflicts: session.conflictCount,
            resolvedConflicts: session.resolvedCount,
            unresolvedConflicts,
            averageResolutionTime: session.resolvedCount > 0
                ? (session.completedAt ?? Date.now()) - session.timestamp / session.resolvedCount
                : 0,
            smartMergeSuccessRate: this.statistics.smartMergeResolutions / Math.max(1, this.statistics.totalResolutions),
        };
    }
    /**
     * Get audit log
     */
    getAuditLog(userId) {
        return this.auditLog.get(userId) ?? [];
    }
    /**
     * Get statistics
     */
    getStatistics() {
        const stats = { ...this.statistics };
        stats.averageConflictsPerSession =
            this.statistics.totalSessions > 0 ? this.statistics.totalConflicts / this.statistics.totalSessions : 0;
        stats.smartMergeSuccessRate =
            this.statistics.totalResolutions > 0
                ? this.statistics.smartMergeResolutions / this.statistics.totalResolutions
                : 0;
        return stats;
    }
    /**
     * Update configuration
     */
    updateConfig(config, userId, ipAddress, userAgent) {
        Object.assign(this.config, config);
        this.recordAudit({
            userId,
            userEmail: '',
            operation: 'merge-session-created',
            status: 'success',
            details: config,
            ipAddress,
            userAgent,
            timestamp: Date.now(),
        });
        this.emit('config-updated', { config: this.config, timestamp: Date.now() });
    }
    /**
     * Shutdown service
     */
    shutdown() {
        this.sessions.clear();
        this.auditLog.clear();
        this.resolutionHistory = [];
        this.emit('shutdown', { timestamp: Date.now() });
    }
    /**
     * Smart merge algorithm
     */
    performSmartMerge(conflict) {
        // Simple smart merge: prefer longer content (typically more complete)
        if (conflict.oursContent.length > conflict.theirsContent.length) {
            return conflict.oursContent;
        }
        else if (conflict.theirsContent.length > conflict.oursContent.length) {
            return conflict.theirsContent;
        }
        else {
            // Same length: prefer ours
            return conflict.oursContent;
        }
    }
    /**
     * Check if conflicts are similar
     */
    isSimilar(conflict1, conflict2) {
        // Same file and within 10 lines
        return (conflict1.filePath === conflict2.filePath &&
            Math.abs(conflict1.lineStart - conflict2.lineStart) <= 10);
    }
    /**
     * Record audit entry
     */
    recordAudit(entry) {
        if (!this.auditLog.has(entry.userId)) {
            this.auditLog.set(entry.userId, []);
        }
        const log = this.auditLog.get(entry.userId);
        log.push(entry);
        // Limit audit log size
        if (log.length > this.config.maxAuditLogSize) {
            log.splice(0, log.length - this.config.maxAuditLogSize);
        }
        this.emit('audit-logged', { entry, timestamp: Date.now() });
    }
}
//# sourceMappingURL=merge-resolver-service.js.map