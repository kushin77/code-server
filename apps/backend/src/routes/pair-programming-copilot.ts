#!/usr/bin/env node
// @file        apps/backend/src/routes/pair-programming-copilot.ts
// @module      collaboration/pair-programming-copilot
// @description REST API endpoints for pair programming AI copilot
// @owner       collab-3.2
// @status      active

import { Request, Response, Router } from 'express';
import { Pool } from 'pg';
import { PairProgrammingAICopilotService } from '../services/pair-programming-copilot';
import { getLogger } from '../lib/logger';

const logger = getLogger('PairProgrammingAICopilotRoutes');

function toOptionalNumber(value: unknown): number | undefined {
  if (value === null || value === undefined || value === '') {
    return undefined;
  }
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : undefined;
}

export function initializePairProgrammingAICopilotRoutes(pool: Pool): Router {
  const router = Router();
  const service = new PairProgrammingAICopilotService(pool);

  service.initialize().catch((error) => {
    logger.error('Failed to initialize pair copilot service', { error });
  });

  router.post('/api/pair-copilot/context', async (req: Request, res: Response) => {
    try {
      const entry = await service.upsertContext({
        sessionId: req.body?.sessionId,
        userId: req.body?.userId,
        filePath: req.body?.filePath,
        functionName: req.body?.functionName,
        editSummary: req.body?.editSummary,
        cursorLine: toOptionalNumber(req.body?.cursorLine),
        cursorColumn: toOptionalNumber(req.body?.cursorColumn),
      });

      res.status(201).json(entry);
    } catch (error) {
      logger.error('Failed to upsert pair copilot context', { error, body: req.body });
      const message = error instanceof Error ? error.message : 'Failed to upsert context';
      res.status(400).json({ error: message });
    }
  });

  router.get('/api/pair-copilot/sessions/:sessionId/context', async (req: Request, res: Response) => {
    try {
      const context = await service.getSharedContext(req.params.sessionId, req.query.requesterId as string | undefined);
      res.json(context);
    } catch (error) {
      logger.error('Failed to get shared pair copilot context', { error, params: req.params, query: req.query });
      const message = error instanceof Error ? error.message : 'Failed to get shared context';
      res.status(400).json({ error: message });
    }
  });

  router.post('/api/pair-copilot/sessions/:sessionId/suggestions', async (req: Request, res: Response) => {
    try {
      const suggestions = await service.generateSuggestions({
        sessionId: req.params.sessionId,
        requesterId: req.body?.requesterId,
        prompt: req.body?.prompt,
        maxSuggestions: toOptionalNumber(req.body?.maxSuggestions),
      });

      res.status(201).json(suggestions);
    } catch (error) {
      logger.error('Failed to generate pair copilot suggestions', { error, params: req.params, body: req.body });
      const message = error instanceof Error ? error.message : 'Failed to generate suggestions';
      res.status(400).json({ error: message });
    }
  });

  return router;
}

export { PairProgrammingAICopilotService } from '../services/pair-programming-copilot';
