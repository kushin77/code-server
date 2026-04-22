#!/usr/bin/env node
// @file        apps/backend/src/services/smart-notification-routing/index.ts
// @module      collaboration/notification-routing
// @description Smart notification routing based on user status and availability
// @owner       collab-4.6
// @status      active

import { EventEmitter } from 'events';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger';

export type NotificationChannel = 'ide' | 'slack' | 'matrix' | 'email';
export type UserStatus = 'online' | 'idle' | 'away' | 'in-meeting' | 'dnd' | 'offline';
export type NotificationPriority = 'urgent' | 'high' | 'normal' | 'low';

export interface NotificationRoute {
  id: string;
  userId: string;
  priority: NotificationPriority;
  channels: NotificationChannel[];
  conditions?: RoutingCondition[];
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export interface RoutingCondition {
  status: UserStatus;
  channels: NotificationChannel[];
  delay?: number; // milliseconds
}

export interface UserStatusInfo {
  userId: string;
  currentStatus: UserStatus;
  lastStatusChange: Date;
  location?: string;
  calendarStatus?: 'free' | 'busy' | 'unknown';
  currentDevice?: 'ide' | 'mobile' | 'desktop' | 'unknown';
}

export interface NotificationDelivery {
  id: string;
  userId: string;
  notificationId: string;
  content: string;
  channel: NotificationChannel;
  status: 'pending' | 'sent' | 'failed' | 'delivered' | 'read';
  attemptCount: number;
  maxAttempts: number;
  sentAt?: Date;
  deliveredAt?: Date;
  readAt?: Date;
  failureReason?: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface SmartNotificationConfig {
  maxDeliveryAttempts?: number;
  deliveryTimeout?: number; // milliseconds
  deduplicationWindow?: number; // milliseconds
}

export class SmartNotificationRoutingService extends EventEmitter {
  private pool: Pool;
  private logger = getLogger('SmartNotificationRoutingService');
  private initialized = false;
  private config: Required<SmartNotificationConfig>;

  constructor(pool: Pool, config: SmartNotificationConfig = {}) {
    super();
    this.pool = pool;
    this.config = {
      maxDeliveryAttempts: config.maxDeliveryAttempts || 3,
      deliveryTimeout: config.deliveryTimeout || 30000,
      deduplicationWindow: config.deduplicationWindow || 60000,
    };
  }

  async initialize(): Promise<void> {
    if (this.initialized) return;

    try {
      await this.createTables();
      this.initialized = true;
      this.logger.info('Smart notification routing database schema initialized');
    } catch (error) {
      this.logger.error('Failed to initialize smart notification routing schema', { error });
      throw error;
    }
  }

