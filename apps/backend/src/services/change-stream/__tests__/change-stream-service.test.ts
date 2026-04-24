/**
 * Change Stream Service Tests
 * @file        apps/backend/src/services/change-stream/__tests__/change-stream-service.test.ts
 * @module      services/change-stream
 * @description Test suite for change stream functionality
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { ChangeStreamService } from '../change-stream-service.js';

describe('Change Stream Service', () => {
  let service: ChangeStreamService;

  beforeEach(() => {
    ChangeStreamService.reset();
    service = ChangeStreamService.getInstance();
  });

  afterEach(() => {
    service.shutdown();
  });

  // Initialization Tests
  describe('Initialization', () => {
    it('should initialize service', () => {
      expect(service).toBeDefined();
      expect((service as any).changes).toBeDefined();
      expect((service as any).subscriptions).toBeDefined();
    });

    it('should return same instance on subsequent calls', () => {
      const instance1 = ChangeStreamService.getInstance();
      const instance2 = ChangeStreamService.getInstance();
      expect(instance1).toBe(instance2);
    });
  });

  // Change Recording Tests
  describe('Change Recording', () => {
    it('should record change', () => {
      const result = service.recordChange(
        {
          entityId: 'file1',
          entityType: 'file',
          operation: 'update',
          userId: 'user1',
          userEmail: 'user1@example.com',
          timestamp: Date.now(),
          status: 'pending',
          severity: 'medium',
          newValue: { content: 'updated' },
          tags: ['test'],
          description: 'Test update',
          metadata: {},
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
      expect(result.changeId).toBeDefined();
    });

    it('should emit change-recorded event', () => {
      return new Promise<void>((resolve) => {
        service.once('change-recorded', (event) => {
          expect(event.data_object.entityId).toBe('file1');
          resolve();
        });

        service.recordChange(
          {
            entityId: 'file1',
            entityType: 'file',
            operation: 'update',
            userId: 'user1',
            userEmail: 'user1@example.com',
            timestamp: Date.now(),
            status: 'pending',
            severity: 'medium',
            newValue: { content: 'updated' },
            tags: ['test'],
            description: 'Test update',
            metadata: {},
          },
          'user1',
          '192.168.1.1',
          'Mozilla'
        );
      });
    });
  });

  // Change Retrieval Tests
  describe('Change Retrieval', () => {
    it('should get change by id', () => {
      const recorded = service.recordChange(
        {
          entityId: 'file1',
          entityType: 'file',
          operation: 'update',
          userId: 'user1',
          userEmail: 'user1@example.com',
          timestamp: Date.now(),
          status: 'pending',
          severity: 'medium',
          newValue: { content: 'updated' },
          tags: ['test'],
          description: 'Test update',
          metadata: {},
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const change = service.getChange(recorded.changeId!);

      expect(change).toBeDefined();
      expect(change?.operation).toBe('update');
    });

    it('should get entity changes', () => {
      service.recordChange(
        {
          entityId: 'file1',
          entityType: 'file',
          operation: 'update',
          userId: 'user1',
          userEmail: 'user1@example.com',
          timestamp: Date.now(),
          status: 'pending',
          severity: 'medium',
          newValue: { content: 'updated' },
          tags: ['test'],
          description: 'Test update',
          metadata: {},
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const changes = service.getEntityChanges('file1');

      expect(Array.isArray(changes)).toBe(true);
      expect(changes.length).toBeGreaterThan(0);
    });
  });

  // Subscription Tests
  describe('Subscriptions', () => {
    it('should create subscription', () => {
      const result = service.createSubscription(
        {
          userId: 'user1',
          entityId: 'file1',
          status: 'active',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
      expect(result.subscriptionId).toBeDefined();
    });

    it('should emit subscription-created event', () => {
      return new Promise<void>((resolve) => {
        service.once('subscription-created', (event) => {
          expect(event.data_object.userId).toBe('user1');
          resolve();
        });

        service.createSubscription(
          {
            userId: 'user1',
            entityId: 'file1',
            status: 'active',
          },
          'user1',
          '192.168.1.1',
          'Mozilla'
        );
      });
    });

    it('should update subscription', () => {
      const created = service.createSubscription(
        {
          userId: 'user1',
          entityId: 'file1',
          status: 'active',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.updateSubscription(
        created.subscriptionId!,
        { status: 'paused' },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
    });

    it('should delete subscription', () => {
      const created = service.createSubscription(
        {
          userId: 'user1',
          entityId: 'file1',
          status: 'active',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.deleteSubscription(created.subscriptionId!, 'user1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
    });

    it('should get subscriptions', () => {
      const subscriptions = service.getSubscriptions('user1');

      expect(Array.isArray(subscriptions)).toBe(true);
    });
  });

  // Change Publishing Tests
  describe('Change Publishing', () => {
    it('should publish change', () => {
      const recorded = service.recordChange(
        {
          entityId: 'file1',
          entityType: 'file',
          operation: 'update',
          userId: 'user1',
          userEmail: 'user1@example.com',
          timestamp: Date.now(),
          status: 'pending',
          severity: 'medium',
          newValue: { content: 'updated' },
          tags: ['test'],
          description: 'Test update',
          metadata: {},
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const change = service.getChange(recorded.changeId!);
      const result = service.publishChange(change!, 'user1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
    });

    it('should emit change-published event', () => {
      return new Promise<void>((resolve) => {
        const recorded = service.recordChange(
          {
            entityId: 'file1',
            entityType: 'file',
            operation: 'update',
            userId: 'user1',
            userEmail: 'user1@example.com',
            timestamp: Date.now(),
            status: 'pending',
            severity: 'medium',
            newValue: { content: 'updated' },
            tags: ['test'],
            description: 'Test update',
            metadata: {},
          },
          'user1',
          '192.168.1.1',
          'Mozilla'
        );

        service.once('change-published', (event) => {
          expect(event.data_object.changeId).toBe(recorded.changeId);
          resolve();
        });

        const change = service.getChange(recorded.changeId!);
        service.publishChange(change!, 'user1', '192.168.1.1', 'Mozilla');
      });
    });
  });

  // Conflict Detection Tests
  describe('Conflict Detection', () => {
    it('should detect conflicts', () => {
      const recorded = service.recordChange(
        {
          entityId: 'file1',
          entityType: 'file',
          operation: 'update',
          userId: 'user1',
          userEmail: 'user1@example.com',
          timestamp: Date.now(),
          status: 'pending',
          severity: 'medium',
          newValue: { content: 'updated' },
          tags: ['test'],
          description: 'Test update',
          metadata: {},
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.detectConflicts(recorded.changeId!, 'user1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
      expect(Array.isArray(result.conflicts)).toBe(true);
    });

    it('should emit conflicts-detected event', () => {
      return new Promise<void>((resolve) => {
        const recorded = service.recordChange(
          {
            entityId: 'file1',
            entityType: 'file',
            operation: 'update',
            userId: 'user1',
            userEmail: 'user1@example.com',
            timestamp: Date.now(),
            status: 'pending',
            severity: 'medium',
            newValue: { content: 'updated' },
            tags: ['test'],
            description: 'Test update',
            metadata: {},
          },
          'user1',
          '192.168.1.1',
          'Mozilla'
        );

        service.once('conflicts-detected', (event) => {
          expect(event.data_object.changeId).toBe(recorded.changeId);
          resolve();
        });

        service.detectConflicts(recorded.changeId!, 'user1', '192.168.1.1', 'Mozilla');
      });
    });

    it('should resolve conflict', () => {
      const recorded = service.recordChange(
        {
          entityId: 'file1',
          entityType: 'file',
          operation: 'update',
          userId: 'user1',
          userEmail: 'user1@example.com',
          timestamp: Date.now(),
          status: 'pending',
          severity: 'medium',
          newValue: { content: 'updated' },
          tags: ['test'],
          description: 'Test update',
          metadata: {},
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const conflicts = service.detectConflicts(recorded.changeId!, 'user1', '192.168.1.1', 'Mozilla');

      if (conflicts.conflicts && conflicts.conflicts.length > 0) {
        const result = service.resolveConflict(
          conflicts.conflicts[0].conflictId,
          'accept',
          'user1',
          '192.168.1.1',
          'Mozilla'
        );

        expect(result.success).toBe(true);
      }
    });
  });

  // Change Application Tests
  describe('Change Application', () => {
    it('should apply change', () => {
      const recorded = service.recordChange(
        {
          entityId: 'file1',
          entityType: 'file',
          operation: 'update',
          userId: 'user1',
          userEmail: 'user1@example.com',
          timestamp: Date.now(),
          status: 'pending',
          severity: 'medium',
          newValue: { content: 'updated' },
          tags: ['test'],
          description: 'Test update',
          metadata: {},
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.applyChange(recorded.changeId!, 'user1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
    });

    it('should emit change-applied event', () => {
      return new Promise<void>((resolve) => {
        const recorded = service.recordChange(
          {
            entityId: 'file1',
            entityType: 'file',
            operation: 'update',
            userId: 'user1',
            userEmail: 'user1@example.com',
            timestamp: Date.now(),
            status: 'pending',
            severity: 'medium',
            newValue: { content: 'updated' },
            tags: ['test'],
            description: 'Test update',
            metadata: {},
          },
          'user1',
          '192.168.1.1',
          'Mozilla'
        );

        service.once('change-applied', (event) => {
          expect(event.data_object.changeId).toBe(recorded.changeId);
          resolve();
        });

        service.applyChange(recorded.changeId!, 'user1', '192.168.1.1', 'Mozilla');
      });
    });

    it('should batch apply changes', () => {
      const recorded1 = service.recordChange(
        {
          entityId: 'file1',
          entityType: 'file',
          operation: 'update',
          userId: 'user1',
          userEmail: 'user1@example.com',
          timestamp: Date.now(),
          status: 'pending',
          severity: 'medium',
          newValue: { content: 'updated' },
          tags: ['test'],
          description: 'Test update',
          metadata: {},
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.batchApplyChanges(
        [recorded1.changeId!],
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
      expect(result.batchId).toBeDefined();
    });
  });

  // Change Revert Tests
  describe('Change Revert', () => {
    it('should revert change', () => {
      const recorded = service.recordChange(
        {
          entityId: 'file1',
          entityType: 'file',
          operation: 'update',
          userId: 'user1',
          userEmail: 'user1@example.com',
          timestamp: Date.now(),
          status: 'pending',
          severity: 'medium',
          newValue: { content: 'updated' },
          tags: ['test'],
          description: 'Test update',
          metadata: {},
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.revertChange(recorded.changeId!, 'user1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
    });

    it('should emit change-reverted event', () => {
      return new Promise<void>((resolve) => {
        const recorded = service.recordChange(
          {
            entityId: 'file1',
            entityType: 'file',
            operation: 'update',
            userId: 'user1',
            userEmail: 'user1@example.com',
            timestamp: Date.now(),
            status: 'pending',
            severity: 'medium',
            newValue: { content: 'updated' },
            tags: ['test'],
            description: 'Test update',
            metadata: {},
          },
          'user1',
          '192.168.1.1',
          'Mozilla'
        );

        service.once('change-reverted', (event) => {
          expect(event.data_object.changeId).toBe(recorded.changeId);
          resolve();
        });

        service.revertChange(recorded.changeId!, 'user1', '192.168.1.1', 'Mozilla');
      });
    });

    it('should rollback changes', () => {
      const recorded = service.recordChange(
        {
          entityId: 'file1',
          entityType: 'file',
          operation: 'update',
          userId: 'user1',
          userEmail: 'user1@example.com',
          timestamp: Date.now(),
          status: 'pending',
          severity: 'medium',
          newValue: { content: 'updated' },
          tags: ['test'],
          description: 'Test update',
          metadata: {},
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.rollbackChanges(
        [recorded.changeId!],
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
      expect(result.rollbackId).toBeDefined();
    });
  });

  // Timeline Tests
  describe('Timeline', () => {
    it('should get change timeline', () => {
      service.recordChange(
        {
          entityId: 'file1',
          entityType: 'file',
          operation: 'update',
          userId: 'user1',
          userEmail: 'user1@example.com',
          timestamp: Date.now(),
          status: 'pending',
          severity: 'medium',
          newValue: { content: 'updated' },
          tags: ['test'],
          description: 'Test update',
          metadata: {},
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const timeline = service.getChangeTimeline('file1');

      expect(timeline).toBeDefined();
      expect(timeline?.entityId).toBe('file1');
    });
  });

  // Statistics Tests
  describe('Statistics', () => {
    it('should get service statistics', () => {
      const stats = service.getStatistics();

      expect(stats).toBeDefined();
      expect(stats.totalChanges).toBeGreaterThanOrEqual(0);
    });

    it('should get user statistics', () => {
      service.recordChange(
        {
          entityId: 'file1',
          entityType: 'file',
          operation: 'update',
          userId: 'user1',
          userEmail: 'user1@example.com',
          timestamp: Date.now(),
          status: 'pending',
          severity: 'medium',
          newValue: { content: 'updated' },
          tags: ['test'],
          description: 'Test update',
          metadata: {},
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const stats = service.getStatistics('user1');

      expect(stats).toBeDefined();
      expect(stats.totalChanges).toBeGreaterThan(0);
    });
  });

  // Audit Logging Tests
  describe('Audit Logging', () => {
    it('should emit audit-logged event', () => {
      return new Promise<void>((resolve) => {
        service.once('audit-logged', (event) => {
          expect(event.data_object.userId).toBeDefined();
          resolve();
        });

        service.recordChange(
          {
            entityId: 'file1',
            entityType: 'file',
            operation: 'update',
            userId: 'user1',
            userEmail: 'user1@example.com',
            timestamp: Date.now(),
            status: 'pending',
            severity: 'medium',
            newValue: { content: 'updated' },
            tags: ['test'],
            description: 'Test update',
            metadata: {},
          },
          'user1',
          '192.168.1.1',
          'Mozilla'
        );
      });
    });

    it('should retrieve audit log', () => {
      const log = service.getAuditLog();

      expect(Array.isArray(log)).toBe(true);
    });
  });

  // Archive Tests
  describe('Archive', () => {
    it('should archive old changes', () => {
      const result = service.archiveOldChanges(90, 'user1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
    });

    it('should emit archive-completed event', () => {
      return new Promise<void>((resolve) => {
        service.once('archive-completed', (event) => {
          expect(event.data_object.userId).toBe('user1');
          resolve();
        });

        service.archiveOldChanges(90, 'user1', '192.168.1.1', 'Mozilla');
      });
    });
  });

  // Export Tests
  describe('Export', () => {
    it('should export changes as json', () => {
      const result = service.exportChanges('file1', 'json', 'user1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
      expect(typeof result.data).toBe('string');
    });

    it('should export changes as csv', () => {
      const result = service.exportChanges('file1', 'csv', 'user1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
      expect(typeof result.data).toBe('string');
    });

    it('should emit changes-exported event', () => {
      return new Promise<void>((resolve) => {
        service.once('changes-exported', (event) => {
          expect(event.data_object.entityId).toBe('file1');
          resolve();
        });

        service.exportChanges('file1', 'json', 'user1', '192.168.1.1', 'Mozilla');
      });
    });
  });

  // Replication Tests
  describe('Replication', () => {
    it('should replicate changes', () => {
      const result = service.replicateChanges([], ['user2'], 'user1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
      expect(result.replicationId).toBeDefined();
    });

    it('should emit replication-started event', () => {
      return new Promise<void>((resolve) => {
        service.once('replication-started', (event) => {
          expect(event.data_object.userId).toBe('user1');
          resolve();
        });

        service.replicateChanges([], ['user2'], 'user1', '192.168.1.1', 'Mozilla');
      });
    });
  });

  // Configuration Tests
  describe('Configuration', () => {
    it('should update configuration', () => {
      return new Promise<void>((resolve) => {
        service.once('config-updated', (event) => {
          expect(event.data_object.config).toBeDefined();
          resolve();
        });

        service.updateConfig({ enableChangeTracking: false });
      });
    });
  });

  // Shutdown Tests
  describe('Shutdown', () => {
    it('should shutdown service cleanly', () => {
      service.shutdown();

      expect((service as any).changes.size).toBe(0);
      expect((service as any).subscriptions.size).toBe(0);
    });
  });
});
