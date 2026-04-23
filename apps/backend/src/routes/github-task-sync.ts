#!/usr/bin/env node
// @file        apps/backend/src/routes/github-task-sync.ts
// @module      routes/github-task-sync
// @description REST API routes for bidirectional GitHub issue sync
// @owner       collab-9
// @status      active

import { Router, Request, Response } from 'express';
import { GitHubTaskSyncService } from '../services/github-task-sync';
import { getLogger } from '../lib/logger';

const logger = getLogger('GitHubTaskSyncRoutes');

/**
 * Initialize GitHub task sync routes
 */
export function initializeGitHubTaskSyncRoutes(
  service: GitHubTaskSyncService
): Router {
  const router = Router();

  // ─────────────────────────────────────────────────────────────────────────
  // Issue Management Endpoints
  // ─────────────────────────────────────────────────────────────────────────

  /**
   * GET /api/github-task-sync/issues - List all issues
   * Query params:
   *   - state: 'open' | 'closed' | 'all'
   *   - labels: comma-separated list of labels
   */
  router.get('/issues', (req: Request, res: Response) => {
    try {
      const state = (req.query.state as string) || 'all';
      
      let tasks = service.getAllTasks();

      if (state === 'open') {
        tasks = service.getOpenTasks();
      } else if (state === 'closed') {
        tasks = service.getClosedTasks();
      }

      // Apply label filter if provided
      if (req.query.labels) {
        const filterLabels = (req.query.labels as string).split(',');
        tasks = tasks.filter((t) =>
          filterLabels.every((label) => t.labels.includes(label))
        );
      }

      res.json({
        status: 'success',
        data: tasks,
        count: tasks.length,
      });
    } catch (error: any) {
      logger.error('Error listing issues', error);
      res.status(500).json({
        status: 'error',
        message: error.message,
      });
    }
  });

  /**
   * GET /api/github-task-sync/issues/:issueNumber - Get a single issue
   */
  router.get('/issues/:issueNumber', (req: Request, res: Response) => {
    try {
      const issueNumber = parseInt(req.params.issueNumber, 10);

      const task = service.getTask(issueNumber);

      if (!task) {
        return res.status(404).json({
          status: 'error',
          message: `Issue #${issueNumber} not found`,
        });
      }

      res.json({
        status: 'success',
        data: task,
      });
    } catch (error: any) {
      logger.error('Error getting issue', error);
      res.status(500).json({
        status: 'error',
        message: error.message,
      });
    }
  });

  /**
   * POST /api/github-task-sync/issues - Create a new issue
   * Body:
   *   {
   *     "title": "string",
   *     "description": "string?",
   *     "labels": ["string"],
   *     "assignees": ["string"]
   *   }
   */
  router.post('/issues', async (req: Request, res: Response) => {
    try {
      const { title, description, labels, assignees } = req.body;

      if (!title) {
        return res.status(400).json({
          status: 'error',
          message: 'Title is required',
        });
      }

      const task = await service.createIssueFromIDE({
        title,
        body: description,
        labels,
        assignees,
      });

      res.status(201).json({
        status: 'success',
        data: task,
        message: `Created issue #${task.issueNumber}`,
      });
    } catch (error: any) {
      logger.error('Error creating issue', error);
      res.status(500).json({
        status: 'error',
        message: error.message,
      });
    }
  });

  /**
   * PATCH /api/github-task-sync/issues/:issueNumber - Update an issue
   * Body:
   *   {
   *     "title": "string?",
   *     "description": "string?",
   *     "state": "open" | "closed"?,
   *     "labels": ["string"]?,
   *     "assignees": ["string"]?
   *   }
   */
  router.patch('/issues/:issueNumber', async (req: Request, res: Response) => {
    try {
      const issueNumber = parseInt(req.params.issueNumber, 10);
      const { title, description, state, labels, assignees } = req.body;

      const task = await service.updateIssueFromIDE(issueNumber, {
        title,
        body: description,
        state,
        labels,
        assignees,
      });

      res.json({
        status: 'success',
        data: task,
        message: `Updated issue #${issueNumber}`,
      });
    } catch (error: any) {
      logger.error('Error updating issue', error);
      res.status(500).json({
        status: 'error',
        message: error.message,
      });
    }
  });

  /**
   * POST /api/github-task-sync/issues/:issueNumber/close - Close an issue
   * Body: { "reason": "string?" }
   */
  router.post('/issues/:issueNumber/close', async (req: Request, res: Response) => {
    try {
      const issueNumber = parseInt(req.params.issueNumber, 10);
      const { reason } = req.body;

      const task = await service.closeIssueFromIDE(issueNumber, reason);

      res.json({
        status: 'success',
        data: task,
        message: `Closed issue #${issueNumber}`,
      });
    } catch (error: any) {
      logger.error('Error closing issue', error);
      res.status(500).json({
        status: 'error',
        message: error.message,
      });
    }
  });

  /**
   * POST /api/github-task-sync/issues/:issueNumber/reopen - Reopen an issue
   */
  router.post('/issues/:issueNumber/reopen', async (req: Request, res: Response) => {
    try {
      const issueNumber = parseInt(req.params.issueNumber, 10);

      const task = await service.reopenIssueFromIDE(issueNumber);

      res.json({
        status: 'success',
        data: task,
        message: `Reopened issue #${issueNumber}`,
      });
    } catch (error: any) {
      logger.error('Error reopening issue', error);
      res.status(500).json({
        status: 'error',
        message: error.message,
      });
    }
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Sync Control Endpoints
  // ─────────────────────────────────────────────────────────────────────────

  /**
   * POST /api/github-task-sync/sync - Trigger manual sync from GitHub
   * Query params:
   *   - state: 'open' | 'closed' | 'all'
   *   - labels: comma-separated
   */
  router.post('/sync', async (req: Request, res: Response) => {
    try {
      const state = (req.query.state as string) || 'all';
      const labels = req.query.labels
        ? (req.query.labels as string).split(',')
        : undefined;

      const result = await service.syncFromGitHub({
        state: state as 'open' | 'closed' | 'all',
        labels,
      });

      res.json({
        status: 'success',
        data: result,
        message: 'Sync complete',
      });
    } catch (error: any) {
      logger.error('Error syncing', error);
      res.status(500).json({
        status: 'error',
        message: error.message,
      });
    }
  });

  /**
   * GET /api/github-task-sync/status - Get sync status
   */
  router.get('/status', (req: Request, res: Response) => {
    try {
      const status = service.getSyncStatus();

      res.json({
        status: 'success',
        data: status,
      });
    } catch (error: any) {
      logger.error('Error getting status', error);
      res.status(500).json({
        status: 'error',
        message: error.message,
      });
    }
  });

  /**
   * GET /api/github-task-sync/conflicts - Get conflict log
   */
  router.get('/conflicts', (req: Request, res: Response) => {
    try {
      const conflicts = service.getConflictLog();

      res.json({
        status: 'success',
        data: conflicts,
        count: conflicts.length,
      });
    } catch (error: any) {
      logger.error('Error getting conflicts', error);
      res.status(500).json({
        status: 'error',
        message: error.message,
      });
    }
  });

  /**
   * DELETE /api/github-task-sync/conflicts - Clear conflict log
   */
  router.delete('/conflicts', (req: Request, res: Response) => {
    try {
      service.clearConflictLog();

      res.json({
        status: 'success',
        message: 'Conflict log cleared',
      });
    } catch (error: any) {
      logger.error('Error clearing conflicts', error);
      res.status(500).json({
        status: 'error',
        message: error.message,
      });
    }
  });

  /**
   * GET /api/github-task-sync/health - Health check
   */
  router.get('/health', async (req: Request, res: Response) => {
    try {
      const health = await service.healthCheck();

      res.status(health.status === 'healthy' ? 200 : 503).json(health);
    } catch (error: any) {
      logger.error('Health check error', error);
      res.status(503).json({
        status: 'unhealthy',
        details: { error: error.message },
      });
    }
  });

  return router;
}

export default initializeGitHubTaskSyncRoutes;
