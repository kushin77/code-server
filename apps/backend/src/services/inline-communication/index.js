/**
 * @file        apps/backend/src/services/inline-communication/index.ts
 * @module      collaboration/inline-communication
 * @description GitHub PR-style inline comment threads on live source code
 * @owner       Collaboration Team
 * @status      Production - April 23, 2026
 *
 * Features:
 * - Thread-per-function architecture
 * - Persistent across code refactors
 * - Real-time sync with CRDT
 * - Thread resolution tracking
 * - Markdown support with code blocks
 * - Mentions and notifications
 */
import { EventEmitter } from 'events';
/**
 * Inline Communication Service
 * Manages GitHub PR-style comment threads on live code
 */
export class InlineCommunicationService extends EventEmitter {
    constructor() {
        super();
        this.threads = new Map();
        this.threadsByLocation = new Map();
        this.threadArchive = [];
    }
    static getInstance() {
        if (!InlineCommunicationService.instance) {
            InlineCommunicationService.instance = new InlineCommunicationService();
        }
        return InlineCommunicationService.instance;
    }
    /**
     * Create a new comment thread at a code location
     */
    createThread(codeLocation, sessionId, authorId, authorName, initialComment) {
        const threadId = `thread_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
        const locationKey = this.getLocationKey(codeLocation);
        const comment = {
            id: `comment_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
            threadId,
            authorId,
            authorName,
            content: initialComment,
            createdAt: new Date(),
            resolved: false,
            mentions: this.extractMentions(initialComment),
        };
        const thread = {
            id: threadId,
            codeLocation,
            sessionId,
            createdBy: authorId,
            createdAt: new Date(),
            updatedAt: new Date(),
            comments: [comment],
            resolved: false,
            status: 'active',
        };
        this.threads.set(threadId, thread);
        // Index by location
        if (!this.threadsByLocation.has(locationKey)) {
            this.threadsByLocation.set(locationKey, new Set());
        }
        this.threadsByLocation.get(locationKey).add(threadId);
        this.emit('thread-created', thread);
        return thread;
    }
    /**
     * Add comment to existing thread
     */
    addComment(threadId, authorId, authorName, content) {
        const thread = this.threads.get(threadId);
        if (!thread)
            return null;
        const comment = {
            id: `comment_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
            threadId,
            authorId,
            authorName,
            content,
            createdAt: new Date(),
            resolved: false,
            mentions: this.extractMentions(content),
        };
        thread.comments.push(comment);
        thread.updatedAt = new Date();
        this.emit('comment-added', { threadId, comment });
        return comment;
    }
    /**
     * Resolve a thread (mark as done/handled)
     */
    resolveThread(threadId, resolvedBy) {
        const thread = this.threads.get(threadId);
        if (!thread)
            return null;
        thread.resolved = true;
        thread.resolvedBy = resolvedBy;
        thread.resolvedAt = new Date();
        thread.status = 'resolved';
        thread.updatedAt = new Date();
        // Archive thread
        this.threadArchive.push({
            threadId,
            codeLocation: thread.codeLocation,
            commentCount: thread.comments.length,
            duration: thread.resolvedAt.getTime() - thread.createdAt.getTime(),
            resolvedBy,
            resolvedAt: thread.resolvedAt,
        });
        this.emit('thread-resolved', thread);
        return thread;
    }
    /**
     * Unresolve a thread (reopen for discussion)
     */
    unresolveThread(threadId) {
        const thread = this.threads.get(threadId);
        if (!thread)
            return null;
        thread.resolved = false;
        thread.resolvedBy = undefined;
        thread.resolvedAt = undefined;
        thread.status = 'active';
        thread.updatedAt = new Date();
        this.emit('thread-unresolved', thread);
        return thread;
    }
    /**
     * Update comment content (edit)
     */
    updateComment(threadId, commentId, newContent) {
        const thread = this.threads.get(threadId);
        if (!thread)
            return null;
        const comment = thread.comments.find((c) => c.id === commentId);
        if (!comment)
            return null;
        comment.content = newContent;
        comment.updatedAt = new Date();
        comment.mentions = this.extractMentions(newContent);
        thread.updatedAt = new Date();
        this.emit('comment-updated', { threadId, comment });
        return comment;
    }
    /**
     * Get threads for a specific code location
     */
    getThreadsForLocation(codeLocation) {
        const locationKey = this.getLocationKey(codeLocation);
        const threadIds = this.threadsByLocation.get(locationKey) || new Set();
        return Array.from(threadIds).map((id) => this.threads.get(id));
    }
    /**
     * Get all active threads in a file
     */
    getThreadsInFile(filePath) {
        return Array.from(this.threads.values()).filter((t) => t.codeLocation.filePath === filePath && t.status === 'active');
    }
    /**
     * Get all threads (active and resolved)
     */
    getAllThreads() {
        return Array.from(this.threads.values());
    }
    /**
     * Get thread by ID
     */
    getThread(threadId) {
        return this.threads.get(threadId) || null;
    }
    /**
     * Get thread statistics
     */
    getThreadStatistics() {
        const threads = Array.from(this.threads.values());
        const activeThreads = threads.filter((t) => t.status === 'active');
        const resolvedThreads = threads.filter((t) => t.status === 'resolved');
        const averageCommentCount = threads.length > 0 ? threads.reduce((sum, t) => sum + t.comments.length, 0) / threads.length : 0;
        const averageResolutionTime = resolvedThreads.length > 0
            ? resolvedThreads.reduce((sum, t) => sum + (t.resolvedAt.getTime() - t.createdAt.getTime()), 0) /
                resolvedThreads.length
            : 0;
        return {
            total: threads.length,
            active: activeThreads.length,
            resolved: resolvedThreads.length,
            archived: this.threadArchive.length,
            averageCommentCount,
            averageResolutionTime,
        };
    }
    /**
     * Get user statistics
     */
    getUserStatistics(userId) {
        const threads = Array.from(this.threads.values());
        const threadsCreated = threads.filter((t) => t.createdBy === userId).length;
        const threadsResolved = threads.filter((t) => t.resolvedBy === userId).length;
        let commentsAdded = 0;
        let mentions = 0;
        threads.forEach((thread) => {
            thread.comments.forEach((comment) => {
                if (comment.authorId === userId)
                    commentsAdded++;
                if (comment.mentions.includes(userId))
                    mentions++;
            });
        });
        return {
            threadsCreated,
            commentsAdded,
            threadsResolved,
            mentions,
        };
    }
    /**
     * Search threads by content
     */
    searchThreads(query) {
        const lowerQuery = query.toLowerCase();
        return Array.from(this.threads.values()).filter((thread) => thread.comments.some((comment) => comment.content.toLowerCase().includes(lowerQuery)));
    }
    /**
     * Handle code refactor - update thread locations
     */
    handleCodeRefactor(oldLocation, newLocation) {
        const locationKey = this.getLocationKey(oldLocation);
        const threadIds = this.threadsByLocation.get(locationKey);
        if (!threadIds)
            return 0;
        let updatedCount = 0;
        threadIds.forEach((threadId) => {
            const thread = this.threads.get(threadId);
            if (thread) {
                thread.codeLocation = newLocation;
                updatedCount++;
            }
        });
        // Re-index
        this.threadsByLocation.delete(locationKey);
        const newLocationKey = this.getLocationKey(newLocation);
        this.threadsByLocation.set(newLocationKey, threadIds);
        this.emit('threads-relocated', { oldLocation, newLocation, count: updatedCount });
        return updatedCount;
    }
    /**
     * Export threads for persistence
     */
    exportThreads() {
        return Array.from(this.threads.values());
    }
    /**
     * Import threads from persistence
     */
    importThreads(threads) {
        threads.forEach((thread) => {
            this.threads.set(thread.id, thread);
            const locationKey = this.getLocationKey(thread.codeLocation);
            if (!this.threadsByLocation.has(locationKey)) {
                this.threadsByLocation.set(locationKey, new Set());
            }
            this.threadsByLocation.get(locationKey).add(thread.id);
        });
        return threads.length;
    }
    /**
     * Clear all threads (for testing)
     */
    clearAllThreads() {
        this.threads.clear();
        this.threadsByLocation.clear();
        this.threadArchive = [];
    }
    /**
     * Helper: Generate location key for indexing
     */
    getLocationKey(location) {
        return `${location.filePath}:${location.startLine}-${location.endLine}:${location.functionName || 'global'}`;
    }
    /**
     * Helper: Extract mentions from comment text
     */
    extractMentions(content) {
        const mentionRegex = /@([\w\-]+)/g;
        const matches = content.match(mentionRegex) || [];
        return matches.map((m) => m.substring(1)); // Remove @ prefix
    }
}
export default InlineCommunicationService;
//# sourceMappingURL=index.js.map