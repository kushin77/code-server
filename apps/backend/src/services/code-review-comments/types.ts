/**
 * Code Review Comment Threads - Type Definitions
 * @file        apps/backend/src/services/code-review-comments/types.ts
 * @module      services/code-review-comments
 * @description Type definitions for threaded comment discussions on code reviews
 */

import { EventEmitter } from 'events';

/**
 * Comment author information
 */
export interface CommentAuthor {
  userId: string;
  userEmail: string;
  userName: string;
}

/**
 * Comment thread
 */
export interface CommentThread {
  id: string;
  reviewRequestId: string;
  createdBy: CommentAuthor;
  createdAt: number;
  updatedAt: number;
  isResolved: boolean;
  resolvedBy?: CommentAuthor;
  resolvedAt?: number;
  location: ThreadLocation;
  title?: string;
  comments: Map<string, ThreadComment>;
  participantIds: Set<string>;
  reactionCounts: Map<string, number>;
  isArchived: boolean;
  archivedAt?: number;
  priority: ThreadPriority;
  tags: string[];
  relatedIssues?: string[];
}

/**
 * Thread location in code
 */
export interface ThreadLocation {
  filePath: string;
  lineNumber?: number;
  startLine?: number;
  endLine?: number;
  columnNumber?: number;
}

/**
 * Comment in thread
 */
export interface ThreadComment {
  id: string;
  threadId: string;
  author: CommentAuthor;
  content: string;
  createdAt: number;
  updatedAt: number;
  editedBy?: CommentAuthor;
  editHistory: CommentEdit[];
  reactionCounts: Map<string, number>;
  mentionedUsers: string[];
  attachments?: Attachment[];
  isDeleted: boolean;
  deletedBy?: CommentAuthor;
  deletedAt?: number;
  approvalStatus?: CommentApprovalStatus;
}

/**
 * Comment edit record
 */
export interface CommentEdit {
  editedAt: number;
  editedBy: CommentAuthor;
  previousContent: string;
}

/**
 * Attachment in comment
 */
export interface Attachment {
  id: string;
  fileName: string;
  fileSize: number;
  mimeType: string;
  uploadedAt: number;
  url: string;
}

/**
 * Comment approval status
 */
export interface CommentApprovalStatus {
  approved: boolean;
  approvedBy?: CommentAuthor;
  approvedAt?: number;
  comment?: string;
}

/**
 * Thread priority level
 */
export type ThreadPriority = 'low' | 'medium' | 'high' | 'critical' | 'blocker';

/**
 * Thread statistics
 */
export interface ThreadStatistics {
  totalThreads: number;
  activeThreads: number;
  resolvedThreads: number;
  totalComments: number;
  averageCommentsPerThread: number;
  averageResolutionTime: number;
  threadsWithReactions: number;
  threadsByPriority: Map<ThreadPriority, number>;
  participantCount: number;
}

/**
 * Audit entry for comment operations
 */
export interface CommentThreadAuditEntry {
  timestamp: number;
  userId: string;
  userEmail: string;
  ipAddress: string;
  userAgent: string;
  operation: CommentThreadOperation;
  reviewRequestId?: string;
  threadId?: string;
  status: 'success' | 'failure';
  details: Map<string, unknown>;
}

/**
 * Comment thread operation type
 */
export type CommentThreadOperation =
  | 'thread-created'
  | 'comment-added'
  | 'comment-edited'
  | 'comment-deleted'
  | 'thread-resolved'
  | 'thread-reopened'
  | 'reaction-added'
  | 'user-mentioned'
  | 'thread-archived'
  | 'thread-unarchived';

/**
 * Service configuration
 */
export interface CommentThreadConfig {
  maxThreadsPerReview: number;
  maxCommentsPerThread: number;
  maxCommentLength: number;
  enableThreadResolution: boolean;
  enableMentions: boolean;
  enableReactions: boolean;
  enableAttachments: boolean;
  enableApprovalRequests: boolean;
  autoArchiveResolvedThreadsAfterDays?: number;
  enableNotifications: boolean;
  maxAuditLogSize: number;
  retentionDays: number;
}

/**
 * Request to create comment thread
 */
export interface CreateCommentThreadRequest {
  reviewRequestId: string;
  createdBy: CommentAuthor;
  location: ThreadLocation;
  title?: string;
  initialComment: string;
  priority?: ThreadPriority;
  tags?: string[];
  mentionedUserIds?: string[];
}

/**
 * Result of creating thread
 */
export interface CreateCommentThreadResult {
  success: boolean;
  threadId?: string;
  thread?: CommentThread;
  error?: string;
}

/**
 * Request to add comment to thread
 */
export interface AddThreadCommentRequest {
  threadId: string;
  author: CommentAuthor;
  content: string;
  mentionedUserIds?: string[];
  attachments?: Attachment[];
}

/**
 * Result of adding comment
 */
export interface AddThreadCommentResult {
  success: boolean;
  commentId?: string;
  comment?: ThreadComment;
  broadcastedTo?: number;
  error?: string;
}

/**
 * Request to edit comment
 */
export interface EditThreadCommentRequest {
  threadId: string;
  commentId: string;
  editedBy: CommentAuthor;
  newContent: string;
}

/**
 * Result of editing comment
 */
export interface EditThreadCommentResult {
  success: boolean;
  comment?: ThreadComment;
  error?: string;
}

