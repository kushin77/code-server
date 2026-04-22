#!/usr/bin/env node
// @file        apps/backend/src/routes/activity-feed.ts
// @module      collaboration/activity-feed
// @description REST API routes for activity feed service
// @owner       collab-4.5
// @status      active

import { Router } from 'express';
import { Pool } from 'pg';
import { ActivityFeedService, type ActivityType, type ActivityStatus, type ActivityFilter } from '../services/activity-feed';
import { getLogger } from '../lib/logger';

const logger = getLogger('ActivityFeedRoutes');

export function initializeActivityFeedRoutes(pool: Pool): Router {
  const router = Router();
  const activityFeedService = new ActivityFeedService(pool);

  activityFeedService.initialize().catch(error => {
    logger.error('Failed to initialize activity feed service', { error });
  });

  // POST /api/activity - Record activity
  router.post('/', async (req, res) => {
    try {
      const { type, title, status = 'info', description, deepLink, userId, repository, metadata, tags } = req.body;

      if (!type || !title) {
        return res.status(400).json({
          error: 'Missing required fields: type, title',
        });
      }

      const activity = await activityFeedService.recordActivity(type as ActivityType, title, status as ActivityStatus, {
        description,
        deepLink,
        userId,
        repository,
        metadata,
        tags,
      });

      res.status(201).json({
        success: true,
        activity,
      });
    } catch (error) {
      logger.error('Failed to record activity', { error, body: req.body });
      res.status(500).json({ error: 'Failed to record activity' });
    }
  });

  // GET /api/activity/:activityId - Get activity by ID
  router.get('/:activityId', async (req, res) => {
    try {
      const { activityId } = req.params;
      const activity = await activityFeedService.getActivity(activityId);

      if (!activity) {
        return res.status(404).json({ error: 'Activity not found' });
      }

      res.json({
        success: true,
        activity,
      });
    } catch (error) {
      logger.error('Failed to get activity', { error, activityId: req.params.activityId });
      res.status(500).json({ error: 'Failed to get activity' });
    }
  });

  // GET /api/activity - List activities with filtering
  router.get('/', async (req, res) => {
    try {
      const { types, statuses, userId, repository, search, tags, limit = '50' } = req.query;

      const filter: ActivityFilter = {};

      if (types) {
        filter.types = typeof types === 'string' ? [types as ActivityType] : (types as ActivityType[]);
      }

      if (statuses) {
        filter.statuses = typeof statuses === 'string' ? [statuses as ActivityStatus] : (statuses as ActivityStatus[]);
      }

      if (userId) {
        filter.userId = userId as string;
      }

      if (repository) {
        filter.repository = repository as string;
      }

      if (search) {
        filter.search = search as string;
      }

      if (tags) {
        filter.tags = typeof tags === 'string' ? [tags] : (tags as string[]);
      }

      const activities = await activityFeedService.getActivities(filter, parseInt(limit as string, 10));

      res.json({
        success: true,
        count: activities.length,
        activities,
      });
    } catch (error) {
      logger.error('Failed to get activities', { error });
      res.status(500).json({ error: 'Failed to get activities' });
    }
  });

  // GET /api/activity/stats - Get activity statistics
  router.get('/stats', async (req, res) => {
    try {
      const { types, statuses, repository } = req.query;

      const filter: ActivityFilter = {};

      if (types) {
        filter.types = typeof types === 'string' ? [types as ActivityType] : (types as ActivityType[]);
      }

      if (statuses) {
        filter.statuses = typeof statuses === 'string' ? [statuses as ActivityStatus] : (statuses as ActivityStatus[]);
      }

      if (repository) {
        filter.repository = repository as string;
      }

      const stats = await activityFeedService.getStats(filter);

      res.json({
        success: true,
        stats,
      });
    } catch (error) {
      logger.error('Failed to get stats', { error });
      res.status(500).json({ error: 'Failed to get stats' });
    }
  });

  // POST /api/activity/subscription - Create subscription
  router.post('/subscription', async (req, res) => {
    try {
      const { userId, filters } = req.body;

      if (!userId) {
        return res.status(400).json({
          error: 'Missing required field: userId',
        });
      }

      const subscription = await activityFeedService.createSubscription(userId, filters || {});

      res.status(201).json({
        success: true,
        subscription,
      });
    } catch (error) {
      logger.error('Failed to create subscription', { error, body: req.body });
      res.status(500).json({ error: 'Failed to create subscription' });
    }
  });

  // GET /api/activity/subscription/:subscriptionId - Get subscription
  router.get('/subscription/:subscriptionId', async (req, res) => {
    try {
      const { subscriptionId } = req.params;
      const subscription = await activityFeedService.getSubscription(subscriptionId);

      if (!subscription) {
        return res.status(404).json({ error: 'Subscription not found' });
      }

      res.json({
        success: true,
        subscription,
      });
    } catch (error) {
      logger.error('Failed to get subscription', { error, subscriptionId: req.params.subscriptionId });
      res.status(500).json({ error: 'Failed to get subscription' });
    }
  });

  // GET /api/activity/subscriptions/:userId - Get user subscriptions
  router.get('/subscriptions/:userId', async (req, res) => {
    try {
      const { userId } = req.params;
      const subscriptions = await activityFeedService.getUserSubscriptions(userId);

      res.json({
        success: true,
        count: subscriptions.length,
        subscriptions,
      });
    } catch (error) {
      logger.error('Failed to get user subscriptions', { error, userId: req.params.userId });
      res.status(500).json({ error: 'Failed to get subscriptions' });
    }
  });

  // DELETE /api/activity/subscription/:subscriptionId - Delete subscription
  router.delete('/subscription/:subscriptionId', async (req, res) => {
    try {
      const { subscriptionId } = req.params;
      await activityFeedService.deleteSubscription(subscriptionId);

      res.json({
        success: true,
        message: 'Subscription deleted',
      });
    } catch (error) {
      logger.error('Failed to delete subscription', { error, subscriptionId: req.params.subscriptionId });
      res.status(500).json({ error: 'Failed to delete subscription' });
    }
  });

  // POST /api/activity/:activityId/notify - Notify subscribers
  router.post('/:activityId/notify', async (req, res) => {
    try {
      const { activityId } = req.params;
      const notifiedCount = await activityFeedService.notifySubscribers(activityId);

      res.json({
        success: true,
        notifiedCount,
      });
    } catch (error) {
      logger.error('Failed to notify subscribers', { error, activityId: req.params.activityId });
      res.status(500).json({ error: 'Failed to notify subscribers' });
    }
  });

  // GET /api/activity/subscription/:subscriptionId/notifications - Get pending notifications
  router.get('/subscription/:subscriptionId/notifications', async (req, res) => {
    try {
      const { subscriptionId } = req.params;
      const { limit = '10' } = req.query;
      const notifications = await activityFeedService.getPendingNotifications(subscriptionId, parseInt(limit as string, 10));

      res.json({
        success: true,
        count: notifications.length,
        notifications,
      });
    } catch (error) {
      logger.error('Failed to get pending notifications', { error, subscriptionId: req.params.subscriptionId });
      res.status(500).json({ error: 'Failed to get notifications' });
    }
  });

  // POST /api/activity/:activityId/read/:subscriptionId - Mark notification as read
  router.post('/:activityId/read/:subscriptionId', async (req, res) => {
    try {
      const { activityId, subscriptionId } = req.params;
      await activityFeedService.markNotificationAsRead(activityId, subscriptionId);

      res.json({
        success: true,
        message: 'Notification marked as read',
      });
    } catch (error) {
      logger.error('Failed to mark notification as read', { error, activityId: req.params.activityId });
      res.status(500).json({ error: 'Failed to mark notification as read' });
    }
  });

  return router;
}

export { ActivityFeedService } from '../services/activity-feed';