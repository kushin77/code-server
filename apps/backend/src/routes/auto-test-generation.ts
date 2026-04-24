#!/usr/bin/env node
// @file        apps/backend/src/routes/auto-test-generation.ts
// @module      collaboration/auto-test-generation
// @description Auto test generation REST endpoints
// @owner       collab-3.9
// @status      active

import { Router, Request, Response } from 'express';
import { AutoTestGenerationService, GenerateTestsRequest } from '../services/auto-test-generation';

export function initializeAutoTestGenerationRoutes(service: AutoTestGenerationService): Router {
  const router = Router();

  // POST /api/tests/generate - Generate tests for a bug fix session
  router.post('/tests/generate', async (req: Request, res: Response) => {
    try {
      const { sessionId, changedFiles, aiContext, bugDescription, fixDescription, suggestedTests } = req.body;

      if (!sessionId || !changedFiles || !bugDescription || !fixDescription) {
        return res.status(400).json({ error: 'Missing required fields' });
      }

      const request: GenerateTestsRequest = {
        sessionId,
        changedFiles,
        aiContext,
        bugDescription,
        fixDescription,
      };

      const tests = await service.generateTestsForSession(request, suggestedTests || []);
      res.json(tests);
    } catch (error) {
      res.status(500).json({ error: String(error) });
    }
  });

  // GET /api/tests/:suggestionId - Get a specific test suggestion
  router.get('/tests/:suggestionId', async (req: Request, res: Response) => {
    try {
      const { suggestionId } = req.params;
      const test = await service.getTestSuggestion(suggestionId);

      if (!test) {
        return res.status(404).json({ error: 'Test suggestion not found' });
      }

      res.json(test);
    } catch (error) {
      res.status(500).json({ error: String(error) });
    }
  });

  // POST /api/tests/:suggestionId/accept - Accept a test suggestion
  router.post('/tests/:suggestionId/accept', async (req: Request, res: Response) => {
    try {
      const { suggestionId } = req.params;
      const test = await service.acceptTestSuggestion(suggestionId);
      res.json(test);
    } catch (error) {
      res.status(500).json({ error: String(error) });
    }
  });

  // POST /api/tests/:suggestionId/reject - Reject a test suggestion
  router.post('/tests/:suggestionId/reject', async (req: Request, res: Response) => {
    try {
      const { suggestionId } = req.params;
      const { reason } = req.body;

      if (!reason) {
        return res.status(400).json({ error: 'Rejection reason is required' });
      }

      const test = await service.rejectTestSuggestion(suggestionId, reason);
      res.json(test);
    } catch (error) {
      res.status(500).json({ error: String(error) });
    }
  });

  // GET /api/sessions/:sessionId/tests - Get all test suggestions for a session
  router.get('/sessions/:sessionId/tests', async (req: Request, res: Response) => {
    try {
      const { sessionId } = req.params;
      const { status } = req.query;
      const tests = await service.getSessionTestSuggestions(sessionId, status as string | undefined);
      res.json(tests);
    } catch (error) {
      res.status(500).json({ error: String(error) });
    }
  });

  // POST /api/tests/:suggestionId/use - Mark a test as used
  router.post('/tests/:suggestionId/use', async (req: Request, res: Response) => {
    try {
      const { suggestionId } = req.params;
      const test = await service.markTestAsUsed(suggestionId);
      res.json(test);
    } catch (error) {
      res.status(500).json({ error: String(error) });
    }
  });

  // POST /api/tests/:suggestionId/execute - Record test execution result
  router.post('/tests/:suggestionId/execute', async (req: Request, res: Response) => {
    try {
      const { suggestionId } = req.params;
      const { passed, durationMs, errorMessage } = req.body;

      if (passed === undefined || durationMs === undefined) {
        return res.status(400).json({ error: 'Missing required fields' });
      }

      await service.recordTestExecution(suggestionId, passed, durationMs, errorMessage);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ error: String(error) });
    }
  });

  // GET /api/sessions/:sessionId/metrics - Get test metrics for a session
  router.get('/sessions/:sessionId/metrics', async (req: Request, res: Response) => {
    try {
      const { sessionId } = req.params;
      const metrics = await service.getTestMetrics(sessionId);
      res.json(metrics);
    } catch (error) {
      res.status(500).json({ error: String(error) });
    }
  });

  // POST /api/tests/:suggestionId/feedback - Add feedback on test
  router.post('/tests/:suggestionId/feedback', async (req: Request, res: Response) => {
    try {
      const { suggestionId } = req.params;
      const { userId, feedbackType, comment } = req.body;

      if (!userId || !feedbackType) {
        return res.status(400).json({ error: 'Missing required fields' });
      }

      await service.addFeedback(suggestionId, userId, feedbackType, comment);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ error: String(error) });
    }
  });

  return router;
}
