/**
 * Notification Aggregator Service Types
 * @file        apps/backend/src/services/notification-aggregator/types.ts
 * @module      services/notification-aggregator
 * @description Type definitions for notification aggregation
 */

/**
 * Notification priority levels
 */
export type NotificationPriority = 'critical' | 'high' | 'medium' | 'low';

/**
 * Notification status
 */
export type NotificationStatus = 'pending' | 'sent' | 'delivered' | 'read' | 'archived' | 'failed';

/**
 * Notification channel
 */
export type NotificationChannel = 'email' | 'in-app' | 'websocket' | 'sms' | 'slack' | 'webhook';

/**
 * Notification category
 */
export type NotificationCategory = 'alert' | 'info' | 'warning' | 'error' | 'success' | 'collaboration';

/**
 * Notification aggregation strategy
 */
export type AggregationStrategy = 'none' | 'time-based' | 'count-based' | 'priority-based';

/**
 * Basic notification metadata
 */
export interface NotificationMetadata {
  notificationId: string;
  userId: string;
  title: string;
  message: string;
  priority: NotificationPriority;
  category: NotificationCategory;
  status: NotificationStatus;
  createdAt: number;
  deliveredAt?: number;
  readAt?: number;
  archivedAt?: number;
  failureReason?: string;
}

/**
 * Notification with channel and destination info
 */
export interface Notification extends NotificationMetadata {
  channel: NotificationChannel;
  destination: string;
  actionUrl?: string;
  actionLabel?: string;
  tags: string[];
  retryCount: number;
  maxRetries: number;
  aggregated: boolean;
  aggregatedWith?: string[]; // Other notification IDs
}

/**
 * Notification batch for aggregation
 */
export interface NotificationBatch {
  batchId: string;
  userId: string;
  notifications: Notification[];
  createdAt: number;
  sendAt: number;
  status: NotificationStatus;
  channel: NotificationChannel;
  digestTitle?: string;
}

/**
 * Aggregation rule configuration
 */
export interface AggregationRule {
  ruleId: string;
  userId: string;
  strategy: AggregationStrategy;
  category: NotificationCategory;
  timeWindowMs?: number; // For time-based aggregation
  countThreshold?: number; // For count-based aggregation
  priorityThreshold?: NotificationPriority; // For priority-based
  enabled: boolean;
  createdAt: number;
}

/**
 * Notification delivery result
 */
export interface DeliveryResult {
  notificationId: string;
  channel: NotificationChannel;
  status: NotificationStatus;
  timestamp: number;
  deliveryTime?: number;
  error?: string;
}

/**
 * Notification statistics
 */
export interface NotificationStatistics {
  totalNotifications: number;
  pendingCount: number;
  sentCount: number;
  deliveredCount: number;
  readCount: number;
  failedCount: number;
  aggregatedCount: number;
  averageDeliveryTimeMs: number;
  byCategory: Record<NotificationCategory, number>;
  byChannel: Record<NotificationChannel, number>;
  byPriority: Record<NotificationPriority, number>;
}

/**
 * Notification delivery policy
 */
export interface DeliveryPolicy {
  policyId: string;
  userId: string;
  channel: NotificationChannel;
  enabled: boolean;
  quietHours?: { start: string; end: string }; // HH:mm format
  maxDailyNotifications?: number;
  minPriorityForDelivery?: NotificationPriority;
  createdAt: number;
}

/**
 * Notification template
 */
export interface NotificationTemplate {
  templateId: string;
  name: string;
  category: NotificationCategory;
  subject: string;
  body: string;
  actionUrl?: string;
  actionLabel?: string;
  createdAt: number;
}

/**
 * Notification sent event
 */
export interface NotificationSentEvent {
  notificationId: string;
  userId: string;
  channel: NotificationChannel;
  timestamp: number;
  status: NotificationStatus;
  deliveryTimeMs?: number;
}

/**
 * Notification read event
 */
export interface NotificationReadEvent {
  notificationId: string;
  userId: string;
  readAt: number;
}

/**
 * Notification digest
 */
export interface NotificationDigest {
  digestId: string;
  userId: string;
  period: 'daily' | 'weekly' | 'monthly';
  notifications: Notification[];
  createdAt: number;
  sentAt?: number;
  totalCount: number;
  categories: Set<NotificationCategory>;
}

/**
 * Batch operation result
 */
export interface BatchOperationResult {
  batchId: string;
  processedCount: number;
  successCount: number;
  failureCount: number;
  timestamp: number;
  errors: string[];
}

/**
 * Notification cleanup result
 */
export interface CleanupResult {
  deletedCount: number;
  archivedCount: number;
  timestamp: number;
}

/**
 * Notification preference
 */
export interface NotificationPreference {
  preferenceId: string;
  userId: string;
  category: NotificationCategory;
  enabled: boolean;
  channels: NotificationChannel[];
  aggregationStrategy: AggregationStrategy;
  createdAt: number;
}

/**
 * Audit entry for notifications
 */
export interface NotificationAuditEntry {
  timestamp: number;
  userId: string;
  userEmail: string;
  action: string;
  notificationId?: string;
  details: Record<string, unknown>;
}

/**
 * Service configuration
 */
export interface NotificationAggregatorConfig {
  enableAggregation: boolean;
  defaultChannel: NotificationChannel;
  defaultPriority: NotificationPriority;
  retryPolicy: {
    maxRetries: number;
    backoffMs: number;
    maxBackoffMs: number;
  };
  aggregationDefaults: {
    timeWindowMs: number;
    countThreshold: number;
  };
  maxNotificationsPerUser: number;
  maxAuditEntries: number;
  cleanupIntervalMs: number;
  enableAnalytics: boolean;
}

/**
 * Notification aggregator service interface
 */
export interface INotificationAggregator {
  createNotification(
    notification: Omit<Notification, 'notificationId' | 'retryCount'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; notificationId?: string };

  sendNotification(
    notificationId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; deliveryTime?: number };

  markAsRead(
    notificationId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  archiveNotification(
    notificationId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  getNotifications(userId: string, limit?: number): Notification[];

  getPendingNotifications(userId: string): Notification[];

  createAggregationRule(
    rule: Omit<AggregationRule, 'ruleId' | 'createdAt'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; ruleId?: string };

  updateAggregationRule(
    ruleId: string,
    updates: Partial<AggregationRule>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  deleteAggregationRule(
    ruleId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  getAggregationRules(userId: string): AggregationRule[];

  aggregateNotifications(
    notificationIds: string[],
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; batchId?: string };

  createDeliveryPolicy(
    policy: Omit<DeliveryPolicy, 'policyId' | 'createdAt'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; policyId?: string };

  updateDeliveryPolicy(
    policyId: string,
    updates: Partial<DeliveryPolicy>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  getDeliveryPolicies(userId: string): DeliveryPolicy[];

  createTemplate(
    template: Omit<NotificationTemplate, 'templateId' | 'createdAt'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; templateId?: string };

  getTemplate(templateId: string): NotificationTemplate | undefined;

  getStatistics(userId?: string): NotificationStatistics;

  getAuditLog(limit?: number): NotificationAuditEntry[];

  batchSendNotifications(
    notificationIds: string[],
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; batchId?: string; successCount?: number };

  retryFailedNotifications(
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; retriedCount?: number };

  cleanupArchivedNotifications(
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; deletedCount?: number };

  updateConfig(config: Partial<NotificationAggregatorConfig>): void;

  shutdown(): void;
}
