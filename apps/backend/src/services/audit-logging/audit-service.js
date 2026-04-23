/**
 * @file        apps/backend/src/services/audit-logging/audit-service.ts
 * @module      security/audit-logging
 * @description SOC2-grade immutable audit logging service
 */
import { EventEmitter } from 'events';
/**
 * In-memory storage for testing (append-only)
 */
class InMemoryAuditStorage {
    constructor() {
        this.logs = []; // Append-only log
    }
    async append(entry) {
        // Validate immutability
        if (!entry._immutable) {
            throw new Error('Audit entry must be marked as immutable');
        }
        if (entry.timestamp !== entry.createdAt) {
            throw new Error('Audit entry timestamp and createdAt must match');
        }
        this.logs.push(entry);
    }
    async query(filter) {
        let filtered = this.logs.filter((log) => log.workspaceId === filter.workspaceId);
        if (filter.userId) {
            filtered = filtered.filter((log) => log.userId === filter.userId);
        }
        if (filter.action) {
            filtered = filtered.filter((log) => log.action === filter.action);
        }
        if (filter.resourceType) {
            filtered = filtered.filter((log) => log.resourceType === filter.resourceType);
        }
        if (filter.resourceId) {
            filtered = filtered.filter((log) => log.resourceId === filter.resourceId);
        }
        if (filter.startTime) {
            filtered = filtered.filter((log) => log.timestamp >= filter.startTime);
        }
        if (filter.endTime) {
            filtered = filtered.filter((log) => log.timestamp <= filter.endTime);
        }
        // Sort by timestamp descending (newest first)
        filtered.sort((a, b) => b.timestamp - a.timestamp);
        const limit = filter.limit || 100;
        const offset = filter.offset || 0;
        return {
            entries: filtered.slice(offset, offset + limit),
            total: filtered.length,
            limit,
            offset,
            hasMore: offset + limit < filtered.length,
        };
    }
    async getById(entryId) {
        return this.logs.find((log) => log.id === entryId) || null;
    }
    async export(workspaceId, format) {
        const logs = this.logs.filter((log) => log.workspaceId === workspaceId);
        if (format === 'json') {
            return JSON.stringify(logs, null, 2);
        }
        // CSV format
        const header = [
            'timestamp',
            'userId',
            'userRole',
            'action',
            'resourceType',
            'resourceId',
            'result',
            'error',
        ].join(',');
        const rows = logs.map((log) => [
            log.timestamp,
            log.userId,
            log.userRole,
            log.action,
            log.resourceType,
            log.resourceId,
            log.result,
            log.error || '',
        ]
            .map((val) => `"${String(val).replace(/"/g, '""')}"`)
            .join(','));
        return [header, ...rows].join('\n');
    }
    async validateIntegrity(workspaceId) {
        const issues = [];
        const workspaceLogs = this.logs.filter((log) => log.workspaceId === workspaceId);
        // Check immutability markers
        for (const log of workspaceLogs) {
            if (!log._immutable) {
                issues.push(`Entry ${log.id} missing immutable marker`);
            }
            if (log.timestamp !== log.createdAt) {
                issues.push(`Entry ${log.id} has mismatched timestamp/createdAt`);
            }
        }
        // Check sequence integrity (timestamps should be monotonically increasing or equal)
        for (let i = 1; i < workspaceLogs.length; i++) {
            if (workspaceLogs[i].timestamp < workspaceLogs[i - 1].timestamp) {
                issues.push(`Entry ${workspaceLogs[i].id} has earlier timestamp than predecessor`);
            }
        }
        return {
            valid: issues.length === 0,
            issues,
        };
    }
}
/**
 * AuditLoggingService: SOC2-compliant immutable logging
 */
