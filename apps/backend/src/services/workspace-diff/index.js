#!/usr/bin/env node
// @file        apps/backend/src/services/workspace-diff/index.ts
// @module      collaboration/workspace-diff
// @description Live workspace diff snapshots for "what changed while you were away"
// @owner       collab-1.7
// @status      active
import { EventEmitter } from 'events';
import { execFileSync } from 'child_process';
import { getLogger } from '../../lib/logger';
export class WorkspaceDiffService extends EventEmitter {
    constructor(pool) {
        super();
        this.logger = getLogger('WorkspaceDiffService');
        this.pool = pool;
    }
    async initialize() {
        await this.createTables();
    }
    async createTables() {
        const client = await this.pool.connect();
        try {
            await client.query(`
        CREATE TABLE IF NOT EXISTS workspace_diff_snapshots (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id TEXT NOT NULL,
          repo_path TEXT NOT NULL,
          base_ref TEXT NOT NULL,
          head_ref TEXT NOT NULL,
          summary TEXT NOT NULL,
          changed_files JSONB NOT NULL,
          generated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);
            await client.query(`
        CREATE TABLE IF NOT EXISTS workspace_diff_files (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          snapshot_id UUID NOT NULL REFERENCES workspace_diff_snapshots(id) ON DELETE CASCADE,
          file_path TEXT NOT NULL,
          previous_path TEXT,
          status TEXT NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_workspace_diff_snapshots_user_repo ON workspace_diff_snapshots(user_id, repo_path, generated_at DESC)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_workspace_diff_files_snapshot ON workspace_diff_files(snapshot_id)`);
        }
        finally {
            client.release();
        }
    }
    async captureWorkspaceDiff(userId, repoPath) {
        const latest = await this.getLatestSnapshot({ userId, repoPath });
        const baseRef = latest?.headRef || 'HEAD~1';
        const headRef = 'HEAD';
        const diff = this.generateDiff(userId, repoPath, baseRef, headRef);
        const snapshot = await this.saveSnapshot({ ...diff, userId, repoPath });
        this.emit('workspace-diff-captured', snapshot);
        return snapshot;
    }
    generateDiff(userId, repoPath, baseRef, headRef) {
        const changedFiles = this.readChangedFiles(repoPath, baseRef, headRef);
        const summary = this.summarizeChanges(changedFiles);
        return {
            userId,
            repoPath,
            baseRef,
            headRef,
            changedFiles,
            summary,
            generatedAt: new Date()
        };
    }
    async saveSnapshot(diff) {
        const client = await this.pool.connect();
        try {
            const snapshotResult = await client.query(`
          INSERT INTO workspace_diff_snapshots (user_id, repo_path, base_ref, head_ref, summary, changed_files)
          VALUES ($1, $2, $3, $4, $5, $6)
          RETURNING id, user_id, repo_path, base_ref, head_ref, summary, changed_files, generated_at
        `, [diff.userId, diff.repoPath, diff.baseRef, diff.headRef, diff.summary, JSON.stringify(diff.changedFiles)]);
            const snapshotRow = snapshotResult.rows[0];
            const snapshotId = snapshotRow.id;
            for (const file of diff.changedFiles) {
                await client.query(`
            INSERT INTO workspace_diff_files (snapshot_id, file_path, previous_path, status)
            VALUES ($1, $2, $3, $4)
          `, [snapshotId, file.path, file.previousPath || null, file.status]);
            }
            return {
                id: snapshotRow.id,
                userId: snapshotRow.user_id,
                repoPath: snapshotRow.repo_path,
                baseRef: snapshotRow.base_ref,
                headRef: snapshotRow.head_ref,
                summary: snapshotRow.summary,
                changedFiles: snapshotRow.changed_files || [],
                generatedAt: snapshotRow.generated_at
            };
        }
        finally {
            client.release();
        }
    }
    async getLatestSnapshot(query) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`
          SELECT id, user_id, repo_path, base_ref, head_ref, summary, changed_files, generated_at
          FROM workspace_diff_snapshots
          WHERE user_id = $1 AND repo_path = $2
          ORDER BY generated_at DESC
          LIMIT 1
        `, [query.userId, query.repoPath]);
            if (result.rows.length === 0) {
                return null;
            }
            const row = result.rows[0];
            return {
                id: row.id,
                userId: row.user_id,
                repoPath: row.repo_path,
                baseRef: row.base_ref,
                headRef: row.head_ref,
                summary: row.summary,
                changedFiles: row.changed_files || [],
                generatedAt: row.generated_at
            };
        }
        finally {
            client.release();
        }
    }
    async listSnapshots(query) {
        const client = await this.pool.connect();
        try {
            const limit = query.limit ?? 10;
            const result = await client.query(`
          SELECT id, user_id, repo_path, base_ref, head_ref, summary, changed_files, generated_at
          FROM workspace_diff_snapshots
          WHERE user_id = $1 AND repo_path = $2
          ORDER BY generated_at DESC
          LIMIT $3
        `, [query.userId, query.repoPath, limit]);
            return result.rows.map(row => ({
                id: row.id,
                userId: row.user_id,
                repoPath: row.repo_path,
                baseRef: row.base_ref,
                headRef: row.head_ref,
                summary: row.summary,
                changedFiles: row.changed_files || [],
                generatedAt: row.generated_at
            }));
        }
        finally {
            client.release();
        }
    }
    async getWorkspaceDiffSinceLastSeen(userId, repoPath) {
        return this.captureWorkspaceDiff(userId, repoPath);
    }
    readChangedFiles(repoPath, baseRef, headRef) {
        const output = execFileSync('git', ['-C', repoPath, 'diff', '--name-status', baseRef, headRef], { encoding: 'utf8' }).trim();
        if (!output) {
            return [];
        }
        return output.split('\n').filter(Boolean).map(line => {
            const parts = line.split('\t');
            const statusCode = parts[0];
            if (statusCode.startsWith('R') || statusCode.startsWith('C')) {
                return {
                    status: statusCode.startsWith('R') ? 'renamed' : 'copied',
                    previousPath: parts[1],
                    path: parts[2]
                };
            }
            const statusMap = {
                A: 'added',
                M: 'modified',
                D: 'deleted',
                U: 'updated'
            };
            return {
                status: statusMap[statusCode] || 'unknown',
                path: parts[1]
            };
        });
    }
    summarizeChanges(changedFiles) {
        if (changedFiles.length === 0) {
            return 'No workspace changes detected since your last check-in.';
        }
        const counts = changedFiles.reduce((accumulator, file) => {
            accumulator[file.status] = (accumulator[file.status] || 0) + 1;
            return accumulator;
        }, {});
        const fragments = Object.entries(counts).map(([status, count]) => `${count} ${status}`);
        return `${changedFiles.length} files changed: ${fragments.join(', ')}`;
    }
}
export async function initializeWorkspaceDiffRoutes(service) {
    const { Router } = require('express');
    const router = Router();
    const logger = getLogger('WorkspaceDiffRoutes');
    router.post('/api/workspace-diff/capture', async (req, res) => {
        try {
            const { userId, repoPath } = req.body;
            const snapshot = await service.captureWorkspaceDiff(userId, repoPath);
            res.status(201).json(snapshot);
        }
        catch (error) {
            logger.error('Failed to capture workspace diff', error);
            res.status(500).json({ error: 'Failed to capture workspace diff' });
        }
    });
    router.get('/api/workspace-diff/latest/:userId', async (req, res) => {
        try {
            const repoPath = req.query.repoPath || '';
            const snapshot = await service.getLatestSnapshot({ userId: req.params.userId, repoPath });
            if (!snapshot) {
                res.status(404).json({ error: 'Workspace diff not found' });
                return;
            }
            res.json(snapshot);
        }
        catch (error) {
            logger.error('Failed to get latest workspace diff', error);
            res.status(500).json({ error: 'Failed to get latest workspace diff' });
        }
    });
    router.get('/api/workspace-diff/:userId', async (req, res) => {
        try {
            const repoPath = req.query.repoPath || '';
            const limit = parseInt(req.query.limit, 10) || 10;
            const snapshots = await service.listSnapshots({ userId: req.params.userId, repoPath, limit });
            res.json(snapshots);
        }
        catch (error) {
            logger.error('Failed to list workspace diffs', error);
            res.status(500).json({ error: 'Failed to list workspace diffs' });
        }
    });
    router.post('/api/workspace-diff/refresh/:userId', async (req, res) => {
        try {
            const repoPath = req.body.repoPath;
            const snapshot = await service.getWorkspaceDiffSinceLastSeen(req.params.userId, repoPath);
            res.json(snapshot);
        }
        catch (error) {
            logger.error('Failed to refresh workspace diff', error);
            res.status(500).json({ error: 'Failed to refresh workspace diff' });
        }
    });
    return router;
}
//# sourceMappingURL=index.js.map