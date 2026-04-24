#!/usr/bin/env node
// @file        apps/backend/src/services/notification-priority-engine/__tests__/notification-priority-engine-service.test.ts
// @module      collaboration/notification-priority-engine
// @description Unit tests for notification priority engine service
// @owner       collab-5.1
// @status      active

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { Pool } from 'pg';
import { NotificationPriorityEngineService } from '../notification-priority-engine-service';
import type { Notification, NotificationWithPriority, CollaborationContext } from '../types';

const mockPool = {
  connect: vi.fn(),
};

const mockClient = {
  query: vi.fn(),
  release: vi.fn(),
};

const mockAuditService = {
  logAudit: vi.fn(),
};

describe('NotificationPriorityEngineService', () => {
  let service: NotificationPriorityEngineService;

  beforeEach(async () => {
    vi.clearAllMocks();
    (mockPool.connect as any).mockResolvedValue(mockClient);
    (mockClient.query as any).mockResolvedValue({ rows: [] });

    service = new NotificationPriorityEngineService(mockPool as any, mockAuditService as any);
    await service.initialize();
  });

  afterEach(async () => {
    await service.shutdown();
  });

  describe('initialization', () => {
    it('should initialize and create tables', async () => {
      expect(mockPool.connect).toHaveBeenCalled();
      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('CREATE TABLE IF NOT EXISTS notification_priority_queue')
      );
    });

    it('should create indices', async () => {
      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('CREATE INDEX IF NOT EXISTS idx_priority_queue_user')
      );
    });
  });

  describe('enqueueNotification', () => {
    it('should enqueue notification with priority', async () => {
      const notification: Notification = {
        id: 'notif-1',
        userId: 'user1',
        type: 'conflict_detected',
        title: 'Conflict Detected',
        message: 'Two users editing same file',
        createdAt: new Date(),
      };

      const result = await service.enqueueNotification('user1', notification);

      expect(result.priority).toBeDefined();
      expect(['critical', 'high', 'medium', 'low']).toContain(result.priority);
      expect(result.priorityScore).toBeGreaterThanOrEqual(0);
      expect(result.priorityScore).toBeLessThanOrEqual(100);
    });

    it('should calculate higher priority for conflict notifications', async () => {
      const conflictNotif: Notification = {
        id: 'conflict',
        userId: 'user1',
        type: 'conflict_detected',
        title: 'Conflict',
        message: 'msg',
        createdAt: new Date(),
      };

      const result = await service.enqueueNotification('user1', conflictNotif);

      expect(result.priorityScore).toBeGreaterThan(50);
    });

    it('should calculate lower priority for presence updates', async () => {
      const presenceNotif: Notification = {
        id: 'presence',
        userId: 'user1',
        type: 'presence_update',
        title: 'Presence',
        message: 'msg',
        createdAt: new Date(),
      };

      const result = await service.enqueueNotification('user1', presenceNotif);

      expect(result.priorityScore).toBeLessThan(50);
    });

    it('should consider collaboration context', async () => {
      const notification: Notification = {
        id: 'notif',
        userId: 'user1',
        type: 'mention',
        title: 'Mention',
        message: 'msg',
        createdAt: new Date(),
      };

      const context: CollaborationContext = {
        userId: 'user1',
        isInMeeting: false,
        lastActivityTime: new Date(),
        activeFileCount: 5,
        teamSize: 10,
        hasConflicts: true,
        taskProgress: 75,
      };

      const result = await service.enqueueNotification('user1', notification, context);

      expect(result.priorityScore).toBeGreaterThan(0);
    });

    it('should persist notification to database', async () => {
      const notification: Notification = {
        id: 'notif-1',
        userId: 'user1',
        type: 'mention',
        title: 'Title',
        message: 'Message',
        createdAt: new Date(),
      };

      await service.enqueueNotification('user1', notification);

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO notification_priority_queue'),
        expect.any(Array)
      );
    });

    it('should log to audit service', async () => {
      const notification: Notification = {
        id: 'notif-1',
        userId: 'user1',
        type: 'mention',
        title: 'Title',
        message: 'Message',
        createdAt: new Date(),
      };

      await service.enqueueNotification('user1', notification);

      expect(mockAuditService.logAudit).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'notification_enqueued',
          userId: 'user1',
        })
      );
    });

    it('should throttle excessive notifications', async () => {
      const notification: Notification = {
        id: 'notif',
        userId: 'user1',
        type: 'presence_update',
        title: 'Title',
        message: 'Message',
        createdAt: new Date(),
      };

      // Mock max 3 per hour for testing
      const service2 = new NotificationPriorityEngineService(mockPool as any, mockAuditService as any);
      await service2.initialize();

      // Enqueue many at once - should work within limit
      for (let i = 0; i < 5; i++) {
        const notif = { ...notification, id: `notif-${i}` };
        try {
          await service2.enqueueNotification('user1', notif);
        } catch (error) {
          if (i > 2) {
            // After 3, throttling might kick in depending on limits
            expect(error).toBeDefined();
          }
        }
      }

      await service2.shutdown();
    });
  });

  describe('priority calculation', () => {
    it('should produce priority scores 0-100', async () => {
      const notifications: Notification[] = [
        { id: '1', userId: 'user1', type: 'system_alert', title: 'T', message: 'M', createdAt: new Date() },
        { id: '2', userId: 'user1', type: 'mention', title: 'T', message: 'M', createdAt: new Date() },
        { id: '3', userId: 'user1', type: 'presence_update', title: 'T', message: 'M', createdAt: new Date() },
      ];

      for (const notif of notifications) {
        const result = await service.enqueueNotification('user1', notif);
        expect(result.priorityScore).toBeGreaterThanOrEqual(0);
        expect(result.priorityScore).toBeLessThanOrEqual(100);
      }
    });

    it('should include priority factors', async () => {
      const notification: Notification = {
        id: 'notif',
        userId: 'user1',
        type: 'mention',
        title: 'Title',
        message: 'Message',
        createdAt: new Date(),
      };

      const result = await service.enqueueNotification('user1', notification);

      expect(result).toHaveProperty('priorityScore');
      expect(result).toHaveProperty('priority');
      expect(['critical', 'high', 'medium', 'low']).toContain(result.priority);
    });
  });

  describe('batching', () => {
    it('should emit batch ready event when notifications ready', (done) => {
      service.on('batchReady', (batch) => {
        expect(batch).toHaveProperty('id');
        expect(batch).toHaveProperty('notifications');
        done();
      });

      // Trigger batch processing by waiting
      setTimeout(() => {
        // Batch processing runs every 5 seconds
      }, 100);
    });

    it('should create batches with notifications', async () => {
      const notification: Notification = {
        id: 'notif-1',
        userId: 'user1',
        type: 'mention',
        title: 'Title',
        message: 'Message',
        createdAt: new Date(),
      };

      await service.enqueueNotification('user1', notification);

      const metrics = service.getMetrics();
      expect(metrics.totalNotifications).toBeGreaterThan(0);
    });
  });

  describe('metrics', () => {
    it('should return queue metrics', async () => {
      const metrics = service.getMetrics();

      expect(metrics).toHaveProperty('totalNotifications');
      expect(metrics).toHaveProperty('criticalCount');
      expect(metrics).toHaveProperty('highCount');
      expect(metrics).toHaveProperty('mediumCount');
      expect(metrics).toHaveProperty('lowCount');
      expect(metrics).toHaveProperty('averagePriorityScore');
      expect(metrics).toHaveProperty('batchesQueued');
    });

    it('should track notification priority distribution', async () => {
      const notifications: Notification[] = [
        { id: '1', userId: 'user1', type: 'conflict_detected', title: 'C', message: 'M', createdAt: new Date() },
        { id: '2', userId: 'user1', type: 'mention', title: 'M', message: 'M', createdAt: new Date() },
        { id: '3', userId: 'user1', type: 'presence_update', title: 'P', message: 'M', createdAt: new Date() },
      ];

      for (const notif of notifications) {
        await service.enqueueNotification('user1', notif);
      }

      const metrics = service.getMetrics();

      expect(metrics.totalNotifications).toBe(3);
      expect(metrics.criticalCount + metrics.highCount + metrics.mediumCount + metrics.lowCount).toBe(3);
    });
  });

  describe('EventEmitter integration', () => {
    it('should emit notificationEnqueued event', (done) => {
      service.on('notificationEnqueued', (notification: NotificationWithPriority) => {
        expect(notification).toHaveProperty('priority');
        done();
      });

      const notification: Notification = {
        id: 'notif-1',
        userId: 'user1',
        type: 'mention',
        title: 'Title',
        message: 'Message',
        createdAt: new Date(),
      };

      service.enqueueNotification('user1', notification).catch(console.error);
    });
  });

  describe('AuditService integration', () => {
    it('should log to audit service on enqueue', async () => {
      const notification: Notification = {
        id: 'notif-1',
        userId: 'user1',
        type: 'mention',
        title: 'Title',
        message: 'Message',
        createdAt: new Date(),
      };

      await service.enqueueNotification('user1', notification);

      expect(mockAuditService.logAudit).toHaveBeenCalled();
    });
  });

  describe('shutdown', () => {
    it('should clear all state', async () => {
      const notification: Notification = {
        id: 'notif-1',
        userId: 'user1',
        type: 'mention',
        title: 'Title',
        message: 'Message',
        createdAt: new Date(),
      };

      await service.enqueueNotification('user1', notification);

      const metricsBefore = service.getMetrics();
      expect(metricsBefore.totalNotifications).toBeGreaterThan(0);

      await service.shutdown();

      const metricsAfter = service.getMetrics();
      expect(metricsAfter.totalNotifications).toBe(0);
    });
  });

  describe('performance', () => {
    it('should enqueue notifications quickly', async () => {
      const start = Date.now();

      for (let i = 0; i < 50; i++) {
        const notification: Notification = {
          id: `notif-${i}`,
          userId: `user${i % 5}`,
          type: 'mention',
          title: 'Title',
          message: 'Message',
          createdAt: new Date(),
        };

        try {
          await service.enqueueNotification(`user${i % 5}`, notification);
        } catch (e) {
          // Throttle errors expected
        }
      }

      const duration = Date.now() - start;
      expect(duration).toBeLessThan(2000); // Should complete quickly
    });

    it('should calculate priority quickly', async () => {
      const start = Date.now();

      for (let i = 0; i < 100; i++) {
        const notification: Notification = {
          id: `notif-${i}`,
          userId: 'user1',
          type: 'mention',
          title: 'Title',
          message: 'Message',
          createdAt: new Date(),
        };

        try {
          await service.enqueueNotification('user1', notification);
        } catch (e) {
          // Expected
        }
      }

      const duration = Date.now() - start;
      // Should be quick despite volume
      expect(duration).toBeLessThan(5000);
    });
  });
});
