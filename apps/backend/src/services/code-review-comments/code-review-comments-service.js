/**
 * Code Review Comment Threads Service
 * @file        apps/backend/src/services/code-review-comments/code-review-comments-service.ts
 * @module      services/code-review-comments
 * @description Threaded comment discussions on code reviews with resolution and notifications
 */
import { EventEmitter } from 'events';
/**
 * Code Review Comment Threads Service
 *
 * Manages threaded discussions on code reviews with:
 * - Comment threads on specific code locations
 * - Comment resolution and archival
 * - User mentions and notifications
 * - Emoji reactions
 * - Edit history and deletion tracking
 * - SOC2-compliant audit logging
 * - Real-time synchronization
 */
export class CodeReviewCommentsService extends EventEmitter {
    constructor() {
        super();
        this.threads = new Map();
        this.threadsByReview = new Map();
        this.commentNotifications = new Map();
        this.auditLogs = new Map();
        this.config = {
            maxThreadsPerReview: 500,
            maxCommentsPerThread: 200,
            maxCommentLength: 10000,
            enableThreadResolution: true,
            enableMentions: true,
            enableReactions: true,
            enableAttachments: true,
            enableApprovalRequests: true,
            autoArchiveResolvedThreadsAfterDays: 30,
            enableNotifications: true,
            maxAuditLogSize: 10000,
            retentionDays: 365,
        };
        this.initialize();
    }
    /**
     * Get or create service instance
     */
    static getInstance(config) {
        if (!CodeReviewCommentsService.instance) {
            CodeReviewCommentsService.instance = new CodeReviewCommentsService();
        }
        if (config) {
            CodeReviewCommentsService.instance.updateConfig(config, 'system', '127.0.0.1', 'node');
        }
        return CodeReviewCommentsService.instance;
    }
    /**
     * Reset instance for testing
     */
    static reset() {
        if (CodeReviewCommentsService.instance) {
            CodeReviewCommentsService.instance.shutdown();
        }
        CodeReviewCommentsService.instance = null;
    }
    /**
     * Initialize service
     */
    initialize() {
        this.emit('initialized', {
            data_object: { service: 'code-review-comments', status: 'initialized' },
            timestamp: Date.now(),
        });
    }
    /**
     * Create comment thread
     */
    createCommentThread(request, ipAddress, userAgent) {
        try {
            const threadId = `thread-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const thread = {
                id: threadId,
                reviewRequestId: request.reviewRequestId,
                createdBy: request.createdBy,
                createdAt: Date.now(),
                updatedAt: Date.now(),
                isResolved: false,
                location: request.location,
                title: request.title,
                comments: new Map(),
                participantIds: new Set([request.createdBy.userId]),
                reactionCounts: new Map(),
                isArchived: false,
                priority: request.priority || 'medium',
                tags: request.tags || [],
                relatedIssues: [],
            };
            // Add initial comment
            const commentId = `comment-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const comment = {
                id: commentId,
                threadId,
                author: request.createdBy,
                content: request.initialComment,
                createdAt: Date.now(),
                updatedAt: Date.now(),
                editHistory: [],
                reactionCounts: new Map(),
                mentionedUsers: request.mentionedUserIds || [],
                isDeleted: false,
            };
            thread.comments.set(commentId, comment);
            // Store thread
            this.threads.set(threadId, thread);
            if (!this.threadsByReview.has(request.reviewRequestId)) {
                this.threadsByReview.set(request.reviewRequestId, new Set());
            }
            this.threadsByReview.get(request.reviewRequestId).add(threadId);
            // Emit events
            this.emit('thread-created', {
                data_object: {
                    threadId,
                    reviewRequestId: request.reviewRequestId,
                    createdBy: request.createdBy.userId,
                },
                timestamp: Date.now(),
            });
            // Audit log
            this.logAudit(request.createdBy.userId, request.createdBy.userEmail, ipAddress, userAgent, 'thread-created', request.reviewRequestId, threadId, { location: request.location, priority: request.priority });
            return { success: true, threadId, thread };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Add comment to thread
     */
    addThreadComment(request, ipAddress, userAgent) {
        try {
            const thread = this.threads.get(request.threadId);
            if (!thread) {
                return { success: false, error: 'Thread not found' };
            }
            const commentId = `comment-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const comment = {
                id: commentId,
                threadId: request.threadId,
                author: request.author,
                content: request.content,
                createdAt: Date.now(),
                updatedAt: Date.now(),
                editHistory: [],
                reactionCounts: new Map(),
                mentionedUsers: request.mentionedUserIds || [],
                attachments: request.attachments,
                isDeleted: false,
            };
            thread.comments.set(commentId, comment);
            thread.participantIds.add(request.author.userId);
            thread.updatedAt = Date.now();
            this.emit('comment-added', {
                data_object: {
                    threadId: request.threadId,
                    commentId,
                    author: request.author.userId,
                    participantCount: thread.participantIds.size,
                },
                timestamp: Date.now(),
            });
            // Handle mentions
            if (request.mentionedUserIds && request.mentionedUserIds.length > 0) {
                this.emit('user-mentioned', {
                    data_object: {
                        threadId: request.threadId,
                        commentId,
                        mentionedCount: request.mentionedUserIds.length,
                    },
                    timestamp: Date.now(),
                });
            }
            // Audit log
            this.logAudit(request.author.userId, request.author.userEmail, ipAddress, userAgent, 'comment-added', thread.reviewRequestId, request.threadId, { commentId, mentionedCount: request.mentionedUserIds?.length || 0 });
            return {
                success: true,
                commentId,
                comment,
                broadcastedTo: thread.participantIds.size,
            };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Edit comment
     */
    editThreadComment(request, ipAddress, userAgent) {
        try {
            const thread = this.threads.get(request.threadId);
            if (!thread) {
                return { success: false, error: 'Thread not found' };
            }
            const comment = thread.comments.get(request.commentId);
            if (!comment) {
                return { success: false, error: 'Comment not found' };
            }
            // Store edit history
            comment.editHistory.push({
                editedAt: Date.now(),
                editedBy: request.editedBy,
                previousContent: comment.content,
            });
            comment.content = request.newContent;
            comment.updatedAt = Date.now();
            comment.editedBy = request.editedBy;
            this.emit('comment-edited', {
                data_object: {
                    threadId: request.threadId,
                    commentId: request.commentId,
                    editedBy: request.editedBy.userId,
                    editCount: comment.editHistory.length,
                },
                timestamp: Date.now(),
            });
            // Audit log
            this.logAudit(request.editedBy.userId, request.editedBy.userEmail, ipAddress, userAgent, 'comment-edited', thread.reviewRequestId, request.threadId, { commentId: request.commentId, editCount: comment.editHistory.length });
            return { success: true, comment };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Delete comment
     */
    deleteThreadComment(request, ipAddress, userAgent) {
        try {
            const thread = this.threads.get(request.threadId);
            if (!thread) {
                return { success: false, error: 'Thread not found' };
            }
            const comment = thread.comments.get(request.commentId);
            if (!comment) {
                return { success: false, error: 'Comment not found' };
            }
            comment.isDeleted = true;
            comment.deletedBy = request.deletedBy;
            comment.deletedAt = Date.now();
            thread.updatedAt = Date.now();
            this.emit('comment-deleted', {
                data_object: {
                    threadId: request.threadId,
                    commentId: request.commentId,
                    deletedBy: request.deletedBy.userId,
                },
                timestamp: Date.now(),
            });
            // Audit log
            this.logAudit(request.deletedBy.userId, request.deletedBy.userEmail, ipAddress, userAgent, 'comment-deleted', thread.reviewRequestId, request.threadId, { commentId: request.commentId, reason: request.reason });
            return { success: true, comment };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Resolve thread
     */
    resolveThread(request, ipAddress, userAgent) {
        try {
            const thread = this.threads.get(request.threadId);
            if (!thread) {
                return { success: false, error: 'Thread not found' };
            }
            thread.isResolved = true;
            thread.resolvedBy = request.resolvedBy;
            thread.resolvedAt = Date.now();
            thread.updatedAt = Date.now();
            this.emit('thread-resolved', {
                data_object: {
                    threadId: request.threadId,
                    resolvedBy: request.resolvedBy.userId,
                    commentCount: thread.comments.size,
                },
                timestamp: Date.now(),
            });
            // Audit log
            this.logAudit(request.resolvedBy.userId, request.resolvedBy.userEmail, ipAddress, userAgent, 'thread-resolved', thread.reviewRequestId, request.threadId, { commentCount: thread.comments.size });
            return { success: true, thread };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Reopen thread
     */
    reopenThread(request, ipAddress, userAgent) {
        try {
            const thread = this.threads.get(request.threadId);
            if (!thread) {
                return { success: false, error: 'Thread not found' };
            }
            thread.isResolved = false;
            thread.resolvedBy = undefined;
            thread.resolvedAt = undefined;
            thread.updatedAt = Date.now();
            this.emit('thread-reopened', {
                data_object: {
                    threadId: request.threadId,
                    reopenedBy: request.reopenedBy.userId,
                    reason: request.reason,
                },
                timestamp: Date.now(),
            });
            // Audit log
            this.logAudit(request.reopenedBy.userId, request.reopenedBy.userEmail, ipAddress, userAgent, 'thread-reopened', thread.reviewRequestId, request.threadId, { reason: request.reason });
            return { success: true, thread };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Add reaction to comment
     */
    addReaction(request, ipAddress, userAgent) {
        try {
            const thread = this.threads.get(request.threadId);
            if (!thread) {
                return { success: false, error: 'Thread not found' };
            }
            const comment = thread.comments.get(request.commentId);
            if (!comment) {
                return { success: false, error: 'Comment not found' };
            }
            const count = comment.reactionCounts.get(request.reactionType) || 0;
            comment.reactionCounts.set(request.reactionType, count + 1);
            thread.updatedAt = Date.now();
            this.emit('reaction-added', {
                data_object: {
                    threadId: request.threadId,
                    commentId: request.commentId,
                    reactionType: request.reactionType,
                    count: count + 1,
                },
                timestamp: Date.now(),
            });
            // Audit log
            this.logAudit(request.userId, request.userEmail, ipAddress, userAgent, 'reaction-added', thread.reviewRequestId, request.threadId, { commentId: request.commentId, reactionType: request.reactionType });
            return { success: true, reactionCounts: comment.reactionCounts };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Mention user in comment
     */
    mentionUser(request, ipAddress, userAgent) {
        try {
            const notification = {
                id: `notif-${Date.now()}-${Math.random().toString(16).slice(2)}`,
                userId: request.userId,
                userEmail: request.userEmail,
                type: 'user-mentioned',
                threadId: request.threadId,
                reviewRequestId: '',
                actor: {
                    userId: request.mentionerEmail.split('@')[0],
                    userEmail: request.mentionerEmail,
                    userName: request.mentionerEmail.split('@')[0],
                },
                message: request.message || `You were mentioned in a comment thread`,
                timestamp: Date.now(),
                isRead: false,
            };
            if (!this.commentNotifications.has(request.userId)) {
                this.commentNotifications.set(request.userId, []);
            }
            this.commentNotifications.get(request.userId).push(notification);
            this.emit('user-mentioned', {
                data_object: {
                    threadId: request.threadId,
                    mentionedUser: request.userId,
                    actor: request.mentionerEmail,
                },
                timestamp: Date.now(),
            });
            // Audit log
            this.logAudit(request.mentionerEmail.split('@')[0], request.mentionerEmail, ipAddress, userAgent, 'user-mentioned', '', request.threadId, { mentionedUser: request.userId, mentionedEmail: request.userEmail });
            return { success: true, notification };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Get comment thread
     */
    getCommentThread(request) {
        try {
            const thread = this.threads.get(request.threadId);
            if (!thread) {
                return { success: false, error: 'Thread not found' };
            }
            const comments = Array.from(thread.comments.values());
            const participantIds = Array.from(thread.participantIds);
            return {
                success: true,
                thread,
                comments,
                participants: participantIds.map((id) => ({
                    userId: id,
                    userEmail: `${id}@example.com`,
                    userName: id,
                })),
            };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * List comment threads
     */
    listCommentThreads(request) {
        try {
            const threadIds = this.threadsByReview.get(request.reviewRequestId) || new Set();
            let threads = Array.from(threadIds)
                .map((id) => this.threads.get(id))
                .filter((t) => t !== undefined);
            // Apply filters
            if (request.filter) {
                if (request.filter.resolved !== undefined) {
                    threads = threads.filter((t) => t.isResolved === request.filter.resolved);
                }
                if (request.filter.archived !== undefined) {
                    threads = threads.filter((t) => t.isArchived === request.filter.archived);
                }
                if (request.filter.priority && request.filter.priority.length > 0) {
                    threads = threads.filter((t) => request.filter.priority.includes(t.priority));
                }
                if (request.filter.tags && request.filter.tags.length > 0) {
                    threads = threads.filter((t) => t.tags.some((tag) => request.filter.tags.includes(tag)));
                }
            }
            // Apply pagination
            const offset = request.offset || 0;
            const limit = request.limit || 50;
            const paginatedThreads = threads.slice(offset, offset + limit);
            return {
                success: true,
                threads: paginatedThreads,
                count: paginatedThreads.length,
                total: threads.length,
            };
        }
        catch (error) {
            return { success: false, threads: [], count: 0, total: 0, error: error.message };
        }
    }
    /**
     * Archive thread
     */
    archiveThread(request, ipAddress, userAgent) {
        try {
            const thread = this.threads.get(request.threadId);
            if (!thread) {
                return { success: false, error: 'Thread not found' };
            }
            thread.isArchived = true;
            thread.archivedAt = Date.now();
            thread.updatedAt = Date.now();
            this.emit('thread-archived', {
                data_object: {
                    threadId: request.threadId,
                    archivedBy: request.archivedBy.userId,
                    commentCount: thread.comments.size,
                },
                timestamp: Date.now(),
            });
            // Audit log
            this.logAudit(request.archivedBy.userId, request.archivedBy.userEmail, ipAddress, userAgent, 'thread-archived', thread.reviewRequestId, request.threadId, { reason: request.reason, commentCount: thread.comments.size });
            return { success: true, thread };
        }
        catch (error) {
            return { success: false, error: error.message };
        }
    }
    /**
     * Get statistics
     */
    getStatistics() {
        const threads = Array.from(this.threads.values());
        const totalThreads = threads.length;
        const activeThreads = threads.filter((t) => !t.isResolved && !t.isArchived).length;
        const resolvedThreads = threads.filter((t) => t.isResolved).length;
        const totalComments = threads.reduce((sum, t) => sum + t.comments.size, 0);
        const averageCommentsPerThread = totalThreads > 0 ? totalComments / totalThreads : 0;
        const resolutionTimes = threads
            .filter((t) => t.resolvedAt && t.createdAt)
            .map((t) => (t.resolvedAt - t.createdAt) / 1000 / 60); // minutes
        const averageThreadResolutionTime = resolutionTimes.length > 0
            ? resolutionTimes.reduce((a, b) => a + b, 0) / resolutionTimes.length
            : 0;
        const threadsWithMentions = threads.filter((t) => Array.from(t.comments.values()).some((c) => c.mentionedUsers.length > 0)).length;
        const threadsWithReactions = threads.filter((t) => Array.from(t.comments.values()).some((c) => c.reactionCounts.size > 0)).length;
        const allParticipants = new Set();
        threads.forEach((t) => t.participantIds.forEach((id) => allParticipants.add(id)));
        return {
            totalThreads,
            activeThreads,
            resolvedThreads,
            totalComments,
            averageCommentsPerThread: Math.round(averageCommentsPerThread * 100) / 100,
            averageThreadResolutionTime: Math.round(averageThreadResolutionTime * 100) / 100,
            mostActiveReviews: Array.from(this.threadsByReview.entries())
                .sort((a, b) => b[1].size - a[1].size)
                .slice(0, 5)
                .map((e) => e[0]),
            totalParticipants: allParticipants.size,
            threadsWithMentions,
            threadsWithReactions,
        };
    }
    /**
     * Update configuration
     */
    updateConfig(config, userId, ipAddress, userAgent) {
        this.config = { ...this.config, ...config };
        this.emit('config-updated', {
            data_object: { userId, config },
            timestamp: Date.now(),
        });
        this.logAudit(userId, `${userId}@example.com`, ipAddress, userAgent, 'thread-created', '', '', {
            configUpdate: config,
        });
    }
    /**
     * Log audit entry
     */
    logAudit(userId, userEmail, ipAddress, userAgent, operation, reviewRequestId, threadId, details) {
        const entry = {
            timestamp: Date.now(),
            userId,
            userEmail,
            ipAddress,
            userAgent,
            operation,
            reviewRequestId,
            threadId,
            status: 'success',
            details: new Map(Object.entries(details)),
        };
        if (!this.auditLogs.has(userId)) {
            this.auditLogs.set(userId, []);
        }
        const logs = this.auditLogs.get(userId);
        logs.push(entry);
        if (logs.length > this.config.maxAuditLogSize) {
            logs.splice(0, logs.length - this.config.maxAuditLogSize);
        }
        this.emit('audit-logged', {
            data_object: { userId, operation, status: 'success' },
            timestamp: Date.now(),
        });
    }
    /**
     * Shutdown service
     */
    shutdown() {
        this.threads.clear();
        this.threadsByReview.clear();
        this.commentNotifications.clear();
        this.auditLogs.clear();
        this.emit('shutdown', {
            data_object: { service: 'code-review-comments', status: 'shutdown' },
            timestamp: Date.now(),
        });
        this.removeAllListeners();
    }
}
//# sourceMappingURL=code-review-comments-service.js.map