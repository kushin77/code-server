#!/usr/bin/env node
// @file        apps/backend/src/services/file-advisory-locks/index.ts
// @module      collaboration/file-advisory-locks
// @description Advisory file lock system for binary assets with auto-expire and release flows
// @owner       collab-1.6
// @status      active

import { EventEmitter } from 'events';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger';

export interface FileAdvisoryLock {
  id: string;
  assetPath: string;
  userId: string;
  reason: string | null;
  isActive: boolean;
  expiresAt: Date;
  releasedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
}

export interface AcquireLockInput {
  assetPath: string;
  userId: string;
  reason?: string;
  ttlMinutes?: number;
}

export interface FileLockQuery {
  assetPath?: string;
  userId?: string;
  includeExpired?: boolean;
}

export class FileAdvisoryLockService extends EventEmitter {
  private logger = getLogger('FileAdvisoryLockService');
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
        CREATE TABLE IF NOT EXISTS file_advisory_locks (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          asset_path TEXT NOT NULL,
          user_id TEXT NOT NULL,
          reason TEXT,
          is_active BOOLEAN NOT NULL DEFAULT TRUE,
          expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
          released_at TIMESTAMP WITH TIME ZONE,
          created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);

      await client.query(`
        CREATE INDEX IF NOT EXISTS idx_file_advisory_locks_asset_path
        ON file_advisory_locks(asset_path, is_active, expires_at DESC)
      `);

      await client.query(`
        CREATE INDEX IF NOT EXISTS idx_file_advisory_locks_user_id
        ON file_advisory_locks(user_id, created_at DESC)
      `);
    } finally {
      client.release();
    }
  }

  async acquireLock(input: AcquireLockInput): Promise<FileAdvisoryLock> {
    const client = await this.pool.connect();
    try {
      const existing = await client.query(
        `
          SELECT id, asset_path, user_id, reason, is_active, expires_at, released_at, created_at, updated_at
          FROM file_advisory_locks
          WHERE asset_path = $1 AND is_active = true AND expires_at > CURRENT_TIMESTAMP
          ORDER BY created_at DESC
          LIMIT 1
        `,
        [input.assetPath]
      );

      if (existing.rows.length > 0) {
        const current = this.rowToLock(existing.rows[0]);
        if (current.userId !== input.userId) {
          throw new Error(`Asset ${input.assetPath} is already locked by ${current.userId}`);
        }

        return current;
      }

      const ttlMinutes = input.ttlMinutes ?? 30;
      const expiresAt = new Date(Date.now() + ttlMinutes * 60 * 1000);
      const result = await client.query(
        `
          INSERT INTO file_advisory_locks (asset_path, user_id, reason, expires_at)
          VALUES ($1, $2, $3, $4)
          RETURNING id, asset_path, user_id, reason, is_active, expires_at, released_at, created_at, updated_at
        `,
        [input.assetPath, input.userId, input.reason || null, expiresAt]
      );

      const lock = this.rowToLock(result.rows[0]);
      this.emit('lock-acquired', lock);
      return lock;
    } finally {
      client.release();
    }
  }

  async releaseLock(lockId: string, userId?: string): Promise<FileAdvisoryLock> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `
          UPDATE file_advisory_locks
          SET is_active = false,
              released_at = CURRENT_TIMESTAMP,
              updated_at = CURRENT_TIMESTAMP
          WHERE id = $1
            AND ($2::text IS NULL OR user_id = $2)
          RETURNING id, asset_path, user_id, reason, is_active, expires_at, released_at, created_at, updated_at
        `,
        [lockId, userId || null]
      );

      if (result.rows.length === 0) {
        throw new Error(`Lock ${lockId} not found`);
      }

      const lock = this.rowToLock(result.rows[0]);
      this.emit('lock-released', lock);
      return lock;
    } finally {
      client.release();
    }
  }

  async renewLock(lockId: string, userId: string, ttlMinutes: number = 30): Promise<FileAdvisoryLock> {
    const client = await this.pool.connect();
    try {
      const expiresAt = new Date(Date.now() + ttlMinutes * 60 * 1000);
      const result = await client.query(
        `
          UPDATE file_advisory_locks
          SET expires_at = $1,
              updated_at = CURRENT_TIMESTAMP
          WHERE id = $2 AND user_id = $3 AND is_active = true
          RETURNING id, asset_path, user_id, reason, is_active, expires_at, released_at, created_at, updated_at
        `,
        [expiresAt, lockId, userId]
      );

      if (result.rows.length === 0) {
        throw new Error(`Unable to renew lock ${lockId}`);
      }

      const lock = this.rowToLock(result.rows[0]);
      this.emit('lock-renewed', lock);
      return lock;
    } finally {
      client.release();
    }
  }

  async getLock(assetPath: string): Promise<FileAdvisoryLock | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `
          SELECT id, asset_path, user_id, reason, is_active, expires_at, released_at, created_at, updated_at
          FROM file_advisory_locks
          WHERE asset_path = $1
          ORDER BY is_active DESC, created_at DESC
          LIMIT 1
        `,
        [assetPath]
      );

      if (result.rows.length === 0) {
        return null;
      }

      return this.rowToLock(result.rows[0]);
    } finally {
      client.release();
    }
  }

  async listLocks(filters: FileLockQuery = {}): Promise<FileAdvisoryLock[]> {
    const client = await this.pool.connect();
    try {
      const conditions: string[] = [];
      const params: Array<string | boolean> = [];

      if (filters.assetPath) {
        params.push(filters.assetPath);
        conditions.push(`asset_path = $${params.length}`);
      }

      if (filters.userId) {
        params.push(filters.userId);
        conditions.push(`user_id = $${params.length}`);
      }

      if (!filters.includeExpired) {
        conditions.push(`(is_active = true AND expires_at > CURRENT_TIMESTAMP)`);
      }

      const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
      const result = await client.query(
        `
          SELECT id, asset_path, user_id, reason, is_active, expires_at, released_at, created_at, updated_at
          FROM file_advisory_locks
          ${whereClause}
          ORDER BY created_at DESC
        `,
        params
      );

      return result.rows.map(row => this.rowToLock(row));
    } finally {
      client.release();
    }
  }

  async cleanupExpiredLocks(): Promise<number> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `
          UPDATE file_advisory_locks
          SET is_active = false,
              released_at = CURRENT_TIMESTAMP,
              updated_at = CURRENT_TIMESTAMP
          WHERE is_active = true AND expires_at <= CURRENT_TIMESTAMP
        `
      );

      return result.rowCount || 0;
    } finally {
      client.release();
    }
  }

  private rowToLock(row: any): FileAdvisoryLock {
    return {
      id: row.id,
      assetPath: row.asset_path,
      userId: row.user_id,
      reason: row.reason,
      isActive: row.is_active,
      expiresAt: row.expires_at,
      releasedAt: row.released_at,
      createdAt: row.created_at,
      updatedAt: row.updated_at
    };
  }
}

