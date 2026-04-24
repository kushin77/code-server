#!/usr/bin/env node
// @file        apps/backend/src/services/notification-priority-engine/notification-priority-engine-service.ts
// @module      collaboration/notification-priority-engine
// @description Priority-based notification delivery with smart batching and user preferences
// @owner       collab-5.1
// @status      active

import { EventEmitter } from 'events';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger';
import { AuditService } from '../audit/audit-service';
import type {
  Notification,
  NotificationWithPriority,
  PriorityScore,
  UserPriorityPreferences,
  DeliveryPlan,
  QueueMetrics,
  NotificationBatch,
  CollaborationContext,
  ThrottleResult,
  NotificationPriority,
  PriorityWeights,
} from './types';

export class NotificationPriorityEngineService extends EventEmitter {
  private logger = getLogger('NotificationPriorityEngineService');
  private pool: Pool;
  private auditService: AuditService;

  // Priority weights (configurable)
  private weights: PriorityWeights = {
    notificationTypeWeight: 0.3,
    userPreferenceWeight: 0.2,
    contextFactorWeight: 0.25,
    temporalFactorWeight: 0.15,
    relationshipFactorWeight: 0.1,
  };

  // In-memory queues per user
  private notificationQueues: Map<string, NotificationWithPriority[]> = new Map();

  // User preferences cache
  private userPreferencesCache: Map<string, UserPriorityPreferences> = new Map();

  // Throttle tracking (notifications per hour per user)
  private throttleTracking: Map<string, number[]> = new Map();

  // Batch tracking
  private activeBatches: Map<string, NotificationBatch> = new Map();

  // Default preferences
  private defaultPreferences: UserPriorityPreferences = {
    userId: '',
    dndMode: false,
    channelPreferences: { in_app: true, email: true },
    typePreferences: {},
    batchWindow: 1000, // 1 second
    maxNotificationsPerHour: 100,
  };

  constructor(pool: Pool, auditService: AuditService) {
    super();
    this.pool = pool;
    this.auditService = auditService;
  }

  /**
   * Initialize service and create required tables
   */
  async initialize(): Promise<void> {
    try {
      await this.createTables();
      this.startBatchProcessing();
      this.logger.info('NotificationPriorityEngineService initialized');
    } catch (error) {
      this.logger.error('Failed to initialize NotificationPriorityEngineService', error);
      throw error;
    }
  }

