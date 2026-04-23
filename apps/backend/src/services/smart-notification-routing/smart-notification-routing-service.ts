#!/usr/bin/env node
// @file        apps/backend/src/services/smart-notification-routing/smart-notification-routing-service.ts
// @module      collaboration/smart-notification-routing
// @description Smart notification routing service with presence-aware delivery
// @owner       collab-4.6
// @status      active

import { EventEmitter } from 'events';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger';
import { AuditService } from '../audit/audit-service';
import type {
  UserStatus,
  UserStatusContext,
  CollaborationEvent,
  RoutingResult,
  BatchDeliveryResult,
  RoutingPolicy,
  DeliveryPlan,
  RoutingMetrics,
  Presence,
  EventPriority,
} from './types';

export class SmartNotificationRoutingService extends EventEmitter {
  private logger = getLogger('SmartNotificationRoutingService');
  private pool: Pool;
  private auditService: AuditService;

  // In-memory cache for user statuses (fast lookup)
  private userStatusCache: Map<string, UserStatus> = new Map();

  // Routing policies per presence state
  private routingPolicies: Map<Presence, RoutingPolicy> = new Map([
    ['online', { presence: 'online', criticalDelay: 0, highDelay: 0, normalDelay: 100, lowDelay: 500 }],
    ['away', { presence: 'away', criticalDelay: 0, highDelay: 100, normalDelay: 1000, lowDelay: 5000 }],
    ['in-meeting', { presence: 'in-meeting', criticalDelay: 5000, highDelay: 5000, normalDelay: 10000, lowDelay: 30000 }],
    ['dnd', { presence: 'dnd', criticalDelay: 0, highDelay: 5000, normalDelay: 30000, lowDelay: 60000 }],
    ['coding', { presence: 'coding', criticalDelay: 5000, highDelay: 5000, normalDelay: 15000, lowDelay: 60000 }],
    ['offline', { presence: 'offline', criticalDelay: 0, highDelay: 0, normalDelay: 0, lowDelay: 0 }],
  ]);

  // Metrics tracking
  private metrics: RoutingMetrics = {
    totalEvents: 0,
    routedCount: 0,
    deferredCount: 0,
    suppressedCount: 0,
    avgDeliveryDelay: 0,
    batchSize: 5,
    timestamp: new Date(),
  };

  constructor(pool: Pool, auditService: AuditService) {
    super();
    this.pool = pool;
    this.auditService = auditService;
  }

  /**
   * Initialize the service and create required tables
   */
  async initialize(): Promise<void> {
    try {
      await this.createTables();
      await this.loadUserStatusCache();
      this.startCleanupInterval();
      this.startBatchProcessingInterval();
      this.logger.info('SmartNotificationRoutingService initialized');
    } catch (error) {
      this.logger.error('Failed to initialize SmartNotificationRoutingService', error);
      throw error;
    }
  }

