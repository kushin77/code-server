/**
 * @file        apps/backend/src/services/code-review/types.ts
 * @module      collaboration/code-review
 * @description Code review request type definitions
 */

/**
 * Priority level for code review requests
 */
export type ReviewPriority = 'low' | 'medium' | 'high' | 'urgent';

/**
 * Review request status
 */
export type ReviewStatus =
  | 'pending'
  | 'in-review'
  | 'approved'
  | 'requested-changes'
  | 'closed';

/**
 * Code snippet or file to be reviewed
 */
export interface ReviewTarget {
  id: string;
  type: 'snippet' | 'file' | 'diff' | 'commit';
  path?: string; // File path
  content?: string; // Code content
  language?: string; // Programming language
  hash?: string; // Diff or commit hash
  lineRange?: {
    start: number;
    end: number;
  };
}

/**
 * Code review request
 */
export interface CodeReviewRequest {
  id: string;
  createdAt: number;
  createdBy: string; // User ID of requester
  workspaceId: string;

  // Request details
  title: string;
  description: string;
  priority: ReviewPriority;

  // Targets to review
  targets: ReviewTarget[];

  // Reviewers
  requestedReviewersIds: string[];
  reviewerBadges?: Record<string, ReviewerBadge>; // Badge info per reviewer

  // Context
  contextNote?: string; // Additional context for reviewers
  relatedIssueId?: string; // Related GitHub issue

  // Status tracking
  status: ReviewStatus;
  reviewsCompleted: number;
  reviewsRequired: number;

  // Metadata
  dueDate?: number;
  labels?: string[];
  estimatedReviewTime?: number; // Minutes

  // Notifications
  notificationsSent: boolean;
  lastReminderAt?: number;
}

/**
 * Individual review response
 */
export interface ReviewResponse {
  id: string;
  requestId: string;
  reviewerId: string;
  createdAt: number;

  // Review content
  status: 'approved' | 'requested-changes' | 'commented';
  feedback: string;
  suggestions?: Array<{
    targetId: string;
    lineNumber?: number;
    text: string;
    suggestion?: string; // Proposed change
  }>;

  // Metadata
  reviewDuration?: number; // Minutes spent reviewing
  isBot?: boolean; // AI-generated review
}

/**
 * Reviewer badge/role
 */
export interface ReviewerBadge {
  reviewerId: string;
  role: 'lead' | 'domain-expert' | 'peer' | 'stakeholder';
  expertise?: string[]; // Areas of expertise
  required: boolean; // Whether approval is required
  approved: boolean; // Has approved
  responded: boolean; // Has responded
}

/**
 * Code review request event (for notifications)
 */
export interface CodeReviewEvent {
  type: 'requested' | 'approved' | 'requested-changes' | 'commented' | 'updated';
  requestId: string;
  reviewerId?: string;
  actorId: string;
  message?: string;
  createdAt: number;
}

/**
 * Code review statistics
 */
export interface CodeReviewStats {
  totalRequests: number;
  pendingRequests: number;
  approvedRequests: number;
  requestedChangesRequests: number;
  closedRequests: number;

  averageReviewTime: number; // Minutes
  averageReviewers: number; // Per request
  approvalRate: number; // % approved

  byPriority: Record<ReviewPriority, number>;
  byReviewer: Record<string, { completed: number; pending: number }>;
}

/**
 * Notification for review requests
 */
export interface ReviewNotification {
  id: string;
  requestId: string;
  recipientId: string;
  type: 'new-request' | 'reminder' | 'update' | 'completed';
  message: string;
  createdAt: number;
  readAt?: number;
}
