/**
 * Activity Feed Service
 * @file        apps/backend/src/services/activity-feed/activity-feed-service.ts
 * @module      services/activity-feed
 * @description Real-time activity feed and engagement tracking
 */
import { EventEmitter } from 'events';
/**
 * Activity Feed Service
 * Manages activity recording, feed generation, and engagement tracking
 */
export class ActivityFeedService extends EventEmitter {
    constructor() {
        super();
        this.activities = new Map();
        this.userActivities = new Map(); // userId -> activityIds
        this.feedEntries = new Map();
        this.filters = new Map();
        this.userFilters = new Map(); // userId -> filterIds
        this.engagement = new Map(); // activityId -> engagement
        this.trends = new Map();
        this.summaries = new Map();
        this.auditLog = new Map(); // userId -> entries
        this.config = {
            enableActivityFeed: true,
            maxActivitiesPerUser: 5000,
            maxFeedEntries: 1000,
            activityRetentionDays: 90,
            notificationEnabled: true,
            autoGenerateSummaries: true,
            summaryGenerationIntervalMs: 86400000, // 1 day
            trendDetectionEnabled: true,
            maxAuditEntries: 5000,
            engagementTrackingEnabled: true,
        };
        this.initialize();
    }
    /**
     * Get or create singleton instance
     */
    static getInstance(config) {
        if (!ActivityFeedService.instance) {
            ActivityFeedService.instance = new ActivityFeedService();
        }
        if (config) {
            ActivityFeedService.instance.updateConfig(config);
        }
        return ActivityFeedService.instance;
    }
    /**
     * Reset singleton for testing
     */
    static reset() {
        ActivityFeedService.instance = undefined;
    }
    /**
     * Initialize service
     */
    initialize() {
        this.emit('initialized', {
            data_object: { service: 'activity-feed', status: 'initialized' },
            timestamp: Date.now(),
        });
    }
    /**
     * Record activity
     */
    recordActivity(activity, userId, ipAddress, userAgent) {
        try {
            if (!this.config.enableActivityFeed) {
                return { success: false };
            }
            const activityId = `activity-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const fullActivity = {
                ...activity,
                activityId,
                timestamp: Date.now(),
                engagement: { viewCount: 0, likeCount: 0, commentCount: 0, shareCount: 0 },
            };
            this.activities.set(activityId, fullActivity);
            this.engagement.set(activityId, fullActivity.engagement);
            if (!this.userActivities.has(userId)) {
                this.userActivities.set(userId, new Set());
            }
            this.userActivities.get(userId).add(activityId);
            this.logAudit(userId, 'record-activity', activityId, {
                type: activity.type,
                entityId: activity.entityId,
            });
            this.emit('activity-recorded', {
                data_object: { activityId, userId, type: activity.type },
                timestamp: Date.now(),
            });
            return { success: true, activityId };
        }
        catch (error) {
            this.logAudit(userId, 'record-activity', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get activity
     */
    getActivity(activityId) {
        return this.activities.get(activityId);
    }
    /**
     * Get user feed
     */
    getUserFeed(userId, limit) {
        const activityIds = this.userActivities.get(userId) || new Set();
        const activities = [];
        for (const id of activityIds) {
            const activity = this.activities.get(id);
            if (activity) {
                activities.push(activity);
            }
        }
        activities.sort((a, b) => b.timestamp - a.timestamp);
        return activities.slice(0, limit || 50);
    }
    /**
     * Get activity feed with entries
     */
    getActivityFeed(userId, filters) {
        const userActivities = this.getUserFeed(userId);
        const entries = [];
        for (const activity of userActivities) {
            let matches = true;
            if (filters?.types && !filters.types.includes(activity.type)) {
                matches = false;
            }
            if (filters?.visibility && activity.visibility !== filters.visibility) {
                matches = false;
            }
            if (matches) {
                const entryId = `entry-${Date.now()}-${Math.random().toString(16).slice(2)}`;
                const entry = {
                    entryId,
                    userId,
                    activities: [activity],
                    createdAt: Date.now(),
                    read: false,
                    archived: false,
                };
                entries.push(entry);
                this.feedEntries.set(entryId, entry);
            }
        }
        return entries;
    }
    /**
     * Create filter
     */
    createFilter(filter, userId, ipAddress, userAgent) {
        try {
            const filterId = `filter-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const fullFilter = { ...filter, filterId };
            this.filters.set(filterId, fullFilter);
            if (!this.userFilters.has(userId)) {
                this.userFilters.set(userId, new Set());
            }
            this.userFilters.get(userId).add(filterId);
            this.logAudit(userId, 'create-filter', '', {
                filterId,
            });
            this.emit('filter-created', {
                data_object: { filterId, userId },
                timestamp: Date.now(),
            });
            return { success: true, filterId };
        }
        catch (error) {
            this.logAudit(userId, 'create-filter', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Update filter
     */
    updateFilter(filterId, updates, userId, ipAddress, userAgent) {
        try {
            const filter = this.filters.get(filterId);
            if (!filter) {
                return { success: false };
            }
            Object.assign(filter, updates);
            this.logAudit(userId, 'update-filter', '', {
                filterId,
            });
            this.emit('filter-updated', {
                data_object: { filterId, userId },
                timestamp: Date.now(),
            });
            return { success: true };
        }
        catch (error) {
            this.logAudit(userId, 'update-filter', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Delete filter
     */
    deleteFilter(filterId, userId, ipAddress, userAgent) {
        try {
            this.filters.delete(filterId);
            this.userFilters.get(userId)?.delete(filterId);
            this.logAudit(userId, 'delete-filter', '', {
                filterId,
            });
            this.emit('filter-deleted', {
                data_object: { filterId, userId },
                timestamp: Date.now(),
            });
            return { success: true };
        }
        catch (error) {
            this.logAudit(userId, 'delete-filter', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get filters
     */
    getFilters(userId) {
        const filterIds = this.userFilters.get(userId) || new Set();
        const filters = [];
        for (const id of filterIds) {
            const filter = this.filters.get(id);
            if (filter) {
                filters.push(filter);
            }
        }
        return filters;
    }
    /**
     * Mark activity as read
     */
    markAsRead(activityId, userId, ipAddress, userAgent) {
        try {
            const activity = this.activities.get(activityId);
            if (!activity) {
                return { success: false };
            }
            this.logAudit(userId, 'mark-as-read', activityId, {});
            this.emit('activity-read', {
                data_object: { activityId, userId },
                timestamp: Date.now(),
            });
            return { success: true };
        }
        catch (error) {
            this.logAudit(userId, 'mark-as-read', activityId, {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Mark entire feed as read
     */
    markFeedAsRead(userId, ipAddress, userAgent) {
        try {
            const entries = Array.from(this.feedEntries.values()).filter((e) => e.userId === userId && !e.read);
            for (const entry of entries) {
                entry.read = true;
            }
            this.logAudit(userId, 'mark-feed-as-read', '', {
                readCount: entries.length,
            });
            this.emit('feed-read', {
                data_object: { userId, readCount: entries.length },
                timestamp: Date.now(),
            });
            return { success: true, readCount: entries.length };
        }
        catch (error) {
            this.logAudit(userId, 'mark-feed-as-read', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Archive activity
     */
    archiveActivity(activityId, userId, ipAddress, userAgent) {
        try {
            const activity = this.activities.get(activityId);
            if (!activity) {
                return { success: false };
            }
            this.logAudit(userId, 'archive-activity', activityId, {});
            this.emit('activity-archived', {
                data_object: { activityId, userId },
                timestamp: Date.now(),
            });
            return { success: true };
        }
        catch (error) {
            this.logAudit(userId, 'archive-activity', activityId, {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get engagement metrics
     */
    getEngagementMetrics(activityId) {
        return this.engagement.get(activityId);
    }
    /**
     * Record engagement
     */
    recordEngagement(activityId, engagementType, userId, ipAddress, userAgent) {
        try {
            if (!this.config.engagementTrackingEnabled) {
                return { success: false };
            }
            const engagement = this.engagement.get(activityId);
            if (!engagement) {
                return { success: false };
            }
            switch (engagementType) {
                case 'view':
                    engagement.viewCount++;
                    break;
                case 'like':
                    engagement.likeCount++;
                    break;
                case 'comment':
                    engagement.commentCount++;
                    break;
                case 'share':
                    engagement.shareCount++;
                    break;
            }
            this.logAudit(userId, 'record-engagement', activityId, {
                engagementType,
            });
            this.emit('engagement-recorded', {
                data_object: { activityId, engagementType },
                timestamp: Date.now(),
            });
            return { success: true };
        }
        catch (error) {
            this.logAudit(userId, 'record-engagement', activityId, {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get trends
     */
    getTrends(period) {
        return Array.from(this.trends.values()).filter((t) => t.period === period);
    }
    /**
     * Get user stats
     */
    getUserStats(userId) {
        const userActivityIds = this.userActivities.get(userId) || new Set();
        const userActivities = [];
        for (const id of userActivityIds) {
            const activity = this.activities.get(id);
            if (activity) {
                userActivities.push(activity);
            }
        }
        return {
            userId,
            totalActivities: userActivities.length,
            activitiesByType: {},
            lastActivityAt: userActivities.length > 0 ? userActivities[0].timestamp : 0,
            engagementScore: 0,
            collaborationCount: userActivities.filter((a) => a.collaborators.length > 0).length,
        };
    }
    /**
     * Generate summary
     */
    generateSummary(userId, period, ipAddress, userAgent) {
        try {
            const summaryId = `summary-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const topActivities = this.getUserFeed(userId, 5);
            const summary = {
                summaryId,
                userId,
                period,
                totalActivities: topActivities.length,
                topActivities,
                topCollaborators: [],
                summaryText: `Activity summary for ${period}`,
                generatedAt: Date.now(),
            };
            this.summaries.set(summaryId, summary);
            this.logAudit(userId, 'generate-summary', '', {
                summaryId,
                period,
            });
            this.emit('summary-generated', {
                data_object: { summaryId, userId, period },
                timestamp: Date.now(),
            });
            return { success: true, summaryId };
        }
        catch (error) {
            this.logAudit(userId, 'generate-summary', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get summary
     */
    getSummary(summaryId) {
        return this.summaries.get(summaryId);
    }
    /**
     * Get recent summaries
     */
    getRecentSummaries(userId, limit) {
        const summaries = Array.from(this.summaries.values()).filter((s) => s.userId === userId);
        summaries.sort((a, b) => b.generatedAt - a.generatedAt);
        return summaries.slice(0, limit || 10);
    }
    /**
     * Batch record activities
     */
    batchRecordActivities(activities, userId, ipAddress, userAgent) {
        try {
            const batchId = `batch-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            let recordedCount = 0;
            for (const activity of activities) {
                const result = this.recordActivity(activity, userId, ipAddress, userAgent);
                if (result.success) {
                    recordedCount++;
                }
            }
            this.logAudit(userId, 'batch-record-activities', '', {
                batchId,
                recordedCount,
                totalCount: activities.length,
            });
            this.emit('batch-recorded', {
                data_object: { batchId, userId, recordedCount },
                timestamp: Date.now(),
            });
            return { success: true, batchId, recordedCount };
        }
        catch (error) {
            this.logAudit(userId, 'batch-record-activities', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get audit log
     */
    getAuditLog(limit) {
        const entries = [];
        for (const [, userEntries] of this.auditLog) {
            entries.push(...userEntries);
        }
        entries.sort((a, b) => b.timestamp - a.timestamp);
        return entries.slice(0, limit || 100);
    }
    /**
     * Cleanup old activities
     */
    cleanupOldActivities(daysOld, userId, ipAddress, userAgent) {
        try {
            const cutoffTime = Date.now() - daysOld * 86400000;
            let deletedCount = 0;
            for (const [id, activity] of this.activities) {
                if (activity.timestamp < cutoffTime) {
                    this.activities.delete(id);
                    this.userActivities.get(activity.userId)?.delete(id);
                    this.engagement.delete(id);
                    deletedCount++;
                }
            }
            this.logAudit(userId, 'cleanup-old-activities', '', {
                daysOld,
                deletedCount,
            });
            this.emit('cleanup-completed', {
                data_object: { userId, deletedCount },
                timestamp: Date.now(),
            });
            return { success: true, deletedCount };
        }
        catch (error) {
            this.logAudit(userId, 'cleanup-old-activities', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Log audit entry
     */
    logAudit(userId, action, activityId, details) {
        if (!this.auditLog.has(userId)) {
            this.auditLog.set(userId, []);
        }
        const entry = {
            timestamp: Date.now(),
            userId,
            userEmail: `user-${userId}@example.com`,
            action,
            activityId: activityId || undefined,
            details: details || {},
        };
        const logs = this.auditLog.get(userId);
        logs.push(entry);
        if (logs.length > this.config.maxAuditEntries) {
            logs.splice(0, logs.length - this.config.maxAuditEntries);
        }
        this.emit('audit-logged', {
            data_object: entry,
            timestamp: Date.now(),
        });
    }
    /**
     * Update configuration
     */
    updateConfig(config) {
        this.config = { ...this.config, ...config };
        this.emit('config-updated', {
            data_object: { config: this.config },
            timestamp: Date.now(),
        });
    }
    /**
     * Shutdown service
     */
    shutdown() {
        this.activities.clear();
        this.userActivities.clear();
        this.feedEntries.clear();
        this.filters.clear();
        this.userFilters.clear();
        this.engagement.clear();
        this.trends.clear();
        this.summaries.clear();
        this.auditLog.clear();
        this.emit('shutdown', {
            data_object: { service: 'activity-feed', status: 'shutdown' },
            timestamp: Date.now(),
        });
    }
}
//# sourceMappingURL=activity-feed-service.js.map