/**
 * @file        apps/backend/src/services/audit-logging/help-queue-audit.ts
 * @module      security/audit-logging
 * @description Help Queue system audit logging
 */

import {
  AuditLoggingService,
  getAuditLoggingService,
} from './audit-service.js';
import { AuditAction } from './types.js';

/**
 * Help Queue audit event types
 */
export type HelpQueueAuditAction =
  | 'CREATE'
  | 'ASSIGN'
  | 'UNASSIGN'
  | 'RESPOND'
  | 'RESOLVE'
  | 'REGISTER_EXPERT'
  | 'CLAIM'
  | 'CLOSE'
  | 'REOPEN';

/**
 * Help Queue item states for audit context
 */
export type HelpQueueItemState =
  | 'OPEN'
  | 'ASSIGNED'
  | 'IN_PROGRESS'
  | 'RESOLVED'
  | 'CLOSED';

/**
 * Help Queue audit event
 */
export interface HelpQueueAuditEvent {
  action: HelpQueueAuditAction;
  itemId: string;
  creatorId: string; // Who created the help request
  assignedToId?: string; // Who it's assigned to
  previousAssignee?: string; // For REASSIGN operations
  expertRegistrationId?: string; // For REGISTER_EXPERT
  respondentId?: string; // Who responded
  responseContent?: string; // Content of response
  itemState: HelpQueueItemState;
  itemCategory?: string; // Help category
  itemDescription: string;
  resolutionSummary?: string; // For RESOLVE operations
  claimedAt?: number; // When expert claimed it
  resolvedAt?: number; // When it was resolved
  error?: string;
}

/**
 * Help Queue audit statistics
 */
export interface HelpQueueAuditStats {
  totalRequests: number;
  requestsByCreator: Record<string, number>;
  requestsByAssignee: Record<string, number>;
  averageResolutionTime: number;
  resolutionRate: number; // % of resolved requests
  expertClaimRate: number; // % of expert claims vs. assignments
  responseCount: number;
  averageResponseTime: number;
}

/**
 * Help Queue Audit Service: Specialized audit logging for help queue
 */
export class HelpQueueAuditService {
  private baseService: AuditLoggingService;

  constructor(baseService?: AuditLoggingService) {
    this.baseService = baseService || new AuditLoggingService();
  }

  /**
   * Initialize service
   */
  async initialize(): Promise<void> {
    await this.baseService.initialize();
    console.log('[HelpQueueAuditService] Initialized');
  }

  /**
   * Log help queue item creation
   */
  async logItemCreated(
    workspaceId: string,
    itemId: string,
    creatorId: string,
    description: string,
    category?: string,
    sessionId?: string
  ): Promise<string> {
    return this.baseService.logEvent(
      workspaceId,
      creatorId,
      'CREATE' as AuditAction,
      'HELP_QUEUE_ITEM',
      itemId,
      {
        description,
        category,
        state: 'OPEN',
      }
    );
  }

  /**
   * Log help queue item assignment
   */
  async logItemAssigned(
    workspaceId: string,
    itemId: string,
    assignedToId: string,
    assignedById: string,
    previousAssignee?: string,
    sessionId?: string
  ): Promise<string> {
    return this.baseService.logEvent(
      workspaceId,
      assignedById,
      'ASSIGN' as AuditAction,
      'HELP_QUEUE_ITEM',
      itemId,
      {
        assignedToId,
        previousAssignee,
        state: 'ASSIGNED',
      }
    );
  }

  /**
   * Log expert claim of help queue item
   */
  async logExpertClaim(
    workspaceId: string,
    itemId: string,
    expertId: string,
    claimedAt: number,
    sessionId?: string
  ): Promise<string> {
    return this.baseService.logEvent(
      workspaceId,
      expertId,
      'CLAIM' as AuditAction,
      'HELP_QUEUE_ITEM',
      itemId,
      {
        expertId,
        claimedAt,
        state: 'IN_PROGRESS',
      }
    );
  }

  /**
   * Log response to help queue item
   */
  async logResponse(
    workspaceId: string,
    itemId: string,
    respondentId: string,
    responseContent: string,
    responseId: string,
    sessionId?: string
  ): Promise<string> {
    return this.baseService.logEvent(
      workspaceId,
      respondentId,
      'RESPOND' as AuditAction,
      'HELP_QUEUE_ITEM',
      itemId,
      {
        respondentId,
        responseId,
        responseLength: responseContent.length,
        state: 'IN_PROGRESS',
      }
    );
  }

