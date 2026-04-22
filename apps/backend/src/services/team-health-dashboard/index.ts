#!/usr/bin/env node
/**
 * @file        apps/backend/src/services/team-health-dashboard/index.ts
 * @module      services/collaboration
 * @description Team health metrics with flow time, pair frequency, review latency, AI utilization
 */

import { EventEmitter } from 'events';
import { Pool, PoolClient } from 'pg';
import { getLogger } from '../../lib/logger';

export interface TeamHealthMetrics {
  teamId: string;
  averageFlowTime: number;
  pairingFrequency: number;
  reviewLatency: number;
  aiUtilization: number;
  collaborationIndex: number;
  healthScore: number;
  generatedAt: Date;
}

export interface WeeklyDigest {
  teamId: string;
  week: string;
  metrics: TeamHealthMetrics;
  topPairs: Array<{ user1: string; user2: string; sessions: number }>;
  slowReviews: Array<{ pullRequestId: string; latency: number }>;
  aiTrends: { usage: number; impactScore: number };
  summary: string;
}

export class TeamHealthDashboardService extends EventEmitter {
  private logger = getLogger('TeamHealthDashboardService');
  private pool: Pool;

  constructor(pool: Pool) {
    super();
    this.pool = pool;
  }

  async initialize(): Promise<void> {
    this.logger.info('Initializing TeamHealthDashboardService');
    await this.createTables();
  }

