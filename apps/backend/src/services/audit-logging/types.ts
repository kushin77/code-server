/**
 * @file        apps/backend/src/services/audit-logging/types.ts
 * @module      security/audit-logging
 * @description SOC2-grade audit logging type definitions
 */

/**
 * Audit event action types
 */
export type AuditAction =
  | 'CREATE'
  | 'READ'
  | 'UPDATE'
  | 'DELETE'
  | 'ASSOCIATE'
  | 'DISASSOCIATE'
  | 'ASSIGN'
  | 'UNASSIGN'
  | 'ACKNOWLEDGE'
  | 'RESOLVE'
  | 'EXPORT';

/**
 * Resource types that can be audited
 */
export type ResourceType =
  | 'MENTION'
  | 'HELP_QUEUE_ITEM'
  | 'CODE_REVIEW'
  | 'DEBUG_SESSION'
  | 'WORKSPACE'
  | 'USER_SESSION';

/**
 * Audit event result status
 */
export type AuditResult = 'SUCCESS' | 'FAILURE' | 'PARTIAL';

/**
 * User role for audit context
 */
export type UserRole = 'admin' | 'user' | 'expert' | 'reviewer' | 'guest';

/**
 * Immutable audit log entry
 */
export interface AuditLogEntry {
  id: string; // Unique identifier (UUID)
  timestamp: number; // Unix timestamp (immutable, set at creation)
  
  // Actor information
  userId: string; // Who performed the action
  userEmail?: string; // For auditability
  userRole: UserRole; // User's role at time of action
  
  // Action details
  action: AuditAction;
  resourceType: ResourceType;
  resourceId: string; // ID of affected resource
  
  // Change context
  result: AuditResult;
  details: Record<string, any>; // Action-specific details
  previousValues?: Record<string, any>; // For UPDATE actions
  newValues?: Record<string, any>; // For UPDATE actions
  
  // Context
  workspaceId: string; // Which workspace this occurred in
  sessionId?: string; // User session (if applicable)
  requestId?: string; // Correlation ID for request tracing
  ipAddress?: string; // Source IP
  userAgent?: string; // Browser/client info
  
  // Error tracking
  error?: string; // If result !== SUCCESS, error message
  errorCode?: string; // Standardized error code
  
  // Immutable markers
  createdAt: number; // Identical to timestamp (redundancy for consistency)
  _immutable: true; // Marker for storage systems
}

/**
 * Audit log query filters
 */
export interface AuditLogQuery {
  workspaceId: string;
  userId?: string;
  action?: AuditAction;
  resourceType?: ResourceType;
  resourceId?: string;
  startTime?: number;
  endTime?: number;
  limit?: number;
  offset?: number;
}

/**
 * Audit log query result
 */
export interface AuditLogQueryResult {
  entries: AuditLogEntry[];
  total: number;
  limit: number;
  offset: number;
  hasMore: boolean;
}

/**
 * Mention-specific audit event
 */
export interface MentionAuditEvent {
  action: 'CREATE' | 'ASSOCIATE' | 'DISASSOCIATE' | 'DELETE';
  mentionId: string;
  mentionText: string;
  userId: string; // Who was mentioned
  createdByUserId: string; // Who created the mention
  resourceId: string; // Resource being mentioned in
  resourceType: 'CODE_SNIPPET' | 'COMMENT' | 'DOCUMENT';
  wasAssociatedWith?: string[]; // If ASSOCIATE, which snippets
  wasDisassociatedFrom?: string[]; // If DISASSOCIATE, which snippets
  result: AuditResult;
  error?: string;
}

/**
 * Audit log storage interface
 */
export interface IAuditLogStorage {
  append(entry: AuditLogEntry): Promise<void>;
  query(filter: AuditLogQuery): Promise<AuditLogQueryResult>;
  getById(entryId: string): Promise<AuditLogEntry | null>;
  export(workspaceId: string, format: 'json' | 'csv'): Promise<string>;
  validateIntegrity(workspaceId: string): Promise<{ valid: boolean; issues: string[] }>;
}

/**
 * Audit statistics for compliance reporting
 */
export interface AuditStatistics {
  totalEntries: number;
  entriesByAction: Record<AuditAction, number>;
  entriesByResourceType: Record<ResourceType, number>;
  entriesByResult: Record<AuditResult, number>;
  failureCount: number;
  failureRate: number;
  dateRange: {
    earliest: number;
    latest: number;
  };
}

/**
 * Compliance report for SOC2
 */
export interface ComplianceReport {
  workspaceId: string;
  generatedAt: number;
  reportPeriod: {
    startTime: number;
    endTime: number;
  };
  statistics: AuditStatistics;
  accessPatterns: {
    usersAccessedResources: number;
    uniqueResources: number;
    topActions: Array<{ action: AuditAction; count: number }>;
  };
  securityEvents: {
    failedActions: AuditLogEntry[];
    suspiciousPatterns: string[];
  };
}
