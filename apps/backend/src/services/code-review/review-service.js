/**
 * @file        apps/backend/src/services/code-review/review-service.ts
 * @module      collaboration/code-review
 * @description Code review request management service
 */
import { EventEmitter } from 'events';
/**
 * CodeReviewService: Manage code review requests
 */
export class CodeReviewService extends EventEmitter {
    constructor() {
        super(...arguments);
        this.isInitialized = false;
        this.requests = new Map();
        this.responses = new Map();
        this.userContextMap = new Map();
    }
    /**
     * Initialize service
     */
    async initialize() {
        if (this.isInitialized)
            return;
        this.isInitialized = true;
        console.log('[CodeReviewService] Initialized');
        this.emit('initialized');
    }
    /**
     * Set user context
     */
    setUserContext(userId, email, name) {
        this.userContextMap.set(userId, { email, name });
    }
    /**
     * Create code review request
     */
    async createRequest(workspaceId, createdBy, title, description, targets, reviewerIds, priority = 'medium') {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const requestId = `review-${workspaceId}-${Date.now()}-${Math.random()
            .toString(16)
            .substring(2, 10)}`;
        const request = {
            id: requestId,
            createdAt: Date.now(),
            createdBy,
            workspaceId,
            title,
            description,
            targets,
            priority,
            requestedReviewersIds: reviewerIds,
            status: 'pending',
            reviewsCompleted: 0,
            reviewsRequired: reviewerIds.length,
            notificationsSent: false,
        };
        this.requests.set(requestId, request);
        console.log(`[CodeReviewService] Created review request ${requestId} with ${reviewerIds.length} reviewers`);
        this.emit('request-created', request);
        return requestId;
    }
    /**
     * Get review request
     */
    async getRequest(requestId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        return this.requests.get(requestId) || null;
    }
    /**
     * List pending requests for reviewer
     */
    async listPendingForReviewer(reviewerId, limit = 10) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const pending = Array.from(this.requests.values())
            .filter((req) => req.status === 'pending' &&
            req.requestedReviewersIds.includes(reviewerId))
            .sort((a, b) => {
            // Sort by priority: urgent > high > medium > low
            const priorityOrder = {
                urgent: 4,
                high: 3,
                medium: 2,
                low: 1,
            };
            return (priorityOrder[b.priority] - priorityOrder[a.priority] ||
                b.createdAt - a.createdAt);
        })
            .slice(0, limit);
        return pending;
    }
    /**
     * Submit review response
     */
    async submitReview(requestId, reviewerId, status, feedback) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const request = this.requests.get(requestId);
        if (!request)
            throw new Error(`Request ${requestId} not found`);
        const reviewId = `review-${requestId}-${reviewerId}-${Date.now()}`;
        const review = {
            id: reviewId,
            requestId,
            reviewerId,
            createdAt: Date.now(),
            status,
            feedback,
        };
        const existingReviews = this.responses.get(requestId) || [];
        existingReviews.push(review);
        this.responses.set(requestId, existingReviews);
        // Update request status
        request.reviewsCompleted++;
        if (status === 'approved') {
            // Mark reviewer as approved
            if (!request.reviewerBadges) {
                request.reviewerBadges = {};
            }
            if (request.reviewerBadges[reviewerId]) {
                request.reviewerBadges[reviewerId].approved = true;
            }
        }
        // Update overall status if all required reviews done
        if (status === 'approved' && request.reviewsCompleted >= request.reviewsRequired) {
            request.status = 'approved';
        }
        else if (status === 'requested-changes') {
            request.status = 'requested-changes';
        }
        console.log(`[CodeReviewService] Submitted ${status} review for ${requestId}`);
        this.emit('review-submitted', { requestId, reviewerId, status });
        return reviewId;
    }
    /**
     * Get reviews for request
     */
    async getReviews(requestId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        return this.responses.get(requestId) || [];
    }
    /**
     * Update review request
     */
    async updateRequest(requestId, updates) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const request = this.requests.get(requestId);
        if (!request)
            throw new Error(`Request ${requestId} not found`);
        Object.assign(request, updates);
        console.log(`[CodeReviewService] Updated review request ${requestId}`);
        this.emit('request-updated', request);
    }
    /**
     * Close review request
     */
    async closeRequest(requestId, reason) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const request = this.requests.get(requestId);
        if (!request)
            throw new Error(`Request ${requestId} not found`);
        request.status = 'closed';
        console.log(`[CodeReviewService] Closed review request ${requestId}`);
        this.emit('request-closed', { requestId, reason });
    }
    /**
     * Set reviewer badges
     */
    async setReviewerBadges(requestId, badges) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const request = this.requests.get(requestId);
        if (!request)
            throw new Error(`Request ${requestId} not found`);
        request.reviewerBadges = badges;
        console.log(`[CodeReviewService] Set reviewer badges for ${requestId}`);
        this.emit('badges-updated', { requestId, badges });
    }
    /**
     * Send review notifications
     */
    async sendNotifications(requestId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const request = this.requests.get(requestId);
        if (!request)
            throw new Error(`Request ${requestId} not found`);
        const sentTo = request.requestedReviewersIds.length;
        request.notificationsSent = true;
        console.log(`[CodeReviewService] Sent notifications for ${requestId} to ${sentTo} reviewers`);
        this.emit('notifications-sent', { requestId, count: sentTo });
        return sentTo;
    }
    /**
     * Get code review statistics
     */
    async getStatistics(workspaceId) {
        const allRequests = Array.from(this.requests.values()).filter((req) => req.workspaceId === workspaceId);
        const stats = {
            totalRequests: allRequests.length,
            pendingRequests: allRequests.filter((r) => r.status === 'pending').length,
            approvedRequests: allRequests.filter((r) => r.status === 'approved').length,
            requestedChangesRequests: allRequests.filter((r) => r.status === 'requested-changes').length,
            closedRequests: allRequests.filter((r) => r.status === 'closed').length,
            averageReviewTime: 0,
            averageReviewers: 0,
            approvalRate: 0,
            byPriority: {
                low: 0,
                medium: 0,
                high: 0,
                urgent: 0,
            },
            byReviewer: {},
        };
        // Calculate aggregates
        let totalReviewers = 0;
        let totalReviewTime = 0;
        let reviewCount = 0;
        for (const request of allRequests) {
            // Count by priority
            stats.byPriority[request.priority]++;
            // Count reviewers
            totalReviewers += request.requestedReviewersIds.length;
            // Count reviews
            const reviews = this.responses.get(request.id) || [];
            for (const review of reviews) {
                reviewCount++;
                if (review.reviewDuration) {
                    totalReviewTime += review.reviewDuration;
                }
                // Count by reviewer
                if (!stats.byReviewer[review.reviewerId]) {
                    stats.byReviewer[review.reviewerId] = {
                        completed: 0,
                        pending: 0,
                    };
                }
                stats.byReviewer[review.reviewerId].completed++;
            }
            // Count pending reviews per reviewer
            for (const reviewerId of request.requestedReviewersIds) {
                const hasReviewed = reviews.some((r) => r.reviewerId === reviewerId);
                if (!hasReviewed) {
                    if (!stats.byReviewer[reviewerId]) {
                        stats.byReviewer[reviewerId] = { completed: 0, pending: 0 };
                    }
                    stats.byReviewer[reviewerId].pending++;
                }
            }
        }
        if (allRequests.length > 0) {
            stats.averageReviewers =
                totalReviewers / allRequests.length;
            stats.approvalRate =
                (stats.approvedRequests / allRequests.length) * 100;
        }
        if (reviewCount > 0) {
            stats.averageReviewTime = totalReviewTime / reviewCount;
        }
        return stats;
    }
    /**
     * Get requests by priority
     */
    async getRequestsByPriority(workspaceId, priority) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        return Array.from(this.requests.values())
            .filter((req) => req.workspaceId === workspaceId && req.priority === priority)
            .sort((a, b) => b.createdAt - a.createdAt);
    }
    /**
     * Search requests
     */
    async searchRequests(workspaceId, query) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const lowerQuery = query.toLowerCase();
        return Array.from(this.requests.values())
            .filter((req) => req.workspaceId === workspaceId &&
            (req.title.toLowerCase().includes(lowerQuery) ||
                req.description.toLowerCase().includes(lowerQuery)))
            .sort((a, b) => b.createdAt - a.createdAt);
    }
}
/**
 * Global service instance
 */
let serviceInstance = null;
/**
 * Get global service instance
 */
export async function getCodeReviewService() {
    if (!serviceInstance) {
        serviceInstance = new CodeReviewService();
        await serviceInstance.initialize();
    }
    return serviceInstance;
}
//# sourceMappingURL=review-service.js.map