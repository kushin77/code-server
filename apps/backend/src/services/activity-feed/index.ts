#!/usr/bin/env node
// @file        apps/backend/src/services/activity-feed/index.ts
// @module      collaboration/activity-feed
// @description Real-time activity feed service with filtering and deep links
// @owner       collab-4.5
// @status      active

import { EventEmitter } from 'events';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger';

export type ActivityType = 'commit' | 'pr' | 'deploy' | 'test-flake' | 'comment' | 'review' | 'merge';
export type ActivityStatus = 'success' | 'failure' | 'warning' | 'info' | 'pending';

export interface Activity {
  id: string;
  type: ActivityType;
  status: ActivityStatus;
  title: string;
  description?: string;
  deepLink?: string;
  userId?: string;
  repository?: string;
  timestamp: Date;
  metadata?: Record<string, any>;
  tags?: string[];
}

export interface ActivityFilter {
  types?: ActivityType[];
  statuses?: ActivityStatus[];
  userId?: string;
  repository?: string;
  search?: string;
  tags?: string[];
  startDate?: Date;
  endDate?: Date;
}

export interface ActivityStats {
  totalActivities: number;
  byType: Record<ActivityType, number>;
  byStatus: Record<ActivityStatus, number>;
  lastActivity: Activity | null;
  uniqueUsers: number;
  repositories: string[];
}

export interface ActivitySubscription {
  id: string;
  userId: string;
  filters: ActivityFilter;
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export interface ActivityConfig {
  maxHistoryDays?: number;
  batchSize?: number;
}

export class ActivityFeedService extends EventEmitter {
  private pool: Pool;
  private logger = getLogger('ActivityFeedService');
  private initialized = false;
  private config: Required<ActivityConfig>;

  constructor(pool: Pool, config: ActivityConfig = {}) {
    super();
    this.pool = pool;
    this.config = {
      maxHistoryDays: config.maxHistoryDays || 7,
      batchSize: config.batchSize || 50,
    };
  }

  async initialize(): Promise<void> {
    if (this.initialized) return;

    try {
      await this.createTables();
      this.initialized = true;
      this.logger.info('Activity feed database schema initialized');
    } catch (error) {
      this.logger.error('Failed to initialize activity feed schema', { error });
      throw error;
    }
  }

