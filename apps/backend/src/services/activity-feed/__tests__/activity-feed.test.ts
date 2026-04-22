#!/usr/bin/env node
// @file        apps/backend/src/services/activity-feed/__tests__/activity-feed.test.ts
// @module      collaboration/activity-feed
// @description Unit tests for activity feed service
// @owner       collab-4.5
// @status      active

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { Pool } from 'pg';
import { ActivityFeedService } from '../index';

vi.mock('../../../lib/logger', () => ({
  getLogger: vi.fn(() => ({
    info: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
  })),
}));

const mockPool = {
  connect: vi.fn(),
  end: vi.fn(),
} as unknown as Pool;

describe('ActivityFeedService', () => {
  let service: ActivityFeedService;
  let mockClient: any;

  beforeEach(async () => {
    vi.clearAllMocks();

    mockClient = {
      query: vi.fn(),
      release: vi.fn(),
    };

    (mockPool.connect as any).mockResolvedValue(mockClient);

    service = new ActivityFeedService(mockPool);
    mockClient.query.mockResolvedValue({ rows: [] });
    await service.initialize();
  });

  describe('initialization', () => {
    it('should initialize with database schema', async () => {
      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('CREATE TABLE IF NOT EXISTS activities')
      );
    });

    it('should create all required tables', async () => {
      const createTableCalls = mockClient.query.mock.calls.filter(call =>
        call[0].includes('CREATE TABLE')
      );
      expect(createTableCalls.length).toBeGreaterThanOrEqual(4);
    });
  });

  describe('recordActivity', () => {
    it('should record a commit activity', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT activity
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT search index

      const activity = await service.recordActivity(
        'commit',
        'Fix: resolve memory leak in WebSocket handler',
        'success',
        { userId: 'user-1', repository: 'code-server', tags: ['memory', 'websocket'] }
      );

      expect(activity).toBeDefined();
      expect(activity.type).toBe('commit');
      expect(activity.title).toBe('Fix: resolve memory leak in WebSocket handler');
      expect(activity.status).toBe('success');
    });

    it('should record a deployment activity', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT activity
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT search index

      const activity = await service.recordActivity(
        'deploy',
        'Deploy v1.5.0 to production',
        'success',
        {
          deepLink: 'https://deploy.example.com/1234',
          repository: 'code-server',
          userId: 'deployer-1',
          metadata: { version: '1.5.0', duration: 120 },
        }
      );

      expect(activity.type).toBe('deploy');
      expect(activity.deepLink).toBe('https://deploy.example.com/1234');
      expect(activity.metadata?.version).toBe('1.5.0');
    });

    it('should record a test flake', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT activity
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT search index

      const activity = await service.recordActivity(
        'test-flake',
        'Intermittent timeout in auth tests',
        'warning',
        {
          repository: 'code-server',
          tags: ['testing', 'auth'],
          metadata: { failureRate: 0.3 },
        }
      );

      expect(activity.type).toBe('test-flake');
      expect(activity.status).toBe('warning');
    });

    it('should create search index for activity', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT activity
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT search index

      await service.recordActivity(
        'pr',
        'Add support for async/await in resolver',
        'success',
        { description: 'Implement async patterns for better performance' }
      );

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO activity_search_index'),
        expect.any(Array)
      );
    });
  });

  describe('getActivity', () => {
    it('should retrieve activity by ID', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [{
          id: 'activity-1',
          type: 'commit',
          status: 'success',
          title: 'Fix bug',
          description: null,
          deep_link: null,
          user_id: 'user-1',
          repository: 'repo',
          timestamp: new Date(),
          metadata: null,
          tags: [],
        }],
      });

      const activity = await service.getActivity('activity-1');

      expect(activity).toBeDefined();
      expect(activity?.id).toBe('activity-1');
      expect(activity?.type).toBe('commit');
    });

    it('should return null if activity not found', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      const activity = await service.getActivity('unknown');

      expect(activity).toBeNull();
    });
  });

  describe('getActivities', () => {
    it('should retrieve activities without filter', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'activity-1',
            type: 'commit',
            status: 'success',
            title: 'Commit 1',
            timestamp: new Date(),
          },
          {
            id: 'activity-2',
            type: 'deploy',
            status: 'success',
            title: 'Deploy 1',
            timestamp: new Date(),
          },
        ],
      });

      const activities = await service.getActivities();

      expect(activities).toHaveLength(2);
      expect(activities[0].type).toBe('commit');
    });

    it('should filter by activity type', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'activity-1',
            type: 'deploy',
            status: 'success',
            title: 'Deploy',
            timestamp: new Date(),
          },
        ],
      });

      await service.getActivities({ types: ['deploy'] });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('type = ANY'),
        expect.any(Array)
      );
    });

    it('should filter by status', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'activity-1',
            type: 'deploy',
            status: 'failure',
            title: 'Failed deploy',
            timestamp: new Date(),
          },
        ],
      });

      await service.getActivities({ statuses: ['failure'] });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('status = ANY'),
        expect.any(Array)
      );
    });

    it('should filter by user ID', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.getActivities({ userId: 'user-1' });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('user_id = '),
        expect.arrayContaining(['user-1'])
      );
    });

    it('should filter by repository', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.getActivities({ repository: 'code-server' });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('repository = '),
        expect.arrayContaining(['code-server'])
      );
    });

    it('should filter by tags', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.getActivities({ tags: ['memory', 'performance'] });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('tags && '),
        expect.any(Array)
      );
    });

    it('should search by text', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.getActivities({ search: 'memory leak' });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('activity_search_index'),
        expect.any(Array)
      );
    });

    it('should respect limit parameter', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.getActivities({}, 25);

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('LIMIT'),
        expect.arrayContaining([25])
      );
    });
  });

  describe('getStats', () => {
    it('should calculate activity statistics', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          { type: 'commit', status: 'success', user_id: 'user-1', repository: 'repo-1' },
          { type: 'commit', status: 'success', user_id: 'user-1', repository: 'repo-1' },
          { type: 'deploy', status: 'success', user_id: 'user-2', repository: 'repo-1' },
          { type: 'deploy', status: 'failure', user_id: null, repository: 'repo-2' },
        ],
      });

      const stats = await service.getStats();

      expect(stats.totalActivities).toBe(4);
      expect(stats.byType.commit).toBe(2);
      expect(stats.byType.deploy).toBe(2);
      expect(stats.byStatus.success).toBe(3);
      expect(stats.byStatus.failure).toBe(1);
      expect(stats.uniqueUsers).toBe(2);
      expect(stats.repositories).toContain('repo-1');
    });

    it('should include last activity', async () => {
      const latestTime = new Date();
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'latest',
            type: 'commit',
            status: 'success',
            title: 'Latest commit',
            timestamp: latestTime,
          },
        ],
      });

      const stats = await service.getStats();

      expect(stats.lastActivity).toBeDefined();
      expect(stats.lastActivity?.title).toBe('Latest commit');
    });

    it('should return empty stats when no activities', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      const stats = await service.getStats();

      expect(stats.totalActivities).toBe(0);
      expect(stats.lastActivity).toBeNull();
    });
  });

  describe('createSubscription', () => {
    it('should create activity subscription', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      const subscription = await service.createSubscription('user-1', {
        types: ['deploy', 'test-flake'],
        statuses: ['failure'],
      });

      expect(subscription).toBeDefined();
      expect(subscription.userId).toBe('user-1');
      expect(subscription.filters.types).toEqual(['deploy', 'test-flake']);
    });
  });

  describe('getSubscription', () => {
    it('should retrieve subscription by ID', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [{
          id: 'sub-1',
          user_id: 'user-1',
          filters: JSON.stringify({ types: ['deploy'] }),
          is_active: true,
          created_at: new Date(),
          updated_at: new Date(),
        }],
      });

      const subscription = await service.getSubscription('sub-1');

      expect(subscription).toBeDefined();
      expect(subscription?.id).toBe('sub-1');
    });

    it('should return null if subscription not found', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      const subscription = await service.getSubscription('unknown');

      expect(subscription).toBeNull();
    });
  });

  describe('getUserSubscriptions', () => {
    it('should retrieve all subscriptions for user', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'sub-1',
            user_id: 'user-1',
            filters: JSON.stringify({}),
            is_active: true,
            created_at: new Date(),
            updated_at: new Date(),
          },
          {
            id: 'sub-2',
            user_id: 'user-1',
            filters: JSON.stringify({ repository: 'code-server' }),
            is_active: true,
            created_at: new Date(),
            updated_at: new Date(),
          },
        ],
      });

      const subscriptions = await service.getUserSubscriptions('user-1');

      expect(subscriptions).toHaveLength(2);
    });
  });

  describe('deleteSubscription', () => {
    it('should delete subscription', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.deleteSubscription('sub-1');

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('DELETE FROM activity_subscriptions'),
        expect.any(Array)
      );
    });
  });

  describe('notifySubscribers', () => {
    it('should notify matching subscribers', async () => {
      // First query: get activity
      mockClient.query.mockResolvedValueOnce({
        rows: [{
          id: 'activity-1',
          type: 'deploy',
          status: 'failure',
          title: 'Deploy failed',
          timestamp: new Date(),
        }],
      });
      // Second query: get subscriptions
      mockClient.query.mockResolvedValueOnce({
        rows: [{
          id: 'sub-1',
          filters: JSON.stringify({ types: ['deploy'], statuses: ['failure'] }),
        }],
      });
      // Third query: insert notification
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.notifySubscribers('activity-1');

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO activity_notifications'),
        expect.any(Array)
      );
    });
  });

  describe('getPendingNotifications', () => {
    it('should retrieve unread notifications', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'activity-1',
            type: 'deploy',
            status: 'failure',
            title: 'Deploy failed',
            timestamp: new Date(),
          },
        ],
      });

      const notifications = await service.getPendingNotifications('sub-1');

      expect(notifications).toHaveLength(1);
      expect(notifications[0].title).toBe('Deploy failed');
    });
  });

  describe('markNotificationAsRead', () => {
    it('should mark notification as read', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.markNotificationAsRead('activity-1', 'sub-1');

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('UPDATE activity_notifications'),
        expect.arrayContaining(['activity-1', 'sub-1'])
      );
    });
  });
});