export class AuditLoggingService extends EventEmitter {
    constructor(storage) {
        super();
        this.isInitialized = false;
        this.userContextMap = new Map();
        this.storage = storage || new InMemoryAuditStorage();
    }
    /**
     * Initialize service
     */
    async initialize() {
        if (this.isInitialized)
            return;
        this.isInitialized = true;
        console.log('[AuditLoggingService] Initialized');
        this.emit('initialized');
    }
    /**
     * Set user context for audit entries
     */
    setUserContext(userId, email, role) {
        this.userContextMap.set(userId, { email, role });
    }
    /**
     * Log a mention-related audit event
     */
    async logMentionEvent(workspaceId, event, sessionId, requestId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const userContext = this.userContextMap.get(event.createdByUserId);
        const now = Date.now();
        const entry = {
            id: `audit-${workspaceId}-${now}-${Math.random().toString(16).substring(2, 10)}`,
            timestamp: now,
            userId: event.createdByUserId,
            userEmail: userContext?.email,
            userRole: userContext?.role || 'user',
            action: event.action,
            resourceType: 'MENTION',
            resourceId: event.mentionId,
            result: event.result,
            details: {
                mentionText: event.mentionText,
                mentionedUserId: event.userId,
                resourceId: event.resourceId,
                resourceType: event.resourceType,
                wasAssociatedWith: event.wasAssociatedWith,
                wasDisassociatedFrom: event.wasDisassociatedFrom,
            },
            workspaceId,
            sessionId,
            requestId,
            error: event.error,
            createdAt: now,
            _immutable: true,
        };
        await this.storage.append(entry);
        console.log(`[AuditLoggingService] Logged ${event.action} for mention ${event.mentionId}`);
        this.emit('audit-logged', entry);
        return entry.id;
    }
    /**
     * Log generic audit event
     */
    async logEvent(workspaceId, userId, action, resourceType, resourceId, details = {}, result = 'SUCCESS', error) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const userContext = this.userContextMap.get(userId);
        const now = Date.now();
        const entry = {
            id: `audit-${workspaceId}-${now}-${Math.random().toString(16).substring(2, 10)}`,
            timestamp: now,
            userId,
            userEmail: userContext?.email,
            userRole: userContext?.role || 'user',
            action,
            resourceType,
            resourceId,
            result,
            details,
            workspaceId,
            error,
            createdAt: now,
            _immutable: true,
        };
        await this.storage.append(entry);
        console.log(`[AuditLoggingService] Logged ${action} for ${resourceType} ${resourceId}`);
        this.emit('audit-logged', entry);
        return entry.id;
    }
    /**
     * Query audit logs
     */
    async queryLogs(filter) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        return this.storage.query(filter);
    }
    /**
     * Get single audit entry
     */
    async getEntry(entryId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        return this.storage.getById(entryId);
    }
    /**
     * Export audit logs for compliance
     */
    async exportLogs(workspaceId, format = 'json') {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        return this.storage.export(workspaceId, format);
    }
    /**
     * Get audit statistics for compliance reporting
     */
    async getStatistics(workspaceId) {
        const result = await this.queryLogs({
            workspaceId,
            limit: 100000, // Large limit to get all for stats
        });
        const entriesByAction = {};
        const entriesByResourceType = {};
        const entriesByResult = {};
        let failureCount = 0;
        let earliestTime = Date.now();
        let latestTime = 0;
        for (const entry of result.entries) {
            entriesByAction[entry.action] =
                (entriesByAction[entry.action] || 0) + 1;
            entriesByResourceType[entry.resourceType] =
                (entriesByResourceType[entry.resourceType] || 0) + 1;
            entriesByResult[entry.result] =
                (entriesByResult[entry.result] || 0) + 1;
            if (entry.result !== 'SUCCESS') {
                failureCount++;
            }
            earliestTime = Math.min(earliestTime, entry.timestamp);
            latestTime = Math.max(latestTime, entry.timestamp);
        }
        return {
            totalEntries: result.total,
            entriesByAction,
            entriesByResourceType,
            entriesByResult,
            failureCount,
            failureRate: result.total > 0 ? (failureCount / result.total) * 100 : 0,
            dateRange: {
                earliest: earliestTime,
                latest: latestTime || Date.now(),
            },
        };
    }
    /**
     * Generate SOC2 compliance report
     */
    async generateComplianceReport(workspaceId, startTime, endTime) {
        const result = await this.queryLogs({
            workspaceId,
            startTime,
            endTime,
            limit: 100000,
        });
        const statistics = await this.getStatistics(workspaceId);
        // Analyze access patterns
        const uniqueUsers = new Set();
        const uniqueResources = new Set();
        const actionCounts = {};
        for (const entry of result.entries) {
            uniqueUsers.add(entry.userId);
            uniqueResources.add(`${entry.resourceType}:${entry.resourceId}`);
            actionCounts[entry.action] =
                (actionCounts[entry.action] || 0) + 1;
        }
        const topActions = Object.entries(actionCounts)
            .map(([action, count]) => ({ action: action, count }))
            .sort((a, b) => b.count - a.count)
            .slice(0, 10);
        // Find suspicious patterns
        const suspiciousPatterns = [];
        if (statistics.failureRate > 5) {
            suspiciousPatterns.push(`High failure rate: ${statistics.failureRate.toFixed(2)}%`);
        }
        // Find failed actions
        const failedActions = result.entries.filter((e) => e.result !== 'SUCCESS');
        return {
            workspaceId,
            generatedAt: Date.now(),
            reportPeriod: { startTime, endTime },
            statistics,
            accessPatterns: {
                usersAccessedResources: uniqueUsers.size,
                uniqueResources: uniqueResources.size,
                topActions,
            },
            securityEvents: {
                failedActions: failedActions.slice(0, 50),
                suspiciousPatterns,
            },
        };
    }
    /**
     * Validate audit log integrity
     */
    async validateIntegrity(workspaceId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        return this.storage.validateIntegrity(workspaceId);
    }
}
/**
 * Global service instance
 */
let serviceInstance = null;
/**
 * Get global service instance
 */
export async function getAuditLoggingService() {
    if (!serviceInstance) {
        serviceInstance = new AuditLoggingService();
        await serviceInstance.initialize();
    }
    return serviceInstance;
}
//# sourceMappingURL=audit-service.js.map