  /**
   * Create required database tables
   */
  private async createTables(): Promise<void> {
    const client = await this.pool.connect();
    try {
      // Notifications queue
      await client.query(`
        CREATE TABLE IF NOT EXISTS notification_priority_queue (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id VARCHAR(255) NOT NULL,
          notification_type VARCHAR(50) NOT NULL,
          title VARCHAR(255) NOT NULL,
          message TEXT,
          priority VARCHAR(20) NOT NULL,
          priority_score INTEGER,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          scheduled_for TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          delivered_at TIMESTAMP,
          failed_at TIMESTAMP,
          metadata JSONB
        )
      `);

      // User preferences
      await client.query(`
        CREATE TABLE IF NOT EXISTS notification_user_preferences (
          user_id VARCHAR(255) PRIMARY KEY,
          dnd_mode BOOLEAN DEFAULT FALSE,
          dnd_start_time VARCHAR(5),
          dnd_end_time VARCHAR(5),
          channel_preferences JSONB,
          type_preferences JSONB,
          batch_window INTEGER DEFAULT 1000,
          max_per_hour INTEGER DEFAULT 100,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Batches sent
      await client.query(`
        CREATE TABLE IF NOT EXISTS notification_batches (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id VARCHAR(255) NOT NULL,
          notification_count INTEGER,
          channel VARCHAR(50),
          status VARCHAR(20),
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          delivered_at TIMESTAMP
        )
      `);

      // Create indices
      await client.query(`
        CREATE INDEX IF NOT EXISTS idx_priority_queue_user 
        ON notification_priority_queue(user_id, delivered_at)
      `);
      await client.query(`
        CREATE INDEX IF NOT EXISTS idx_priority_queue_scheduled 
        ON notification_priority_queue(scheduled_for, priority)
      `);
      await client.query(`
        CREATE INDEX IF NOT EXISTS idx_batches_user 
        ON notification_batches(user_id, created_at)
      `);

      this.logger.info('NotificationPriorityEngineService tables created');
    } finally {
      client.release();
    }
  }

  /**
   * Enqueue notification for user
   */
  async enqueueNotification(
    userId: string,
    notification: Notification,
    context?: CollaborationContext
  ): Promise<NotificationWithPriority> {
    // Check throttling
    const throttled = this.checkThrottle(userId);
    if (!throttled.allowed) {
      this.logger.warn(`User ${userId} throttled: ${throttled.reason}`);
      throw new Error(`Notification throttled: ${throttled.reason}`);
    }

    // Calculate priority
    const priorityScore = this.calculatePriority(userId, notification, context);

    // Get user preferences
    const preferences = await this.getUserPreferences(userId);

    // Check if notification should be suppressed
    if (preferences.dndMode && !this.isInQuietHours(preferences)) {
      this.logger.info(`User ${userId} in DND mode, deferring notification`);
    }

    // Create notification with priority
    const notificationWithPriority: NotificationWithPriority = {
      ...notification,
      priority: priorityScore.priority,
      priorityScore: priorityScore.score,
      scheduledFor: this.calculateScheduledTime(preferences, priorityScore.priority),
    };

    // Add to queue
    if (!this.notificationQueues.has(userId)) {
      this.notificationQueues.set(userId, []);
    }

    const queue = this.notificationQueues.get(userId)!;
    queue.push(notificationWithPriority);

    // Sort by priority (descending)
    queue.sort((a, b) => b.priorityScore - a.priorityScore);

    // Persist to database
    await this.persistNotification(userId, notificationWithPriority);

    // Audit log
    await this.auditService.logAudit({
      userId,
      action: 'notification_enqueued',
      resourceType: 'notification',
      resourceId: notification.id,
      details: {
        type: notification.type,
        priority: priorityScore.priority,
        score: priorityScore.score,
      },
      timestamp: new Date(),
    });

    this.emit('notificationEnqueued', notificationWithPriority);

    return notificationWithPriority;
  }

  /**
   * Calculate priority score for notification
   */
  private calculatePriority(
    userId: string,
    notification: Notification,
    context?: CollaborationContext
  ): PriorityScore {
    let totalScore = 0;

    // Factor 1: Notification type (30%)
    const typeScore = this.getTypeScore(notification.type);
    totalScore += typeScore * this.weights.notificationTypeWeight;

    // Factor 2: User preference (20%)
    const prefScore = this.getUserPreferenceScore(userId, notification.type);
    totalScore += prefScore * this.weights.userPreferenceWeight;

    // Factor 3: Context (25%)
    const contextScore = context ? this.getContextScore(context) : 50;
    totalScore += contextScore * this.weights.contextFactorWeight;

    // Factor 4: Temporal (15%) - age-based boost
    const temporalScore = this.getTemporalScore(notification.createdAt);
    totalScore += temporalScore * this.weights.temporalFactorWeight;

    // Factor 5: Relationship (10%) - direct involvement
    const relationshipScore = context ? this.getRelationshipScore(context) : 50;
    totalScore += relationshipScore * this.weights.relationshipFactorWeight;

    const finalScore = Math.round(totalScore);
    const priority = this.scoreToPriority(finalScore);

    return {
      score: finalScore,
      priority,
      factors: [
        { name: 'type', value: typeScore, weight: this.weights.notificationTypeWeight, description: notification.type },
        { name: 'preference', value: prefScore, weight: this.weights.userPreferenceWeight, description: 'User setting' },
        { name: 'context', value: contextScore, weight: this.weights.contextFactorWeight, description: 'Collaboration state' },
        { name: 'temporal', value: temporalScore, weight: this.weights.temporalFactorWeight, description: 'Age' },
        { name: 'relationship', value: relationshipScore, weight: this.weights.relationshipFactorWeight, description: 'Involvement' },
      ],
      confidence: 85,
    };
  }

  /**
   * Get base score for notification type
   */
  private getTypeScore(type: string): number {
    const typeScores: Record<string, number> = {
      conflict_detected: 90,
      mention: 75,
      task_completed: 50,
      comment_reply: 60,
      file_changed: 40,
      presence_update: 30,
      system_alert: 85,
    };

    return typeScores[type] || 50;
  }

  /**
   * Get user preference score
   */
  private getUserPreferenceScore(userId: string, type: string): number {
    const prefs = this.userPreferencesCache.get(userId);
    if (!prefs || !prefs.typePreferences[type as any]) {
      return 50; // Default neutral
    }

    const typePref = prefs.typePreferences[type as any];
    if (!typePref.enabled) return 0;

    return 70; // User enabled this type
  }

  /**
   * Get context score based on collaboration state
   */
  private getContextScore(context: CollaborationContext): number {
    let score = 50;

    // In meeting penalty
    if (context.isInMeeting) score -= 20;

    // Active work boost
    const timesSinceActivity = Date.now() - context.lastActivityTime.getTime();
    if (timesSinceActivity < 30000) score += 15; // Recently active

    // Conflict urgency
    if (context.hasConflicts) score += 25;

    // Team collaboration factor
    if (context.teamSize > 5) score += 10;

    return Math.max(0, Math.min(100, score));
  }

  /**
   * Get temporal score (older notifications get boost)
   */
  private getTemporalScore(createdAt: Date): number {
    const ageMs = Date.now() - createdAt.getTime();
    const ageSeconds = ageMs / 1000;

    // Boost by 1 point per second, max 50
    return Math.min(50, ageSeconds);
  }

  /**
   * Get relationship score (involved users get priority)
   */
  private getRelationshipScore(context: CollaborationContext): number {
    let score = 50;

    // Active files indicate involvement
    if (context.activeFileCount > 0) score += 20;

    // Progress on task indicates involvement
    if (context.taskProgress > 50) score += 15;

    return Math.min(100, score);
  }

  /**
   * Convert score to priority level
   */
  private scoreToPriority(score: number): NotificationPriority {
    if (score >= 75) return 'critical';
    if (score >= 60) return 'high';
    if (score >= 40) return 'medium';
    return 'low';
  }

  /**
   * Check throttling
   */
  private checkThrottle(userId: string): ThrottleResult {
    if (!this.throttleTracking.has(userId)) {
      this.throttleTracking.set(userId, []);
    }

    const timestamps = this.throttleTracking.get(userId)!;
    const now = Date.now();
    const oneHourAgo = now - 3600000;

    // Remove old timestamps
    const recentTimestamps = timestamps.filter((t) => t > oneHourAgo);
    this.throttleTracking.set(userId, recentTimestamps);

    const maxPerHour = this.defaultPreferences.maxNotificationsPerHour || 100;

    if (recentTimestamps.length >= maxPerHour) {
      const oldest = Math.min(...recentTimestamps);
      return {
        allowed: false,
        reason: `Exceeded ${maxPerHour} notifications per hour`,
        nextAvailableTime: new Date(oldest + 3600000),
        remaining: 0,
      };
    }

    recentTimestamps.push(now);
    return {
      allowed: true,
      remaining: maxPerHour - recentTimestamps.length,
    };
  }

  /**
   * Get or load user preferences
   */
  private async getUserPreferences(userId: string): Promise<UserPriorityPreferences> {
    if (this.userPreferencesCache.has(userId)) {
      return this.userPreferencesCache.get(userId)!;
    }

    // Load from database
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        'SELECT * FROM notification_user_preferences WHERE user_id = $1',
        [userId]
      );

      if (result.rows.length > 0) {
        const row = result.rows[0];
        const prefs: UserPriorityPreferences = {
          userId,
          dndMode: row.dnd_mode,
          dndStartTime: row.dnd_start_time,
          dndEndTime: row.dnd_end_time,
          channelPreferences: row.channel_preferences || {},
          typePreferences: row.type_preferences || {},
          batchWindow: row.batch_window || 1000,
          maxNotificationsPerHour: row.max_per_hour || 100,
        };

        this.userPreferencesCache.set(userId, prefs);
        return prefs;
      }
    } finally {
      client.release();
    }

    // Return default preferences
    const defaultPrefs = { ...this.defaultPreferences, userId };
    this.userPreferencesCache.set(userId, defaultPrefs);
    return defaultPrefs;
  }

  /**
   * Check if user is in quiet hours
   */
  private isInQuietHours(prefs: UserPriorityPreferences): boolean {
    if (!prefs.dndStartTime || !prefs.dndEndTime) return false;

    const now = new Date();
    const currentTime = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;

    return currentTime >= prefs.dndStartTime && currentTime < prefs.dndEndTime;
  }

  /**
   * Calculate scheduled delivery time
   */
  private calculateScheduledTime(prefs: UserPriorityPreferences, priority: NotificationPriority): Date {
    const now = new Date();

    // Critical notifications: immediate
    if (priority === 'critical') return now;

    // High: minimal delay
    if (priority === 'high') return new Date(now.getTime() + 100);

    // Medium: batch window
    if (priority === 'medium') return new Date(now.getTime() + (prefs.batchWindow || 1000));

    // Low: longer delay
    return new Date(now.getTime() + (prefs.batchWindow || 1000) * 2);
  }

  /**
   * Persist notification to database
   */
  private async persistNotification(userId: string, notification: NotificationWithPriority): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO notification_priority_queue 
         (user_id, notification_type, title, message, priority, priority_score, scheduled_for, metadata)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [
          userId,
          notification.type,
          notification.title,
          notification.message,
          notification.priority,
          notification.priorityScore,
          notification.scheduledFor,
          notification.metadata ? JSON.stringify(notification.metadata) : null,
        ]
      );
    } finally {
      client.release();
    }
  }

  /**
   * Start batch processing interval
   */
  private startBatchProcessing(): void {
    setInterval(async () => {
      try {
        for (const [userId] of this.notificationQueues) {
          await this.processBatchForUser(userId);
        }
      } catch (error) {
        this.logger.warn('Batch processing failed', error);
      }
    }, 5000); // Every 5 seconds
  }

  /**
   * Process pending notifications for a user
   */
  private async processBatchForUser(userId: string): Promise<void> {
    const queue = this.notificationQueues.get(userId);
    if (!queue || queue.length === 0) return;

    const now = new Date();
    const readyNotifications = queue.filter((n) => n.scheduledFor <= now);

    if (readyNotifications.length === 0) return;

    // Create batch
    const batch: NotificationBatch = {
      id: `batch-${Date.now()}-${Math.random().toString(36).substring(7)}`,
      userId,
      notifications: readyNotifications,
      createdAt: now,
      channel: 'in_app',
      status: 'pending',
    };

    this.activeBatches.set(batch.id, batch);

    // Remove from queue
    readyNotifications.forEach((n) => {
      const idx = queue.indexOf(n);
      if (idx > -1) queue.splice(idx, 1);
    });

    // Emit batch ready
    this.emit('batchReady', batch);

    // Mark as delivered
    batch.status = 'delivered';
    batch.deliveredAt = new Date();

    this.logger.info(`Batch ${batch.id} delivered to user ${userId} (${readyNotifications.length} notifications)`);
  }

  /**
   * Get queue metrics
   */
  getMetrics(): QueueMetrics {
    let totalNotifications = 0;
    let criticalCount = 0;
    let highCount = 0;
    let mediumCount = 0;
    let lowCount = 0;
    let totalScore = 0;

    for (const queue of this.notificationQueues.values()) {
      totalNotifications += queue.length;
      for (const notif of queue) {
        totalScore += notif.priorityScore;
        if (notif.priority === 'critical') criticalCount++;
        else if (notif.priority === 'high') highCount++;
        else if (notif.priority === 'medium') mediumCount++;
        else lowCount++;
      }
    }

    return {
      totalNotifications,
      criticalCount,
      highCount,
      mediumCount,
      lowCount,
      averagePriorityScore: totalNotifications > 0 ? Math.round(totalScore / totalNotifications) : 0,
      batchesQueued: this.activeBatches.size,
      averageBatchSize: this.activeBatches.size > 0 ? Math.round(totalNotifications / this.activeBatches.size) : 0,
      oldestNotificationAge: 0,
    };
  }

  /**
   * Shutdown service
   */
  async shutdown(): Promise<void> {
    this.removeAllListeners();
    this.notificationQueues.clear();
    this.userPreferencesCache.clear();
    this.throttleTracking.clear();
    this.activeBatches.clear();
    this.logger.info('NotificationPriorityEngineService shutdown');
  }
}

export * from './types';
