#!/usr/bin/env node
// @file        apps/backend/src/services/workspace-forking/index.ts
// @module      collaboration/workspace-forking
// @description Create git branches from the current workspace state for exploratory coding
// @owner       collab-1.5
// @status      active
import { EventEmitter } from 'events';
import { execFileSync } from 'child_process';
import { getLogger } from '../../lib/logger';
export class WorkspaceForkingService extends EventEmitter {
    constructor(pool) {
        super();
        this.logger = getLogger('WorkspaceForkingService');
        this.pool = pool;
    }
    async initialize() {
        await this.createTables();
    }
    async createTables() {
        const client = await this.pool.connect();
        try {
            await client.query(`
        CREATE TABLE IF NOT EXISTS workspace_forks (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id TEXT NOT NULL,
          repo_path TEXT NOT NULL,
          base_ref TEXT NOT NULL,
          base_commit TEXT NOT NULL,
          fork_branch TEXT NOT NULL,
          description TEXT,
          archived BOOLEAN NOT NULL DEFAULT FALSE,
          created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
          archived_at TIMESTAMP WITH TIME ZONE
        )
      `);
            await client.query(`
        CREATE INDEX IF NOT EXISTS idx_workspace_forks_user_repo
        ON workspace_forks(user_id, repo_path, created_at DESC)
      `);
            await client.query(`
        CREATE INDEX IF NOT EXISTS idx_workspace_forks_branch
        ON workspace_forks(fork_branch)
      `);
        }
        finally {
            client.release();
        }
    }
    async createFork(input) {
        const client = await this.pool.connect();
        try {
            const baseRef = input.baseRef || 'HEAD';
            const baseCommit = this.resolveCommit(input.repoPath, baseRef);
            const forkBranch = input.forkBranch || this.buildForkBranchName(input.userId, baseCommit);
            execFileSync('git', ['-C', input.repoPath, 'branch', forkBranch, baseCommit], { encoding: 'utf8' });
            const result = await client.query(`
          INSERT INTO workspace_forks (user_id, repo_path, base_ref, base_commit, fork_branch, description)
          VALUES ($1, $2, $3, $4, $5, $6)
          RETURNING id, user_id, repo_path, base_ref, base_commit, fork_branch, description, archived, created_at, archived_at
        `, [input.userId, input.repoPath, baseRef, baseCommit, forkBranch, input.description || null]);
            const fork = this.rowToFork(result.rows[0]);
            this.emit('fork-created', fork);
            return fork;
        }
        finally {
            client.release();
        }
    }
    async listForks(userId, repoPath) {
        const client = await this.pool.connect();
        try {
            const params = [userId];
            let query = `
        SELECT id, user_id, repo_path, base_ref, base_commit, fork_branch, description, archived, created_at, archived_at
        FROM workspace_forks
        WHERE user_id = $1
      `;
            if (repoPath) {
                params.push(repoPath);
                query += ` AND repo_path = $2`;
            }
            query += ` ORDER BY created_at DESC`;
            const result = await client.query(query, params);
            return result.rows.map(row => this.rowToFork(row));
        }
        finally {
            client.release();
        }
    }
    async getFork(forkId) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`
          SELECT id, user_id, repo_path, base_ref, base_commit, fork_branch, description, archived, created_at, archived_at
          FROM workspace_forks
          WHERE id = $1
        `, [forkId]);
            if (result.rows.length === 0)
                return null;
            return this.rowToFork(result.rows[0]);
        }
        finally {
            client.release();
        }
    }
    async archiveFork(forkId) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`
          UPDATE workspace_forks
          SET archived = true,
              archived_at = CURRENT_TIMESTAMP
          WHERE id = $1
          RETURNING id, user_id, repo_path, base_ref, base_commit, fork_branch, description, archived, created_at, archived_at
        `, [forkId]);
            if (result.rows.length === 0) {
                throw new Error(`Workspace fork ${forkId} not found`);
            }
            const fork = this.rowToFork(result.rows[0]);
            this.emit('fork-archived', fork);
            return fork;
        }
        finally {
            client.release();
        }
    }
    resolveCommit(repoPath, ref) {
        return execFileSync('git', ['-C', repoPath, 'rev-parse', ref], { encoding: 'utf8' }).trim();
    }
    buildForkBranchName(userId, baseCommit) {
        const safeUserId = userId.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'user';
        return `fork/${safeUserId}/${baseCommit.slice(0, 8)}`;
    }
    rowToFork(row) {
        return {
            id: row.id,
            userId: row.user_id,
            repoPath: row.repo_path,
            baseRef: row.base_ref,
            baseCommit: row.base_commit,
            forkBranch: row.fork_branch,
            description: row.description,
            archived: row.archived,
            createdAt: row.created_at,
            archivedAt: row.archived_at
        };
    }
}
export async function initializeWorkspaceForkingRoutes(service) {
    const { Router } = require('express');
    const router = Router();
    const logger = getLogger('WorkspaceForkingRoutes');
    router.post('/api/workspace-forks', async (req, res) => {
        try {
            const { userId, repoPath, baseRef, forkBranch, description } = req.body;
            const fork = await service.createFork({ userId, repoPath, baseRef, forkBranch, description });
            res.status(201).json(fork);
        }
        catch (error) {
            logger.error('Failed to create workspace fork', error);
            res.status(500).json({ error: 'Failed to create workspace fork' });
        }
    });
    router.get('/api/workspace-forks/:userId', async (req, res) => {
        try {
            const repoPath = req.query.repoPath || undefined;
            const forks = await service.listForks(req.params.userId, repoPath);
            res.json(forks);
        }
        catch (error) {
            logger.error('Failed to list workspace forks', error);
            res.status(500).json({ error: 'Failed to list workspace forks' });
        }
    });
    router.get('/api/workspace-forks/fork/:forkId', async (req, res) => {
        try {
            const fork = await service.getFork(req.params.forkId);
            if (!fork) {
                res.status(404).json({ error: 'Workspace fork not found' });
                return;
            }
            res.json(fork);
        }
        catch (error) {
            logger.error('Failed to get workspace fork', error);
            res.status(500).json({ error: 'Failed to get workspace fork' });
        }
    });
    router.post('/api/workspace-forks/:forkId/archive', async (req, res) => {
        try {
            const fork = await service.archiveFork(req.params.forkId);
            res.json(fork);
        }
        catch (error) {
            logger.error('Failed to archive workspace fork', error);
            res.status(500).json({ error: 'Failed to archive workspace fork' });
        }
    });
    return router;
}
//# sourceMappingURL=index.js.map