#!/usr/bin/env node
// @file        apps/backend/src/services/activity-stream/activity-stream-service.ts
// @module      collaboration/activity-stream/service
// @description ActivityStreamService for real-time activity aggregation and queryable event stream
// @owner       collab-6.2
// @status      active
import { EventEmitter } from 'events';
/**
 * ActivityStreamService
 *
 * Aggregates real-time activities from team members and provides queryable event stream.
 * Features:
 * - Real-time <100ms event ingestion
 * - Queryable activity history with filtering
 * - Smart subscriptions for personalized activity feeds
 * - Team metrics and trend analysis
 * - Activity deduplication and batching
 *
 * @example
 * ```typescript
 * const service = new ActivityStreamService();
 * await service.initialize();
 *
 * // Ingest activity
 * const activity: Activity = {
 *   activityId: 'activity-123',
 *   type: 'code_change',
 *   userId: 'user-456',
 *   userName: 'John',
 *   timestamp: new Date(),
 *   description: 'Pushed 3 commits',
 *   metadata: { branchName: 'feature/xyz', commitCount: 3 },
 * };
 * await service.ingestActivity(activity);
 *
 * // Query activities
 * const stream = await service.queryActivities({
 *   teamId: 'team-123',
 *   activityTypes: ['code_change', 'review'],
 *   startDate: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000), // Last 7 days
 * });
 *
 * // Subscribe to changes
 * const subscription = await service.subscribe('user-456', {
 *   teamId: 'team-123',
 *   activityTypes: ['code_change', 'review'],
 * });
 * ```
 */
