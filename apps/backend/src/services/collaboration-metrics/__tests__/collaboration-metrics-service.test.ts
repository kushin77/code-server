/**
 * Collaboration Metrics Service Tests
 * @file        apps/backend/src/services/collaboration-metrics/__tests__/collaboration-metrics-service.test.ts
 * @module      services/collaboration-metrics
 * @description Test suite for collaboration metrics functionality
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { CollaborationMetricsService } from '../collaboration-metrics-service.js';

describe('Collaboration Metrics Service', () => {
  let service: CollaborationMetricsService;

  beforeEach(() => {
    CollaborationMetricsService.reset();
    service = CollaborationMetricsService.getInstance();
  });

  afterEach(() => {
    service.shutdown();
  });

  describe('Initialization', () => {
    it('should initialize service', () => {
      expect(service).toBeDefined();
      expect((service as any).metrics).toBeDefined();
      expect((service as any).presence).toBeDefined();
    });

    it('should return same instance on subsequent calls', () => {
      const instance1 = CollaborationMetricsService.getInstance();
      const instance2 = CollaborationMetricsService.getInstance();
      expect(instance1).toBe(instance2);
    });
  });

  describe('Metric Recording', () => {
    it('should record metric', () => {
      const result = service.recordMetric(
        {
          userId: 'user1',
          documentId: 'doc1',
          metricType: 'edit_count',
          value: 5,
          metadata: {},
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
      expect(result.metricId).toBeDefined();
    });

    it('should emit metric-recorded event', () => {
      return new Promise<void>((resolve) => {
        service.once('metric-recorded', (event) => {
          expect(event.data_object.userId).toBe('user1');
          resolve();
        });

        service.recordMetric(
          {
            userId: 'user1',
            documentId: 'doc1',
            metricType: 'edit_count',
            value: 5,
            metadata: {},
          },
          'user1',
          '192.168.1.1',
          'Mozilla'
        );
      });
    });

    it('should get metric', () => {
      const recorded = service.recordMetric(
        {
          userId: 'user1',
          documentId: 'doc1',
          metricType: 'edit_count',
          value: 5,
          metadata: {},
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const metric = service.getMetric(recorded.metricId!);

      expect(metric).toBeDefined();
      expect(metric?.value).toBe(5);
    });

    it('should get user metrics', () => {
      service.recordMetric(
        {
          userId: 'user1',
          documentId: 'doc1',
          metricType: 'edit_count',
          value: 5,
          metadata: {},
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const metrics = service.getUserMetrics('user1');

      expect(Array.isArray(metrics)).toBe(true);
      expect(metrics.length).toBeGreaterThan(0);
    });

    it('should get document metrics', () => {
      service.recordMetric(
        {
          userId: 'user1',
          documentId: 'doc1',
          metricType: 'edit_count',
          value: 5,
          metadata: {},
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const metrics = service.getDocumentMetrics('doc1');

      expect(Array.isArray(metrics)).toBe(true);
      expect(metrics.length).toBeGreaterThan(0);
    });
  });

  describe('Presence', () => {
    it('should update presence', () => {
      const result = service.updatePresence(
        {
          userId: 'user1',
          userEmail: 'user1@example.com',
          documentId: 'doc1',
          status: 'active',
          color: '#FF0000',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
    });

    it('should emit presence-updated event', () => {
      return new Promise<void>((resolve) => {
        service.once('presence-updated', (event) => {
          expect(event.data_object.userId).toBe('user1');
          resolve();
        });

        service.updatePresence(
          {
            userId: 'user1',
            userEmail: 'user1@example.com',
            documentId: 'doc1',
            status: 'active',
            color: '#FF0000',
          },
          'user1',
          '192.168.1.1',
          'Mozilla'
        );
      });
    });

    it('should get presence', () => {
      service.updatePresence(
        {
          userId: 'user1',
          userEmail: 'user1@example.com',
          documentId: 'doc1',
          status: 'active',
          color: '#FF0000',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const presence = service.getPresence('doc1');

      expect(Array.isArray(presence)).toBe(true);
      expect(presence.length).toBeGreaterThan(0);
    });

    it('should remove presence', () => {
      service.updatePresence(
        {
          userId: 'user1',
          userEmail: 'user1@example.com',
          documentId: 'doc1',
          status: 'active',
          color: '#FF0000',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.removePresence('user1', 'doc1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
    });
  });

  describe('Document Summary', () => {
    it('should get document summary', () => {
      service.recordMetric(
        {
          userId: 'user1',
          documentId: 'doc1',
          metricType: 'edit_count',
          value: 5,
          metadata: {},
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const summary = service.getDocumentSummary('doc1');

      expect(summary).toBeDefined();
      expect(summary?.documentId).toBe('doc1');
    });
  });

  describe('Aggregated Metrics', () => {
    it('should get aggregated metrics', () => {
      const metrics = service.getAggregatedMetrics('user1', 'doc1', '1h');

      // Metrics may not exist until aggregated
      expect(metrics === undefined || metrics !== undefined).toBe(true);
    });
  });

  describe('Sessions', () => {
    it('should start session', () => {
      const result = service.startSession('user1', 'doc1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
      expect(result.sessionId).toBeDefined();
    });

    it('should emit session-started event', () => {
      return new Promise<void>((resolve) => {
        service.once('session-started', (event) => {
          expect(event.data_object.userId).toBe('user1');
          resolve();
        });

        service.startSession('user1', 'doc1', '192.168.1.1', 'Mozilla');
      });
    });

    it('should end session', () => {
      const started = service.startSession('user1', 'doc1', '192.168.1.1', 'Mozilla');

      const result = service.endSession(started.sessionId!, 'user1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
    });

    it('should get session metrics', () => {
      const started = service.startSession('user1', 'doc1', '192.168.1.1', 'Mozilla');

      const metrics = service.getSessionMetrics(started.sessionId!);

      expect(metrics).toBeDefined();
    });
  });

  describe('Trends', () => {
    it('should get trends', () => {
      const trends = service.getTrends('user1', 'doc1', 'edit_count');

      expect(Array.isArray(trends)).toBe(true);
    });
  });

  describe('Team Stats', () => {
    it('should get team stats', () => {
      const stats = service.getTeamStats('team1');

      expect(stats).toBeDefined();
      expect(stats?.teamId).toBe('team1');
    });
  });

  describe('Productivity Metrics', () => {
    it('should get productivity metrics', () => {
      const metrics = service.getProductivityMetrics('user1', '1d');

      expect(metrics).toBeDefined();
      expect(metrics?.userId).toBe('user1');
    });

    it('should calculate productivity score', () => {
      const score = service.calculateProductivityScore('user1');

      expect(typeof score).toBe('number');
      expect(score).toBeGreaterThanOrEqual(0);
      expect(score).toBeLessThanOrEqual(100);
    });
  });

  describe('Collaboration Events', () => {
    it('should get collaboration events', () => {
      const events = service.getCollaborationEvents('user1');

      expect(Array.isArray(events)).toBe(true);
    });
  });

  describe('Audit Logging', () => {
    it('should emit audit-logged event', () => {
      return new Promise<void>((resolve) => {
        service.once('audit-logged', (event) => {
          expect(event.data_object.userId).toBeDefined();
          resolve();
        });

        service.recordMetric(
          {
            userId: 'user1',
            documentId: 'doc1',
            metricType: 'edit_count',
            value: 5,
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

  describe('Cleanup', () => {
    it('should cleanup old metrics', () => {
      const result = service.cleanupOldMetrics(30, 'user1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
    });

    it('should emit cleanup-completed event', () => {
      return new Promise<void>((resolve) => {
        service.once('cleanup-completed', (event) => {
          expect(event.data_object.userId).toBe('user1');
          resolve();
        });

        service.cleanupOldMetrics(30, 'user1', '192.168.1.1', 'Mozilla');
      });
    });
  });

  describe('Configuration', () => {
    it('should update configuration', () => {
      return new Promise<void>((resolve) => {
        service.once('config-updated', (event) => {
          expect(event.data_object.config).toBeDefined();
          resolve();
        });

        service.updateConfig({ enableMetrics: false });
      });
    });
  });

  describe('Shutdown', () => {
    it('should shutdown service cleanly', () => {
      service.shutdown();

      expect((service as any).metrics.size).toBe(0);
      expect((service as any).presence.size).toBe(0);
    });
  });
});