  private async createTables(): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // User status tracking
      await client.query(`
        CREATE TABLE IF NOT EXISTS user_status (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id TEXT NOT NULL UNIQUE,
          current_status TEXT NOT NULL CHECK (current_status IN ('online', 'idle', 'away', 'in-meeting', 'dnd', 'offline')),
          last_status_change TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          location TEXT,
          calendar_status TEXT CHECK (calendar_status IN ('free', 'busy', 'unknown')),
          current_device TEXT CHECK (current_device IN ('ide', 'mobile', 'desktop', 'unknown')),
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);

      // Notification routes
      await client.query(`
        CREATE TABLE IF NOT EXISTS notification_routes (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id TEXT NOT NULL,
          priority TEXT NOT NULL CHECK (priority IN ('urgent', 'high', 'normal', 'low')),
          channels TEXT[] NOT NULL,
          conditions JSONB,
          is_active BOOLEAN DEFAULT true,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          UNIQUE(user_id, priority)
        )
      `);

      // Notification deliveries
      await client.query(`
        CREATE TABLE IF NOT EXISTS notification_deliveries (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id TEXT NOT NULL,
          notification_id TEXT NOT NULL,
          content TEXT NOT NULL,
          channel TEXT NOT NULL CHECK (channel IN ('ide', 'slack', 'matrix', 'email')),
          status TEXT NOT NULL CHECK (status IN ('pending', 'sent', 'failed', 'delivered', 'read')),
          attempt_count INTEGER DEFAULT 0,
          max_attempts INTEGER DEFAULT 3,
          sent_at TIMESTAMP WITH TIME ZONE,
          delivered_at TIMESTAMP WITH TIME ZONE,
          read_at TIMESTAMP WITH TIME ZONE,
          failure_reason TEXT,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);

      // Delivery history for audit
      await client.query(`
        CREATE TABLE IF NOT EXISTS notification_delivery_history (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          delivery_id UUID NOT NULL REFERENCES notification_deliveries(id) ON DELETE CASCADE,
          status_from TEXT,
          status_to TEXT NOT NULL,
          reason TEXT,
          attempt_number INTEGER,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);

      // Deduplication cache
      await client.query(`
        CREATE TABLE IF NOT EXISTS notification_dedup_cache (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id TEXT NOT NULL,
          notification_hash TEXT NOT NULL,
          last_delivery_at TIMESTAMP WITH TIME ZONE NOT NULL,
          UNIQUE(user_id, notification_hash)
        )
      `);

      // Indexes
      await client.query(`
        CREATE INDEX IF NOT EXISTS idx_user_status_user ON user_status(user_id);
        CREATE INDEX IF NOT EXISTS idx_user_status_current ON user_status(current_status);
        CREATE INDEX IF NOT EXISTS idx_notification_routes_user ON notification_routes(user_id);
        CREATE INDEX IF NOT EXISTS idx_notification_routes_active ON notification_routes(is_active);
        CREATE INDEX IF NOT EXISTS idx_notification_deliveries_user ON notification_deliveries(user_id);
        CREATE INDEX IF NOT EXISTS idx_notification_deliveries_status ON notification_deliveries(status);
        CREATE INDEX IF NOT EXISTS idx_notification_deliveries_channel ON notification_deliveries(channel);
        CREATE INDEX IF NOT EXISTS idx_delivery_history_delivery ON notification_delivery_history(delivery_id);
        CREATE INDEX IF NOT EXISTS idx_dedup_cache_user ON notification_dedup_cache(user_id);
        CREATE INDEX IF NOT EXISTS idx_dedup_cache_hash ON notification_dedup_cache(notification_hash);
      `);

      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async updateUserStatus(userId: string, status: UserStatus, context?: Partial<UserStatusInfo>): Promise<void> {
    const client = await this.pool.connect();
    try {
      const existing = await client.query(
        'SELECT id FROM user_status WHERE user_id = $1',
        [userId]
      );

      if (existing.rows.length === 0) {
        await client.query(
          `INSERT INTO user_status (user_id, current_status, location, calendar_status, current_device)
           VALUES ($1, $2, $3, $4, $5)`,
          [userId, status, context?.location || null, context?.calendarStatus || null, context?.currentDevice || null]
        );
      } else {
        await client.query(
          `UPDATE user_status SET current_status = $1, last_status_change = NOW(),
                                  location = COALESCE($2, location),
                                  calendar_status = COALESCE($3, calendar_status),
                                  current_device = COALESCE($4, current_device),
                                  updated_at = NOW()
           WHERE user_id = $5`,
          [status, context?.location, context?.calendarStatus, context?.currentDevice, userId]
        );
      }

      this.logger.info('User status updated', { userId, status });
      this.emit('status-changed', { userId, status, timestamp: new Date() });
    } catch (error) {
      this.logger.error('Failed to update user status', { error, userId });
      throw error;
    } finally {
      client.release();
    }
  }

  async getUserStatus(userId: string): Promise<UserStatusInfo | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        'SELECT * FROM user_status WHERE user_id = $1',
        [userId]
      );

      if (result.rows.length === 0) {
        return null;
      }

      const row = result.rows[0];
      return {
        userId: row.user_id,
        currentStatus: row.current_status,
        lastStatusChange: new Date(row.last_status_change),
        location: row.location,
        calendarStatus: row.calendar_status,
        currentDevice: row.current_device,
      };
    } catch (error) {
      this.logger.error('Failed to get user status', { error, userId });
      throw error;
    } finally {
      client.release();
    }
  }

  async setNotificationRoute(userId: string, priority: NotificationPriority, channels: NotificationChannel[], conditions?: RoutingCondition[]): Promise<NotificationRoute> {
    const client = await this.pool.connect();
    try {
      const id = require('crypto').randomUUID();

      await client.query(
        `INSERT INTO notification_routes (id, user_id, priority, channels, conditions)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (user_id, priority) DO UPDATE SET channels = $4, conditions = $5, updated_at = NOW()`,
        [id, userId, priority, channels, conditions ? JSON.stringify(conditions) : null]
      );

      this.logger.info('Notification route set', { userId, priority, channels });

      return {
        id,
        userId,
        priority,
        channels,
        conditions,
        isActive: true,
        createdAt: new Date(),
        updatedAt: new Date(),
      };
    } catch (error) {
      this.logger.error('Failed to set notification route', { error, userId, priority });
      throw error;
    } finally {
      client.release();
    }
  }

  async getNotificationRoute(userId: string, priority: NotificationPriority): Promise<NotificationRoute | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT * FROM notification_routes WHERE user_id = $1 AND priority = $2`,
        [userId, priority]
      );

      if (result.rows.length === 0) {
        return null;
      }

      const row = result.rows[0];
      return {
        id: row.id,
        userId: row.user_id,
        priority: row.priority,
        channels: row.channels,
        conditions: this.normalizeConditions(row.conditions),
        isActive: row.is_active,
        createdAt: new Date(row.created_at),
        updatedAt: new Date(row.updated_at),
      };
    } catch (error) {
      this.logger.error('Failed to get notification route', { error, userId });
      throw error;
    } finally {
      client.release();
    }
  }