export async function initializeFileAdvisoryLockRoutes(service: FileAdvisoryLockService) {
  const { Router } = require('express');
  const router = Router();
  const logger = getLogger('FileAdvisoryLockRoutes');

  router.post('/api/file-locks/acquire', async (req, res) => {
    try {
      const { assetPath, userId, reason, ttlMinutes } = req.body;
      const lock = await service.acquireLock({ assetPath, userId, reason, ttlMinutes });
      res.status(201).json(lock);
    } catch (error) {
      logger.error('Failed to acquire file lock', error);
      res.status(409).json({ error: 'Failed to acquire file lock' });
    }
  });

  router.post('/api/file-locks/:lockId/renew', async (req, res) => {
    try {
      const { lockId } = req.params;
      const { userId, ttlMinutes } = req.body;
      const lock = await service.renewLock(lockId, userId, ttlMinutes);
      res.json(lock);
    } catch (error) {
      logger.error('Failed to renew file lock', error);
      res.status(400).json({ error: 'Failed to renew file lock' });
    }
  });

  router.delete('/api/file-locks/:lockId', async (req, res) => {
    try {
      const { lockId } = req.params;
      const userId = (req.query.userId as string) || undefined;
      const lock = await service.releaseLock(lockId, userId);
      res.json(lock);
    } catch (error) {
      logger.error('Failed to release file lock', error);
      res.status(404).json({ error: 'Failed to release file lock' });
    }
  });

  router.get('/api/file-locks', async (req, res) => {
    try {
      const locks = await service.listLocks({
        assetPath: (req.query.assetPath as string) || undefined,
        userId: (req.query.userId as string) || undefined,
        includeExpired: req.query.includeExpired === 'true'
      });
      res.json(locks);
    } catch (error) {
      logger.error('Failed to list file locks', error);
      res.status(500).json({ error: 'Failed to list file locks' });
    }
  });

  router.post('/api/file-locks/cleanup', async (req, res) => {
    try {
      const count = await service.cleanupExpiredLocks();
      res.json({ cleaned: count });
    } catch (error) {
      logger.error('Failed to cleanup file locks', error);
      res.status(500).json({ error: 'Failed to cleanup file locks' });
    }
  });

  router.get('/api/file-locks/:assetPath', async (req, res) => {
    try {
      const assetPath = decodeURIComponent(req.params.assetPath);
      const lock = await service.getLock(assetPath);
      if (!lock) {
        res.status(404).json({ error: 'Lock not found' });
        return;
      }
      res.json(lock);
    } catch (error) {
      logger.error('Failed to get file lock', error);
      res.status(500).json({ error: 'Failed to get file lock' });
    }
  });

  return router;
}
