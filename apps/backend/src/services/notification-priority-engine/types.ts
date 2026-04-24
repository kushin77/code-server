#!/usr/bin/env node
// @file        apps/backend/src/services/notification-priority-engine/types.ts
// @module      collaboration/notification-priority-engine
// @description Type definitions for notification priority engine service
// @owner       collab-5.1
// @status      active

/**
 * Notification priority levels
 */
export type NotificationPriority = 'critical' | 'high' | 'medium' | 'low';

/**
 * Notification type categories
 */
export type NotificationType =
  | 'conflict_detected'
  | 'mention'
  | 'task_completed'
  | 'comment_reply'
  | 'file_changed'
  | 'presence_update'
  | 'system_alert';

/**
 * Notification delivery channel
 */
export type DeliveryChannel = 'in_app' | 'email' | 'push' | 'webhook';

/**
 * Notification with priority metadata
 */
export interface Notification {
  id: string;
  userId: string;
  type: NotificationType;
  title: string;
  message: string;
  metadata?: Record<string, unknown>;
  createdAt: Date;
  readAt?: Date;
  priority?: NotificationPriority;
}

/**
 * Notification with calculated priority
 */
export interface NotificationWithPriority extends Notification {
  priority: NotificationPriority;
  priorityScore: number; // 0-100
  scheduledFor: Date; // When to deliver
}

/**
 * Priority score calculation result
 */
export interface PriorityScore {
  score: number; // 0-100
  priority: NotificationPriority;
  factors: PriorityFactor[];
  confidence: number; // 0-100 confidence in score
}

/**
 * Individual priority scoring factor
 */
export interface PriorityFactor {
  name: string;
  value: number; // 0-100
  weight: number; // 0-1
  description: string;
}

/**
 * User's notification preferences
 */
export interface UserPriorityPreferences {
  userId: string;
  dndMode: boolean; // Do not disturb
  dndStartTime?: string; // HH:mm format
  dndEndTime?: string; // HH:mm format
  channelPreferences: {
    [K in DeliveryChannel]?: boolean;
  };
  typePreferences: {
    [K in NotificationType]?: {
      enabled: boolean;
      minPriority?: NotificationPriority;
      channels?: DeliveryChannel[];
    };
  };
  batchWindow?: number; // milliseconds
  maxNotificationsPerHour?: number;
}

/**
 * Priority calculation weights
 */
export interface PriorityWeights {
  notificationTypeWeight: number; // 0.3
  userPreferenceWeight: number; // 0.2
  contextFactorWeight: number; // 0.25
  temporalFactorWeight: number; // 0.15
  relationshipFactorWeight: number; // 0.1
}

/**
 * Delivery plan for a batch
 */
export interface DeliveryPlan {
  batchId: string;
  notifications: NotificationWithPriority[];
  scheduledFor: Date;
  channels: DeliveryChannel[];
  estimatedDeliveryTime: number; // milliseconds
}

/**
 * Queue metrics
 */
export interface QueueMetrics {
  totalNotifications: number;
  criticalCount: number;
  highCount: number;
  mediumCount: number;
  lowCount: number;
  averagePriorityScore: number;
  batchesQueued: number;
  averageBatchSize: number;
  oldestNotificationAge: number; // milliseconds
}

/**
 * Notification batch
 */
export interface NotificationBatch {
  id: string;
  userId: string;
  notifications: NotificationWithPriority[];
  createdAt: Date;
  deliveredAt?: Date;
  channel: DeliveryChannel;
  status: 'pending' | 'processing' | 'delivered' | 'failed';
}

/**
 * Collaboration context for priority calculation
 */
export interface CollaborationContext {
  userId: string;
  isInMeeting: boolean;
  lastActivityTime: Date;
  activeFileCount: number;
  teamSize: number;
  hasConflicts: boolean;
  taskProgress: number; // 0-100
}

/**
 * Throttle result
 */
export interface ThrottleResult {
  allowed: boolean;
  reason?: string;
  nextAvailableTime?: Date;
  remaining: number; // notifications remaining in quota
}