export class ActivityStreamService extends EventEmitter {
    constructor(config) {
        super();
        this.activities = new Map();
        this.subscriptions = new Map();
        this.metrics = new Map();
        this.batchQueue = [];
        this.isInitialized = false;
        this.config = {
            enableRealTime: true,
            enableMetrics: true,
            enableRetention: true,
            retentionDays: 90,
            batchSize: 50,
            flushIntervalMs: 5000,
            maxCacheSize: 10000,
            enableDeduplication: true,
        };
        this.batchFlushTimer = null;
        this.deduplicationCache = new Set();
        this.config = { ...this.config, ...config };
    }
    /**
     * Initialize service
     */
    async initialize() {
        if (this.isInitialized)
            return;
        // Start batch flush interval
        if (this.config.flushIntervalMs) {
            this.batchFlushTimer = setInterval(() => {
                this.flushBatch().catch(console.error);
            }, this.config.flushIntervalMs);
        }
        this.isInitialized = true;
        this.emit('initialized');
    }
    /**
     * Shutdown service
     */
    async shutdown() {
        if (this.batchFlushTimer) {
            clearInterval(this.batchFlushTimer);
        }
        await this.flushBatch();
        this.activities.clear();
        this.subscriptions.clear();
        this.metrics.clear();
        this.deduplicationCache.clear();
        this.isInitialized = false;
    }
    /**
     * Ingest activity into the stream
     * @param activity Activity to ingest
     */
    async ingestActivity(activity) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        // Deduplication check
        if (this.config.enableDeduplication) {
            const activityHash = this.hashActivity(activity);
            if (this.deduplicationCache.has(activityHash)) {
                return; // Skip duplicate
            }
            this.deduplicationCache.add(activityHash);
        }
        // Add to batch queue
        this.batchQueue.push(activity);
        // Flush if batch is full
        if (this.batchQueue.length >= this.config.batchSize) {
            await this.flushBatch();
        }
        // Real-time event
        if (this.config.enableRealTime) {
            const event = {
                eventId: `event-${Date.now()}-${Math.random()}`,
                activity,
                timestamp: new Date(),
                subscriberCount: this.subscriptions.size,
            };
            this.emit('activity', event);
            this.notifySubscribers(activity);
        }
    }
    /**
     * Query activities with filters
     */
    async queryActivities(filter) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        let results = Array.from(this.activities.values());
        // Apply filters
        if (filter.userId) {
            results = results.filter((a) => a.userId === filter.userId);
        }
        if (filter.activityTypes && filter.activityTypes.length > 0) {
            results = results.filter((a) => filter.activityTypes.includes(a.type));
        }
        if (filter.startDate) {
            results = results.filter((a) => a.timestamp >= filter.startDate);
        }
        if (filter.endDate) {
            results = results.filter((a) => a.timestamp <= filter.endDate);
        }
        if (filter.priority && filter.priority.length > 0) {
            results = results.filter((a) => a.priority && filter.priority.includes(a.priority));
        }
        if (filter.tags && filter.tags.length > 0) {
            results = results.filter((a) => a.tags && a.tags.some((t) => filter.tags.includes(t)));
        }
        if (filter.searchText) {
            const searchLower = filter.searchText.toLowerCase();
            results = results.filter((a) => a.description.toLowerCase().includes(searchLower) ||
                a.userName.toLowerCase().includes(searchLower));
        }
        // Sort by timestamp descending
        results.sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime());
        // Pagination
        const limit = filter.limit || 50;
        const offset = filter.offset || 0;
        const paginatedResults = results.slice(offset, offset + limit);
        const hasMore = offset + limit < results.length;
        const cursor = hasMore ? Buffer.from(`${offset + limit}`).toString('base64') : undefined;
        return {
            streamId: `stream-${Date.now()}`,
            teamId: filter.teamId || 'default',
            activities: paginatedResults,
            totalCount: results.length,
            hasMore,
            cursor,
        };
    }
    /**
     * Subscribe to activity stream changes
     */
    async subscribe(userId, filter) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const subscription = {
            subscriptionId: `sub-${userId}-${Date.now()}`,
            userId,
            filter,
            createdAt: new Date(),
            isActive: true,
        };
        this.subscriptions.set(subscription.subscriptionId, subscription);
        this.emit('subscriptionCreated', subscription);
        return subscription;
    }
    /**
     * Unsubscribe from activity stream
     */
    async unsubscribe(subscriptionId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const subscription = this.subscriptions.get(subscriptionId);
        if (subscription) {
            subscription.isActive = false;
            this.subscriptions.delete(subscriptionId);
            this.emit('subscriptionDeleted', subscriptionId);
        }
    }
    /**
     * Get team activity metrics
     */
    async getTeamMetrics(teamId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const teamActivities = Array.from(this.activities.values()).filter((a) => a.metadata.teamId === teamId || !a.metadata.teamId);
        const metrics = {
            teamId,
            totalActivities: teamActivities.length,
            activitiesByType: {},
            activitiesByUser: {},
            hourlyActivities: {},
            dailyActivities: {},
            avgActivityLatency: 0,
            peakActivityHour: 0,
            mostActiveUser: '',
            mostCommonActivityType: 'code_change',
            lastActivityTime: new Date(),
        };
        // Calculate metrics
        let totalLatency = 0;
        const hourCounts = {};
        const dayCounts = {};
        teamActivities.forEach((activity) => {
            // By type
            if (!metrics.activitiesByType[activity.type]) {
                metrics.activitiesByType[activity.type] = 0;
            }
            metrics.activitiesByType[activity.type]++;
            // By user
            if (!metrics.activitiesByUser[activity.userId]) {
                metrics.activitiesByUser[activity.userId] = 0;
            }
            metrics.activitiesByUser[activity.userId]++;
            // Hourly
            const hour = new Date(activity.timestamp).getHours();
            hourCounts[hour] = (hourCounts[hour] || 0) + 1;
            // Daily
            const day = activity.timestamp.toISOString().split('T')[0];
            dayCounts[day] = (dayCounts[day] || 0) + 1;
            // Latency (simulated as 0 for in-memory)
            totalLatency += 0;
        });
        metrics.hourlyActivities = hourCounts;
        metrics.dailyActivities = dayCounts;
        metrics.avgActivityLatency = teamActivities.length > 0 ? totalLatency / teamActivities.length : 0;
        metrics.peakActivityHour = Object.entries(hourCounts).sort((a, b) => b[1] - a[1])[0]?.[0]
            ? parseInt(Object.entries(hourCounts).sort((a, b) => b[1] - a[1])[0][0])
            : 0;
        metrics.mostActiveUser = Object.entries(metrics.activitiesByUser).sort((a, b) => b[1] - a[1])[0]?.[0] || '';
        metrics.mostCommonActivityType =
            Object.entries(metrics.activitiesByType).sort((a, b) => b[1] - a[1])[0]?.[0] ||
                'code_change';
        this.metrics.set(teamId, metrics);
        return metrics;
    }
    /**
     * Get trend analysis for team
     */
    async analyzeTrend(teamId, period) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const teamActivities = Array.from(this.activities.values()).filter((a) => a.metadata.teamId === teamId || !a.metadata.teamId);
        const now = new Date();
        const periodMs = period === 'hour'
            ? 60 * 60 * 1000
            : period === 'day'
                ? 24 * 60 * 60 * 1000
                : period === 'week'
                    ? 7 * 24 * 60 * 60 * 1000
                    : 30 * 24 * 60 * 60 * 1000;
        const currentPeriodStart = new Date(now.getTime() - periodMs);
        const previousPeriodStart = new Date(currentPeriodStart.getTime() - periodMs);
        const currentActivities = teamActivities.filter((a) => a.timestamp >= currentPeriodStart && a.timestamp <= now);
        const previousActivities = teamActivities.filter((a) => a.timestamp >= previousPeriodStart && a.timestamp < currentPeriodStart);
        const currentCount = currentActivities.length;
        const previousCount = previousActivities.length;
        const changePercentage = previousCount > 0 ? ((currentCount - previousCount) / previousCount) * 100 : 0;
        // Trending analysis
        const typeDistribution = {};
        const userDistribution = {};
        currentActivities.forEach((a) => {
            typeDistribution[a.type] = (typeDistribution[a.type] || 0) + 1;
            userDistribution[a.userId] = (userDistribution[a.userId] || 0) + 1;
        });
        const trendingActivityTypes = Object.entries(typeDistribution)
            .sort((a, b) => b[1] - a[1])
            .slice(0, 3)
            .map(([type]) => type);
        const trendingUsers = Object.entries(userDistribution)
            .sort((a, b) => b[1] - a[1])
            .slice(0, 3)
            .map(([userId]) => userId);
        return {
            teamId,
            period,
            trend: changePercentage > 10 ? 'increasing' : changePercentage < -10 ? 'decreasing' : 'stable',
            changePercentage,
            previousPeriodTotal: previousCount,
            currentPeriodTotal: currentCount,
            trendingActivityTypes,
            trendingUsers,
        };
    }
    /**
     * Aggregate activities for a period
     */
    async aggregateActivities(teamId, startTime, endTime, period) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const teamActivities = Array.from(this.activities.values()).filter((a) => (a.metadata.teamId === teamId || !a.metadata.teamId) &&
            a.timestamp >= startTime &&
            a.timestamp <= endTime);
        const typeDistribution = {};
        const uniqueUsers = new Set();
        teamActivities.forEach((a) => {
            typeDistribution[a.type] = (typeDistribution[a.type] || 0) + 1;
            uniqueUsers.add(a.userId);
        });
        return {
            period,
            startTime,
            endTime,
            activities: teamActivities.sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime()),
            metrics: {
                totalCount: teamActivities.length,
                uniqueUsers: uniqueUsers.size,
                typeDistribution,
            },
        };
    }
    /**
     * Flush batch to persistent storage
     */
    async flushBatch() {
        if (this.batchQueue.length === 0)
            return;
        const batch = this.batchQueue.splice(0, this.config.batchSize);
        batch.forEach((activity) => {
            this.activities.set(activity.activityId, activity);
            // Enforce retention policy
            if (this.config.enableRetention && this.activities.size > this.config.maxCacheSize) {
                this.enforceRetention();
            }
        });
        this.emit('batchFlushed', batch.length);
    }
    /**
     * Enforce retention policy
     */
    enforceRetention() {
        const retentionMs = this.config.retentionDays * 24 * 60 * 60 * 1000;
        const cutoffTime = new Date(Date.now() - retentionMs);
        let removedCount = 0;
        this.activities.forEach((activity, id) => {
            if (activity.timestamp < cutoffTime) {
                this.activities.delete(id);
                removedCount++;
            }
        });
        if (removedCount > 0) {
            this.emit('retentionEnforced', removedCount);
        }
    }
    /**
     * Notify subscribers of new activity
     */
    notifySubscribers(activity) {
        this.subscriptions.forEach((subscription) => {
            if (!subscription.isActive)
                return;
            let matches = true;
            // Check filters
            if (subscription.filter.userId && subscription.filter.userId !== activity.userId) {
                matches = false;
            }
            if (subscription.filter.activityTypes &&
                subscription.filter.activityTypes.length > 0 &&
                !subscription.filter.activityTypes.includes(activity.type)) {
                matches = false;
            }
            if (subscription.filter.tags && subscription.filter.tags.length > 0) {
                if (!activity.tags || !activity.tags.some((t) => subscription.filter.tags.includes(t))) {
                    matches = false;
                }
            }
            if (matches) {
                subscription.lastNotifiedAt = new Date();
                this.emit('subscriptionNotification', { subscriptionId: subscription.subscriptionId, activity });
            }
        });
    }
    /**
     * Hash activity for deduplication
     */
    hashActivity(activity) {
        return `${activity.userId}-${activity.type}-${activity.timestamp.getTime()}`;
    }
}
//# sourceMappingURL=activity-stream-service.js.map