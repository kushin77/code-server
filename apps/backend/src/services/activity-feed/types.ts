/**
 * Real-time Activity Feed Service Types
 * @file        apps/backend/src/services/activity-feed/types.ts
 * @module      services/activity-feed
 * @description Type definitions for activity feed functionality
 */

/**
 * Activity type classification
 */
export type ActivityType = 'file_modified' | 'file_created' | 'file_deleted' | 'comment_added' | 'collaboration' | 'permission_change' | 'status_update' | 'share';

/**
 * Activity visibility level
 */
export type ActivityVisibility = 'public' | 'team' | 'private' | 'restricted';

/**
 * Activity engagement metric
 */
export interface ActivityEngagement {
  viewCount: number;
  likeCount: number;
  commentCount: number;
  shareCount: number;
}

/**
 * Basic activity metadata
 */
export interface ActivityMetadata {
  activityId: string;
  userId: string;
  userEmail: string;
  timestamp: number;
  type: ActivityType;
  entityId: string;
  entityType: 'file' | 'workspace' | 'comment' | 'project';
  visibility: ActivityVisibility;
}

/**
 * Detailed activity information
 */
export interface Activity extends ActivityMetadata {
  title: string;
  description: string;
  changes?: Record<string, { old: unknown; new: unknown }>;
  tags: string[];
  collaborators: string[];
  metadata: Record<string, unknown>;
  engagement: ActivityEngagement;
  relatedActivities?: string[];
}

/**
 * Activity feed entry
 */
export interface ActivityFeedEntry {
  entryId: string;
  userId: string;
  activities: Activity[];
  createdAt: number;
  read: boolean;
  archived: boolean;
}

/**
 * Activity filter configuration
 */
export interface ActivityFilter {
  filterId: string;
  userId: string;
  types?: ActivityType[];
  visibility?: ActivityVisibility;
  entityTypes?: string[];
  timeRangeMs?: number;
  collaboratorsFilter?: string[];
  enabled: boolean;
}

/**
 * Activity notification
 */
export interface ActivityNotification {
  notificationId: string;
  userId: string;
  activity: Activity;
  sentAt: number;
  readAt?: number;
  deliveryChannels: string[];
}

/**
 * Activity trend data
 */
export interface ActivityTrend {
  trendId: string;
  period: 'daily' | 'weekly' | 'monthly';
  activityType: ActivityType;
  count: number;
  trending: boolean;
  trendScore: number;
}

/**
 * User activity statistics
 */
export interface UserActivityStats {
  userId: string;
  totalActivities: number;
  activitiesByType: Record<ActivityType, number>;
  lastActivityAt: number;
  engagementScore: number;
  collaborationCount: number;
}

/**
 * Activity summary
 */
export interface ActivitySummary {
  summaryId: string;
  userId: string;
  period: 'daily' | 'weekly' | 'monthly';
  totalActivities: number;
  topActivities: Activity[];
  topCollaborators: Array<{ userId: string; interactionCount: number }>;
  summaryText: string;
  generatedAt: number;
}

/**
 * Activity batch operation
 */
export interface ActivityBatch {
  batchId: string;
  userId: string;
  activities: Activity[];
  createdAt: number;
  processedAt?: number;
  status: 'pending' | 'processed' | 'failed';
}

/**
 * Activity audit entry
 */
export interface ActivityAuditEntry {
  timestamp: number;
  userId: string;
  userEmail: string;
  action: string;
  activityId?: string;
  details: Record<string, unknown>;
}

/**
 * Service configuration
 */
export interface ActivityFeedConfig {
  enableActivityFeed: boolean;
  maxActivitiesPerUser: number;
  maxFeedEntries: number;
  activityRetentionDays: number;
  notificationEnabled: boolean;
  autoGenerateSummaries: boolean;
  summaryGenerationIntervalMs: number;
  trendDetectionEnabled: boolean;
  maxAuditEntries: number;
  engagementTrackingEnabled: boolean;
}

/**
 * Activity feed service interface
 */
export interface IActivityFeedService {
  recordActivity(
    activity: Omit<Activity, 'activityId' | 'timestamp' | 'engagement'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; activityId?: string };

  getActivity(activityId: string): Activity | undefined;

  getUserFeed(userId: string, limit?: number): Activity[];

  getActivityFeed(userId: string, filters?: Partial<ActivityFilter>): ActivityFeedEntry[];

  createFilter(
    filter: Omit<ActivityFilter, 'filterId'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; filterId?: string };

  updateFilter(
    filterId: string,
    updates: Partial<ActivityFilter>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  deleteFilter(
    filterId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  getFilters(userId: string): ActivityFilter[];

  markAsRead(
    activityId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  markFeedAsRead(
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; readCount?: number };

  archiveActivity(
    activityId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  getEngagementMetrics(activityId: string): ActivityEngagement | undefined;

  recordEngagement(
    activityId: string,
    engagementType: 'view' | 'like' | 'comment' | 'share',
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  getTrends(period: 'daily' | 'weekly' | 'monthly'): ActivityTrend[];

  getUserStats(userId: string): UserActivityStats;

  generateSummary(
    userId: string,
    period: 'daily' | 'weekly' | 'monthly',
    ipAddress: string,
    userAgent: string
  ): { success: boolean; summaryId?: string };

  getSummary(summaryId: string): ActivitySummary | undefined;

  getRecentSummaries(userId: string, limit?: number): ActivitySummary[];

  batchRecordActivities(
    activities: Array<Omit<Activity, 'activityId' | 'timestamp' | 'engagement'>>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; batchId?: string; recordedCount?: number };

  getAuditLog(limit?: number): ActivityAuditEntry[];

  cleanupOldActivities(
    daysOld: number,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; deletedCount?: number };

  updateConfig(config: Partial<ActivityFeedConfig>): void;

  shutdown(): void;
}
