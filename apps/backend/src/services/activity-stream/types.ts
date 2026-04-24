#!/usr/bin/env node
// @file        apps/backend/src/services/activity-stream/types.ts
// @module      collaboration/activity-stream/types
// @description Type definitions for ActivityStreamService
// @owner       collab-6.2
// @status      active

/**
 * Enumeration of activity types
 */
export enum ActivityType {
  CODE_CHANGE = 'code_change',
  COLLABORATION = 'collaboration',
  DECISION = 'decision',
  SYSTEM_EVENT = 'system_event',
  COMMENT = 'comment',
  REVIEW = 'review',
  MERGE = 'merge',
  DEPLOYMENT = 'deployment',
  MEETING = 'meeting',
  MENTION = 'mention',
}

/**
 * Represents a single activity in the stream
 */
export interface Activity {
  activityId: string;
  type: ActivityType;
  userId: string;
  userName: string;
  timestamp: Date;
  description: string;
  metadata: Record<string, unknown>;
  relatedEntities?: RelatedEntity[];
  priority?: 'low' | 'medium' | 'high' | 'critical';
  tags?: string[];
}

/**
 * Represents related entities linked to an activity
 */
export interface RelatedEntity {
  type: 'file' | 'issue' | 'pr' | 'user' | 'team' | 'project';
  id: string;
  name: string;
  url?: string;
}

/**
 * Activity stream container with metadata
 */
export interface ActivityStream {
  streamId: string;
  teamId: string;
  activities: Activity[];
  totalCount: number;
  hasMore: boolean;
  cursor?: string;
}

/**
 * Filters for querying activities
 */
export interface ActivityFilter {
  userId?: string;
  teamId?: string;
  activityTypes?: ActivityType[];
  startDate?: Date;
  endDate?: Date;
  priority?: ('low' | 'medium' | 'high' | 'critical')[];
  tags?: string[];
  searchText?: string;
  limit?: number;
  offset?: number;
}

/**
 * Subscription to activity stream changes
 */
export interface Subscription {
  subscriptionId: string;
  userId: string;
  filter: ActivityFilter;
  createdAt: Date;
  isActive: boolean;
  lastNotifiedAt?: Date;
}

/**
 * Team activity metrics
 */
export interface TeamActivityMetrics {
  teamId: string;
  totalActivities: number;
  activitiesByType: Record<ActivityType, number>;
  activitiesByUser: Record<string, number>;
  hourlyActivities: Record<string, number>;
  dailyActivities: Record<string, number>;
  avgActivityLatency: number;
  peakActivityHour: number;
  mostActiveUser: string;
  mostCommonActivityType: ActivityType;
  lastActivityTime: Date;
}

/**
 * Real-time event emitted when activity occurs
 */
export interface ActivityEvent {
  eventId: string;
  activity: Activity;
  timestamp: Date;
  subscriberCount: number;
}

/**
 * Configuration options for ActivityStreamService
 */
export interface ActivityStreamConfig {
  enableRealTime?: boolean;
  enableMetrics?: boolean;
  enableRetention?: boolean;
  retentionDays?: number;
  batchSize?: number;
  flushIntervalMs?: number;
  maxCacheSize?: number;
  enableDeduplication?: boolean;
}

/**
 * Activity aggregation result
 */
export interface AggregationResult {
  period: 'hour' | 'day' | 'week' | 'month';
  startTime: Date;
  endTime: Date;
  activities: Activity[];
  metrics: {
    totalCount: number;
    uniqueUsers: number;
    typeDistribution: Record<ActivityType, number>;
  };
}

/**
 * Activity trend analysis
 */
export interface TrendAnalysis {
  teamId: string;
  period: 'hour' | 'day' | 'week' | 'month';
  trend: 'increasing' | 'decreasing' | 'stable';
  changePercentage: number;
  previousPeriodTotal: number;
  currentPeriodTotal: number;
  trendingActivityTypes: ActivityType[];
  trendingUsers: string[];
}