/**
 * Request to delete comment
 */
export interface DeleteThreadCommentRequest {
  threadId: string;
  commentId: string;
  deletedBy: CommentAuthor;
  reason?: string;
}

/**
 * Result of deleting comment
 */
export interface DeleteThreadCommentResult {
  success: boolean;
  comment?: ThreadComment;
  error?: string;
}

/**
 * Request to resolve thread
 */
export interface ResolveThreadRequest {
  threadId: string;
  resolvedBy: CommentAuthor;
  resolutionComment?: string;
}

/**
 * Result of resolving thread
 */
export interface ResolveThreadResult {
  success: boolean;
  thread?: CommentThread;
  error?: string;
}

/**
 * Request to reopen thread
 */
export interface ReopenThreadRequest {
  threadId: string;
  reopenedBy: CommentAuthor;
  reason?: string;
}

/**
 * Result of reopening thread
 */
export interface ReopenThreadResult {
  success: boolean;
  thread?: CommentThread;
  error?: string;
}

/**
 * Request to add reaction to comment
 */
export interface AddReactionRequest {
  threadId: string;
  commentId: string;
  userId: string;
  userEmail: string;
  reactionType: string;
}

/**
 * Result of adding reaction
 */
export interface AddReactionResult {
  success: boolean;
  reactionCounts?: Map<string, number>;
  error?: string;
}

/**
 * Request to mention user in comment
 */
export interface MentionUserRequest {
  threadId: string;
  commentId: string;
  userId: string;
  userEmail: string;
  userName: string;
  mentionerEmail: string;
  message?: string;
}

/**
 * Result of mentioning user
 */
export interface MentionUserResult {
  success: boolean;
  notification?: UserNotification;
  error?: string;
}

/**
 * User notification
 */
export interface UserNotification {
  id: string;
  userId: string;
  userEmail: string;
  type: NotificationType;
  threadId: string;
  reviewRequestId: string;
  actor: CommentAuthor;
  message: string;
  timestamp: number;
  isRead: boolean;
  readAt?: number;
}

/**
 * Notification type
 */
export type NotificationType =
  | 'comment-reply'
  | 'user-mentioned'
  | 'thread-resolved'
  | 'thread-archived'
  | 'reaction-added';

/**
 * Request to get thread
 */
export interface GetThreadRequest {
  threadId: string;
}

/**
 * Result of getting thread
 */
export interface GetThreadResult {
  success: boolean;
  thread?: CommentThread;
  comments?: ThreadComment[];
  participants?: CommentAuthor[];
  error?: string;
}

/**
 * Request to list threads
 */
export interface ListThreadsRequest {
  reviewRequestId: string;
  filter?: {
    resolved?: boolean;
    archived?: boolean;
    priority?: ThreadPriority[];
    tags?: string[];
  };
  limit?: number;
  offset?: number;
}

/**
 * Result of listing threads
 */
export interface ListThreadsResult {
  success: boolean;
  threads: CommentThread[];
  count: number;
  total: number;
  error?: string;
}

/**
 * Request to archive thread
 */
export interface ArchiveThreadRequest {
  threadId: string;
  archivedBy: CommentAuthor;
  reason?: string;
}

/**
 * Result of archiving thread
 */
export interface ArchiveThreadResult {
  success: boolean;
  thread?: CommentThread;
  error?: string;
}

/**
 * Service statistics
 */
export interface CommentThreadServiceStatistics {
  totalThreads: number;
  activeThreads: number;
  resolvedThreads: number;
  totalComments: number;
  averageCommentsPerThread: number;
  averageThreadResolutionTime: number;
  mostActiveReviews: string[];
  totalParticipants: number;
  threadsWithMentions: number;
  threadsWithReactions: number;
}

/**
 * Service interface
 */
export interface ICommentThreadService extends EventEmitter {
  createCommentThread(
    request: CreateCommentThreadRequest,
    ipAddress: string,
    userAgent: string
  ): CreateCommentThreadResult;

  addThreadComment(
    request: AddThreadCommentRequest,
    ipAddress: string,
    userAgent: string
  ): AddThreadCommentResult;

  editThreadComment(
    request: EditThreadCommentRequest,
    ipAddress: string,
    userAgent: string
  ): EditThreadCommentResult;

  deleteThreadComment(
    request: DeleteThreadCommentRequest,
    ipAddress: string,
    userAgent: string
  ): DeleteThreadCommentResult;

  resolveThread(
    request: ResolveThreadRequest,
    ipAddress: string,
    userAgent: string
  ): ResolveThreadResult;

  reopenThread(
    request: ReopenThreadRequest,
    ipAddress: string,
    userAgent: string
  ): ReopenThreadResult;

  addReaction(
    request: AddReactionRequest,
    ipAddress: string,
    userAgent: string
  ): AddReactionResult;

  mentionUser(
    request: MentionUserRequest,
    ipAddress: string,
    userAgent: string
  ): MentionUserResult;

  getCommentThread(request: GetThreadRequest): GetThreadResult;

  listCommentThreads(request: ListThreadsRequest): ListThreadsResult;

  archiveThread(
    request: ArchiveThreadRequest,
    ipAddress: string,
    userAgent: string
  ): ArchiveThreadResult;

  getStatistics(): CommentThreadServiceStatistics;

  updateConfig(
    config: Partial<CommentThreadConfig>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): void;

  shutdown(): void;
}