  private async createTables(): Promise<void> {
    const client = await this.pool.connect();
    try {
      // Create team_health_metrics table
      await client.query(`
        CREATE TABLE IF NOT EXISTS team_health_metrics (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          team_id UUID NOT NULL,
          average_flow_time_mins FLOAT,
          pairing_frequency FLOAT,
          review_latency_hours FLOAT,
          ai_utilization_percent FLOAT,
          collaboration_index FLOAT,
          health_score FLOAT,
          generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create team_pairing_sessions table
      await client.query(`
        CREATE TABLE IF NOT EXISTS team_pairing_sessions (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          team_id UUID NOT NULL,
          user_id_1 UUID NOT NULL,
          user_id_2 UUID NOT NULL,
          session_duration_mins FLOAT,
          started_at TIMESTAMP,
          ended_at TIMESTAMP
        )
      `);

      // Create code_review_metrics table
      await client.query(`
        CREATE TABLE IF NOT EXISTS code_review_metrics (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          team_id UUID NOT NULL,
          pull_request_id UUID NOT NULL,
          reviewer_id UUID NOT NULL,
          time_to_first_review_mins FLOAT,
          total_review_time_mins FLOAT,
          reviewed_at TIMESTAMP
        )
      `);

      // Create ai_utilization_tracking table
      await client.query(`
        CREATE TABLE IF NOT EXISTS ai_utilization_tracking (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          team_id UUID NOT NULL,
          user_id UUID NOT NULL,
          ai_command VARCHAR(255),
          used_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create flow_time_tracking table
      await client.query(`
        CREATE TABLE IF NOT EXISTS flow_time_tracking (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          team_id UUID NOT NULL,
          user_id UUID NOT NULL,
          activity_type VARCHAR(50),
          duration_mins FLOAT,
          recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create weekly_digests table
      await client.query(`
        CREATE TABLE IF NOT EXISTS weekly_digests (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          team_id UUID NOT NULL,
          week_start_date DATE,
          metrics JSONB,
          top_pairs JSONB,
          slow_reviews JSONB,
          ai_trends JSONB,
          summary TEXT,
          generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create indexes
      await client.query(`CREATE INDEX IF NOT EXISTS idx_team_health_metrics_team_id ON team_health_metrics(team_id, generated_at DESC)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_pairing_sessions_team_id ON team_pairing_sessions(team_id)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_code_review_team_id ON code_review_metrics(team_id)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_ai_utilization_team_id ON ai_utilization_tracking(team_id)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_flow_time_team_id ON flow_time_tracking(team_id)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_weekly_digests_team_id ON weekly_digests(team_id)`);

      this.logger.info('Team health dashboard tables created successfully');
    } finally {
      client.release();
    }
  }

  async recordFlowTime(teamId: string, userId: string, activityType: string, durationMins: number): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO flow_time_tracking (team_id, user_id, activity_type, duration_mins) VALUES ($1, $2, $3, $4)`,
        [teamId, userId, activityType, durationMins]
      );

      this.emit('flow-time-recorded', { teamId, userId, durationMins });
    } finally {
      client.release();
    }
  }

  async recordPairingSession(teamId: string, userId1: string, userId2: string, durationMins: number): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO team_pairing_sessions (team_id, user_id_1, user_id_2, session_duration_mins, started_at, ended_at)
         VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '1 minute' * $4)`,
        [teamId, userId1, userId2, durationMins]
      );

      this.emit('pairing-recorded', { teamId, userId1, userId2, durationMins });
    } finally {
      client.release();
    }
  }

  async recordCodeReviewMetrics(teamId: string, pullRequestId: string, reviewerId: string, timeToFirstReviewMins: number, totalReviewTimeMins: number): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO code_review_metrics (team_id, pull_request_id, reviewer_id, time_to_first_review_mins, total_review_time_mins)
         VALUES ($1, $2, $3, $4, $5)`,
        [teamId, pullRequestId, reviewerId, timeToFirstReviewMins, totalReviewTimeMins]
      );

      this.emit('review-recorded', { teamId, pullRequestId, timeToFirstReviewMins });
    } finally {
      client.release();
    }
  }

  async recordAIUtilization(teamId: string, userId: string, aiCommand: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO ai_utilization_tracking (team_id, user_id, ai_command) VALUES ($1, $2, $3)`,
        [teamId, userId, aiCommand]
      );
    } finally {
      client.release();
    }
  }

  async calculateTeamHealthMetrics(teamId: string): Promise<TeamHealthMetrics> {
    const client = await this.pool.connect();
    try {
      // Calculate average flow time
      const flowResult = await client.query(
        `SELECT AVG(duration_mins) as avg_flow_time FROM flow_time_tracking WHERE team_id = $1 AND recorded_at > NOW() - INTERVAL '7 days'`,
        [teamId]
      );
      const avgFlowTime = flowResult.rows[0]?.avg_flow_time || 0;

      // Calculate pairing frequency
      const pairingResult = await client.query(
        `SELECT COUNT(*) as pair_count FROM team_pairing_sessions WHERE team_id = $1 AND started_at > NOW() - INTERVAL '7 days'`,
        [teamId]
      );
      const pairingFreq = pairingResult.rows[0]?.pair_count || 0;

      // Calculate review latency
      const reviewResult = await client.query(
        `SELECT AVG(time_to_first_review_mins) as avg_latency FROM code_review_metrics WHERE team_id = $1 AND reviewed_at > NOW() - INTERVAL '7 days'`,
        [teamId]
      );
      const reviewLatency = (reviewResult.rows[0]?.avg_latency || 0) / 60; // Convert to hours

      // Calculate AI utilization
      const aiResult = await client.query(
        `SELECT COUNT(*) as ai_uses FROM ai_utilization_tracking WHERE team_id = $1 AND used_at > NOW() - INTERVAL '7 days'`,
        [teamId]
      );
      const aiUsageCount = aiResult.rows[0]?.ai_uses || 0;

      // Calculate collaboration index (0-100)
      const collaborationIndex = Math.min(100, (pairingFreq * 2) + (aiUsageCount * 0.5));

      // Calculate overall health score
      const healthScore = Math.min(100,
        (100 - Math.min(avgFlowTime, 100)) * 0.3 +
        (pairingFreq > 0 ? 100 : 0) * 0.2 +
        (100 - Math.min(reviewLatency, 100)) * 0.3 +
        (aiUsageCount > 0 ? 100 : 0) * 0.2
      );

      const metrics: TeamHealthMetrics = {
        teamId,
        averageFlowTime: avgFlowTime,
        pairingFrequency: pairingFreq,
        reviewLatency,
        aiUtilization: (aiUsageCount / Math.max(1, pairingFreq + 1)) * 100,
        collaborationIndex,
        healthScore,
        generatedAt: new Date()
      };

      // Store metrics
      await client.query(
        `INSERT INTO team_health_metrics (team_id, average_flow_time_mins, pairing_frequency, review_latency_hours, ai_utilization_percent, collaboration_index, health_score)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [teamId, avgFlowTime, pairingFreq, reviewLatency, metrics.aiUtilization, collaborationIndex, healthScore]
      );

      this.emit('metrics-calculated', { teamId, healthScore });

      return metrics;
    } finally {
      client.release();
    }
  }

  async getLatestMetrics(teamId: string): Promise<TeamHealthMetrics | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT team_id, average_flow_time_mins, pairing_frequency, review_latency_hours, ai_utilization_percent, collaboration_index, health_score, generated_at
         FROM team_health_metrics
         WHERE team_id = $1
         ORDER BY generated_at DESC
         LIMIT 1`,
        [teamId]
      );

      if (result.rows.length === 0) return null;

      const row = result.rows[0];
      return {
        teamId: row.team_id,
        averageFlowTime: row.average_flow_time_mins,
        pairingFrequency: row.pairing_frequency,
        reviewLatency: row.review_latency_hours,
        aiUtilization: row.ai_utilization_percent,
        collaborationIndex: row.collaboration_index,
        healthScore: row.health_score,
        generatedAt: row.generated_at
      };
    } finally {
      client.release();
    }
  }

  async generateWeeklyDigest(teamId: string): Promise<WeeklyDigest> {
    const client = await this.pool.connect();
    try {
      const metrics = await this.calculateTeamHealthMetrics(teamId);

      // Get top pairing combinations
      const pairingResult = await client.query(
        `SELECT user_id_1, user_id_2, COUNT(*) as sessions FROM team_pairing_sessions
         WHERE team_id = $1 AND started_at > NOW() - INTERVAL '7 days'
         GROUP BY user_id_1, user_id_2
         ORDER BY sessions DESC
         LIMIT 5`,
        [teamId]
      );
      const topPairs = pairingResult.rows.map(r => ({
        user1: r.user_id_1,
        user2: r.user_id_2,
        sessions: r.sessions
      }));

      // Get slow reviews
      const reviewResult = await client.query(
        `SELECT pull_request_id, time_to_first_review_mins FROM code_review_metrics
         WHERE team_id = $1 AND reviewed_at > NOW() - INTERVAL '7 days'
         ORDER BY time_to_first_review_mins DESC
         LIMIT 5`,
        [teamId]
      );
      const slowReviews = reviewResult.rows.map(r => ({
        pullRequestId: r.pull_request_id,
        latency: r.time_to_first_review_mins
      }));

      // AI trends
      const aiTrends = {
        usage: (metrics.aiUtilization || 0),
        impactScore: (metrics.healthScore * 0.8) // AI impact on health
      };

      // Generate summary
      const summary = this.generateSummaryText(metrics, topPairs, slowReviews);

      const digest: WeeklyDigest = {
        teamId,
        week: new Date().toISOString().split('T')[0],
        metrics,
        topPairs,
        slowReviews,
        aiTrends,
        summary
      };

      // Store digest
      await client.query(
        `INSERT INTO weekly_digests (team_id, week_start_date, metrics, top_pairs, slow_reviews, ai_trends, summary)
         VALUES ($1, CURRENT_DATE, $2, $3, $4, $5, $6)`,
        [teamId, JSON.stringify(metrics), JSON.stringify(topPairs), JSON.stringify(slowReviews), JSON.stringify(aiTrends), summary]
      );

      this.emit('digest-generated', { teamId, healthScore: metrics.healthScore });

      return digest;
    } finally {
      client.release();
    }
  }

  private generateSummaryText(metrics: TeamHealthMetrics, topPairs: any[], slowReviews: any[]): string {
    let summary = `Team Health Report\n\n`;
    summary += `Overall Health Score: ${metrics.healthScore.toFixed(1)}/100\n`;
    summary += `Average Flow Time: ${metrics.averageFlowTime.toFixed(1)} minutes\n`;
    summary += `Pairing Sessions (7d): ${metrics.pairingFrequency}\n`;
    summary += `Review Latency: ${metrics.reviewLatency.toFixed(1)} hours\n`;
    summary += `AI Utilization: ${metrics.aiUtilization.toFixed(1)}%\n`;
    summary += `Collaboration Index: ${metrics.collaborationIndex.toFixed(1)}\n`;

    if (topPairs.length > 0) {
      summary += `\nTop Pairing Pairs: ${topPairs.map(p => `${p.user1}-${p.user2}`).join(', ')}\n`;
    }

    if (slowReviews.length > 0) {
      summary += `\nAreas for Improvement: Review latency averaging ${slowReviews[0].latency.toFixed(0)} minutes\n`;
    }

    return summary;
  }

  async getWeeklyDigest(teamId: string): Promise<WeeklyDigest | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT team_id, week_start_date, metrics, top_pairs, slow_reviews, ai_trends, summary, generated_at
         FROM weekly_digests
         WHERE team_id = $1
         ORDER BY generated_at DESC
         LIMIT 1`,
        [teamId]
      );

      if (result.rows.length === 0) return null;

      const row = result.rows[0];
      return {
        teamId: row.team_id,
        week: row.week_start_date,
        metrics: row.metrics,
        topPairs: row.top_pairs,
        slowReviews: row.slow_reviews,
        aiTrends: row.ai_trends,
        summary: row.summary
      };
    } finally {
      client.release();
    }
  }

  async getTeamHistory(teamId: string, days: number = 30): Promise<TeamHealthMetrics[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT team_id, average_flow_time_mins, pairing_frequency, review_latency_hours, ai_utilization_percent, collaboration_index, health_score, generated_at
         FROM team_health_metrics
         WHERE team_id = $1 AND generated_at > NOW() - INTERVAL '1 day' * $2
         ORDER BY generated_at DESC`,
        [teamId, days]
      );

      return result.rows.map(row => ({
        teamId: row.team_id,
        averageFlowTime: row.average_flow_time_mins,
        pairingFrequency: row.pairing_frequency,
        reviewLatency: row.review_latency_hours,
        aiUtilization: row.ai_utilization_percent,
        collaborationIndex: row.collaboration_index,
        healthScore: row.health_score,
        generatedAt: row.generated_at
      }));
    } finally {
      client.release();
    }
  }
}

