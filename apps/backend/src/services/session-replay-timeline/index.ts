#!/usr/bin/env bash
/**
 * @file        apps/backend/src/services/session-replay-timeline/index.ts
 * @module      services/analytics
 * @description Session replay timeline with event log, deployment overlays, and full JSON event details
 */

import { EventEmitter } from 'events';
import { Pool, PoolClient } from 'pg';
import { getLogger } from '../../lib/logger';

export interface TimelineEvent {
  id: string;
  sessionId: string;
  eventType: string;
  timestamp: Date;
  eventData: Record<string, any>;
  userAction?: string;
  ipAddress?: string;
  userAgent?: string;
}

export interface DeploymentOverlay {
  id: string;
  deploymentTime: Date;
  version: string;
  environment: string;
  changesSummary?: string;
}

export interface SessionReplay {
  sessionId: string;
  userId: string;
  startTime: Date;
  endTime?: Date;
  duration?: number;
  eventCount: number;
  events: TimelineEvent[];
  deployments: DeploymentOverlay[];
}

export interface TimelineQuery {
  sessionId: string;
  startTime?: Date;
  endTime?: Date;
  eventTypes?: string[];
  limit?: number;
}

export class SessionReplayTimelineService extends EventEmitter {
  private logger = getLogger('SessionReplayTimelineService');
  private pool: Pool;

  constructor(pool: Pool) {
    super();
    this.pool = pool;
  }

  async initialize(): Promise<void> {
    this.logger.info('Initializing SessionReplayTimelineService');
    await this.createTables();
  }

