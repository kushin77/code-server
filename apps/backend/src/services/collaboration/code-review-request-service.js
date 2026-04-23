#!/usr/bin/env node
// @file        apps/backend/src/services/collaboration/code-review-request-service.ts
// @module      services/collaboration
// @description Service for managing code review requests with notifications and tracking
import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';
import { getTracer, withSpanSync } from '../../lib/tracing';
const logger = getLogger('CodeReviewRequestService');
const tracer = getTracer('collaboration/code-review');
/**
 * Code Review Request Service
 * Manages code review request lifecycle, notifications, and badges
 */
class CodeReviewRequestService extends EventEmitter {
    constructor() {
        super();
        this.requests = new Map();
        this.notifications = new Map();
        this.reviewerBadges = new Map();
        this.requestsByReviewer = new Map();
    }
    static getInstance() {
        if (!CodeReviewRequestService.instance) {
            CodeReviewRequestService.instance = new CodeReviewRequestService();
        }
        return CodeReviewRequestService.instance;
    }
    /**
     * Reset all state (for testing)
     */
    reset() {
        this.requests.clear();
        this.notifications.clear();
        this.reviewerBadges.clear();
        this.requestsByReviewer.clear();
    }
    /**
     * Create a new code review request
     */
    createRequest(requesterId, reviewerId, workspaceId, contextNote, priority = 'normal', filePath, dueAt) {
        return withSpanSync(tracer, 'collaboration.code-review.createRequest', {
            'requester.id': requesterId,
            'reviewer.id': reviewerId,
            'workspace.id': workspaceId,
            priority,
        }, () => {
            const requestId = `review-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
            const request = {
                id: requestId,
                requesterId,
                reviewerId,
                workspaceId,
                filePath,
                contextNote,
                priority,
                status: 'pending',
                createdAt: Date.now(),
                dueAt,
            };
            this.requests.set(requestId, request);
            // Add to reviewer's queue
            if (!this.requestsByReviewer.has(reviewerId)) {
                this.requestsByReviewer.set(reviewerId, []);
            }
            this.requestsByReviewer.get(reviewerId).push(requestId);
            // Create notification
            this.createNotification(requestId, reviewerId, 'review_requested');
            this.emit('reviewRequested', request);
            logger.info(`Code review requested: ${requestId} from ${requesterId} to ${reviewerId}`);
            return request;
        });
    }
    /**
     * Get a code review request
     */
    getRequest(requestId) {
        return this.requests.get(requestId);
    }
    /**
     * List pending requests for a reviewer
     */
    getPendingRequestsForReviewer(reviewerId) {
        const requestIds = this.requestsByReviewer.get(reviewerId) || [];
        return requestIds
            .map((id) => this.requests.get(id))
            .filter((r) => r && r.status === 'pending');
    }
    /**
     * List all requests from a requester
     */
    getRequestsByRequester(requesterId) {
        return Array.from(this.requests.values()).filter((r) => r.requesterId === requesterId);
    }
    /**
     * Respond to a review request
     */
    respondToRequest(requestId, reviewerId, status, comment) {
        return withSpanSync(tracer, 'collaboration.code-review.respondToRequest', {
            'request.id': requestId,
            'reviewer.id': reviewerId,
            status,
        }, () => {
            const request = this.requests.get(requestId);
            if (!request)
                return undefined;
            request.status = status;
            request.respondedAt = Date.now();
            request.response = {
                status,
                comment,
                timestamp: Date.now(),
                reviewerId,
            };
            // Update badge
            const badgeKey = `${request.reviewerId}-${status}`;
            const badge = this.reviewerBadges.get(badgeKey) || {
                type: status,
                count: 0,
                lastUpdated: Date.now(),
            };
            badge.count++;
            badge.lastUpdated = Date.now();
            this.reviewerBadges.set(badgeKey, badge);
            request.badge = badge;
            // Create notification for requester
            this.createNotification(requestId, request.requesterId, 'review_response');
            this.emit('reviewResponded', request);
            logger.info(`Code review response: ${requestId} with status ${status}`);
            return request;
        });
    }
    /**
     * Dismiss a review request
     */
    dismissRequest(requestId) {
        return withSpanSync(tracer, 'collaboration.code-review.dismissRequest', {
            'request.id': requestId,
        }, () => {
            const request = this.requests.get(requestId);
            if (!request)
                return undefined;
            request.status = 'dismissed';
            request.respondedAt = Date.now();
            this.emit('reviewDismissed', request);
            logger.info(`Code review dismissed: ${requestId}`);
            return request;
        });
    }
    /**
     * Set due date for a request
     */
    setDueDate(requestId, dueAt) {
        return withSpanSync(tracer, 'collaboration.code-review.setDueDate', {
            'request.id': requestId,
            'review.due_at': dueAt,
        }, () => {
            const request = this.requests.get(requestId);
            if (!request)
                return undefined;
            request.dueAt = dueAt;
            this.emit('dueDateSet', request);
            logger.info(`Due date set for review ${requestId}: ${new Date(dueAt).toISOString()}`);
            return request;
        });
    }
    /**
     * Check for overdue requests
     */
    getOverdueRequests() {
        const now = Date.now();
        return Array.from(this.requests.values()).filter((r) => r.status === 'pending' && r.dueAt && r.dueAt < now);
    }
    /**
     * Send reminder for pending request
     */
    sendReminder(requestId) {
        return withSpanSync(tracer, 'collaboration.code-review.sendReminder', {
            'request.id': requestId,
        }, () => {
            const request = this.requests.get(requestId);
            if (!request || request.status !== 'pending')
                return undefined;
            this.createNotification(requestId, request.reviewerId, 'review_reminder');
            this.emit('reminderSent', request);
            logger.info(`Reminder sent for review ${requestId}`);
            return request;
        });
    }
    /**
     * Create notification
     */
    createNotification(requestId, recipientId, type) {
        const notificationId = `notif-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
        const notification = {
            id: notificationId,
            requestId,
            recipientId,
            type,
            read: false,
            createdAt: Date.now(),
        };
        this.notifications.set(notificationId, notification);
        this.emit('notificationCreated', notification);
        logger.info(`Notification created: ${notificationId} for ${recipientId}`);
        return notification;
    }
    /**
     * Get notifications for a user
     */
    getNotificationsForUser(userId) {
        return Array.from(this.notifications.values()).filter((n) => n.recipientId === userId);
    }
    /**
     * Mark notification as read
     */
    markNotificationAsRead(notificationId) {
        return withSpanSync(tracer, 'collaboration.code-review.markNotificationAsRead', {
            'notification.id': notificationId,
        }, () => {
            const notification = this.notifications.get(notificationId);
            if (!notification)
                return undefined;
            notification.read = true;
            this.emit('notificationRead', notification);
            logger.info(`Notification marked as read: ${notificationId}`);
            return notification;
        });
    }
    /**
     * Get unread notification count for a user
     */
    getUnreadNotificationCount(userId) {
        return Array.from(this.notifications.values()).filter((n) => n.recipientId === userId && !n.read).length;
    }
    /**
     * Get reviewer badges
     */
    getReviewerBadges(reviewerId) {
        const badges = [];
        this.reviewerBadges.forEach((badge, key) => {
            if (key.startsWith(reviewerId)) {
                badges.push(badge);
            }
        });
        return badges;
    }
    /**
     * Get review statistics for a reviewer
     */
    getReviewerStats(reviewerId) {
        const requests = this.getPendingRequestsForReviewer(reviewerId);
        const allRequests = (this.requestsByReviewer.get(reviewerId) || []).map((id) => this.requests.get(id));
        const responded = allRequests.filter((r) => r && r.respondedAt);
        const responseTimes = responded
            .filter((r) => r && r.respondedAt)
            .map((r) => r.respondedAt - r.createdAt);
        const avgResponseTime = responseTimes.length > 0 ? responseTimes.reduce((a, b) => a + b) / responseTimes.length : 0;
        const approvedCount = responded.filter((r) => r && r.status === 'approved').length;
        const changesRequestedCount = responded.filter((r) => r && r.status === 'requested_changes').length;
        const commentedCount = responded.filter((r) => r && r.status === 'commented').length;
        return {
            totalRequests: allRequests.length,
            approvedCount,
            changesRequestedCount,
            commentedCount,
            averageResponseTime: avgResponseTime,
            pendingCount: requests.length,
        };
    }
    /**
     * Expire old requests (older than 30 days)
     */
    expireOldRequests(maxAgeMs = 30 * 24 * 60 * 60 * 1000) {
        return withSpanSync(tracer, 'collaboration.code-review.expireOldRequests', {
            'review.max_age_ms': maxAgeMs,
        }, () => {
            const now = Date.now();
            const expired = [];
            this.requests.forEach((request) => {
                if (request.status === 'pending' && now - request.createdAt > maxAgeMs) {
                    request.status = 'expired';
                    expired.push(request);
                    this.emit('requestExpired', request);
                }
            });
            logger.info(`Expired ${expired.length} old review requests`);
            return expired;
        });
    }
    /**
     * Get all requests for a workspace
     */
    getRequestsByWorkspace(workspaceId) {
        return Array.from(this.requests.values()).filter((r) => r.workspaceId === workspaceId);
    }
    /**
     * Get request statistics for workspace
     */
    getWorkspaceStats(workspaceId) {
        const requests = this.getRequestsByWorkspace(workspaceId);
        const pending = requests.filter((r) => r.status === 'pending');
        const responded = requests.filter((r) => r.respondedAt);
        const responseTimes = responded.map((r) => r.respondedAt - r.createdAt);
        const avgResponseTime = responseTimes.length > 0 ? responseTimes.reduce((a, b) => a + b) / responseTimes.length : 0;
        const approvedCount = responded.filter((r) => r.status === 'approved').length;
        const highPriorityPending = pending.filter((r) => r.priority === 'high' || r.priority === 'critical').length;
        return {
            totalRequests: requests.length,
            pendingRequests: pending.length,
            approvedCount,
            averageResponseTime: avgResponseTime,
            highPriorityPending,
        };
    }
}
const instance = new CodeReviewRequestService();
export default instance;
export { CodeReviewRequestService };
//# sourceMappingURL=code-review-request-service.js.map