  /**
   * Create required database tables
   */
  private async createTables(): Promise<void> {
    const client = await this.pool.connect();
    try {
      // User status tracking table
      await client.query(`
        CREATE TABLE IF NOT EXISTS smart_notification_user_status (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id VARCHAR(255) NOT NULL UNIQUE,
          presence VARCHAR(50) NOT NULL,
          location VARCHAR(100),
          current_device VARCHAR(50),
          calendar_status VARCHAR(50),
          last_activity TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          metadata JSONB,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Notification queue table
      await client.query(`
        CREATE TABLE IF NOT EXISTS smart_notification_queue (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id VARCHAR(255) NOT NULL,
          event_type VARCHAR(100) NOT NULL,
          priority VARCHAR(20) NOT NULL,
          context JSONB NOT NULL,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          scheduled_delivery TIMESTAMP NOT NULL,
          delivered_at TIMESTAMP,
          delivery_method VARCHAR(50),
          metadata JSONB
        )
      `);

      // Routing metrics table for audit
      await client.query(`
        CREATE TABLE IF NOT EXISTS smart_notification_metrics (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          event_id VARCHAR(255) NOT NULL,
          total_recipients INTEGER,
          routed_count INTEGER,
          deferred_count INTEGER,
          suppressed_count INTEGER,
          avg_delay_ms INTEGER,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create indices for performance
      await client.query(`
        CREATE INDEX IF NOT EXISTS idx_snr_user_status_user_id ON smart_notification_user_status(user_id)
      `);
      await client.query(`
        CREATE INDEX IF NOT EXISTS idx_snr_queue_user_id ON smart_notification_queue(user_id, delivered_at)
      `);
      await client.query(`
        CREATE INDEX IF NOT EXISTS idx_snr_queue_delivery ON smart_notification_queue(scheduled_delivery)
        WHERE delivered_at IS NULL
      `);

      this.logger.info('SmartNotificationRoutingService tables created successfully');
    } finally {
      client.release();
    }
  }

  /**
   * Load user status cache from database
   */
  private async loadUserStatusCache(): Promise<void> {
    const client = await this.pool.connect();
    try {
      const result = await client.query('SELECT * FROM smart_notification_user_status');
      result.rows.forEach((row) => {
        const status: UserStatus = {
          id: row.id,
          userId: row.user_id,
          presence: row.presence,
          location: row.location,
          currentDevice: row.current_device,
          calendarStatus: row.calendar_status,
          lastActivity: new Date(row.last_activity),
          updatedAt: new Date(row.updated_at),
        };
        this.userStatusCache.set(row.user_id, status);
      });
      this.logger.info(`Loaded ${this.userStatusCache.size} user statuses into cache`);
    } finally {
      client.release();
    }
  }

  /**
   * Update or create user status
   */
  async updateUserStatus(
    userId: string,
    presence: Presence,
    context?: UserStatusContext
  ): Promise<UserStatus> {
    const client = await this.pool.connect();
    try {
      const existing = this.userStatusCache.get(userId);
      const timestamp = new Date();

      let status: UserStatus;

      if (existing) {
        // Update existing status
        const result = await client.query(
          `UPDATE smart_notification_user_status 
           SET presence = $1, 
               location = $2,
               current_device = $3,
               calendar_status = $4,
               last_activity = $5,
               updated_at = $6,
               metadata = $7
           WHERE user_id = $8
           RETURNING *`,
          [
            presence,
            context?.location || existing.location,
            context?.currentDevice || existing.currentDevice,
            context?.calendarStatus || existing.calendarStatus,
            timestamp,
            timestamp,
            JSON.stringify(context?.metadata || {}),
            userId,
          ]
        );

        status = {
          id: result.rows[0].id,
          userId: result.rows[0].user_id,
          presence,
          location: result.rows[0].location,
          currentDevice: result.rows[0].current_device,
          calendarStatus: result.rows[0].calendar_status,
          lastActivity: new Date(result.rows[0].last_activity),
          updatedAt: new Date(result.rows[0].updated_at),
        };
      } else {
        // Insert new status
        const result = await client.query(
          `INSERT INTO smart_notification_user_status 
           (user_id, presence, location, current_device, calendar_status, last_activity, updated_at, metadata)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
           RETURNING *`,
          [
            userId,
            presence,
            context?.location,
            context?.currentDevice,
            context?.calendarStatus,
            timestamp,
            timestamp,
            JSON.stringify(context?.metadata || {}),
          ]
        );

        status = {
          id: result.rows[0].id,
          userId: result.rows[0].user_id,
          presence,
          location: result.rows[0].location,
          currentDevice: result.rows[0].current_device,
          calendarStatus: result.rows[0].calendar_status,
          lastActivity: new Date(result.rows[0].last_activity),
          updatedAt: new Date(result.rows[0].updated_at),
        };
      }

      // Update cache
      this.userStatusCache.set(userId, status);

      // Audit log the status change
      await this.auditService.logAudit({
        userId,
        action: 'user_status_update',
        resourceType: 'notification_status',
        resourceId: status.id,
        details: {
          presence,
          location: context?.location,
          device: context?.currentDevice,
        },
        timestamp,
      });

      this.emit('userStatusUpdated', status);
      return status;
    } finally {
      client.release();
    }
  }

  /**
   * Get user status from cache (fast path)
   */
  getUserStatus(userId: string): UserStatus | undefined {
    return this.userStatusCache.get(userId);
  }

  /**
   * Route a collaboration event to target users with intelligent delivery
   */
  async routeEvent(
    event: CollaborationEvent,
    targetUserIds: string[]
  ): Promise<RoutingResult> {
    const routed: string[] = [];
    const deferred: string[] = [];
    const suppressed: string[] = [];

    const timestamp = new Date();

    for (const userId of targetUserIds) {
      const status = this.userStatusCache.get(userId);

      if (!status) {
        // User not found in cache, defer for later
        deferred.push(userId);
        continue;
      }

      const deliveryPlan = this.getDeliveryPlan(userId, status, event.priority);

      if (deliveryPlan.method === 'immediate') {
        routed.push(userId);
      } else if (deliveryPlan.method === 'batch') {
        deferred.push(userId);
        // Add to notification queue
        await this.enqueueNotification(userId, event, deliveryPlan.deliveryTime);
      } else {
        suppressed.push(userId);
      }
    }

    const result: RoutingResult = {
      eventId: event.id,
      routed,
      deferred,
      suppressed,
      total: targetUserIds.length,
      timestamp,
    };

    // Log metrics
    this.metrics.totalEvents++;
    this.metrics.routedCount += routed.length;
    this.metrics.deferredCount += deferred.length;
    this.metrics.suppressedCount += suppressed.length;

    // Store routing metrics
    await this.storeRoutingMetrics(event.id, result);

    // Audit log the routing decision
    await this.auditService.logAudit({
      userId: event.userId,
      action: 'event_routing',
      resourceType: 'collaboration_event',
      resourceId: event.id,
      details: {
        eventType: event.type,
        priority: event.priority,
        routed: routed.length,
        deferred: deferred.length,
        suppressed: suppressed.length,
      },
      timestamp,
    });

    this.emit('eventRouted', result);
    return result;
  }

  /**
   * Determine delivery plan for a user based on presence and event priority
   */
  private getDeliveryPlan(
    userId: string,
    status: UserStatus,
    priority: EventPriority
  ): DeliveryPlan {
    const policy = this.routingPolicies.get(status.presence);
    if (!policy) {
      throw new Error(`No routing policy defined for presence: ${status.presence}`);
    }

    const now = new Date();
    let delay = 0;
    let method: 'immediate' | 'batch' | 'suppress' = 'immediate';
    let reason = 'default routing';

    // Determine delay based on priority and presence
    switch (priority) {
      case 'critical':
        delay = policy.criticalDelay ?? 0;
        if (status.presence === 'offline') {
          method = 'batch';
          reason = 'user offline, will batch';
        }
        break;
      case 'high':
        delay = policy.highDelay ?? 0;
        if (status.presence === 'offline' || status.presence === 'dnd') {
          method = 'batch';
          reason = `user ${status.presence}, will batch`;
        }
        break;
      case 'normal':
        delay = policy.normalDelay ?? 0;
        if (status.presence === 'in-meeting' || status.presence === 'coding' || status.presence === 'offline') {
          method = 'batch';
          reason = `user ${status.presence}, will batch`;
        }
        break;
      case 'low':
        delay = policy.lowDelay ?? 0;
        if (
          status.presence === 'away' ||
          status.presence === 'in-meeting' ||
          status.presence === 'offline' ||
          status.presence === 'dnd'
        ) {
          method = 'batch';
          reason = `user ${status.presence}, will batch`;
        }
        break;
    }

    const deliveryTime = new Date(now.getTime() + delay);

    return {
      userId,
      deliveryTime,
      method,
      devices: this.getTargetDevices(status),
      reason,
    };
  }

  /**
   * Determine which devices to notify based on user status
   */
  private getTargetDevices(status: UserStatus): string[] {
    const devices = [];

    // Always notify the current device if online
    if (status.presence !== 'offline' && status.currentDevice) {
      devices.push(status.currentDevice);
    }

    // For critical events or online users, also notify web/desktop
    if (status.presence === 'online' || status.presence === 'coding') {
      if (!devices.includes('ide')) devices.push('ide');
      if (!devices.includes('web')) devices.push('web');
    }

    return devices.length > 0 ? devices : ['web']; // Default to web if nothing else
  }

  /**
   * Enqueue notification for deferred delivery
   */
  private async enqueueNotification(
    userId: string,
    event: CollaborationEvent,
    scheduledDelivery: Date
  ): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO smart_notification_queue 
         (user_id, event_type, priority, context, scheduled_delivery, delivery_method)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [userId, event.type, event.priority, JSON.stringify(event.context), scheduledDelivery, 'batch']
      );
    } finally {
      client.release();
    }
  }

  /**
   * Process deferred notification queue
   */
  async processDeferredQueue(): Promise<BatchDeliveryResult> {
    const client = await this.pool.connect();
    try {
      const now = new Date();
      const result = await client.query(
        `SELECT id, user_id FROM smart_notification_queue 
         WHERE delivered_at IS NULL AND scheduled_delivery <= $1
         ORDER BY scheduled_delivery ASC
         LIMIT 100`,
        [now]
      );

      const processed = result.rows.length;
      const batchId = `batch-${Date.now()}`;

      // Mark as delivered
      if (processed > 0) {
        const ids = result.rows.map((r) => r.id);
        await client.query(
          `UPDATE smart_notification_queue 
           SET delivered_at = $1
           WHERE id = ANY($2)`,
          [now, ids]
        );
      }

      const deliveryResult: BatchDeliveryResult = {
        batchId,
        processed,
        failed: 0,
        skipped: 0,
        timestamp: now,
      };

      this.emit('batchProcessed', deliveryResult);
      return deliveryResult;
    } finally {
      client.release();
    }
  }

  /**
   * Store routing metrics for analysis
   */
  private async storeRoutingMetrics(eventId: string, result: RoutingResult): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO smart_notification_metrics 
         (event_id, total_recipients, routed_count, deferred_count, suppressed_count)
         VALUES ($1, $2, $3, $4, $5)`,
        [eventId, result.total, result.routed.length, result.deferred.length, result.suppressed.length]
      );
    } catch (error) {
      this.logger.warn('Failed to store routing metrics', error);
    } finally {
      client.release();
    }
  }

  /**
   * Get current routing metrics
   */
  getMetrics(): RoutingMetrics {
    return { ...this.metrics, timestamp: new Date() };
  }

  /**
   * Start cleanup interval for stale entries
   */
  private startCleanupInterval(): void {
    // Clean up delivered notifications older than 7 days
    setInterval(
      async () => {
        try {
          const client = await this.pool.connect();
          try {
            const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
            await client.query(
              'DELETE FROM smart_notification_queue WHERE delivered_at < $1',
              [sevenDaysAgo]
            );
          } finally {
            client.release();
          }
        } catch (error) {
          this.logger.warn('Cleanup interval failed', error);
        }
      },
      60 * 60 * 1000 // Every hour
    );
  }

  /**
   * Start batch processing interval
   */
  private startBatchProcessingInterval(): void {
    setInterval(
      async () => {
        try {
          await this.processDeferredQueue();
        } catch (error) {
          this.logger.warn('Batch processing interval failed', error);
        }
      },
      5 * 60 * 1000 // Every 5 minutes
    );
  }

  /**
   * Cleanup and shutdown
   */
  async shutdown(): Promise<void> {
    this.removeAllListeners();
    this.userStatusCache.clear();
    this.logger.info('SmartNotificationRoutingService shutdown');
  }
}

export * from './types';