  private async createTables(): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // Activities table
      await client.query(`
        CREATE TABLE IF NOT EXISTS activities (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          type TEXT NOT NULL CHECK (type IN ('commit', 'pr', 'deploy', 'test-flake', 'comment', 'review', 'merge')),
          status TEXT NOT NULL CHECK (status IN ('success', 'failure', 'warning', 'info', 'pending')),
          title TEXT NOT NULL,
          description TEXT,
          deep_link TEXT,
          user_id TEXT,
          repository TEXT,
          timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
          metadata JSONB,
          tags TEXT[],
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);

      // Activity subscriptions
      await client.query(`
        CREATE TABLE IF NOT EXISTS activity_subscriptions (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id TEXT NOT NULL,
          filters JSONB NOT NULL,
          is_active BOOLEAN DEFAULT true,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          UNIQUE(user_id, filters)
        )
      `);

      // Activity notifications log
      await client.query(`
        CREATE TABLE IF NOT EXISTS activity_notifications (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
          subscription_id UUID NOT NULL REFERENCES activity_subscriptions(id) ON DELETE CASCADE,
          sent_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          read_at TIMESTAMP WITH TIME ZONE
        )
      `);

      // Activity search index
      await client.query(`
        CREATE TABLE IF NOT EXISTS activity_search_index (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
          search_text TEXT,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);

      // Indexes
      await client.query(`
        CREATE INDEX IF NOT EXISTS idx_activities_type ON activities(type);
        CREATE INDEX IF NOT EXISTS idx_activities_status ON activities(status);
        CREATE INDEX IF NOT EXISTS idx_activities_timestamp ON activities(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_activities_user ON activities(user_id);
        CREATE INDEX IF NOT EXISTS idx_activities_repository ON activities(repository);
        CREATE INDEX IF NOT EXISTS idx_activities_tags ON activities USING GIN(tags);
        CREATE INDEX IF NOT EXISTS idx_subscriptions_user ON activity_subscriptions(user_id);
        CREATE INDEX IF NOT EXISTS idx_subscriptions_active ON activity_subscriptions(is_active);
        CREATE INDEX IF NOT EXISTS idx_notifications_activity ON activity_notifications(activity_id);
        CREATE INDEX IF NOT EXISTS idx_notifications_subscription ON activity_notifications(subscription_id);
        CREATE INDEX IF NOT EXISTS idx_search_text ON activity_search_index USING GIN(to_tsvector('english', search_text));
      `);

      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async recordActivity(
    type: ActivityType,
    title: string,
    status: ActivityStatus = 'info',
    options?: { description?: string; deepLink?: string; userId?: string; repository?: string; metadata?: any; tags?: string[] }
  ): Promise<Activity> {
    const client = await this.pool.connect();
    try {
      const id = require('crypto').randomUUID();
      const now = new Date();

      await client.query(
        `INSERT INTO activities (id, type, status, title, description, deep_link, user_id, repository, metadata, tags)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
        [
          id,
          type,
          status,
          title,
          options?.description || null,
          options?.deepLink || null,
          options?.userId || null,
          options?.repository || null,
          options?.metadata ? JSON.stringify(options.metadata) : null,
          options?.tags || [],
        ]
      );

      // Index for search
      const searchText = `${title} ${options?.description || ''}`.toLowerCase();
      await client.query(
        `INSERT INTO activity_search_index (activity_id, search_text) VALUES ($1, $2)`,
        [id, searchText]
      );

      this.logger.info('Activity recorded', { id, type, title });
      this.emit('activity', { id, type, status, title, timestamp: now });

      return {
        id,
        type,
        status,
        title,
        description: options?.description,
        deepLink: options?.deepLink,
        userId: options?.userId,
        repository: options?.repository,
        timestamp: now,
        metadata: options?.metadata,
        tags: options?.tags,
      };
    } catch (error) {
      this.logger.error('Failed to record activity', { error, type, title });
      throw error;
    } finally {
      client.release();
    }
  }

  async getActivity(activityId: string): Promise<Activity | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        'SELECT * FROM activities WHERE id = $1',
        [activityId]
      );

      if (result.rows.length === 0) {
        return null;
      }

      const row = result.rows[0];
      return {
        id: row.id,
        type: row.type,
        status: row.status,
        title: row.title,
        description: row.description,
        deepLink: row.deep_link,
        userId: row.user_id,
        repository: row.repository,
        timestamp: new Date(row.timestamp),
        metadata: row.metadata ? JSON.parse(row.metadata) : undefined,
        tags: row.tags,
      };
    } catch (error) {
      this.logger.error('Failed to get activity', { error, activityId });
      throw error;
    } finally {
      client.release();
    }
  }

  async getActivities(filter?: ActivityFilter, limit: number = 50): Promise<Activity[]> {
    const client = await this.pool.connect();
    try {
      let query = 'SELECT * FROM activities WHERE timestamp >= NOW() - INTERVAL \'1 day\' * $1';
      const params: any[] = [this.config.maxHistoryDays];

      if (filter?.types && filter.types.length > 0) {
        query += ` AND type = ANY($${params.length + 1})`;
        params.push(filter.types);
      }

      if (filter?.statuses && filter.statuses.length > 0) {
        query += ` AND status = ANY($${params.length + 1})`;
        params.push(filter.statuses);
      }

      if (filter?.userId) {
        query += ` AND user_id = $${params.length + 1}`;
        params.push(filter.userId);
      }

      if (filter?.repository) {
        query += ` AND repository = $${params.length + 1}`;
        params.push(filter.repository);
      }

      if (filter?.tags && filter.tags.length > 0) {
        query += ` AND tags && $${params.length + 1}`;
        params.push(filter.tags);
      }

      if (filter?.search) {
        query += ` AND id IN (
          SELECT activity_id FROM activity_search_index 
          WHERE search_text ILIKE $${params.length + 1}
        )`;
        params.push(`%${filter.search}%`);
      }

      if (filter?.startDate) {
        query += ` AND timestamp >= $${params.length + 1}`;
        params.push(filter.startDate);
      }

      if (filter?.endDate) {
        query += ` AND timestamp <= $${params.length + 1}`;
        params.push(filter.endDate);
      }

      query += ` ORDER BY timestamp DESC LIMIT $${params.length + 1}`;
      params.push(limit);

      const result = await client.query(query, params);

      return result.rows.map(row => ({
        id: row.id,
        type: row.type,
        status: row.status,
        title: row.title,
        description: row.description,
        deepLink: row.deep_link,
        userId: row.user_id,
        repository: row.repository,
        timestamp: new Date(row.timestamp),
        metadata: row.metadata ? JSON.parse(row.metadata) : undefined,
        tags: row.tags,
      }));
    } catch (error) {
      this.logger.error('Failed to get activities', { error });
      throw error;
    } finally {
      client.release();
    }
  }

  async getStats(filter?: ActivityFilter): Promise<ActivityStats> {
    const client = await this.pool.connect();
    try {
      let query = 'SELECT * FROM activities WHERE timestamp >= NOW() - INTERVAL \'1 day\' * $1';
      const params: any[] = [this.config.maxHistoryDays];

      if (filter?.types && filter.types.length > 0) {
        query += ` AND type = ANY($${params.length + 1})`;
        params.push(filter.types);
      }

      if (filter?.repository) {
        query += ` AND repository = $${params.length + 1}`;
        params.push(filter.repository);
      }

      const result = await client.query(query, params);
      const activities = result.rows;

      const byType: Record<ActivityType, number> = {
        commit: 0,
        pr: 0,
        deploy: 0,
        'test-flake': 0,
        comment: 0,
        review: 0,
        merge: 0,
      };

      const byStatus: Record<ActivityStatus, number> = {
        success: 0,
        failure: 0,
        warning: 0,
        info: 0,
        pending: 0,
      };

      const userSet = new Set<string>();
      const repoSet = new Set<string>();

      for (const activity of activities) {
        byType[activity.type]++;
        byStatus[activity.status]++;
        if (activity.user_id) userSet.add(activity.user_id);
        if (activity.repository) repoSet.add(activity.repository);
      }

      return {
        totalActivities: activities.length,
        byType,
        byStatus,
        lastActivity: activities.length > 0 ? {
          id: activities[0].id,
          type: activities[0].type,
          status: activities[0].status,
          title: activities[0].title,
          timestamp: new Date(activities[0].timestamp),
        } : null,
        uniqueUsers: userSet.size,
        repositories: Array.from(repoSet),
      };
    } catch (error) {
      this.logger.error('Failed to get stats', { error });
      throw error;
    } finally {
      client.release();
    }
  }

  async createSubscription(userId: string, filters: ActivityFilter): Promise<ActivitySubscription> {
    const client = await this.pool.connect();
    try {
      const id = require('crypto').randomUUID();

      await client.query(
        `INSERT INTO activity_subscriptions (id, user_id, filters)
         VALUES ($1, $2, $3)`,
        [id, userId, JSON.stringify(filters)]
      );

      this.logger.info('Activity subscription created', { userId, id });

      return {
        id,
        userId,
        filters,
        isActive: true,
        createdAt: new Date(),
        updatedAt: new Date(),
      };
    } catch (error) {
      this.logger.error('Failed to create subscription', { error, userId });
      throw error;
    } finally {
      client.release();
    }
  }

  async getSubscription(subscriptionId: string): Promise<ActivitySubscription | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        'SELECT * FROM activity_subscriptions WHERE id = $1',
        [subscriptionId]
      );

      if (result.rows.length === 0) {
        return null;
      }

      const row = result.rows[0];
      return {
        id: row.id,
        userId: row.user_id,
        filters: JSON.parse(row.filters),
        isActive: row.is_active,
        createdAt: new Date(row.created_at),
        updatedAt: new Date(row.updated_at),
      };
    } catch (error) {
      this.logger.error('Failed to get subscription', { error, subscriptionId });
      throw error;
    } finally {
      client.release();
    }
  }

  async getUserSubscriptions(userId: string): Promise<ActivitySubscription[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        'SELECT * FROM activity_subscriptions WHERE user_id = $1 ORDER BY created_at DESC',
        [userId]
      );

      return result.rows.map(row => ({
        id: row.id,
        userId: row.user_id,
        filters: JSON.parse(row.filters),
        isActive: row.is_active,
        createdAt: new Date(row.created_at),
        updatedAt: new Date(row.updated_at),
      }));
    } catch (error) {
      this.logger.error('Failed to get user subscriptions', { error, userId });
      throw error;
    } finally {
      client.release();
    }
  }

  async deleteSubscription(subscriptionId: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        'DELETE FROM activity_subscriptions WHERE id = $1',
        [subscriptionId]
      );

      this.logger.info('Subscription deleted', { subscriptionId });
    } catch (error) {
      this.logger.error('Failed to delete subscription', { error, subscriptionId });
      throw error;
    } finally {
      client.release();
    }
  }

  async notifySubscribers(activityId: string): Promise<number> {
    const client = await this.pool.connect();
    try {
      const activity = await this.getActivity(activityId);
      if (!activity) {
        throw new Error(`Activity ${activityId} not found`);
      }

      const result = await client.query(
        `SELECT id, filters FROM activity_subscriptions WHERE is_active = true`
      );

      let notifiedCount = 0;
      for (const subscription of result.rows) {
        const filters = JSON.parse(subscription.filters);

        // Check if activity matches filters
        if (this.matchesFilter(activity, filters)) {
          await client.query(
            `INSERT INTO activity_notifications (activity_id, subscription_id) VALUES ($1, $2)`,
            [activityId, subscription.id]
          );
          notifiedCount++;
        }
      }

      this.logger.info('Subscribers notified', { activityId, count: notifiedCount });
      return notifiedCount;
    } catch (error) {
      this.logger.error('Failed to notify subscribers', { error, activityId });
      throw error;
    } finally {
      client.release();
    }
  }

  private matchesFilter(activity: Activity, filter: ActivityFilter): boolean {
    if (filter.types && !filter.types.includes(activity.type)) return false;
    if (filter.statuses && !filter.statuses.includes(activity.status)) return false;
    if (filter.userId && activity.userId !== filter.userId) return false;
    if (filter.repository && activity.repository !== filter.repository) return false;
    if (filter.tags && (!activity.tags || !activity.tags.some(t => filter.tags?.includes(t)))) return false;
    return true;
  }

  async getPendingNotifications(subscriptionId: string, limit: number = 10): Promise<Activity[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT a.* FROM activities a
         INNER JOIN activity_notifications n ON a.id = n.activity_id
         WHERE n.subscription_id = $1 AND n.read_at IS NULL
         ORDER BY a.timestamp DESC LIMIT $2`,
        [subscriptionId, limit]
      );

      return result.rows.map(row => ({
        id: row.id,
        type: row.type,
        status: row.status,
        title: row.title,
        description: row.description,
        deepLink: row.deep_link,
        userId: row.user_id,
        repository: row.repository,
        timestamp: new Date(row.timestamp),
        metadata: row.metadata ? JSON.parse(row.metadata) : undefined,
        tags: row.tags,
      }));
    } catch (error) {
      this.logger.error('Failed to get pending notifications', { error, subscriptionId });
      throw error;
    } finally {
      client.release();
    }
  }

  async markNotificationAsRead(activityId: string, subscriptionId: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `UPDATE activity_notifications SET read_at = NOW()
         WHERE activity_id = $1 AND subscription_id = $2`,
        [activityId, subscriptionId]
      );

      this.logger.info('Notification marked as read', { activityId, subscriptionId });
    } catch (error) {
      this.logger.error('Failed to mark notification as read', { error });
      throw error;
    } finally {
      client.release();
    }
  }
}