  async getUserRoutes(userId: string): Promise<NotificationRoute[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT * FROM notification_routes WHERE user_id = $1 ORDER BY priority`,
        [userId]
      );

      return result.rows.map(row => ({
        id: row.id,
        userId: row.user_id,
        priority: row.priority,
        channels: row.channels,
        conditions: this.normalizeConditions(row.conditions),
        isActive: row.is_active,
        createdAt: new Date(row.created_at),
        updatedAt: new Date(row.updated_at),
      }));
    } catch (error) {
      this.logger.error('Failed to get user routes', { error, userId });
      throw error;
    } finally {
      client.release();
    }
  }

  async routeNotification(userId: string, notificationId: string, content: string, priority: NotificationPriority = 'normal'): Promise<NotificationDelivery[]> {
    const client = await this.pool.connect();
    try {
      // Get user status
      const statusResult = await client.query(
        'SELECT current_status FROM user_status WHERE user_id = $1',
        [userId]
      );
      const userStatus = statusResult.rows[0]?.current_status || 'offline';

      // Get routing config
      const routeResult = await client.query(
        `SELECT channels, conditions FROM notification_routes WHERE user_id = $1 AND priority = $2 AND is_active = true`,
        [userId, priority]
      );

      let channels = ['ide', 'slack', 'matrix'] as NotificationChannel[];
      if (routeResult.rows.length > 0) {
        const route = routeResult.rows[0];
        const conditions = this.normalizeConditions(route.conditions);
        const matchingCondition = conditions.find(c => c.status === userStatus);
        if (matchingCondition) {
          channels = matchingCondition.channels;
        } else {
          channels = route.channels;
        }
      } else {
        // Default routing: IDE if online, Slack if away, Matrix if in meeting
        switch (userStatus) {
          case 'online':
          case 'idle':
            channels = ['ide'];
            break;
          case 'away':
            channels = ['slack'];
            break;
          case 'in-meeting':
            channels = ['matrix'];
            break;
          default:
            channels = ['email'];
        }
      }

      // Check deduplication
      const contentHash = require('crypto').createHash('sha256').update(content).digest('hex');
      const dedupResult = await client.query(
        `SELECT last_delivery_at FROM notification_dedup_cache WHERE user_id = $1 AND notification_hash = $2`,
        [userId, contentHash]
      );

      const deliveries: NotificationDelivery[] = [];

      if (dedupResult.rows.length === 0 || (Date.now() - new Date(dedupResult.rows[0].last_delivery_at).getTime()) > this.config.deduplicationWindow) {
        // Create delivery records
        for (const channel of channels) {
          const deliveryId = require('crypto').randomUUID();
          await client.query(
            `INSERT INTO notification_deliveries (id, user_id, notification_id, content, channel, status, max_attempts)
             VALUES ($1, $2, $3, $4, $5, 'pending', $6)`,
            [deliveryId, userId, notificationId, content, channel, this.config.maxDeliveryAttempts]
          );

          deliveries.push({
            id: deliveryId,
            userId,
            notificationId,
            content,
            channel,
            status: 'pending',
            attemptCount: 0,
            maxAttempts: this.config.maxDeliveryAttempts,
            createdAt: new Date(),
            updatedAt: new Date(),
          });
        }

        // Update dedup cache
        await client.query(
          `INSERT INTO notification_dedup_cache (user_id, notification_hash, last_delivery_at)
           VALUES ($1, $2, NOW())
           ON CONFLICT (user_id, notification_hash) DO UPDATE SET last_delivery_at = NOW()`,
          [userId, contentHash]
        );

        this.logger.info('Notification routed to channels', { userId, channels, priority });
        this.emit('notification-routed', { userId, channels, priority, timestamp: new Date() });
      }

      return deliveries;
    } catch (error) {
      this.logger.error('Failed to route notification', { error, userId, notificationId });
      throw error;
    } finally {
      client.release();
    }
  }

  async recordDelivery(deliveryId: string, success: boolean, failureReason?: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      const getResult = await client.query(
        'SELECT status, attempt_count, max_attempts FROM notification_deliveries WHERE id = $1',
        [deliveryId]
      );

      if (getResult.rows.length === 0) {
        throw new Error(`Delivery ${deliveryId} not found`);
      }

      const delivery = getResult.rows[0];
      const newAttemptCount = (delivery.attempt_count || 0) + 1;
      const newStatus = success ? 'sent' : (newAttemptCount >= delivery.max_attempts ? 'failed' : 'pending');

      await client.query(
        `UPDATE notification_deliveries
         SET status = $1, attempt_count = $2, sent_at = $3, failure_reason = $4, updated_at = NOW()
         WHERE id = $5`,
        [newStatus, newAttemptCount, success ? new Date() : null, failureReason || null, deliveryId]
      );

      // Record history
      await client.query(
        `INSERT INTO notification_delivery_history (delivery_id, status_from, status_to, reason, attempt_number)
         VALUES ($1, $2, $3, $4, $5)`,
        [deliveryId, delivery.status, newStatus, failureReason, newAttemptCount]
      );

      await client.query('COMMIT');
      this.logger.info('Delivery recorded', { deliveryId, success, status: newStatus });
    } catch (error) {
      await client.query('ROLLBACK');
      this.logger.error('Failed to record delivery', { error, deliveryId });
      throw error;
    } finally {
      client.release();
    }
  }

  async markAsDelivered(deliveryId: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `UPDATE notification_deliveries SET status = 'delivered', delivered_at = NOW(), updated_at = NOW()
         WHERE id = $1`,
        [deliveryId]
      );

      this.logger.info('Delivery marked as delivered', { deliveryId });
    } catch (error) {
      this.logger.error('Failed to mark delivery as delivered', { error, deliveryId });
      throw error;
    } finally {
      client.release();
    }
  }

  async markAsRead(deliveryId: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `UPDATE notification_deliveries SET status = 'read', read_at = NOW(), updated_at = NOW()
         WHERE id = $1`,
        [deliveryId]
      );

      this.logger.info('Delivery marked as read', { deliveryId });
    } catch (error) {
      this.logger.error('Failed to mark delivery as read', { error, deliveryId });
      throw error;
    } finally {
      client.release();
    }
  }

  async getPendingDeliveries(limit: number = 10): Promise<NotificationDelivery[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT * FROM notification_deliveries WHERE status = 'pending' AND attempt_count < max_attempts
         ORDER BY created_at ASC LIMIT $1`,
        [limit]
      );

