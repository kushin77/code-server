#!/usr/bin/env node
// @file        apps/backend/src/routes/code-review-request.ts
// @module      routes/collaboration
// @description REST API endpoints for code review request management

import { Router, Request, Response } from 'express';
import service from '../services/collaboration/code-review-request-service';
import { getLogger } from '../lib/logger';

const logger = getLogger('CodeReviewRequestRoutes');
const router = Router();

/**
 * POST /api/reviews
 * Create a new code review request
 */
router.post('/', (req: Request, res: Response) => {
  try {
    const { requesterId, reviewerId, workspaceId, contextNote, priority, filePath, dueAt } = req.body;

    if (!requesterId || !reviewerId || !workspaceId || !contextNote) {
      return res.status(400).json({
        success: false,
        error: 'requesterId, reviewerId, workspaceId, and contextNote are required',
      });
    }

    const request = service.createRequest(requesterId, reviewerId, workspaceId, contextNote, priority || 'normal', filePath, dueAt);
    res.status(201).json({
      success: true,
      data: request,
    });
  } catch (error) {
    logger.error('Failed to create code review request', error as Error);
    res.status(500).json({
      success: false,
      error: 'Failed to create code review request',
    });
  }
});

/**
 * GET /api/reviews/:requestId
 * Get a code review request
 */
router.get('/:requestId', (req: Request, res: Response) => {
  try {
    const { requestId } = req.params;
    const request = service.getRequest(requestId);

    if (!request) {
      return res.status(404).json({
        success: false,
        error: 'Code review request not found',
      });
    }

    res.status(200).json({
      success: true,
      data: request,
    });
  } catch (error) {
    logger.error('Failed to get code review request', error as Error);
    res.status(500).json({
      success: false,
      error: 'Failed to get code review request',
    });
  }
});

/**
 * GET /api/reviews/reviewer/:reviewerId/pending
 * Get pending requests for a reviewer
 */
router.get('/reviewer/:reviewerId/pending', (req: Request, res: Response) => {
  try {
    const { reviewerId } = req.params;
    const requests = service.getPendingRequestsForReviewer(reviewerId);

    res.status(200).json({
      success: true,
      data: requests,
    });
  } catch (error) {
    logger.error('Failed to get pending requests', error as Error);
    res.status(500).json({
      success: false,
      error: 'Failed to get pending requests',
    });
  }
});

/**
 * GET /api/reviews/requester/:requesterId
 * Get all requests from a requester
 */
router.get('/requester/:requesterId', (req: Request, res: Response) => {
  try {
    const { requesterId } = req.params;
    const requests = service.getRequestsByRequester(requesterId);

    res.status(200).json({
      success: true,
      data: requests,
    });
  } catch (error) {
    logger.error('Failed to get requester requests', error as Error);
    res.status(500).json({
      success: false,
      error: 'Failed to get requester requests',
    });
  }
});

/**
 * POST /api/reviews/:requestId/respond
 * Respond to a code review request
 */
router.post('/:requestId/respond', (req: Request, res: Response) => {
  try {
    const { requestId } = req.params;
    const { reviewerId, status, comment } = req.body;

    if (!reviewerId || !status || !comment) {
      return res.status(400).json({
        success: false,
        error: 'reviewerId, status, and comment are required',
      });
    }

    if (!['approved', 'requested_changes', 'commented'].includes(status)) {
      return res.status(400).json({
        success: false,
        error: 'status must be one of: approved, requested_changes, commented',
      });
    }

    const updated = service.respondToRequest(requestId, reviewerId, status, comment);
    if (!updated) {
      return res.status(404).json({
        success: false,
        error: 'Code review request not found',
      });
    }

    res.status(200).json({
      success: true,
      data: updated,
    });
  } catch (error) {
    logger.error('Failed to respond to review request', error as Error);
    res.status(500).json({
      success: false,
      error: 'Failed to respond to review request',
    });
  }
});

/**
 * POST /api/reviews/:requestId/dismiss
 * Dismiss a code review request
 */
router.post('/:requestId/dismiss', (req: Request, res: Response) => {
  try {
    const { requestId } = req.params;
    const updated = service.dismissRequest(requestId);

    if (!updated) {
      return res.status(404).json({
        success: false,
        error: 'Code review request not found',
      });
    }

    res.status(200).json({
      success: true,
      data: updated,
    });
  } catch (error) {
    logger.error('Failed to dismiss code review request', error as Error);
    res.status(500).json({
      success: false,
      error: 'Failed to dismiss code review request',
    });
  }
});

/**
 * PATCH /api/reviews/:requestId/due-date
 * Set due date for a code review request
 */
router.patch('/:requestId/due-date', (req: Request, res: Response) => {
  try {
    const { requestId } = req.params;
    const { dueAt } = req.body;

    if (typeof dueAt !== 'number') {
      return res.status(400).json({
        success: false,
        error: 'dueAt must be a number (timestamp)',
      });
    }

    const updated = service.setDueDate(requestId, dueAt);
    if (!updated) {
      return res.status(404).json({
        success: false,
        error: 'Code review request not found',
      });
    }

    res.status(200).json({
      success: true,
      data: updated,
    });
  } catch (error) {
    logger.error('Failed to set due date', error as Error);
    res.status(500).json({
      success: false,
      error: 'Failed to set due date',
    });
  }
});

