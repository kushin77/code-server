/**
 * @file        apps/backend/src/services/audit-logging/help-queue-audit.ts
 * @module      security/audit-logging
 * @description Help Queue system audit logging
 */
import { AuditLoggingService, getAuditLoggingService, } from './audit-service.js';
/**
 * Help Queue Audit Service: Specialized audit logging for help queue
 */
export class HelpQueueAuditService {
    constructor(baseService) {
        this.baseService = baseService || new AuditLoggingService();
    }
    /**
     * Initialize service
     */
    async initialize() {
        await this.baseService.initialize();
        console.log('[HelpQueueAuditService] Initialized');
    }
    /**
     * Log help queue item creation
     */
    async logItemCreated(workspaceId, itemId, creatorId, description, category, sessionId) {
        return this.baseService.logEvent(workspaceId, creatorId, 'CREATE', 'HELP_QUEUE_ITEM', itemId, {
            description,
            category,
            state: 'OPEN',
        });
    }
    /**
     * Log help queue item assignment
     */
    async logItemAssigned(workspaceId, itemId, assignedToId, assignedById, previousAssignee, sessionId) {
        return this.baseService.logEvent(workspaceId, assignedById, 'ASSIGN', 'HELP_QUEUE_ITEM', itemId, {
            assignedToId,
            previousAssignee,
            state: 'ASSIGNED',
        });
    }
    /**
     * Log expert claim of help queue item
     */
    async logExpertClaim(workspaceId, itemId, expertId, claimedAt, sessionId) {
        return this.baseService.logEvent(workspaceId, expertId, 'CLAIM', 'HELP_QUEUE_ITEM', itemId, {
            expertId,
            claimedAt,
            state: 'IN_PROGRESS',
        });
    }
    /**
     * Log response to help queue item
     */
    async logResponse(workspaceId, itemId, respondentId, responseContent, responseId, sessionId) {
        return this.baseService.logEvent(workspaceId, respondentId, 'RESPOND', 'HELP_QUEUE_ITEM', itemId, {
            respondentId,
            responseId,
            responseLength: responseContent.length,
            state: 'IN_PROGRESS',
        });
    }
    /**
     * Log help queue item resolution
     */
    async logItemResolved(workspaceId, itemId, resolvedById, resolutionSummary, resolvedAt, responseCount, sessionId) {
        return this.baseService.logEvent(workspaceId, resolvedById, 'RESOLVE', 'HELP_QUEUE_ITEM', itemId, {
            resolutionSummary,
            resolvedAt,
            responseCount,
            resolutionLength: resolutionSummary.length,
            state: 'RESOLVED',
        });
    }
    /**
     * Log expert registration for help queue
     */
    async logExpertRegistration(workspaceId, expertId, expertise, registeredById, sessionId) {
        return this.baseService.logEvent(workspaceId, registeredById, 'REGISTER_EXPERT', 'HELP_QUEUE_ITEM', `expert-${expertId}`, {
            expertId,
            expertise,
        });
    }
    /**
     * Log help queue item closure
     */
    async logItemClosed(workspaceId, itemId, closedById, reason, sessionId) {
        return this.baseService.logEvent(workspaceId, closedById, 'CLOSE', 'HELP_QUEUE_ITEM', itemId, {
            reason,
            state: 'CLOSED',
        });
    }
    /**
     * Log help queue item reopened
     */
    async logItemReopened(workspaceId, itemId, reopenedById, reason, sessionId) {
        return this.baseService.logEvent(workspaceId, reopenedById, 'REOPEN', 'HELP_QUEUE_ITEM', itemId, {
            reason,
            state: 'OPEN',
        });
    }
    /**
     * Get help queue audit statistics
     */
    async getStatistics(workspaceId) {
        const result = await this.baseService.queryLogs({
            workspaceId,
            resourceType: 'HELP_QUEUE_ITEM',
            limit: 100000,
        });
        const requestsByCreator = {};
        const requestsByAssignee = {};
        let responseCount = 0;
        let claimCount = 0;
        let resolveCount = 0;
        let totalResolutionTime = 0;
        let createTime;
        let resolveTime;
        for (const entry of result.entries) {
            if (entry.action === 'CREATE') {
                requestsByCreator[entry.userId] =
                    (requestsByCreator[entry.userId] || 0) + 1;
                createTime = entry.timestamp;
            }
            else if (entry.action === 'ASSIGN') {
                const assignedToId = entry.details.assignedToId;
                if (assignedToId) {
                    requestsByAssignee[assignedToId] =
                        (requestsByAssignee[assignedToId] || 0) + 1;
                }
            }
            else if (entry.action === 'RESPOND') {
                responseCount++;
            }
            else if (entry.action === 'CLAIM') {
                claimCount++;
            }
            else if (entry.action === 'RESOLVE') {
                resolveCount++;
                resolveTime = entry.timestamp;
                if (createTime) {
                    totalResolutionTime += resolveTime - createTime;
                }
            }
        }
        const totalRequests = requestsByCreator[Object.keys(requestsByCreator)[0]] || 0;
        return {
            totalRequests: result.total,
            requestsByCreator,
            requestsByAssignee,
            averageResolutionTime: resolveCount > 0 ? totalResolutionTime / resolveCount : 0,
            resolutionRate: result.total > 0 ? (resolveCount / result.total) * 100 : 0,
            expertClaimRate: claimCount + resolveCount > 0
                ? (claimCount / (claimCount + resolveCount)) * 100
                : 0,
            responseCount,
            averageResponseTime: responseCount > 0 ? totalResolutionTime / responseCount : 0,
        };
    }
}
/**
 * Global help queue audit service instance
 */
let helpQueueAuditInstance = null;
/**
 * Get global help queue audit service instance
 */
export async function getHelpQueueAuditService() {
    if (!helpQueueAuditInstance) {
        const baseService = await getAuditLoggingService();
        helpQueueAuditInstance = new HelpQueueAuditService(baseService);
        await helpQueueAuditInstance.initialize();
    }
    return helpQueueAuditInstance;
}
//# sourceMappingURL=help-queue-audit.js.map