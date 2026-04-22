#!/usr/bin/env node
// @file        apps/backend/src/routes/help-queue-audit.ts
// @module      routes
// @description Help Queue audit logging REST API endpoints

import { Router, Request, Response } from 'express';
import { HelpQueueAuditService } from '../services/help-queue/help-queue-audit';
import { getLogger } from '../lib/logger';

const router = Router();
const service = HelpQueueAuditService.getInstance();
const logger = getLogger('HelpQueueAuditRoutes');

/**
 * Serialize audit entry for JSON response
 */
function serializeEntry(entry: any) {
  return {
    ...entry,
    _immutable: entry._immutable,
    _createdAt: entry._createdAt,
  };
}

/**
 * POST /api/help-queue-audit/queue-items
 * Log a queue item event
 */
router.post('/queue-items', (req: Request, res: Response) => {
  try {
    const {
      userId,
      action,
      queueItemId,
      workspaceId,
      success,
      metadata,
      errorMessage,
      userEmail,
      userRole,
    } = req.body;

    // Validation
    if (!userId || !action || !queueItemId || !workspaceId) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: userId, action, queueItemId, workspaceId',
      });
    }

    // Set user context
    if (userEmail || userRole) {
      service.setUserContext(userEmail, userRole);
    }

    const entry = service.logQueueItemEvent(
      userId,
      action,
      queueItemId,
      workspaceId,
      success,
      metadata,
      errorMessage
    );

    res.status(201).json({
      success: true,
      data: serializeEntry(entry),
    });
  } catch (error: any) {
    logger.error('Failed to log queue item event', {
      error: error.message,
      stack: error.stack,
    });
    res.status(500).json({
      success: false,
      error: 'Failed to log event',
    });
  }
});

/**
 * POST /api/help-queue-audit/experts
 * Log an expert event
 */
router.post('/experts', (req: Request, res: Response) => {
  try {
    const {
      userId,
      action,
      expertId,
      workspaceId,
      success,
      metadata,
      errorMessage,
      userEmail,
      userRole,
    } = req.body;

    // Validation
    if (!userId || !action || !expertId || !workspaceId) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: userId, action, expertId, workspaceId',
      });
    }

    // Set user context
    if (userEmail || userRole) {
      service.setUserContext(userEmail, userRole);
    }

    const entry = service.logExpertEvent(
      userId,
      action,
      expertId,
      workspaceId,
      success,
      metadata,
      errorMessage
    );

    res.status(201).json({
      success: true,
      data: serializeEntry(entry),
    });
  } catch (error: any) {
    logger.error('Failed to log expert event', {
      error: error.message,
      stack: error.stack,
    });
    res.status(500).json({
      success: false,
      error: 'Failed to log event',
    });
  }
});

/**
 * GET /api/help-queue-audit/workspace/:workspaceId/logs
 * Query audit logs with filters
 */
router.get('/workspace/:workspaceId/logs', (req: Request, res: Response) => {
  try {
    const { workspaceId } = req.params;
    const {
      userId,
      action,
      queueItemId,
      expertId,
      success,
      startTime,
      endTime,
      limit,
      offset,
    } = req.query;

    // Convert query params to numbers where needed
    const filters = {
      userId: userId as string | undefined,
      action: action as string | undefined,
      queueItemId: queueItemId as string | undefined,
      expertId: expertId as string | undefined,
      success: success !== undefined ? success === 'true' : undefined,
      startTime: startTime ? parseInt(startTime as string, 10) : undefined,
      endTime: endTime ? parseInt(endTime as string, 10) : undefined,
      limit: limit ? parseInt(limit as string, 10) : 50,
      offset: offset ? parseInt(offset as string, 10) : 0,
    };

    const result = service.queryLogs(workspaceId, filters);

    res.status(200).json({
      success: true,
      data: {
        entries: result.entries.map(serializeEntry),
        total: result.total,
        limit: filters.limit,
        offset: filters.offset,
      },
    });
  } catch (error: any) {
    logger.error('Failed to query logs', {
      error: error.message,
      stack: error.stack,
    });
    res.status(500).json({
      success: false,
      error: 'Failed to query logs',
    });
  }
});

/**
 * GET /api/help-queue-audit/workspace/:workspaceId/statistics
 * Get audit statistics for compliance
 */
router.get('/workspace/:workspaceId/statistics', (req: Request, res: Response) => {
  try {
    const { workspaceId } = req.params;

    const stats = service.getStatistics(workspaceId);

    res.status(200).json({
      success: true,
      data: stats,
    });
  } catch (error: any) {
    logger.error('Failed to get statistics', {
      error: error.message,
      stack: error.stack,
    });
    res.status(500).json({
      success: false,
      error: 'Failed to get statistics',
    });
  }
});

/**
 * GET /api/help-queue-audit/workspace/:workspaceId
 * Get all logs for workspace
 */
router.get('/workspace/:workspaceId', (req: Request, res: Response) => {
  try {
    const { workspaceId } = req.params;

    const logs = service.getWorkspaceLogs(workspaceId);

    res.status(200).json({
      success: true,
      data: {
        entries: logs.map(serializeEntry),
        total: logs.length,
      },
    });
  } catch (error: any) {
    logger.error('Failed to get workspace logs', {
      error: error.message,
      stack: error.stack,
    });
    res.status(500).json({
      success: false,
      error: 'Failed to get logs',
    });
  }
});

/**
 * GET /api/help-queue-audit/health
 * Health check endpoint
 */
router.get('/health', (req: Request, res: Response) => {
  res.status(200).json({
    success: true,
    data: {
      status: 'ok',
      service: 'help-queue-audit',
    },
  });
});

export default router;
