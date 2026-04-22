#!/usr/bin/env node
// @file        apps/backend/src/routes/help-queue.ts
// @module      collaboration/help-queue
// @description REST API routes for help queue service
// @owner       collab-4.7
// @status      active

import { Router } from 'express';
import { Pool } from 'pg';
import { HelpQueueService, type CodeSnippet, type HelpUrgency } from '../services/help-queue';
import { getLogger } from '../lib/logger';

const logger = getLogger('HelpQueueRoutes');

export function initializeHelpQueueRoutes(pool: Pool): Router {
  const router = Router();
  const helpQueueService = new HelpQueueService(pool);

  helpQueueService.initialize().catch(error => {
    logger.error('Failed to initialize help queue service', { error });
  });

  // POST /api/help - Create help request
  router.post('/', async (req, res) => {
    try {
      const { userId, codeSnippet, question, urgency = 'normal', tags } = req.body;

      if (!userId || !codeSnippet || !question) {
        return res.status(400).json({
          error: 'Missing required fields: userId, codeSnippet, question',
        });
      }

      const request = await helpQueueService.createRequest(
        userId,
        codeSnippet as CodeSnippet,
        question,
        (urgency as HelpUrgency) || 'normal',
        tags
      );

      res.status(201).json({
        success: true,
        request,
      });
    } catch (error) {
      logger.error('Failed to create help request', { error, body: req.body });
      res.status(500).json({ error: 'Failed to create request' });
    }
  });

  // GET /api/help/:requestId - Get help request
  router.get('/:requestId', async (req, res) => {
    try {
      const { requestId } = req.params;
      const request = await helpQueueService.getRequest(requestId);

      if (!request) {
        return res.status(404).json({ error: 'Request not found' });
      }

      res.json({
        success: true,
        request,
      });
    } catch (error) {
      logger.error('Failed to get help request', { error, requestId: req.params.requestId });
      res.status(500).json({ error: 'Failed to get request' });
    }
  });

  // GET /api/help/user/:userId - Get user's requests
  router.get('/user/:userId', async (req, res) => {
    try {
      const { userId } = req.params;
      const { status } = req.query;

      const requests = await helpQueueService.getUserRequests(userId, status as any);

      res.json({
        success: true,
        count: requests.length,
        requests,
      });
    } catch (error) {
      logger.error('Failed to get user requests', { error, userId: req.params.userId });
      res.status(500).json({ error: 'Failed to get requests' });
    }
  });

  // GET /api/help/queue/open - Get open requests
  router.get('/queue/open', async (req, res) => {
    try {
      const { limit = '10' } = req.query;
      const requests = await helpQueueService.getOpenRequests(parseInt(limit as string, 10));

      res.json({
        success: true,
        count: requests.length,
        requests,
      });
    } catch (error) {
      logger.error('Failed to get open requests', { error });
      res.status(500).json({ error: 'Failed to get open requests' });
    }
  });

  // POST /api/help/:requestId/enrich - Enrich question with AI
  router.post('/:requestId/enrich', async (req, res) => {
    try {
      const { requestId } = req.params;
      const { enrichedQuestion } = req.body;

      if (!enrichedQuestion) {
        return res.status(400).json({ error: 'Missing required field: enrichedQuestion' });
      }

      await helpQueueService.enrichQuestion(requestId, enrichedQuestion);

      res.json({
        success: true,
        message: 'Question enriched',
      });
    } catch (error) {
      logger.error('Failed to enrich question', { error, requestId: req.params.requestId });
      res.status(500).json({ error: 'Failed to enrich question' });
    }
  });

  // POST /api/help/:requestId/assign - Assign to expert
  router.post('/:requestId/assign', async (req, res) => {
    try {
      const { requestId } = req.params;
      const { expertId } = req.body;

      if (!expertId) {
        return res.status(400).json({ error: 'Missing required field: expertId' });
      }

      await helpQueueService.assignToExpert(requestId, expertId);

      res.json({
        success: true,
        message: 'Request assigned',
      });
    } catch (error) {
      logger.error('Failed to assign request', { error, requestId: req.params.requestId });
      res.status(500).json({ error: 'Failed to assign request' });
    }
  });

  // POST /api/help/:requestId/respond - Add response
  router.post('/:requestId/respond', async (req, res) => {
    try {
      const { requestId } = req.params;
      const { expertId, response, codeProposal } = req.body;

      if (!expertId || !response) {
        return res.status(400).json({
          error: 'Missing required fields: expertId, response',
        });
      }

      await helpQueueService.respondToRequest(requestId, expertId, response, codeProposal);

      res.json({
        success: true,
        message: 'Response added',
      });
    } catch (error) {
      logger.error('Failed to add response', { error, requestId: req.params.requestId });
      res.status(500).json({ error: 'Failed to add response' });
    }
  });

  // POST /api/help/:requestId/resolve - Resolve request
  router.post('/:requestId/resolve', async (req, res) => {
    try {
      const { requestId } = req.params;
      const { expertId } = req.body;

      if (!expertId) {
        return res.status(400).json({ error: 'Missing required field: expertId' });
      }

      const slaBroken = await helpQueueService.resolveRequest(requestId, expertId);

      res.json({
        success: true,
        message: 'Request resolved',
        slaMetric: slaBroken,
      });
    } catch (error) {
      logger.error('Failed to resolve request', { error, requestId: req.params.requestId });
      res.status(500).json({ error: 'Failed to resolve request' });
    }
  });

  // GET /api/help/metrics/sla - Get SLA metrics
  router.get('/metrics/sla', async (req, res) => {
    try {
      const { timeframeMs = (7 * 24 * 60 * 60 * 1000).toString() } = req.query;

      const metrics = await helpQueueService.getSLAMetrics(parseInt(timeframeMs as string, 10));

      res.json({
        success: true,
        metrics,
      });
    } catch (error) {
      logger.error('Failed to get SLA metrics', { error });
      res.status(500).json({ error: 'Failed to get metrics' });
    }
  });

  // POST /api/help/experts/register - Register expert
  router.post('/experts/register', async (req, res) => {
    try {
      const { userId, expertise } = req.body;

      if (!userId || !Array.isArray(expertise)) {
        return res.status(400).json({
          error: 'Missing required fields: userId (string), expertise (array)',
        });
      }

      await helpQueueService.registerExpert(userId, expertise);

      res.json({
        success: true,
        message: 'Expert registered',
      });
    } catch (error) {
      logger.error('Failed to register expert', { error, body: req.body });
      res.status(500).json({ error: 'Failed to register expert' });
    }
  });

  // GET /api/help/experts/available - Get available experts
  router.get('/experts/available', async (req, res) => {
    try {
      const { tags } = req.query;
      const tagArray = tags ? (typeof tags === 'string' ? [tags] : tags) : undefined;

      const experts = await helpQueueService.getAvailableExperts(tagArray as string[]);

      res.json({
        success: true,
        count: experts.length,
        experts,
      });
    } catch (error) {
      logger.error('Failed to get available experts', { error });
      res.status(500).json({ error: 'Failed to get experts' });
    }
  });

  return router;
}

export { HelpQueueService } from '../services/help-queue';