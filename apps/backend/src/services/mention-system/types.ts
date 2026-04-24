/**
 * Mention System Types
 * @mentions in code, comments, commits with SOC2-grade audit logging
 */

/**
 * Mention target (what was mentioned)
 */
export interface MentionTarget {
  type: 'file' | 'line' | 'function' | 'variable' | 'comment' | 'issue' | 'pr' | 'commit';
  fileId?: string;
  filePath?: string;
  lineNumber?: number;
  functionName?: string;
  variableName?: string;
  commentId?: string;
  issueNumber?: number;
  prNumber?: number;
  commitSha?: string;
  snippet?: string; // Code snippet context
}

/**
 * User mention
 */
export interface UserMention {
  id: string;
  userId: string;
  mentionedUserId: string;
  createdAt: number;
  mentionedAt: number;
}

/**
 * Mention notification
 */
export interface MentionNotification {
  id: string;
  mentionId: string;
  userId: string;
  createdBy: string;
  target: MentionTarget;
  context: string; // Message context where mention occurred
  contextType: 'code' | 'comment' | 'commit-message' | 'pr-review' | 'issue-comment' | 'chat';
  workspaceId?: string;
  sessionId?: string;
  createdAt: number;
  readAt?: number;
  acknowledged: boolean;
  priority: 'low' | 'normal' | 'high' | 'urgent';
}

/**
 * Mention statistics
 */
export interface MentionStats {
  totalMentions: number;
  mentionsByType: Record<string, number>;
  mentionsByUser: Record<string, number>;
  mentionedByUser: Record<string, number>;
  mentionsByTarget: Record<string, number>;
  mentionsByContext: Record<string, number>;
  unreadCount: number;
  averageResponseTime: number; // ms
  priorityDistribution: Record<string, number>;
}

/**
 * Mention query
 */
export interface MentionQuery {
  userId?: string;
  mentionedUserId?: string;
  targetType?: MentionTarget['type'];
  contextType?: MentionNotification['contextType'];
  priority?: MentionNotification['priority'];
  unreadOnly?: boolean;
  startTime?: number;
  endTime?: number;
  limit?: number;
  offset?: number;
}

/**
 * Audit log entry for mention system
 * Integrates with AuditLogService
 */
export interface MentionAuditEntry {
  id: string;
  mentionId: string;
  userId: string;
  mentionedUserId: string;
  sessionId?: string;
  workspaceId?: string;
  operation: 'created' | 'acknowledged' | 'read' | 'deleted' | 'shared' | 'exported';
  targetType: MentionTarget['type'];
  targetPath?: string;
  ipAddress?: string;
  userAgent?: string;
  timestamp: number;
  status: 'success' | 'denied' | 'error';
  reason?: string; // If denied or error
}

/**
 * Mention settings per user
 */
export interface MentionSettings {
  userId: string;
  emailNotifications: boolean;
  pushNotifications: boolean;
  slackNotifications?: boolean;
  mentionHighlighting: boolean;
  auditLogging: boolean; // Allow audit logging of this user's mentions
  privacyLevel: 'public' | 'internal' | 'private'; // Who can mention this user
  blockedUsers?: string[]; // Users who cannot mention this user
  createdAt: number;
  updatedAt: number;
}

/**
 * Mention search result
 */
export interface MentionSearchResult {
  id: string;
  notification: MentionNotification;
  matchContext: string;
  relevance: number; // 0-100
}

/**
 * Service configuration
 */
export interface MentionSystemConfig {
  enabled: boolean;
  auditLoggingEnabled: boolean;
  maxMentionsPerMessage: number;
  maxMentionsPerDay: number;
  retentionDays: number; // How long to keep mentions
  enableEmailNotifications: boolean;
  enablePushNotifications: boolean;
  enableAcknowledgment: boolean;
  enablePriority: boolean;
  maxAuditLogSize: number; // Max entries to keep
}