export async function initializeTeamHealthDashboardRoutes(service: TeamHealthDashboardService) {
  const { Router } = require('express');
  const router = Router();
  const logger = getLogger('TeamHealthDashboardRoutes');

  router.post('/api/team-health/flow-time', async (req, res) => {
    try {
      const { teamId, userId, activityType, durationMins } = req.body;
      await service.recordFlowTime(teamId, userId, activityType, durationMins);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to record flow time', error);
      res.status(500).json({ error: 'Failed to record flow time' });
    }
  });

  router.post('/api/team-health/pairing', async (req, res) => {
    try {
      const { teamId, userId1, userId2, durationMins } = req.body;
      await service.recordPairingSession(teamId, userId1, userId2, durationMins);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to record pairing session', error);
      res.status(500).json({ error: 'Failed to record pairing session' });
    }
  });

  router.post('/api/team-health/review', async (req, res) => {
    try {
      const { teamId, pullRequestId, reviewerId, timeToFirstReviewMins, totalReviewTimeMins } = req.body;
      await service.recordCodeReviewMetrics(teamId, pullRequestId, reviewerId, timeToFirstReviewMins, totalReviewTimeMins);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to record review metrics', error);
      res.status(500).json({ error: 'Failed to record review metrics' });
    }
  });

  router.post('/api/team-health/ai-usage', async (req, res) => {
    try {
      const { teamId, userId, aiCommand } = req.body;
      await service.recordAIUtilization(teamId, userId, aiCommand);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to record AI usage', error);
      res.status(500).json({ error: 'Failed to record AI usage' });
    }
  });

  router.get('/api/team-health/metrics/:teamId', async (req, res) => {
    try {
      const metrics = await service.getLatestMetrics(req.params.teamId);
      if (!metrics) {
        res.status(404).json({ error: 'Metrics not found' });
        return;
      }
      res.json(metrics);
    } catch (error) {
      logger.error('Failed to get metrics', error);
      res.status(500).json({ error: 'Failed to get metrics' });
    }
  });

  router.post('/api/team-health/calculate/:teamId', async (req, res) => {
    try {
      const metrics = await service.calculateTeamHealthMetrics(req.params.teamId);
      res.json(metrics);
    } catch (error) {
      logger.error('Failed to calculate metrics', error);
      res.status(500).json({ error: 'Failed to calculate metrics' });
    }
  });

  router.post('/api/team-health/digest/:teamId', async (req, res) => {
    try {
      const digest = await service.generateWeeklyDigest(req.params.teamId);
      res.json(digest);
    } catch (error) {
      logger.error('Failed to generate digest', error);
      res.status(500).json({ error: 'Failed to generate digest' });
    }
  });

  router.get('/api/team-health/digest/:teamId', async (req, res) => {
    try {
      const digest = await service.getWeeklyDigest(req.params.teamId);
      if (!digest) {
        res.status(404).json({ error: 'Digest not found' });
        return;
      }
      res.json(digest);
    } catch (error) {
      logger.error('Failed to get digest', error);
      res.status(500).json({ error: 'Failed to get digest' });
    }
  });

  router.get('/api/team-health/history/:teamId', async (req, res) => {
    try {
      const days = parseInt(req.query.days as string) || 30;
      const history = await service.getTeamHistory(req.params.teamId, days);
      res.json(history);
    } catch (error) {
      logger.error('Failed to get history', error);
      res.status(500).json({ error: 'Failed to get history' });
    }
  });

  return router;
}