  /**
   * Log help queue item resolution
   */
  async logItemResolved(
    workspaceId: string,
    itemId: string,
    resolvedById: string,
    resolutionSummary: string,
    resolvedAt: number,
    responseCount: number,
    sessionId?: string
  ): Promise<string> {
    return this.baseService.logEvent(
      workspaceId,
      resolvedById,
      'RESOLVE' as AuditAction,
      'HELP_QUEUE_ITEM',
      itemId,
      {
        resolutionSummary,
        resolvedAt,
        responseCount,
        resolutionLength: resolutionSummary.length,
        state: 'RESOLVED',
      }
    );
  }

  /**
   * Log expert registration for help queue
   */
  async logExpertRegistration(
    workspaceId: string,
    expertId: string,
    expertise: string[],
    registeredById: string,
    sessionId?: string
  ): Promise<string> {
    return this.baseService.logEvent(
      workspaceId,
      registeredById,
      'REGISTER_EXPERT' as AuditAction,
      'HELP_QUEUE_ITEM',
      `expert-${expertId}`,
      {
        expertId,
        expertise,
      }
    );
  }

  /**
   * Log help queue item closure
   */
  async logItemClosed(
    workspaceId: string,
    itemId: string,
    closedById: string,
    reason?: string,
    sessionId?: string
  ): Promise<string> {
    return this.baseService.logEvent(
      workspaceId,
      closedById,
      'CLOSE' as AuditAction,
      'HELP_QUEUE_ITEM',
      itemId,
      {
        reason,
        state: 'CLOSED',
      }
    );
  }

  /**
   * Log help queue item reopened
   */
  async logItemReopened(
    workspaceId: string,
    itemId: string,
    reopenedById: string,
    reason: string,
    sessionId?: string
  ): Promise<string> {
    return this.baseService.logEvent(
      workspaceId,
      reopenedById,
      'REOPEN' as AuditAction,
      'HELP_QUEUE_ITEM',
      itemId,
      {
        reason,
        state: 'OPEN',
      }
    );
  }

  /**
   * Get help queue audit statistics
   */
  async getStatistics(workspaceId: string): Promise<HelpQueueAuditStats> {
    const result = await this.baseService.queryLogs({
      workspaceId,
      resourceType: 'HELP_QUEUE_ITEM',
      limit: 100000,
    });

    const requestsByCreator: Record<string, number> = {};
    const requestsByAssignee: Record<string, number> = {};
    let responseCount = 0;
    let claimCount = 0;
    let resolveCount = 0;
    let totalResolutionTime = 0;
    let createTime: number | undefined;
    let resolveTime: number | undefined;

    for (const entry of result.entries) {
      if (entry.action === 'CREATE') {
        requestsByCreator[entry.userId] =
          (requestsByCreator[entry.userId] || 0) + 1;
        createTime = entry.timestamp;
      } else if (entry.action === 'ASSIGN') {
        const assignedToId = entry.details.assignedToId;
        if (assignedToId) {
          requestsByAssignee[assignedToId] =
            (requestsByAssignee[assignedToId] || 0) + 1;
        }
      } else if (entry.action === 'RESPOND') {
        responseCount++;
      } else if (entry.action === 'CLAIM') {
        claimCount++;
      } else if (entry.action === 'RESOLVE') {
        resolveCount++;
        resolveTime = entry.timestamp;
        if (createTime) {
          totalResolutionTime += resolveTime - createTime;
        }
      }
    }

    const totalRequests =
      requestsByCreator[Object.keys(requestsByCreator)[0]] || 0;

    return {
      totalRequests: result.total,
      requestsByCreator,
      requestsByAssignee,
      averageResolutionTime:
        resolveCount > 0 ? totalResolutionTime / resolveCount : 0,
      resolutionRate:
        result.total > 0 ? (resolveCount / result.total) * 100 : 0,
      expertClaimRate:
        claimCount + resolveCount > 0
          ? (claimCount / (claimCount + resolveCount)) * 100
          : 0,
      responseCount,
      averageResponseTime:
        responseCount > 0 ? totalResolutionTime / responseCount : 0,
    };
  }
}

/**
 * Global help queue audit service instance
 */
let helpQueueAuditInstance: HelpQueueAuditService | null = null;

/**
 * Get global help queue audit service instance
 */
export async function getHelpQueueAuditService(): Promise<HelpQueueAuditService> {
  if (!helpQueueAuditInstance) {
    const baseService = await getAuditLoggingService();
    helpQueueAuditInstance = new HelpQueueAuditService(baseService);
    await helpQueueAuditInstance.initialize();
  }
  return helpQueueAuditInstance;
}
