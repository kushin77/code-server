#!/usr/bin/env bash
/**
 * @file        apps/backend/src/services/code-ownership-graph/index.ts
 * @module      services/collaboration
 * @description D3 visualization of file ownership with bus-factor and contributor heatmap
 */

import { EventEmitter } from 'events';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger';

export interface FileOwnership {
  filePath: string;
  primaryOwner: string;
  contributors: Array<{ userId: string; commitCount: number; percentage: number }>;
  busFactor: number;
  lastModified: Date;
  createdAt: Date;
}

export interface OwnershipGraph {
  nodes: Array<{ id: string; label: string; type: 'file' | 'contributor'; commits: number }>;
  edges: Array<{ source: string; target: string; weight: number }>;
  busFactor: { critical: string[]; medium: string[] };
}

export interface ContributorHeatmap {
  userId: string;
  totalCommits: number;
  filesOwned: number;
  busFactor1Count: number;
  recentActivity: number;
  dominantFiles: string[];
}

export class CodeOwnershipGraphService extends EventEmitter {
  private logger = getLogger('CodeOwnershipGraphService');
  private pool: Pool;

  constructor(pool: Pool) {
    super();
    this.pool = pool;
  }

  async initialize(): Promise<void> {
    this.logger.info('Initializing CodeOwnershipGraphService');
    await this.createTables();
  }

