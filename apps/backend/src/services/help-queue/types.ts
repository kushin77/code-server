/**
 * Help Queue Service Types
 * SOC2-grade audit logging for help queue operations
 */

/**
 * Help queue request types
 */
export type HelpRequestType =
  | 'debugging'
  | 'feature-usage'
  | 'installation'
  | 'performance'
  | 'integration'
  | 'documentation'
  | 'general';

/**
 * Help request status
 */
export type HelpRequestStatus = 'open' | 'assigned' | 'in-progress' | 'resolved' | 'closed' | 'abandoned';

/**
 * Expert expertise level
 */
export type ExpertiseLevel = 'beginner' | 'intermediate' | 'expert' | 'architect';

/**
 * Help request priority
 */
export type RequestPriority = 'low' | 'normal' | 'high' | 'urgent';

/**
 * Help request
 */
export interface HelpRequest {
  id: string;
  userId: string;
  userEmail: string;
  type: HelpRequestType;
  title: string;
  description: string;
  code?: string;
  codeLanguage?: string;
  context?: string;
  attachments?: string[];
  priority: RequestPriority;
  createdAt: number;
  updatedAt: number;
  assignedExpertId?: string;
  assignedExpertEmail?: string;
  assignedAt?: number;
  status: HelpRequestStatus;
  resolvedAt?: number;
  resolutionNotes?: string;
  workspaceId?: string;
  sessionId?: string;
  rating?: number;
  feedback?: string;
}

/**
 * Help expert profile
 */
export interface HelpExpert {
  id: string;
  userId: string;
  email: string;
  name: string;
  expertise: ExpertiseLevel;
  skills: string[];
  registeredAt: number;
  activeRequests: number;
  totalResolved: number;
  averageResolutionTime: number;
  rating: number;
  bio?: string;
  isActive: boolean;
}

/**
 * Help response/message
 */
export interface HelpResponse {
  id: string;
  requestId: string;
  responderId: string;
  responderEmail: string;
  responderRole: 'requester' | 'expert' | 'admin';
  message: string;
  code?: string;
  codeLanguage?: string;
  attachments?: string[];
  createdAt: number;
  isResolution: boolean;
}

/**
 * SOC2 audit entry for help queue operations
 */
export interface HelpQueueAuditEntry {
  id: string;
  requestId: string;
  userId: string;
  userEmail: string;
  userRole: 'requester' | 'expert' | 'admin';
  operation: 'created' | 'assigned' | 'responded' | 'resolved' | 'closed' | 'rated' | 'expert-registered' | 'accessed';
  status: 'success' | 'denied' | 'error';
  ipAddress?: string;
  userAgent?: string;
  timestamp: number;
  resourceType: 'help-request' | 'help-response' | 'help-expert' | 'help-queue';
  resourceId: string;
  details?: Record<string, unknown>;
  reason?: string;
  previousStatus?: HelpRequestStatus;
  newStatus?: HelpRequestStatus;
}

/**
 * Help queue statistics
 */
export interface HelpQueueStats {
  totalRequests: number;
  requestsByType: Record<HelpRequestType, number>;
  requestsByStatus: Record<HelpRequestStatus, number>;
  requestsByPriority: Record<RequestPriority, number>;
  requestsByUser: Record<string, number>;
  averageResolutionTime: number;
  averageRating: number;
  totalExperts: number;
  expertsByLevel: Record<ExpertiseLevel, number>;
  activeRequests: number;
  resolvedRequests: number;
  averageResponseTime: number;
  totalResponses: number;
}

/**
 * Help queue query
 */
export interface HelpQueueQuery {
  userId?: string;
  expertId?: string;
  type?: HelpRequestType;
  status?: HelpRequestStatus;
  priority?: RequestPriority;
  startTime?: number;
  endTime?: number;
  limit?: number;
  offset?: number;
  sortBy?: 'created' | 'updated' | 'priority' | 'status';
  sortOrder?: 'asc' | 'desc';
}

/**
 * Help queue query result
 */
export interface HelpQueueQueryResult {
  requests: HelpRequest[];
  total: number;
  limit: number;
  offset: number;
}

/**
 * Help queue assignment
 */
export interface HelpAssignment {
  requestId: string;
  expertId: string;
  expertEmail: string;
  assignedAt: number;
  status: 'pending' | 'accepted' | 'declined';
  acceptedAt?: number;
}

/**
 * Help expert statistics
 */
export interface ExpertStats {
  expertId: string;
  totalAssigned: number;
  totalResolved: number;
  averageResolutionTime: number;
  averageRating: number;
  activeRequests: number;
  skillsUsed: Record<string, number>;
}

/**
 * Help queue settings
 */
export interface HelpQueueSettings {
  userId: string;
  emailNotifications: boolean;
  pushNotifications: boolean;
  slackIntegration: boolean;
  privacyLevel: 'public' | 'internal' | 'private';
  showProfile: boolean;
  allowExpertContact: boolean;
  createdAt: number;
  updatedAt: number;
}

/**
 * Help queue configuration
 */
export interface HelpQueueConfig {
  enabled: boolean;
  auditLoggingEnabled: boolean;
  maxRequestsPerUser: number;
  maxRequestsPerDay: number;
  assignmentTimeout: number;
  responseTimeout: number;
  retentionDays: number;
  notificationsEnabled: boolean;
  maxAuditLogSize: number;
  enableExpertRating: boolean;
  enableRequestRating: boolean;
}

/**
 * Help resolution
 */
export interface HelpResolution {
  requestId: string;
  expertId: string;
  expertEmail: string;
  resolutionNotes: string;
  resolvedAt: number;
  rating?: number;
  feedback?: string;
}
