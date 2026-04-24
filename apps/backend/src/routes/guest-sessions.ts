#!/usr/bin/env node
// @file        apps/backend/src/routes/guest-sessions.ts
// @module      collaboration/guest-sessions
// @description Guest session REST API endpoints
// @owner       collab-5.5
// @status      active

import { Router, Request, Response } from 'express';
import { GuestSessionService, AccessLevel } from '../services/guest-sessions';
import { getLogger } from '../lib/logger';

const logger = getLogger('GuestSessionRoutes');

export function initializeGuestSessionRoutes(service: GuestSessionService): Router {
  const router = Router();

  // Create guest session
  router.post('/api/guest/sessions', async (req: Request, res: Response) => {
    try {
      const { userId, scopedPath, ttlMinutes, accessLevel } = req.body;

      if (!userId || !scopedPath) {
        return res.status(400).json({ error: 'Missing userId or scopedPath' });
      }

      const session = await service.createGuestSession(
        userId,
        scopedPath,
        ttlMinutes,
        (accessLevel as AccessLevel) || 'read'
      );

      logger.info('Guest session created via API', { userId, sessionId: session.id });
      res.status(201).json(session);
    } catch (error) {
      logger.error('Failed to create guest session', { error });
      res.status(500).json({ error: 'Failed to create guest session' });
    }
  });

  // Get guest session
  router.get('/api/guest/sessions/:guestToken', async (req: Request, res: Response) => {
    try {
      const { guestToken } = req.params;

      const session = await service.getGuestSession(guestToken);

      if (!session) {
        return res.status(404).json({ error: 'Guest session not found or expired' });
      }

      logger.debug('Guest session retrieved', { sessionId: session.id });
      res.json(session);
    } catch (error) {
      logger.error('Failed to get guest session', { error });
      res.status(500).json({ error: 'Failed to get guest session' });
    }
  });

  // Validate access
  router.post('/api/guest/validate', async (req: Request, res: Response) => {
    try {
      const { guestToken, requestedPath } = req.body;

      if (!guestToken || !requestedPath) {
        return res.status(400).json({ error: 'Missing guestToken or requestedPath' });
      }

      const validation = await service.validateGuestAccess(guestToken, requestedPath);

      logger.debug('Guest access validated', { allowed: validation.allowed });
      res.json(validation);
    } catch (error) {
      logger.error('Failed to validate guest access', { error });
      res.status(500).json({ error: 'Failed to validate guest access' });
    }
  });

  // Track activity
  router.post('/api/guest/activity', async (req: Request, res: Response) => {
    try {
      const { guestToken, action, path, ipAddress, userAgent } = req.body;

      if (!guestToken || !action || !path) {
        return res.status(400).json({ error: 'Missing guestToken, action, or path' });
      }

      await service.trackActivity(guestToken, action, path, ipAddress, userAgent);

      logger.debug('Activity tracked', { action, path });
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to track activity', { error });
      res.status(500).json({ error: 'Failed to track activity' });
    }
  });

  // List user sessions
  router.get('/api/guest/user/:userId/sessions', async (req: Request, res: Response) => {
    try {
      const { userId } = req.params;

      const sessions = await service.getUserSessions(userId);

      logger.info('User sessions retrieved', { userId, count: sessions.length });
      res.json(sessions);
    } catch (error) {
      logger.error('Failed to get user sessions', { error });
      res.status(500).json({ error: 'Failed to get user sessions' });
    }
  });

  // Revoke session
  router.post('/api/guest/sessions/:guestSessionId/revoke', async (req: Request, res: Response) => {
    try {
      const { guestSessionId } = req.params;

      await service.revokeSession(guestSessionId);

      logger.info('Guest session revoked via API', { guestSessionId });
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to revoke session', { error });
      res.status(500).json({ error: 'Failed to revoke session' });
    }
  });

  // Get session activity
  router.get('/api/guest/sessions/:guestSessionId/activity', async (req: Request, res: Response) => {
    try {
      const { guestSessionId } = req.params;
      const limit = Math.min(parseInt(req.query.limit as string, 10) || 50, 100);

      const activity = await service.getSessionActivity(guestSessionId, limit);

      logger.debug('Session activity retrieved', { guestSessionId, count: activity.length });
      res.json(activity);
    } catch (error) {
      logger.error('Failed to get session activity', { error });
      res.status(500).json({ error: 'Failed to get session activity' });
    }
  });

  // Get session stats
  router.get('/api/guest/user/:userId/stats', async (req: Request, res: Response) => {
    try {
      const { userId } = req.params;

      const stats = await service.getSessionStats(userId);

      logger.info('Session stats retrieved', { userId });
      res.json(stats);
    } catch (error) {
      logger.error('Failed to get session stats', { error });
      res.status(500).json({ error: 'Failed to get session stats' });
    }
  });

  // Cleanup expired sessions (admin endpoint)
  router.post('/api/guest/cleanup', async (req: Request, res: Response) => {
    try {
      const count = await service.cleanupExpiredSessions();

      logger.info('Expired sessions cleaned up', { count });
      res.json({ cleaned: count });
    } catch (error) {
      logger.error('Failed to cleanup expired sessions', { error });
      res.status(500).json({ error: 'Failed to cleanup expired sessions' });
    }
  });

  return router;
}

export { GuestSessionService } from '../services/guest-sessions';