  private async createTables(): Promise<void> {
    const client = await this.pool.connect();
    try {
      // Create file_ownership table
      await client.query(`
        CREATE TABLE IF NOT EXISTS file_ownership (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          file_path VARCHAR(512) UNIQUE NOT NULL,
          primary_owner UUID NOT NULL,
          contributors JSONB,
          bus_factor INT,
          last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create ownership_commits table
      await client.query(`
        CREATE TABLE IF NOT EXISTS ownership_commits (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          file_path VARCHAR(512) NOT NULL,
          user_id UUID NOT NULL,
          commit_count INT DEFAULT 1,
          commit_sha VARCHAR(40),
          committed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create bus_factor_analysis table
      await client.query(`
        CREATE TABLE IF NOT EXISTS bus_factor_analysis (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          file_path VARCHAR(512) NOT NULL UNIQUE,
          bus_factor INT,
          critical_files JSONB,
          analysis_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create contributor_heatmap table
      await client.query(`
        CREATE TABLE IF NOT EXISTS contributor_heatmap (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID NOT NULL UNIQUE,
          total_commits INT DEFAULT 0,
          files_owned INT DEFAULT 0,
          bus_factor_1_count INT DEFAULT 0,
          recent_activity INT DEFAULT 0,
          dominant_files JSONB,
          generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create codeowners_file_cache table
      await client.query(`
        CREATE TABLE IF NOT EXISTS codeowners_file_cache (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          file_path VARCHAR(512) NOT NULL UNIQUE,
          owners JSONB,
          parsed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create indexes
      await client.query(`CREATE INDEX IF NOT EXISTS idx_file_ownership_path ON file_ownership(file_path)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_ownership_commits_file ON ownership_commits(file_path, user_id)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_bus_factor_file ON bus_factor_analysis(file_path)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_contributor_heatmap_user ON contributor_heatmap(user_id)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_codeowners_cache_path ON codeowners_file_cache(file_path)`);

      this.logger.info('Code ownership graph tables created successfully');
    } finally {
      client.release();
    }
  }

  async recordCommit(filePath: string, userId: string, commitSha: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      // Increment commit count
      const existingResult = await client.query(
        `SELECT id, commit_count FROM ownership_commits WHERE file_path = $1 AND user_id = $2 LIMIT 1`,
        [filePath, userId]
      );

      if (existingResult.rows.length > 0) {
        await client.query(
          `UPDATE ownership_commits SET commit_count = commit_count + 1 WHERE file_path = $1 AND user_id = $2`,
          [filePath, userId]
        );
      } else {
        await client.query(
          `INSERT INTO ownership_commits (file_path, user_id, commit_count, commit_sha) VALUES ($1, $2, 1, $3)`,
          [filePath, userId, commitSha]
        );
      }

      // Update file ownership
      const topContributorResult = await client.query(
        `SELECT user_id FROM ownership_commits WHERE file_path = $1 ORDER BY commit_count DESC LIMIT 1`,
        [filePath]
      );

      if (topContributorResult.rows.length > 0) {
        const topContributor = topContributorResult.rows[0].user_id;

        const contributorsResult = await client.query(
          `SELECT user_id, commit_count FROM ownership_commits WHERE file_path = $1 ORDER BY commit_count DESC`,
          [filePath]
        );

        const total = contributorsResult.rows.reduce((sum, row) => sum + row.commit_count, 0);
        const contributors = contributorsResult.rows.map(row => ({
          userId: row.user_id,
          commitCount: row.commit_count,
          percentage: (row.commit_count / total) * 100
        }));

        const existingOwnershipResult = await client.query(
          `SELECT id FROM file_ownership WHERE file_path = $1`,
          [filePath]
        );

        if (existingOwnershipResult.rows.length > 0) {
          await client.query(
            `UPDATE file_ownership SET primary_owner = $1, contributors = $2, last_modified = CURRENT_TIMESTAMP WHERE file_path = $3`,
            [topContributor, JSON.stringify(contributors), filePath]
          );
        } else {
          await client.query(
            `INSERT INTO file_ownership (file_path, primary_owner, contributors) VALUES ($1, $2, $3)`,
            [filePath, topContributor, JSON.stringify(contributors)]
          );
        }
      }

      this.emit('commit-recorded', { filePath, userId, commitSha });
    } finally {
      client.release();
    }
  }

  async getFileOwnership(filePath: string): Promise<FileOwnership | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT file_path, primary_owner, contributors, bus_factor, last_modified, created_at
         FROM file_ownership WHERE file_path = $1`,
        [filePath]
      );

      if (result.rows.length === 0) return null;

      const row = result.rows[0];
      return {
        filePath: row.file_path,
        primaryOwner: row.primary_owner,
        contributors: row.contributors || [],
        busFactor: row.bus_factor || 0,
        lastModified: row.last_modified,
        createdAt: row.created_at
      };
    } finally {
      client.release();
    }
  }

  async analyzeBusFactor(filePath: string): Promise<number> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT contributors FROM file_ownership WHERE file_path = $1`,
        [filePath]
      );

      if (result.rows.length === 0) return 0;

      const contributors = result.rows[0].contributors || [];
      let busFactor = 0;

      for (const contributor of contributors) {
        if (contributor.percentage >= 50) {
          busFactor = 1;
          break;
        }
        if (contributor.percentage >= 25) {
          busFactor = Math.max(busFactor, 2);
        }
        if (contributor.percentage >= 15) {
          busFactor = Math.max(busFactor, 3);
        }
      }

      // Update bus factor
      await client.query(
        `UPDATE file_ownership SET bus_factor = $1 WHERE file_path = $2`,
        [busFactor, filePath]
      );

      this.emit('bus-factor-analyzed', { filePath, busFactor });

      return busFactor;
    } finally {
      client.release();
    }
  }

  async getOwnershipGraph(): Promise<OwnershipGraph> {
    const client = await this.pool.connect();
    try {
      const filesResult = await client.query(
        `SELECT file_path, primary_owner, contributors, bus_factor FROM file_ownership ORDER BY last_modified DESC LIMIT 100`
      );

      const nodes: any[] = [];
      const edges: any[] = [];
      const busFactorCritical: string[] = [];
      const busFactorMedium: string[] = [];

      // Add file nodes and edges
      for (const file of filesResult.rows) {
        nodes.push({
          id: file.file_path,
          label: file.file_path.split('/').pop(),
          type: 'file',
          commits: 1
        });

        if (file.bus_factor === 1) {
          busFactorCritical.push(file.file_path);
        } else if (file.bus_factor === 2) {
          busFactorMedium.push(file.file_path);
        }

        const contributors = file.contributors || [];
        for (const contributor of contributors) {
          if (!nodes.some(n => n.id === contributor.userId)) {
            nodes.push({
              id: contributor.userId,
              label: contributor.userId,
              type: 'contributor',
              commits: contributor.commitCount
            });
          }

          edges.push({
            source: contributor.userId,
            target: file.file_path,
            weight: contributor.percentage
          });
        }
      }

      return {
        nodes,
        edges,
        busFactor: {
          critical: busFactorCritical,
          medium: busFactorMedium
        }
      };
    } finally {
      client.release();
    }
  }

  async generateContributorHeatmap(userId: string): Promise<ContributorHeatmap> {
    const client = await this.pool.connect();
    try {
      // Get total commits
      const commitsResult = await client.query(
        `SELECT COUNT(*) as total_commits FROM ownership_commits WHERE user_id = $1`,
        [userId]
      );
      const totalCommits = parseInt(commitsResult.rows[0]?.total_commits || 0);

      // Get files owned
      const filesResult = await client.query(
        `SELECT COUNT(*) as files_owned FROM file_ownership WHERE primary_owner = $1`,
        [userId]
      );
      const filesOwned = parseInt(filesResult.rows[0]?.files_owned || 0);

      // Get bus factor 1 count
      const busFactor1Result = await client.query(
        `SELECT COUNT(*) as bus_factor_1 FROM file_ownership WHERE primary_owner = $1 AND bus_factor = 1`,
        [userId]
      );
      const busFactor1Count = parseInt(busFactor1Result.rows[0]?.bus_factor_1 || 0);

      // Get recent activity (last 7 days)
      const recentResult = await client.query(
        `SELECT COUNT(*) as recent_activity FROM ownership_commits WHERE user_id = $1 AND committed_at > NOW() - INTERVAL '7 days'`,
        [userId]
      );
      const recentActivity = parseInt(recentResult.rows[0]?.recent_activity || 0);

      // Get dominant files
      const dominantFilesResult = await client.query(
        `SELECT file_path FROM ownership_commits WHERE user_id = $1 ORDER BY commit_count DESC LIMIT 5`,
        [userId]
      );
      const dominantFiles = dominantFilesResult.rows.map(r => r.file_path);

      const heatmap: ContributorHeatmap = {
        userId,
        totalCommits,
        filesOwned,
        busFactor1Count,
        recentActivity,
        dominantFiles
      };

      // Store heatmap
      const existingResult = await client.query(
        `SELECT id FROM contributor_heatmap WHERE user_id = $1`,
        [userId]
      );

      if (existingResult.rows.length > 0) {
        await client.query(
          `UPDATE contributor_heatmap SET total_commits = $1, files_owned = $2, bus_factor_1_count = $3, recent_activity = $4, dominant_files = $5
           WHERE user_id = $6`,
          [totalCommits, filesOwned, busFactor1Count, recentActivity, JSON.stringify(dominantFiles), userId]
        );
      } else {
        await client.query(
          `INSERT INTO contributor_heatmap (user_id, total_commits, files_owned, bus_factor_1_count, recent_activity, dominant_files)
           VALUES ($1, $2, $3, $4, $5, $6)`,
          [userId, totalCommits, filesOwned, busFactor1Count, recentActivity, JSON.stringify(dominantFiles)]
        );
      }

      this.emit('heatmap-generated', { userId, totalCommits, filesOwned });

      return heatmap;
    } finally {
      client.release();
    }
  }

  async getContributorHeatmap(userId: string): Promise<ContributorHeatmap | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT user_id, total_commits, files_owned, bus_factor_1_count, recent_activity, dominant_files
         FROM contributor_heatmap WHERE user_id = $1`,
        [userId]
      );

      if (result.rows.length === 0) return null;

      const row = result.rows[0];
      return {
        userId: row.user_id,
        totalCommits: row.total_commits,
        filesOwned: row.files_owned,
        busFactor1Count: row.bus_factor_1_count,
        recentActivity: row.recent_activity,
        dominantFiles: row.dominant_files || []
      };
    } finally {
      client.release();
    }
  }

  async parseCodeowners(content: string): Promise<any> {
    const lines = content.split('\n').filter(line => !line.startsWith('#') && line.trim());
    const codeowners: any = {};

    for (const line of lines) {
      const parts = line.split(/\s+/);
      if (parts.length >= 2) {
        const pattern = parts[0];
        const owners = parts.slice(1);
        codeowners[pattern] = owners;
      }
    }

    return codeowners;
  }

  async cacheCodeowners(filePath: string, content: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      const owners = await this.parseCodeowners(content);

      const existingResult = await client.query(
        `SELECT id FROM codeowners_file_cache WHERE file_path = $1`,
        [filePath]
      );

      if (existingResult.rows.length > 0) {
        await client.query(
          `UPDATE codeowners_file_cache SET owners = $1, parsed_at = CURRENT_TIMESTAMP WHERE file_path = $2`,
          [JSON.stringify(owners), filePath]
        );
      } else {
        await client.query(
          `INSERT INTO codeowners_file_cache (file_path, owners) VALUES ($1, $2)`,
          [filePath, JSON.stringify(owners)]
        );
      }

      this.emit('codeowners-cached', { filePath });
    } finally {
      client.release();
    }
  }

