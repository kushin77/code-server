import { EventEmitter } from 'events';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger';

export interface ExpertiseContribution {
  id: string;
  userId: string;
  filePath: string;
  functionName: string | null;
  expertiseScore: number;
  commitCount: number;
  createdAt: Date;
}

export interface ExpertiseHeatmapEntry {
  target: string;
  targetType: 'file' | 'function';
  experts: Array<{ userId: string; percentage: number; score: number }>;
  totalScore: number;
}

export interface ExpertMatch {
  target: string;
  targetType: 'file' | 'function';
  userId: string;
  percentage: number;
  score: number;
}

export class ExpertiseHeatmapService extends EventEmitter {
  private logger = getLogger('ExpertiseHeatmapService');
  private pool: Pool;

  constructor(pool: Pool) {
    super();
    this.pool = pool;
  }

  async initialize(): Promise<void> {
    await this.createTables();
  }

  private async createTables(): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(`
        CREATE TABLE IF NOT EXISTS expertise_contributions (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id VARCHAR(255) NOT NULL,
          file_path VARCHAR(512) NOT NULL,
          function_name VARCHAR(255),
          expertise_score NUMERIC NOT NULL DEFAULT 0,
          commit_count INTEGER NOT NULL DEFAULT 1,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);

      await client.query(`
        CREATE TABLE IF NOT EXISTS expertise_heatmap_snapshots (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          target VARCHAR(512) NOT NULL,
          target_type VARCHAR(32) NOT NULL CHECK (target_type IN ('file', 'function')),
          heatmap JSONB NOT NULL,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);

      await client.query(`
        CREATE TABLE IF NOT EXISTS expertise_lookup_cache (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          target VARCHAR(512) NOT NULL UNIQUE,
          user_id VARCHAR(255) NOT NULL,
          percentage NUMERIC NOT NULL,
          score NUMERIC NOT NULL,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);

      await client.query(`CREATE INDEX IF NOT EXISTS idx_expertise_contributions_file ON expertise_contributions(file_path, function_name)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_expertise_contributions_user ON expertise_contributions(user_id)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_expertise_snapshot_target ON expertise_heatmap_snapshots(target, target_type)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_expertise_lookup_target ON expertise_lookup_cache(target)`);
    } finally {
      client.release();
    }
  }

  async recordContribution(
    userId: string,
    filePath: string,
    functionName: string | null,
    expertiseScore: number,
    commitCount: number = 1
  ): Promise<ExpertiseContribution> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `
          INSERT INTO expertise_contributions (user_id, file_path, function_name, expertise_score, commit_count)
          VALUES ($1, $2, $3, $4, $5)
          RETURNING id, user_id, file_path, function_name, expertise_score, commit_count, created_at
        `,
        [userId, filePath, functionName, expertiseScore, commitCount]
      );

      const row = result.rows[0];
      const contribution: ExpertiseContribution = {
        id: row.id,
        userId: row.user_id,
        filePath: row.file_path,
        functionName: row.function_name,
        expertiseScore: Number(row.expertise_score),
        commitCount: row.commit_count,
        createdAt: row.created_at
      };

      this.emit('contribution-recorded', contribution);
      return contribution;
    } finally {
      client.release();
    }
  }

  async generateHeatmap(target: string, targetType: 'file' | 'function' = 'file'): Promise<ExpertiseHeatmapEntry> {
    const client = await this.pool.connect();
    try {
      const query = targetType === 'function'
        ? `SELECT user_id, SUM(expertise_score) AS score FROM expertise_contributions WHERE function_name = $1 GROUP BY user_id ORDER BY score DESC`
        : `SELECT user_id, SUM(expertise_score) AS score FROM expertise_contributions WHERE file_path = $1 GROUP BY user_id ORDER BY score DESC`;

      const result = await client.query(query, [target]);
      const totalScore = result.rows.reduce((sum, row) => sum + Number(row.score || 0), 0);
      const experts = result.rows.map(row => ({
        userId: row.user_id,
        score: Number(row.score),
        percentage: totalScore === 0 ? 0 : (Number(row.score) / totalScore) * 100
      }));

      const heatmap: ExpertiseHeatmapEntry = {
        target,
        targetType,
        experts,
        totalScore
      };

      await client.query(
        `
          INSERT INTO expertise_heatmap_snapshots (target, target_type, heatmap)
          VALUES ($1, $2, $3)
          ON CONFLICT DO NOTHING
        `,
        [target, targetType, JSON.stringify(heatmap)]
      );

      this.emit('heatmap-generated', heatmap);
      return heatmap;
    } finally {
      client.release();
    }
  }

  async findExpert(target: string, targetType: 'file' | 'function' = 'file'): Promise<ExpertMatch | null> {
    const client = await this.pool.connect();
    try {
      const query = targetType === 'function'
        ? `SELECT user_id, SUM(expertise_score) AS score FROM expertise_contributions WHERE function_name = $1 GROUP BY user_id ORDER BY score DESC LIMIT 1`
        : `SELECT user_id, SUM(expertise_score) AS score FROM expertise_contributions WHERE file_path = $1 GROUP BY user_id ORDER BY score DESC LIMIT 1`;

      const result = await client.query(query, [target]);
      if (result.rows.length === 0) return null;

      const row = result.rows[0];
      const score = Number(row.score);
      const totalRows = await client.query(
        targetType === 'function'
          ? `SELECT SUM(expertise_score) AS total FROM expertise_contributions WHERE function_name = $1`
          : `SELECT SUM(expertise_score) AS total FROM expertise_contributions WHERE file_path = $1`,
        [target]
      );
      const total = Number(totalRows.rows[0]?.total || 0);
      const percentage = total === 0 ? 0 : (score / total) * 100;

      const match: ExpertMatch = {
        target,
        targetType,
        userId: row.user_id,
        percentage,
        score
      };

      await client.query(
        `
          INSERT INTO expertise_lookup_cache (target, user_id, percentage, score)
          VALUES ($1, $2, $3, $4)
          ON CONFLICT (target)
          DO UPDATE SET user_id = EXCLUDED.user_id, percentage = EXCLUDED.percentage, score = EXCLUDED.score, created_at = CURRENT_TIMESTAMP
        `,
        [target, row.user_id, percentage, score]
      );

      this.emit('expert-found', match);
      return match;
    } finally {
      client.release();
    }
  }

  async listContributions(userId: string): Promise<ExpertiseContribution[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT id, user_id, file_path, function_name, expertise_score, commit_count, created_at FROM expertise_contributions WHERE user_id = $1 ORDER BY created_at DESC`,
        [userId]
      );

      return result.rows.map(row => ({
        id: row.id,
        userId: row.user_id,
        filePath: row.file_path,
        functionName: row.function_name,
        expertiseScore: Number(row.expertise_score),
        commitCount: row.commit_count,
        createdAt: row.created_at
      }));
    } finally {
      client.release();
    }
  }

  async getLatestHeatmap(target: string, targetType: 'file' | 'function' = 'file'): Promise<ExpertiseHeatmapEntry | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT heatmap FROM expertise_heatmap_snapshots WHERE target = $1 AND target_type = $2 ORDER BY created_at DESC LIMIT 1`,
        [target, targetType]
      );

      if (result.rows.length === 0) return null;
      return result.rows[0].heatmap;
    } finally {
      client.release();
    }
  }
}

export async function initializeExpertiseHeatmapRoutes(service: ExpertiseHeatmapService) {
  const { Router } = require('express');
  const router = Router();
  const logger = getLogger('ExpertiseHeatmapRoutes');

  router.post('/api/expertise/contributions', async (req, res) => {
    try {
      const { userId, filePath, functionName, expertiseScore, commitCount } = req.body;
      const contribution = await service.recordContribution(userId, filePath, functionName || null, expertiseScore, commitCount || 1);
      res.json(contribution);
    } catch (error) {
      logger.error('Failed to record expertise contribution', error);
      res.status(500).json({ error: 'Failed to record expertise contribution' });
    }
  });

  router.post('/api/expertise/heatmap', async (req, res) => {
    try {
      const { target, targetType } = req.body;
      const heatmap = await service.generateHeatmap(target, targetType || 'file');
      res.json(heatmap);
    } catch (error) {
      logger.error('Failed to generate expertise heatmap', error);
      res.status(500).json({ error: 'Failed to generate expertise heatmap' });
    }
  });

  router.get('/api/expertise/heatmap/:target', async (req, res) => {
    try {
      const targetType = (req.query.targetType as 'file' | 'function') || 'file';
      const heatmap = await service.getLatestHeatmap(req.params.target, targetType);
      if (!heatmap) {
        res.status(404).json({ error: 'Heatmap not found' });
        return;
      }
      res.json(heatmap);
    } catch (error) {
      logger.error('Failed to get expertise heatmap', error);
      res.status(500).json({ error: 'Failed to get expertise heatmap' });
    }
  });

  router.get('/api/expertise/expert/:target', async (req, res) => {
    try {
      const targetType = (req.query.targetType as 'file' | 'function') || 'file';
      const expert = await service.findExpert(req.params.target, targetType);
      if (!expert) {
        res.status(404).json({ error: 'Expert not found' });
        return;
      }
      res.json(expert);
    } catch (error) {
      logger.error('Failed to find expert', error);
      res.status(500).json({ error: 'Failed to find expert' });
    }
  });

  router.get('/api/expertise/contributions/:userId', async (req, res) => {
    try {
      const contributions = await service.listContributions(req.params.userId);
      res.json(contributions);
    } catch (error) {
      logger.error('Failed to list expertise contributions', error);
      res.status(500).json({ error: 'Failed to list expertise contributions' });
    }
  });

  return router;
}
