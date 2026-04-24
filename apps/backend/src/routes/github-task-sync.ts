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

  /**
   * POST /api/github-task-sync/webhook - GitHub webhook endpoint
   * Receives GitHub webhook events and broadcasts to connected WebSocket clients
   * Headers: X-Hub-Signature-256, X-GitHub-Delivery, X-GitHub-Event
   * Body: Raw GitHub webhook payload
   */
  router.post('/webhook', async (req: Request, res: Response) => {
    try {
      const signature = req.headers['x-hub-signature-256'] as string;
      const deliveryId = req.headers['x-github-delivery'] as string;
      const deliveryTime = req.headers['x-github-delivery-timestamp'] as string || new Date().toISOString();
      const eventType = req.headers['x-github-event'] as string;

      // Log webhook receipt
      logger.info('GitHub webhook received', {
        deliveryId,
        eventType,
        timestamp: deliveryTime,
      });

      // Validate webhook signature
      if (!signature || !deliveryId) {
        logger.warn('Webhook missing required headers', { signature: !!signature, deliveryId: !!deliveryId });
        return res.status(400).json({
          status: 'error',
          message: 'Missing X-Hub-Signature-256 or X-GitHub-Delivery header',
        });
      }

      // Get webhook handler from service (if available)
      // Note: Webhook handler should be attached to service during initialization
      const webhookHandler = (service as any).webhookHandler;
      if (!webhookHandler) {
        logger.error('Webhook handler not available');
        return res.status(503).json({
          status: 'error',
          message: 'Webhook handler not initialized',
        });
      }

      // Process webhook (verify signature, validate, deduplicate)
      const body = JSON.stringify(req.body);
      const event = await webhookHandler.processWebhook(body, signature, deliveryId, deliveryTime);

      if (!event) {
        // Webhook was rejected (invalid signature, timestamp, etc.)
        return res.status(401).json({
          status: 'error',
          message: 'Webhook verification failed',
        });
      }

      // Check if this is an issue-related event
      if (!webhookHandler.isIssueEvent(event)) {
        logger.debug('Webhook is not an issue event, ignoring', { eventType, deliveryId });
        return res.status(200).json({
          status: 'success',
          message: 'Webhook received but not an issue event',
        });
      }

      // Extract issue data from event
      const issueNumber = event.payload.issue?.number;
      if (!issueNumber) {
        logger.warn('Issue number not found in webhook', { deliveryId });
        return res.status(400).json({
          status: 'error',
          message: 'Issue number not found in webhook payload',
        });
      }

      // Update local task state based on webhook action
      try {
        const action = event.payload.action;
        const issueData = event.payload.issue;

        logger.info(`Processing webhook action: ${action} for issue #${issueNumber}`, {
          deliveryId,
          issueNumber,
        });

        // Handle different webhook actions
        switch (action) {
          case 'opened':
          case 'edited':
          case 'reopened':
            // Update or create task from webhook data
            if (issueData) {
              const updatedTask = await service.updateIssueFromGitHub(issueNumber, {
                title: issueData.title,
                body: issueData.body,
                state: issueData.state,
                labels: issueData.labels.map((l) => l.name),
                assignees: issueData.assignee ? [issueData.assignee.login] : [],
              });
              logger.info(`Updated task #${issueNumber} from webhook`, { deliveryId });
            }
            break;

          case 'closed':
            // Close task
            await service.closeIssueFromGitHub(issueNumber);
            logger.info(`Closed task #${issueNumber} from webhook`, { deliveryId });
            break;

          case 'labeled':
          case 'unlabeled':
            // Update labels
            if (issueData) {
              const updatedTask = await service.updateIssueFromGitHub(issueNumber, {
                labels: issueData.labels.map((l) => l.name),
              });
              logger.info(`Updated labels for #${issueNumber} from webhook`, { deliveryId });
            }
            break;

          case 'assigned':
          case 'unassigned':
            // Update assignees
            if (issueData) {
              const updatedTask = await service.updateIssueFromGitHub(issueNumber, {
                assignees: issueData.assignee ? [issueData.assignee.login] : [],
              });
              logger.info(`Updated assignees for #${issueNumber} from webhook`, { deliveryId });
            }
            break;

          default:
            logger.debug(`Ignoring webhook action: ${action}`, { deliveryId });
        }

        // Broadcast update to connected WebSocket clients
        const broadcaster = (service as any).broadcaster;
        if (broadcaster) {
          const broadcastMessage = {
            type: action === 'closed' ? 'issue-closed' : 'issue-updated',
            issueNumber,
            action,
            data: {
              title: issueData?.title,
              state: issueData?.state,
              labels: issueData?.labels.map((l) => l.name),
              assignees: issueData?.assignee ? [issueData.assignee.login] : [],
              timestamp: new Date(issueData?.updated_at || Date.now()).getTime(),
            },
            timestamp: Date.now(),
          };

          broadcaster.broadcast(broadcastMessage);
          logger.info(`Broadcast webhook event to clients`, {
            deliveryId,
            issueNumber,
            clientsConnected: broadcaster.getClientCount(),
          });
        }

        // Emit event for other listeners
        service.emit('webhook-processed', {
          deliveryId,
          issueNumber,
          action,
          timestamp: Date.now(),
        });

        // Return success response
        res.json({
          status: 'success',
          message: `Webhook processed for issue #${issueNumber}`,
          data: {
            deliveryId,
            issueNumber,
            action,
          },
        });
      } catch (processingError: any) {
        logger.error('Error processing webhook event', {
          error: processingError.message,
          deliveryId,
          issueNumber,
        });

        // Return 202 Accepted even on processing error (GitHub will retry)
        res.status(202).json({
          status: 'partial',
          message: 'Webhook received but processing encountered an error',
          error: processingError.message,
        });
      }
    } catch (error: any) {
      logger.error('Webhook endpoint error', error);
      res.status(500).json({
        status: 'error',
        message: error.message,
      });
    }
  });

  return router;
}

export default initializeGitHubTaskSyncRoutes;