  async getCriticalFiles(): Promise<string[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT file_path FROM file_ownership WHERE bus_factor = 1 ORDER BY last_modified DESC`
      );

      return result.rows.map(r => r.file_path);
    } finally {
      client.release();
    }
  }

  async getTopContributors(limit: number = 10): Promise<Array<{ userId: string; commits: number }>> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT user_id, COUNT(*) as commits FROM ownership_commits GROUP BY user_id ORDER BY commits DESC LIMIT $1`,
        [limit]
      );

      return result.rows.map(r => ({
        userId: r.user_id,
        commits: parseInt(r.commits)
      }));
    } finally {
      client.release();
    }
  }

  async getFileChangeHistory(filePath: string, days: number = 30): Promise<any[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT user_id, commit_count, committed_at FROM ownership_commits
         WHERE file_path = $1 AND committed_at > NOW() - INTERVAL '1 day' * $2
         ORDER BY committed_at DESC`,
        [filePath, days]
      );

      return result.rows;
    } finally {
      client.release();
    }
  }
}

export async function initializeCodeOwnershipGraphRoutes(service: CodeOwnershipGraphService) {
  const { Router } = require('express');
  const router = Router();
  const logger = getLogger('CodeOwnershipGraphRoutes');

  router.post('/api/ownership/commits', async (req, res) => {
    try {
      const { filePath, userId, commitSha } = req.body;
      await service.recordCommit(filePath, userId, commitSha);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to record commit', error);
      res.status(500).json({ error: 'Failed to record commit' });
    }
  });

  router.get('/api/ownership/file/:filePath', async (req, res) => {
    try {
      const filePath = decodeURIComponent(req.params.filePath);
      const ownership = await service.getFileOwnership(filePath);
      if (!ownership) {
        res.status(404).json({ error: 'File not found' });
        return;
      }
      res.json(ownership);
    } catch (error) {
      logger.error('Failed to get file ownership', error);
      res.status(500).json({ error: 'Failed to get file ownership' });
    }
  });

  router.post('/api/ownership/bus-factor/:filePath', async (req, res) => {
    try {
      const filePath = decodeURIComponent(req.params.filePath);
      const busFactor = await service.analyzeBusFactor(filePath);
      res.json({ busFactor });
    } catch (error) {
      logger.error('Failed to analyze bus factor', error);
      res.status(500).json({ error: 'Failed to analyze bus factor' });
    }
  });

  router.get('/api/ownership/graph', async (req, res) => {
    try {
      const graph = await service.getOwnershipGraph();
      res.json(graph);
    } catch (error) {
      logger.error('Failed to get ownership graph', error);
      res.status(500).json({ error: 'Failed to get ownership graph' });
    }
  });

  router.post('/api/ownership/heatmap/:userId', async (req, res) => {
    try {
      const heatmap = await service.generateContributorHeatmap(req.params.userId);
      res.json(heatmap);
    } catch (error) {
      logger.error('Failed to generate heatmap', error);
      res.status(500).json({ error: 'Failed to generate heatmap' });
    }
  });

  router.get('/api/ownership/heatmap/:userId', async (req, res) => {
    try {
      const heatmap = await service.getContributorHeatmap(req.params.userId);
      if (!heatmap) {
        res.status(404).json({ error: 'Heatmap not found' });
        return;
      }
      res.json(heatmap);
    } catch (error) {
      logger.error('Failed to get heatmap', error);
      res.status(500).json({ error: 'Failed to get heatmap' });
    }
  });

  router.post('/api/ownership/codeowners', async (req, res) => {
    try {
      const { filePath, content } = req.body;
      await service.cacheCodeowners(filePath, content);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to cache codeowners', error);
      res.status(500).json({ error: 'Failed to cache codeowners' });
    }
  });

  router.get('/api/ownership/critical-files', async (req, res) => {
    try {
      const files = await service.getCriticalFiles();
      res.json({ files });
    } catch (error) {
      logger.error('Failed to get critical files', error);
      res.status(500).json({ error: 'Failed to get critical files' });
    }
  });

  router.get('/api/ownership/top-contributors', async (req, res) => {
    try {
      const limit = parseInt(req.query.limit as string) || 10;
      const contributors = await service.getTopContributors(limit);
      res.json(contributors);
    } catch (error) {
      logger.error('Failed to get top contributors', error);
      res.status(500).json({ error: 'Failed to get top contributors' });
    }
  });

  router.get('/api/ownership/file-history/:filePath', async (req, res) => {
    try {
      const filePath = decodeURIComponent(req.params.filePath);
      const days = parseInt(req.query.days as string) || 30;
      const history = await service.getFileChangeHistory(filePath, days);
      res.json(history);
    } catch (error) {
      logger.error('Failed to get file history', error);
      res.status(500).json({ error: 'Failed to get file history' });
    }
  });

  return router;
}