  private async createTables(): Promise<void> {
    const client = await this.pool.connect();
    try {
      // Create session_replay_timeline table
      await client.query(`
        CREATE TABLE IF NOT EXISTS session_replay_timeline (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          session_id UUID NOT NULL,
          user_id UUID NOT NULL,
          event_type VARCHAR(255) NOT NULL,
          event_data JSONB NOT NULL,
          user_action VARCHAR(255),
          ip_address INET,
          user_agent TEXT,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create session_replay_sessions table
      await client.query(`
        CREATE TABLE IF NOT EXISTS session_replay_sessions (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID NOT NULL,
          start_time TIMESTAMP NOT NULL,
          end_time TIMESTAMP,
          duration_seconds INTEGER,
          event_count INTEGER DEFAULT 0,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create deployment_overlays table
      await client.query(`
        CREATE TABLE IF NOT EXISTS deployment_overlays (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          deployment_time TIMESTAMP NOT NULL,
          version VARCHAR(255) NOT NULL,
          environment VARCHAR(255) NOT NULL,
          changes_summary TEXT,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create indexes
      await client.query(`CREATE INDEX IF NOT EXISTS idx_session_replay_timeline_session_id ON session_replay_timeline(session_id)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_session_replay_timeline_event_type ON session_replay_timeline(event_type)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_session_replay_timeline_created_at ON session_replay_timeline(created_at DESC)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_session_replay_sessions_user_id ON session_replay_sessions(user_id)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_deployment_overlays_deployment_time ON deployment_overlays(deployment_time DESC)`);

      this.logger.info('Session replay timeline tables created successfully');
    } finally {
      client.release();
    }
  }

  async recordEvent(sessionId: string, userId: string, eventType: string, eventData: Record<string, any>, userAction?: string, ipAddress?: string, userAgent?: string): Promise<TimelineEvent> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `INSERT INTO session_replay_timeline (session_id, user_id, event_type, event_data, user_action, ip_address, user_agent)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING id, session_id, event_type, EXTRACT(EPOCH FROM created_at) as timestamp, event_data, user_action, ip_address, user_agent`,
        [sessionId, userId, eventType, JSON.stringify(eventData), userAction, ipAddress, userAgent]
      );

      const event = result.rows[0];
      this.emit('event-recorded', { sessionId, eventType, timestamp: new Date(event.timestamp * 1000) });
      
      return {
        id: event.id,
        sessionId: event.session_id,
        eventType: event.event_type,
        timestamp: new Date(event.timestamp * 1000),
        eventData: event.event_data,
        userAction: event.user_action,
        ipAddress: event.ip_address,
        userAgent: event.user_agent
      };
    } finally {
      client.release();
    }
  }

  async getSessionReplay(sessionId: string, query?: TimelineQuery): Promise<SessionReplay | null> {
    const client = await this.pool.connect();
    try {
      // Get session metadata
      const sessionResult = await client.query(
        `SELECT id, user_id, start_time, end_time, duration_seconds, event_count
         FROM session_replay_sessions
         WHERE id = $1`,
        [sessionId]
      );

      if (sessionResult.rows.length === 0) {
        return null;
      }

      const session = sessionResult.rows[0];

      // Get events for session
      let eventQuery = `
        SELECT id, session_id, event_type, EXTRACT(EPOCH FROM created_at) as timestamp, 
               event_data, user_action, ip_address, user_agent
        FROM session_replay_timeline
        WHERE session_id = $1
      `;
      const params: any[] = [sessionId];
      let paramIndex = 2;

      if (query?.eventTypes && query.eventTypes.length > 0) {
        eventQuery += ` AND event_type = ANY($${paramIndex})`;
        params.push(query.eventTypes);
        paramIndex++;
      }

      if (query?.startTime) {
        eventQuery += ` AND created_at >= $${paramIndex}`;
        params.push(query.startTime);
        paramIndex++;
      }

      if (query?.endTime) {
        eventQuery += ` AND created_at <= $${paramIndex}`;
        params.push(query.endTime);
        paramIndex++;
      }

      eventQuery += ` ORDER BY created_at ASC`;
      if (query?.limit) {
        eventQuery += ` LIMIT $${paramIndex}`;
        params.push(query.limit);
      }

      const eventsResult = await client.query(eventQuery, params);

      const events = eventsResult.rows.map(row => ({
        id: row.id,
        sessionId: row.session_id,
        eventType: row.event_type,
        timestamp: new Date(row.timestamp * 1000),
        eventData: row.event_data,
        userAction: row.user_action,
        ipAddress: row.ip_address,
        userAgent: row.user_agent
      }));

      // Get deployment overlays
      const deploymentResult = await client.query(
        `SELECT id, deployment_time, version, environment, changes_summary
         FROM deployment_overlays
         WHERE deployment_time >= $1 AND deployment_time <= $2
         ORDER BY deployment_time ASC`,
        [session.start_time, session.end_time || new Date()]
      );

      const deployments = deploymentResult.rows.map(row => ({
        id: row.id,
        deploymentTime: new Date(row.deployment_time),
        version: row.version,
        environment: row.environment,
        changesSummary: row.changes_summary
      }));

      return {
        sessionId,
        userId: session.user_id,
        startTime: new Date(session.start_time),
        endTime: session.end_time ? new Date(session.end_time) : undefined,
        duration: session.duration_seconds,
        eventCount: session.event_count,
        events,
        deployments
      };
    } finally {
      client.release();
    }
  }

  async createSession(userId: string, startTime: Date): Promise<string> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `INSERT INTO session_replay_sessions (user_id, start_time)
         VALUES ($1, $2)
         RETURNING id`,
        [userId, startTime]
      );
      
      const sessionId = result.rows[0].id;
      this.emit('session-created', { sessionId, userId });
      return sessionId;
    } finally {
      client.release();
    }
  }

  async endSession(sessionId: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      const now = new Date();
      
      // Get start time to calculate duration
      const startResult = await client.query(
        `SELECT start_time FROM session_replay_sessions WHERE id = $1`,
        [sessionId]
      );

      if (startResult.rows.length === 0) return;

      const startTime = new Date(startResult.rows[0].start_time);
      const duration = Math.floor((now.getTime() - startTime.getTime()) / 1000);

      // Count events
      const countResult = await client.query(
        `SELECT COUNT(*) as count FROM session_replay_timeline WHERE session_id = $1`,
        [sessionId]
      );

      const eventCount = countResult.rows[0].count;

      await client.query(
        `UPDATE session_replay_sessions
         SET end_time = $1, duration_seconds = $2, event_count = $3
         WHERE id = $4`,
        [now, duration, eventCount, sessionId]
      );

      this.emit('session-ended', { sessionId, duration, eventCount });
    } finally {
      client.release();
    }
  }

  async recordDeployment(deploymentTime: Date, version: string, environment: string, changesSummary?: string): Promise<DeploymentOverlay> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `INSERT INTO deployment_overlays (deployment_time, version, environment, changes_summary)
         VALUES ($1, $2, $3, $4)
         RETURNING id, deployment_time, version, environment, changes_summary`,
        [deploymentTime, version, environment, changesSummary]
      );

      const deployment = result.rows[0];
      this.emit('deployment-recorded', { version, environment });

      return {
        id: deployment.id,
        deploymentTime: new Date(deployment.deployment_time),
        version: deployment.version,
        environment: deployment.environment,
        changesSummary: deployment.changes_summary
      };
    } finally {
      client.release();
    }
  }

  async getEventDetail(eventId: string): Promise<TimelineEvent | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT id, session_id, event_type, EXTRACT(EPOCH FROM created_at) as timestamp, 
                event_data, user_action, ip_address, user_agent
         FROM session_replay_timeline
         WHERE id = $1`,
        [eventId]
      );

      if (result.rows.length === 0) return null;

      const row = result.rows[0];
      return {
        id: row.id,
        sessionId: row.session_id,
        eventType: row.event_type,
        timestamp: new Date(row.timestamp * 1000),
        eventData: row.event_data,
        userAction: row.user_action,
        ipAddress: row.ip_address,
        userAgent: row.user_agent
      };
    } finally {
      client.release();
    }
  }

  async cleanupOldSessions(daysOld: number = 30): Promise<number> {
    const client = await this.pool.connect();
    try {
      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - daysOld);

      // Delete old events
      await client.query(
        `DELETE FROM session_replay_timeline
         WHERE created_at < $1`,
        [cutoffDate]
      );

      // Delete old sessions
      const result = await client.query(
        `DELETE FROM session_replay_sessions
         WHERE start_time < $1
         RETURNING id`,
        [cutoffDate]
      );

      const deletedCount = result.rows.length;
      this.emit('sessions-cleaned', { count: deletedCount, daysOld });
      
      return deletedCount;
    } finally {
      client.release();
    }
  }
}

export async function initializeSessionReplayTimelineRoutes(service: SessionReplayTimelineService) {
  const { Router } = require('express');
  const router = Router();
  const logger = getLogger('SessionReplayTimelineRoutes');

  router.post('/api/sessions/:sessionId/events', async (req, res) => {
    try {
      const { sessionId } = req.params;
      const { eventType, eventData, userAction, ipAddress, userAgent } = req.body;
      const userId = req.user?.id || req.body.userId;

      const event = await service.recordEvent(sessionId, userId, eventType, eventData, userAction, ipAddress, userAgent);
      res.json(event);
    } catch (error) {
      logger.error('Failed to record event', error);
      res.status(500).json({ error: 'Failed to record event' });
    }
  });

  router.get('/api/sessions/:sessionId/replay', async (req, res) => {
    try {
      const { sessionId } = req.params;
      const replay = await service.getSessionReplay(sessionId);
      
      if (!replay) {
        return res.status(404).json({ error: 'Session not found' });
      }

      res.json(replay);
    } catch (error) {
      logger.error('Failed to get session replay', error);
      res.status(500).json({ error: 'Failed to get session replay' });
    }
  });

  router.post('/api/sessions', async (req, res) => {
    try {
      const { userId, startTime } = req.body;
      const sessionId = await service.createSession(userId, new Date(startTime));
      res.json({ sessionId });
    } catch (error) {
      logger.error('Failed to create session', error);
      res.status(500).json({ error: 'Failed to create session' });
    }
  });

  router.post('/api/sessions/:sessionId/end', async (req, res) => {
    try {
      const { sessionId } = req.params;
      await service.endSession(sessionId);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to end session', error);
      res.status(500).json({ error: 'Failed to end session' });
    }
  });

  router.get('/api/events/:eventId', async (req, res) => {
    try {
      const { eventId } = req.params;
      const event = await service.getEventDetail(eventId);
      
      if (!event) {
        return res.status(404).json({ error: 'Event not found' });
      }

      res.json(event);
    } catch (error) {
      logger.error('Failed to get event detail', error);
      res.status(500).json({ error: 'Failed to get event detail' });
    }
  });

  router.post('/api/deployments', async (req, res) => {
    try {
      const { deploymentTime, version, environment, changesSummary } = req.body;
      const deployment = await service.recordDeployment(new Date(deploymentTime), version, environment, changesSummary);
      res.json(deployment);
    } catch (error) {
      logger.error('Failed to record deployment', error);
      res.status(500).json({ error: 'Failed to record deployment' });
    }
  });

  router.post('/api/sessions/cleanup', async (req, res) => {
    try {
      const { daysOld } = req.body;
      const count = await service.cleanupOldSessions(daysOld || 30);
      res.json({ cleanedCount: count });
    } catch (error) {
      logger.error('Failed to cleanup sessions', error);
      res.status(500).json({ error: 'Failed to cleanup sessions' });
    }
  });

  return router;
}
