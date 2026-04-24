/**
 * Activity Feed Service
 * @file        apps/backend/src/services/activity-feed/activity-feed-service.ts
 * @module      services/activity-feed
 * @description Real-time activity feed and engagement tracking
 */

import { EventEmitter } from 'events';
import {
  Activity,
  ActivityFeedEntry,
  ActivityFilter,
  ActivityTrend,
  UserActivityStats,
  ActivitySummary,
  ActivityAuditEntry,
  ActivityFeedConfig,
  IActivityFeedService,
  ActivityEngagement,
} from './types.js';

/**
 * Activity Feed Service
 * Manages activity recording, feed generation, and engagement tracking
 */
export class ActivityFeedService extends EventEmitter implements IActivityFeedService {
  private static instance: ActivityFeedService | undefined;
  private activities: Map<string, Activity> = new Map();
  private userActivities: Map<string, Set<string>> = new Map(); // userId -> activityIds
  private feedEntries: Map<string, ActivityFeedEntry> = new Map();
  private filters: Map<string, ActivityFilter> = new Map();
  private userFilters: Map<string, Set<string>> = new Map(); // userId -> filterIds
  private engagement: Map<string, ActivityEngagement> = new Map(); // activityId -> engagement
  private trends: Map<string, ActivityTrend> = new Map();
  private summaries: Map<string, ActivitySummary> = new Map();
  private auditLog: Map<string, ActivityAuditEntry[]> = new Map(); // userId -> entries
  private config: ActivityFeedConfig = {
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

  private constructor() {
    super();
    this.initialize();
  }

  /**
   * Get or create singleton instance
   */
  public static getInstance(config?: Partial<ActivityFeedConfig>): ActivityFeedService {
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
  public static reset(): void {
    ActivityFeedService.instance = undefined;
  }

  /**
   * Initialize service
   */
  private initialize(): void {
    this.emit('initialized', {
      data_object: { service: 'activity-feed', status: 'initialized' },
      timestamp: Date.now(),
    });
  }

  /**
   * Record activity
   */
  public recordActivity(
    activity: Omit<Activity, 'activityId' | 'timestamp' | 'engagement'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; activityId?: string } {
    try {
      if (!this.config.enableActivityFeed) {
        return { success: false };
      }

      const activityId = `activity-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const fullActivity: Activity = {
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
      this.userActivities.get(userId)!.add(activityId);

      this.logAudit(userId, 'record-activity', activityId, {
        type: activity.type,
        entityId: activity.entityId,
      });

      this.emit('activity-recorded', {
        data_object: { activityId, userId, type: activity.type },
        timestamp: Date.now(),
      });

      return { success: true, activityId };
    } catch (error) {
      this.logAudit(userId, 'record-activity', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get activity
   */
  public getActivity(activityId: string): Activity | undefined {
    return this.activities.get(activityId);
  }

  /**
   * Get user feed
   */
  public getUserFeed(userId: string, limit?: number): Activity[] {
    const activityIds = this.userActivities.get(userId) || new Set();
    const activities: Activity[] = [];

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
  public getActivityFeed(userId: string, filters?: Partial<ActivityFilter>): ActivityFeedEntry[] {
    const userActivities = this.getUserFeed(userId);
    const entries: ActivityFeedEntry[] = [];

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
        const entry: ActivityFeedEntry = {
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
  public createFilter(
    filter: Omit<ActivityFilter, 'filterId'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; filterId?: string } {
    try {
      const filterId = `filter-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const fullFilter: ActivityFilter = { ...filter, filterId };

      this.filters.set(filterId, fullFilter);

      if (!this.userFilters.has(userId)) {
        this.userFilters.set(userId, new Set());
      }
      this.userFilters.get(userId)!.add(filterId);

      this.logAudit(userId, 'create-filter', '', {
        filterId,
      });

      this.emit('filter-created', {
        data_object: { filterId, userId },
        timestamp: Date.now(),
      });

      return { success: true, filterId };
    } catch (error) {
      this.logAudit(userId, 'create-filter', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Update filter
   */
  public updateFilter(
    filterId: string,
    updates: Partial<ActivityFilter>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
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
    } catch (error) {
      this.logAudit(userId, 'update-filter', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Delete filter
   */
  public deleteFilter(
    filterId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
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
    } catch (error) {
      this.logAudit(userId, 'delete-filter', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get filters
   */
  public getFilters(userId: string): ActivityFilter[] {
    const filterIds = this.userFilters.get(userId) || new Set();
    const filters: ActivityFilter[] = [];

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
  public markAsRead(
    activityId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
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
    } catch (error) {
      this.logAudit(userId, 'mark-as-read', activityId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Mark entire feed as read
   */
  public markFeedAsRead(
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; readCount?: number } {
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
    } catch (error) {
      this.logAudit(userId, 'mark-feed-as-read', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Archive activity
   */
  public archiveActivity(
    activityId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
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
    } catch (error) {
      this.logAudit(userId, 'archive-activity', activityId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get engagement metrics
   */
  public getEngagementMetrics(activityId: string): ActivityEngagement | undefined {
    return this.engagement.get(activityId);
  }

  /**
   * Record engagement
   */
  public recordEngagement(
    activityId: string,
    engagementType: 'view' | 'like' | 'comment' | 'share',
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
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
    } catch (error) {
      this.logAudit(userId, 'record-engagement', activityId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get trends
   */
  public getTrends(period: 'daily' | 'weekly' | 'monthly'): ActivityTrend[] {
    return Array.from(this.trends.values()).filter((t) => t.period === period);
  }

  /**
   * Get user stats
   */
  public getUserStats(userId: string): UserActivityStats {
    const userActivityIds = this.userActivities.get(userId) || new Set();
    const userActivities: Activity[] = [];

    for (const id of userActivityIds) {
      const activity = this.activities.get(id);
      if (activity) {
        userActivities.push(activity);
      }
    }

    return {
      userId,
      totalActivities: userActivities.length,
      activitiesByType: {} as Record<string, number>,
      lastActivityAt: userActivities.length > 0 ? userActivities[0].timestamp : 0,
      engagementScore: 0,
      collaborationCount: userActivities.filter((a) => a.collaborators.length > 0).length,
    };
  }

  /**
   * Generate summary
   */
  public generateSummary(
    userId: string,
    period: 'daily' | 'weekly' | 'monthly',
    ipAddress: string,
    userAgent: string
  ): { success: boolean; summaryId?: string } {
    try {
      const summaryId = `summary-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const topActivities = this.getUserFeed(userId, 5);

      const summary: ActivitySummary = {
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
    } catch (error) {
      this.logAudit(userId, 'generate-summary', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get summary
   */
  public getSummary(summaryId: string): ActivitySummary | undefined {
    return this.summaries.get(summaryId);
  }

  /**
   * Get recent summaries
   */
  public getRecentSummaries(userId: string, limit?: number): ActivitySummary[] {
    const summaries = Array.from(this.summaries.values()).filter((s) => s.userId === userId);
    summaries.sort((a, b) => b.generatedAt - a.generatedAt);
    return summaries.slice(0, limit || 10);
  }

  /**
   * Batch record activities
   */
  public batchRecordActivities(
    activities: Array<Omit<Activity, 'activityId' | 'timestamp' | 'engagement'>>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; batchId?: string; recordedCount?: number } {
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
    } catch (error) {
      this.logAudit(userId, 'batch-record-activities', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get audit log
   */
  public getAuditLog(limit?: number): ActivityAuditEntry[] {
    const entries: ActivityAuditEntry[] = [];
    for (const [, userEntries] of this.auditLog) {
      entries.push(...userEntries);
    }
    entries.sort((a, b) => b.timestamp - a.timestamp);
    return entries.slice(0, limit || 100);
  }

  /**
   * Cleanup old activities
   */
  public cleanupOldActivities(
    daysOld: number,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; deletedCount?: number } {
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
    } catch (error) {
      this.logAudit(userId, 'cleanup-old-activities', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Log audit entry
   */
  private logAudit(userId: string, action: string, activityId: string, details?: Record<string, unknown>): void {
    if (!this.auditLog.has(userId)) {
      this.auditLog.set(userId, []);
    }

    const entry: ActivityAuditEntry = {
      timestamp: Date.now(),
      userId,
      userEmail: `user-${userId}@example.com`,
      action,
      activityId: activityId || undefined,
      details: details || {},
    };

    const logs = this.auditLog.get(userId)!;
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
  public updateConfig(config: Partial<ActivityFeedConfig>): void {
    this.config = { ...this.config, ...config };

    this.emit('config-updated', {
      data_object: { config: this.config },
      timestamp: Date.now(),
    });
  }

  /**
   * Shutdown service
   */
  public shutdown(): void {
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
