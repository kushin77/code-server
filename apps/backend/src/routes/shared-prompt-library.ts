#!/usr/bin/env node
// @file        apps/backend/src/routes/shared-prompt-library.ts
// @module      collaboration/shared-prompt-library
// @description Shared prompt library REST API endpoints
// @owner       collab-3.5
// @status      active

import { Router, Request, Response } from 'express';
import { SharedPromptLibraryService, PromptCategory, PromptVisibility } from '../services/shared-prompt-library';
import { getLogger } from '../lib/logger';

const logger = getLogger('SharedPromptLibraryRoutes');

export function initializeSharedPromptLibraryRoutes(service: SharedPromptLibraryService): Router {
  const router = Router();

  // Create prompt
  router.post('/api/prompts', async (req: Request, res: Response) => {
    try {
      const { teamId, name, content, category, createdBy, description, visibility, tags } = req.body;

      if (!teamId || !name || !content || !category || !createdBy) {
        return res.status(400).json({ error: 'Missing required fields' });
      }

      const prompt = await service.createPrompt(
        teamId,
        name,
        content,
        category as PromptCategory,
        createdBy,
        { description, visibility: visibility as PromptVisibility, tags }
      );

      logger.info('Prompt created via API', { teamId, promptId: prompt.id, name });
      res.status(201).json(prompt);
    } catch (error) {
      logger.error('Failed to create prompt', { error });
      res.status(500).json({ error: 'Failed to create prompt' });
    }
  });

  // Get prompt
  router.get('/api/prompts/:promptId', async (req: Request, res: Response) => {
    try {
      const { promptId } = req.params;

      const prompt = await service.getPrompt(promptId);

      if (!prompt) {
        return res.status(404).json({ error: 'Prompt not found' });
      }

      logger.debug('Prompt retrieved', { promptId });
      res.json(prompt);
    } catch (error) {
      logger.error('Failed to get prompt', { error });
      res.status(500).json({ error: 'Failed to get prompt' });
    }
  });

  // List team prompts
  router.get('/api/teams/:teamId/prompts', async (req: Request, res: Response) => {
    try {
      const { teamId } = req.params;
      const { category } = req.query;

      const prompts = await service.listTeamPrompts(teamId, category as PromptCategory);

      logger.info('Team prompts retrieved', { teamId, count: prompts.length });
      res.json(prompts);
    } catch (error) {
      logger.error('Failed to list team prompts', { error });
      res.status(500).json({ error: 'Failed to list team prompts' });
    }
  });

  // Update prompt
  router.put('/api/prompts/:promptId', async (req: Request, res: Response) => {
    try {
      const { promptId } = req.params;
      const { content, updatedBy, changeDescription } = req.body;

      if (!content || !updatedBy) {
        return res.status(400).json({ error: 'Missing content or updatedBy' });
      }

      const prompt = await service.updatePrompt(promptId, content, updatedBy, changeDescription);

      logger.info('Prompt updated via API', { promptId, version: prompt.version });
      res.json(prompt);
    } catch (error) {
      logger.error('Failed to update prompt', { error });
      res.status(500).json({ error: 'Failed to update prompt' });
    }
  });

  // Get prompt suggestions
  router.post('/api/prompts/suggest', async (req: Request, res: Response) => {
    try {
      const { teamId, context, category } = req.body;

      if (!teamId || !context) {
        return res.status(400).json({ error: 'Missing teamId or context' });
      }

      const suggestions = await service.suggestPrompts(teamId, context, category as PromptCategory);

      logger.debug('Prompts suggested', { teamId, count: suggestions.length });
      res.json(suggestions);
    } catch (error) {
      logger.error('Failed to suggest prompts', { error });
      res.status(500).json({ error: 'Failed to suggest prompts' });
    }
  });

  // Track usage
  router.post('/api/prompts/:promptId/usage', async (req: Request, res: Response) => {
    try {
      const { promptId } = req.params;
      const { userId, context } = req.body;

      if (!userId) {
        return res.status(400).json({ error: 'Missing userId' });
      }

      await service.trackUsage(promptId, userId, context);

      logger.debug('Usage tracked', { promptId, userId });
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to track usage', { error });
      res.status(500).json({ error: 'Failed to track usage' });
    }
  });

  // Rate prompt
  router.post('/api/prompts/:promptId/rate', async (req: Request, res: Response) => {
    try {
      const { promptId } = req.params;
      const { userId, rating, comment } = req.body;

      if (!userId || rating === undefined) {
        return res.status(400).json({ error: 'Missing userId or rating' });
      }

      await service.ratePrompt(promptId, userId, rating, comment);

      logger.info('Prompt rated via API', { promptId, userId, rating });
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to rate prompt', { error });
      res.status(500).json({ error: 'Failed to rate prompt' });
    }
  });

  // Get prompt versions
  router.get('/api/prompts/:promptId/versions', async (req: Request, res: Response) => {
    try {
      const { promptId } = req.params;

      const versions = await service.getPromptVersions(promptId);

      logger.debug('Prompt versions retrieved', { promptId, count: versions.length });
      res.json(versions);
    } catch (error) {
      logger.error('Failed to get prompt versions', { error });
      res.status(500).json({ error: 'Failed to get prompt versions' });
    }
  });

  return router;
}

export { SharedPromptLibraryService } from '../services/shared-prompt-library';