/**
 * GET /api/reviews/overdue/list
 * Get overdue code review requests
 */
router.get('/overdue/list', (req: Request, res: Response) => {
  try {
    const overdue = service.getOverdueRequests();
    res.status(200).json({
      success: true,
      data: overdue,
    });
  } catch (error) {
    logger.error('Failed to get overdue requests', error as Error);
    res.status(500).json({
      success: false,
      error: 'Failed to get overdue requests',
    });
  }
});

/**
 * POST /api/reviews/:requestId/remind
 * Send reminder for a code review request
 */
router.post('/:requestId/remind', (req: Request, res: Response) => {
  try {
    const { requestId } = req.params;
    const updated = service.sendReminder(requestId);

    if (!updated) {
      return res.status(404).json({
        success: false,
        error: 'Code review request not found',
      });
    }

    res.status(200).json({
      success: true,
      data: updated,
    });
  } catch (error) {
    logger.error('Failed to send reminder', error as Error);
    res.status(500).json({
      success: false,
      error: 'Failed to send reminder',
    });
  }
});

/**
 * GET /api/reviews/notifications/:userId
 * Get notifications for a user
 */
router.get('/notifications/:userId', (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const notifications = service.getNotificationsForUser(userId);

    res.status(200).json({
      success: true,
      data: notifications,
    });
  } catch (error) {
    logger.error('Failed to get notifications', error as Error);
    res.status(500).json({
      success: false,
      error: 'Failed to get notifications',
    });
  }
});

/**
 * PATCH /api/reviews/notifications/:notificationId/read
 * Mark notification as read
 */
router.patch('/notifications/:notificationId/read', (req: Request, res: Response) => {
  try {
    const { notificationId } = req.params;
    const updated = service.markNotificationAsRead(notificationId);

    if (!updated) {
      return res.status(404).json({
        success: false,
        error: 'Notification not found',
      });
    }

    res.status(200).json({
      success: true,
      data: updated,
    });
  } catch (error) {
    logger.error('Failed to mark notification as read', error as Error);
    res.status(500).json({
      success: false,
      error: 'Failed to mark notification as read',
    });
  }
});

/**
 * GET /api/reviews/unread-count/:userId
 * Get unread notification count for a user
 */
router.get('/unread-count/:userId', (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const count = service.getUnreadNotificationCount(userId);

    res.status(200).json({
      success: true,
      data: { unreadCount: count },
    });
  } catch (error) {
    logger.error('Failed to get unread count', error as Error);
    res.status(500).json({
      success: false,
      error: 'Failed to get unread count',
    });
  }
});

/**
 * GET /api/reviews/reviewer/:reviewerId/stats
 * Get reviewer statistics
 */
router.get('/reviewer/:reviewerId/stats', (req: Request, res: Response) => {
  try {
    const { reviewerId } = req.params;
    const stats = service.getReviewerStats(reviewerId);

    res.status(200).json({
      success: true,
      data: stats,
    });
  } catch (error) {
    logger.error('Failed to get reviewer stats', error as Error);
    res.status(500).json({
      success: false,
      error: 'Failed to get reviewer stats',
    });
  }
});

/**
 * GET /api/reviews/workspace/:workspaceId/requests
 * Get all requests for a workspace
 */
router.get('/workspace/:workspaceId/requests', (req: Request, res: Response) => {
  try {
    const { workspaceId } = req.params;
    const requests = service.getRequestsByWorkspace(workspaceId);

    res.status(200).json({
      success: true,
      data: requests,
    });
  } catch (error) {
    logger.error('Failed to get workspace requests', error as Error);
    res.status(500).json({
      success: false,
      error: 'Failed to get workspace requests',
    });
  }
});

/**
 * GET /api/reviews/workspace/:workspaceId/stats
 * Get workspace statistics
 */
router.get('/workspace/:workspaceId/stats', (req: Request, res: Response) => {
  try {
    const { workspaceId } = req.params;
    const stats = service.getWorkspaceStats(workspaceId);

    res.status(200).json({
      success: true,
      data: stats,
    });
  } catch (error) {
    logger.error('Failed to get workspace stats', error as Error);
    res.status(500).json({
      success: false,
      error: 'Failed to get workspace stats',
    });
  }
});

/**
 * POST /api/reviews/expire-old
 * Expire old code review requests
 */
router.post('/expire-old', (req: Request, res: Response) => {
  try {
    const { maxAgeMs } = req.body;
    const expired = service.expireOldRequests(maxAgeMs);

    res.status(200).json({
      success: true,
      data: {
        expiredCount: expired.length,
        expired,
      },
    });
  } catch (error) {
    logger.error('Failed to expire old requests', error as Error);
    res.status(500).json({
      success: false,
      error: 'Failed to expire old requests',
    });
  }
});

export default router;
