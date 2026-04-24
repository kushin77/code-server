#!/usr/bin/env node
// @file        apps/backend/src/routes/rich-presence.ts
// @module      routes/rich-presence
// @description Routes for rich presence and collaboration features

import { Router, Request, Response } from 'express';
import service, { BulkPresenceQuery } from '../services/collaboration/rich-presence-service';
import { getLogger } from '../lib/logger';
import { tracingMiddleware } from '../middleware/tracing';

const logger = getLogger('RichPresenceRoutes');
const router = Router();

router.use(tracingMiddleware);

/**
 * Get all online users (must come before :userId routes)
 * GET /api/presence/online/all
 */
router.get('/presence/online/all', (req: Request, res: Response) => {
  try {
    const users = service.getOnlineUsers();

    res.status(200).json({
      success: true,
      data: users,
      count: users.length,
    });
  } catch (error) {
    logger.error(`Failed to get online users: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Get users editing a file (must come before :userId routes)
 * GET /api/presence/file
 */
router.get('/presence/file', (req: Request, res: Response) => {
  try {
    const { path } = req.query;

    if (!path) {
      return res.status(400).json({
        success: false,
        error: 'Missing required parameter: path',
      });
    }

    const users = service.getUsersOnFile(String(path));

    res.status(200).json({
      success: true,
      data: users,
      count: users.length,
    });
  } catch (error) {
    logger.error(`Failed to get users on file: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Get users on a function (must come before :userId routes)
 * GET /api/presence/function
 */
router.get('/presence/function', (req: Request, res: Response) => {
  try {
    const { name } = req.query;

    if (!name) {
      return res.status(400).json({
        success: false,
        error: 'Missing required parameter: name',
      });
    }

    const users = service.getUsersOnFunction(String(name));

    res.status(200).json({
      success: true,
      data: users,
      count: users.length,
    });
  } catch (error) {
    logger.error(`Failed to get users on function: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Get users on a task (must come before :userId routes)
 * GET /api/presence/task
 */
router.get('/presence/task', (req: Request, res: Response) => {
  try {
    const { id } = req.query;

    if (!id) {
      return res.status(400).json({
        success: false,
        error: 'Missing required parameter: id',
      });
    }

    const users = service.getUsersOnTask(String(id));

    res.status(200).json({
      success: true,
      data: users,
      count: users.length,
    });
  } catch (error) {
    logger.error(`Failed to get users on task: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Get presence statistics (must come before :userId routes)
 * GET /api/presence/stats/all
 */
router.get('/presence/stats/all', (req: Request, res: Response) => {
  try {
    const stats = service.getStatistics();

    res.status(200).json({
      success: true,
      data: stats,
    });
  } catch (error) {
    logger.error(`Failed to get statistics: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Count users by status (must come before :userId routes)
 * GET /api/presence/count/status
 */
router.get('/presence/count/status', (req: Request, res: Response) => {
  try {
    const { workspaceId } = req.query;

    const counts = service.countByStatus(workspaceId ? String(workspaceId) : undefined);

    res.status(200).json({
      success: true,
      data: counts,
    });
  } catch (error) {
    logger.error(`Failed to count by status: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Update user presence
 * POST /api/presence/update
 */
router.post('/presence/update', (req: Request, res: Response) => {
  try {
    const { userId, username, email, avatarUrl, status, workspaceId, sessionId } = req.body;

    if (!userId) {
      return res.status(400).json({
        success: false,
        error: 'Missing required field: userId',
      });
    }

    const presence = service.updatePresence(userId, {
      username,
      email,
      avatarUrl,
      status,
      workspaceId,
      sessionId,
    });

    res.status(200).json({
      success: true,
      data: presence,
    });
  } catch (error) {
    logger.error(`Failed to update presence: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Set user status
 * PATCH /api/presence/:userId/status
 */
router.patch('/presence/:userId/status', (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const { status } = req.body;

    if (!status || !['online', 'away', 'idle', 'offline'].includes(status)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid status value',
      });
    }

    const presence = service.setStatus(userId, status);
    if (!presence) {
      return res.status(404).json({
        success: false,
        error: 'User presence not found',
      });
    }

    res.status(200).json({ success: true, data: presence });
  } catch (error) {
    logger.error(`Failed to set status: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Set current file being edited
 * PATCH /api/presence/:userId/file
 */
router.patch('/presence/:userId/file', (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const { path, line, column } = req.body;

    if (!path) {
      return res.status(400).json({
        success: false,
        error: 'Missing required field: path',
      });
    }

    const presence = service.setCurrentFile(userId, { path, line, column });
    if (!presence) {
      return res.status(404).json({
        success: false,
        error: 'User presence not found',
      });
    }

    res.status(200).json({ success: true, data: presence });
  } catch (error) {
    logger.error(`Failed to set current file: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Set current function being debugged/edited
 * PATCH /api/presence/:userId/function
 */
router.patch('/presence/:userId/function', (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const { name, file, line } = req.body;

    if (!name || !file || typeof line !== 'number') {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: name, file, line',
      });
    }

    const presence = service.setCurrentFunction(userId, { name, file, line });
    if (!presence) {
      return res.status(404).json({
        success: false,
        error: 'User presence not found',
      });
    }

    res.status(200).json({ success: true, data: presence });
  } catch (error) {
    logger.error(`Failed to set current function: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Set current task
 * PATCH /api/presence/:userId/task
 */
router.patch('/presence/:userId/task', (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const { id, title, status } = req.body;

    if (!id || !title || !status) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: id, title, status',
      });
    }

    const presence = service.setCurrentTask(userId, { id, title, status });
    if (!presence) {
      return res.status(404).json({
        success: false,
        error: 'User presence not found',
      });
    }

    res.status(200).json({ success: true, data: presence });
  } catch (error) {
    logger.error(`Failed to set current task: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Set custom status
 * PATCH /api/presence/:userId/custom-status
 */
router.patch('/presence/:userId/custom-status', (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const { emoji, text, expiresIn } = req.body;

    const presence = service.setCustomStatus(userId, { emoji, text, expiresIn });
    if (!presence) {
      return res.status(404).json({
        success: false,
        error: 'User presence not found',
      });
    }

    res.status(200).json({ success: true, data: presence });
  } catch (error) {
    logger.error(`Failed to set custom status: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Clear custom status
 * DELETE /api/presence/:userId/custom-status
 */
router.delete('/presence/:userId/custom-status', (req: Request, res: Response) => {
  try {
    const { userId } = req.params;

    const presence = service.clearCustomStatus(userId);
    if (!presence) {
      return res.status(404).json({
        success: false,
        error: 'User presence not found',
      });
    }

    res.status(200).json({ success: true, data: presence });
  } catch (error) {
    logger.error(`Failed to clear custom status: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Set cursor position
 * PATCH /api/presence/:userId/cursor
 */
router.patch('/presence/:userId/cursor', (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const { x, y } = req.body;

    if (typeof x !== 'number' || typeof y !== 'number') {
      return res.status(400).json({
        success: false,
        error: 'Invalid cursor position',
      });
    }

    const presence = service.setCursorPosition(userId, { x, y });
    if (!presence) {
      return res.status(404).json({
        success: false,
        error: 'User presence not found',
      });
    }

    res.status(200).json({ success: true, data: presence });
  } catch (error) {
    logger.error(`Failed to set cursor position: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Query presence with filters
 * POST /api/presence/query
 */
router.post('/presence/query', (req: Request, res: Response) => {
  try {
    const query: BulkPresenceQuery = req.body;

    const results = service.queryPresence(query);

    res.status(200).json({
      success: true,
      data: results,
      count: results.length,
    });
  } catch (error) {
    logger.error(`Failed to query presence: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Get all users in workspace
 * GET /api/presence/workspace/:workspaceId
 */
router.get('/presence/workspace/:workspaceId', (req: Request, res: Response) => {
  try {
    const { workspaceId } = req.params;

    const presences = service.getWorkspacePresence(workspaceId);

    res.status(200).json({
      success: true,
      data: presences,
      count: presences.length,
    });
  } catch (error) {
    logger.error(`Failed to get workspace presence: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Get users editing a file
 * GET /api/presence/file
 */
router.get('/presence/file', (req: Request, res: Response) => {
  try {
    const { path } = req.query;

    if (!path) {
      return res.status(400).json({
        success: false,
        error: 'Missing required parameter: path',
      });
    }

    const users = service.getUsersOnFile(String(path));

    res.status(200).json({
      success: true,
      data: users,
      count: users.length,
    });
  } catch (error) {
    logger.error(`Failed to get users on file: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Get users on a function
 * GET /api/presence/function
 */
router.get('/presence/function', (req: Request, res: Response) => {
  try {
    const { name } = req.query;

    if (!name) {
      return res.status(400).json({
        success: false,
        error: 'Missing required parameter: name',
      });
    }

    const users = service.getUsersOnFunction(String(name));

    res.status(200).json({
      success: true,
      data: users,
      count: users.length,
    });
  } catch (error) {
    logger.error(`Failed to get users on function: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Get users on a task
 * GET /api/presence/task
 */
router.get('/presence/task', (req: Request, res: Response) => {
  try {
    const { id } = req.query;

    if (!id) {
      return res.status(400).json({
        success: false,
        error: 'Missing required parameter: id',
      });
    }

    const users = service.getUsersOnTask(String(id));

    res.status(200).json({
      success: true,
      data: users,
      count: users.length,
    });
  } catch (error) {
    logger.error(`Failed to get users on task: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Get all online users
 * GET /api/presence/online/all
 */
router.get('/presence/online/all', (req: Request, res: Response) => {
  try {
    const users = service.getOnlineUsers();

    res.status(200).json({
      success: true,
      data: users,
      count: users.length,
    });
  } catch (error) {
    logger.error(`Failed to get online users: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Query presence with filters
 * POST /api/presence/query
 */
router.post('/presence/query', (req: Request, res: Response) => {
  try {
    const query: BulkPresenceQuery = req.body;

    const results = service.queryPresence(query);

    res.status(200).json({
      success: true,
      data: results,
      count: results.length,
    });
  } catch (error) {
    logger.error(`Failed to query presence: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Broadcast presence update
 * POST /api/presence/:userId/broadcast
 */
router.post('/presence/:userId/broadcast', (req: Request, res: Response) => {
  try {
    const { userId } = req.params;

    const presence = service.broadcastPresenceUpdate(userId);
    if (!presence) {
      return res.status(404).json({
        success: false,
        error: 'User presence not found',
      });
    }

    res.status(200).json({ success: true, data: presence });
  } catch (error) {
    logger.error(`Failed to broadcast presence: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Get presence statistics
 * GET /api/presence/stats/all
 */
router.get('/presence/stats/all', (req: Request, res: Response) => {
  try {
    const stats = service.getStatistics();

    res.status(200).json({
      success: true,
      data: stats,
    });
  } catch (error) {
    logger.error(`Failed to get statistics: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Count users by status
 * GET /api/presence/count/status
 */
router.get('/presence/count/status', (req: Request, res: Response) => {
  try {
    const { workspaceId } = req.query;

    const counts = service.countByStatus(workspaceId ? String(workspaceId) : undefined);

    res.status(200).json({
      success: true,
      data: counts,
    });
  } catch (error) {
    logger.error(`Failed to count by status: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Remove user presence
 * DELETE /api/presence/:userId
 */
router.delete('/presence/:userId', (req: Request, res: Response) => {
  try {
    const { userId } = req.params;

    const removed = service.removePresence(userId);
    if (!removed) {
      return res.status(404).json({
        success: false,
        error: 'User presence not found',
      });
    }

    res.status(200).json({ success: true });
  } catch (error) {
    logger.error(`Failed to remove presence: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Get user presence (must come after specific :userId routes)
 * GET /api/presence/:userId
 */
router.get('/presence/:userId', (req: Request, res: Response) => {
  try {
    const { userId } = req.params;

    const presence = service.getPresence(userId);
    if (!presence) {
      return res.status(404).json({
        success: false,
        error: 'User presence not found',
      });
    }

    res.status(200).json({ success: true, data: presence });
  } catch (error) {
    logger.error(`Failed to get presence: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Get all users in workspace
 * GET /api/presence/workspace/:workspaceId
 */
router.get('/presence/workspace/:workspaceId', (req: Request, res: Response) => {
  try {
    const { workspaceId } = req.params;

    const presences = service.getWorkspacePresence(workspaceId);

    res.status(200).json({
      success: true,
      data: presences,
      count: presences.length,
    });
  } catch (error) {
    logger.error(`Failed to get workspace presence: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

export default router;
