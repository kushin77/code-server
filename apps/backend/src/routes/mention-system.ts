#!/usr/bin/env node
// @file        apps/backend/src/routes/mention-system.ts
// @module      collaboration/mention-system
// @description REST API routes for @mention system
// @owner       collab-2.5
// @status      active

import { Router } from 'express';
import { Pool } from 'pg';
import { MentionSystemService, ParseMentionsRequest, SendNotificationRequest } from '../services/mention-system';
import { getLogger } from '../lib/logger';

const logger = getLogger('MentionSystemRoutes');

export function initializeMentionSystemRoutes(pool: Pool): Router {
  const router = Router();
  const mentionService = new MentionSystemService(pool);

  // Initialize the service
  mentionService.initialize().catch(error => {
    logger.error('Failed to initialize mention system service', { error });
  });

  // POST /api/mentions/parse - Parse mentions in text
  router.post('/parse', async (req, res) => {
    try {
      const { text, author, context } = req.body;

      if (!text || !author || !context) {
        return res.status(400).json({ error: 'Missing required fields: text, author, context' });
      }

      const request: ParseMentionsRequest = { text, author, context };
      const mentions = await mentionService.processMentions(request);

      res.json({
        success: true,
        mentionCount: mentions.length,
        mentions,
      });
    } catch (error) {
      logger.error('Failed to parse mentions', { error, body: req.body });
      res.status(500).json({ error: 'Failed to parse mentions' });
    }
  });

  // POST /api/mentions/send - Send notifications for a mention
  router.post('/send', async (req, res) => {
    try {
      const { mention, channels, matrixRoomId, emailAddress } = req.body;

      if (!mention || !channels || !Array.isArray(channels)) {
        return res.status(400).json({ error: 'Missing required fields: mention, channels' });
      }

      const request: SendNotificationRequest = {
        mention,
        channels,
        matrixRoomId,
        emailAddress,
      };

      await mentionService.sendNotifications(request);

      res.json({ success: true, message: 'Notifications sent' });
    } catch (error) {
      logger.error('Failed to send notifications', { error, body: req.body });
      res.status(500).json({ error: 'Failed to send notifications' });
    }
  });

  // GET /api/mentions/user/:userId - Get all mentions for a user
  router.get('/user/:userId', async (req, res) => {
    try {
      const { userId } = req.params;
      const { limit = '50', offset = '0' } = req.query;

      const mentions = await mentionService.getMentionsForUser(
        userId,
        parseInt(limit as string),
        parseInt(offset as string)
      );

      res.json({
        success: true,
        mentionCount: mentions.length,
        mentions,
      });
    } catch (error) {
      logger.error('Failed to get mentions for user', { error, userId: req.params.userId });
      res.status(500).json({ error: 'Failed to get mentions' });
    }
  });

  // GET /api/mentions/preferences/:userId - Get notification preferences
  router.get('/preferences/:userId', async (req, res) => {
    try {
      const { userId } = req.params;
      const preferences = await mentionService.getMentionNotificationPreferences(userId);

      if (!preferences) {
        return res.status(404).json({ error: 'Preferences not found' });
      }

      res.json({
        success: true,
        preferences,
      });
    } catch (error) {
      logger.error('Failed to get preferences', { error, userId: req.params.userId });
      res.status(500).json({ error: 'Failed to get preferences' });
    }
  });

  // PUT /api/mentions/preferences/:userId - Set notification preferences
  router.put('/preferences/:userId', async (req, res) => {
    try {
      const { userId } = req.params;
      const preferences = req.body;

      await mentionService.setMentionNotificationPreferences(userId, preferences);

      res.json({
        success: true,
        message: 'Preferences updated',
      });
    } catch (error) {
      logger.error('Failed to set preferences', { error, userId: req.params.userId, body: req.body });
      res.status(500).json({ error: 'Failed to set preferences' });
    }
  });

  // POST /api/mentions/digest/generate - Generate email digest
  router.post('/digest/generate', async (req, res) => {
    try {
      const { userId, frequency = 'daily' } = req.body;

      if (!userId) {
        return res.status(400).json({ error: 'Missing required field: userId' });
      }

      const digest = await mentionService.generateEmailDigest(userId, frequency);

      res.json({
        success: true,
        digest,
      });
    } catch (error) {
      logger.error('Failed to generate email digest', { error, body: req.body });
      res.status(500).json({ error: 'Failed to generate email digest' });
    }
  });

  // POST /api/mentions/digest/mark-sent - Mark digest entries as sent
  router.post('/digest/mark-sent', async (req, res) => {
    try {
      const { userId, mentionIds } = req.body;

      if (!userId || !Array.isArray(mentionIds)) {
        return res.status(400).json({ error: 'Missing required fields: userId, mentionIds' });
      }

      await mentionService.markDigestAsSent(userId, mentionIds);

      res.json({
        success: true,
        message: 'Digest marked as sent',
      });
    } catch (error) {
      logger.error('Failed to mark digest as sent', { error, body: req.body });
      res.status(500).json({ error: 'Failed to mark digest as sent' });
    }
  });

  return router;
}

export { MentionSystemService } from '../services/mention-system';