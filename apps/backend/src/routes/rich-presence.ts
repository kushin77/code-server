#!/usr/bin/env node
// @file        apps/backend/src/routes/rich-presence.ts
// @module      collaboration/rich-presence
// @description REST API routes for rich presence state
// @owner       collab-4.1
// @status      active

import { Request, Response, Router } from 'express';
import { RichPresenceService } from '../services/rich-presence';
import { getLogger } from '../lib/logger';

const logger = getLogger('RichPresenceRoutes');

export function initializeRichPresenceRoutes(service: RichPresenceService): Router {
  const router = Router();

  router.post('/api/presence/users/:userId', async (req: Request, res: Response) => {
    try {
      const record = await service.upsertPresence({
        userId: req.params.userId,
        teamId: req.body?.teamId,
        filePath: req.body?.filePath,
        functionName: req.body?.functionName,
        task: req.body?.task,
        customStatus: req.body?.customStatus,
        sessionId: req.body?.sessionId,
      });

      res.status(201).json(record);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to upsert presence';
      logger.error('Failed to upsert presence', { error, body: req.body, params: req.params });
      res.status(400).json({ error: message });
    }
  });

  router.get('/api/presence/users/:userId', async (req: Request, res: Response) => {
    try {
      const presence = await service.getPresence(req.params.userId);
      if (!presence) {
        return res.status(404).json({ error: 'Presence not found' });
      }

      res.json(presence);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to get presence';
      logger.error('Failed to get presence', { error, params: req.params });
      res.status(400).json({ error: message });
    }
  });

  router.get('/api/presence/teams/:teamId', async (req: Request, res: Response) => {
    try {
      const records = await service.listTeamPresence(req.params.teamId);
      res.json({ teamId: req.params.teamId, count: records.length, records });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to list team presence';
      logger.error('Failed to list team presence', { error, params: req.params });
      res.status(400).json({ error: message });
    }
  });

  router.delete('/api/presence/users/:userId', async (req: Request, res: Response) => {
    try {
      await service.clearPresence(req.params.userId);
      res.json({ success: true });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to clear presence';
      logger.error('Failed to clear presence', { error, params: req.params });
      res.status(400).json({ error: message });
    }
  });

  return router;
}

export { RichPresenceService } from '../services/rich-presence';
