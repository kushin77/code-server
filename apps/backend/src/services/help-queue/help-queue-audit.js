#!/usr/bin/env node
// @file        apps/backend/src/services/help-queue/help-queue-audit.ts
// @module      services/help-queue
// @description Audit logging for Help Queue service - SOC2 compliance
import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';
const logger = getLogger('HelpQueueAudit');
/**
 * Help Queue Audit Service - SOC2-grade immutable logging
 */
export class HelpQueueAuditService extends EventEmitter {
    constructor() {
        super();
        this.logs = new Map(); // workspaceId -> logs
        this.nextId = 0;
        this.userContext = {};
    }
    /**
     * Get singleton instance
     */
    static getInstance() {
        if (!HelpQueueAuditService.instance) {
            HelpQueueAuditService.instance = new HelpQueueAuditService();
        }
        return HelpQueueAuditService.instance;
    }
    /**
     * Set current user context for audit logging
     */
    setUserContext(email, role) {
        this.userContext = { email, role };
    }
    /**
     * Log a Help Queue audit event
     */
    logQueueItemEvent(userId, action, queueItemId, workspaceId, success, metadata, errorMessage) {
        const entry = {
            id: `audit-${++this.nextId}`,
            timestamp: Date.now(),
            userId,
            userEmail: this.userContext.email,
            userRole: this.userContext.role,
            action,
            queueItemId,
            workspaceId,
            resourceType: 'QUEUE_ITEM',
            success,
            errorMessage,
            metadata,
            _immutable: true,
            _createdAt: Date.now(),
        };
        // Append to workspace logs
        if (!this.logs.has(workspaceId)) {
            this.logs.set(workspaceId, []);
        }
        this.logs.get(workspaceId).push(entry);
        logger.info(`Queue item audit: ${action} for ${queueItemId} by ${userId}`, {
            success,
            workspaceId,
        });
        this.emit('audit-logged', entry);
        return entry;
    }
    /**
     * Log expert-related audit event
     */
    logExpertEvent(userId, action, expertId, workspaceId, success, metadata, errorMessage) {
        const entry = {
            id: `audit-${++this.nextId}`,
            timestamp: Date.now(),
            userId,
            userEmail: this.userContext.email,
            userRole: this.userContext.role,
            action,
            expertId,
            workspaceId,
            resourceType: 'EXPERT',
            success,
            errorMessage,
            metadata,
            _immutable: true,
            _createdAt: Date.now(),
        };
        if (!this.logs.has(workspaceId)) {
            this.logs.set(workspaceId, []);
        }
        this.logs.get(workspaceId).push(entry);
        logger.info(`Expert audit: ${action} for ${expertId} by ${userId}`, {
            success,
            workspaceId,
        });
        this.emit('audit-logged', entry);
        return entry;
    }
    /**
     * Get all audit entries for a workspace
     */
    getWorkspaceLogs(workspaceId) {
        return this.logs.get(workspaceId) || [];
    }
    /**
     * Query audit logs with filters
     */
    queryLogs(workspaceId, filters) {
        let entries = this.getWorkspaceLogs(workspaceId);
        if (filters?.userId) {
            entries = entries.filter((e) => e.userId === filters.userId);
        }
        if (filters?.action) {
            entries = entries.filter((e) => e.action === filters.action);
        }
        if (filters?.queueItemId) {
            entries = entries.filter((e) => e.queueItemId === filters.queueItemId);
        }
        if (filters?.expertId) {
            entries = entries.filter((e) => e.expertId === filters.expertId);
        }
        if (filters?.success !== undefined) {
            entries = entries.filter((e) => e.success === filters.success);
        }
        if (filters?.startTime !== undefined) {
            entries = entries.filter((e) => e.timestamp >= filters.startTime);
        }
        if (filters?.endTime !== undefined) {
            entries = entries.filter((e) => e.timestamp <= filters.endTime);
        }
        const total = entries.length;
        const limit = filters?.limit || 50;
        const offset = filters?.offset || 0;
        return {
            entries: entries.slice(offset, offset + limit),
            total,
        };
    }
    /**
     * Get statistics for compliance reporting
     */
    getStatistics(workspaceId) {
        const entries = this.getWorkspaceLogs(workspaceId);
        const entriesByAction = {};
        const entriesByResourceType = {};
        let failures = 0;
        const failuresByAction = {};
        entries.forEach((entry) => {
            entriesByAction[entry.action] = (entriesByAction[entry.action] || 0) + 1;
            entriesByResourceType[entry.resourceType] =
                (entriesByResourceType[entry.resourceType] || 0) + 1;
            if (!entry.success) {
                failures++;
                failuresByAction[entry.action] = (failuresByAction[entry.action] || 0) + 1;
            }
        });
        return {
            totalEntries: entries.length,
            entriesByAction,
            entriesByResourceType,
            successRate: entries.length > 0 ? (entries.length - failures) / entries.length : 1,
            failureRate: entries.length > 0 ? failures / entries.length : 0,
            failuresByAction,
        };
    }
    /**
     * Reset logs (for testing)
     */
    reset() {
        this.logs.clear();
        this.nextId = 0;
        this.userContext = {};
        this.removeAllListeners();
    }
}
export default HelpQueueAuditService.getInstance();
//# sourceMappingURL=help-queue-audit.js.map