      return result.rows.map(row => ({
        id: row.id,
        userId: row.user_id,
        notificationId: row.notification_id,
        content: row.content,
        channel: row.channel,
        status: row.status,
        attemptCount: row.attempt_count,
        maxAttempts: row.max_attempts,
        sentAt: row.sent_at ? new Date(row.sent_at) : undefined,
        deliveredAt: row.delivered_at ? new Date(row.delivered_at) : undefined,
        readAt: row.read_at ? new Date(row.read_at) : undefined,
        failureReason: row.failure_reason,
        createdAt: new Date(row.created_at),
        updatedAt: new Date(row.updated_at),
      }));
    } catch (error) {
      this.logger.error('Failed to get pending deliveries', { error });
      throw error;
    } finally {
      client.release();
    }
  }

  async getDeliveryHistory(deliveryId: string): Promise<any[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT * FROM notification_delivery_history WHERE delivery_id = $1 ORDER BY created_at ASC`,
        [deliveryId]
      );

      return result.rows.map(row => ({
        id: row.id,
        deliveryId: row.delivery_id,
        statusFrom: row.status_from,
        statusTo: row.status_to,
        reason: row.reason,
        attemptNumber: row.attempt_number,
        createdAt: new Date(row.created_at),
      }));
    } catch (error) {
      this.logger.error('Failed to get delivery history', { error, deliveryId });
      throw error;
    } finally {
      client.release();
    }
  }

  private normalizeConditions(value: unknown): RoutingCondition[] {
    if (!value) {
      return [];
    }

    if (Array.isArray(value)) {
      return value as RoutingCondition[];
    }

    if (typeof value === 'string') {
      try {
        const parsed = JSON.parse(value);
        return Array.isArray(parsed) ? (parsed as RoutingCondition[]) : [];
      } catch {
        return [];
      }
    }

    return [];
  }
}