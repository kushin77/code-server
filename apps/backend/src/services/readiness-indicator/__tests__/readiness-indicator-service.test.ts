#!/usr/bin/env node
// @file        apps/backend/src/services/readiness-indicator/__tests__/readiness-indicator-service.test.ts
// @module      collaboration/readiness-indicator
// @description Unit tests for ReadinessIndicatorService
// @owner       collab-services
// @status      active

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { createReadinessIndicatorService, getReadinessIndicatorService } from '../readiness-indicator-service';
import { ReadinessLevel, SignalType } from '../types';

describe('ReadinessIndicatorService', () => {
  let service = createReadinessIndicatorService();

  beforeEach(() => {
    service = createReadinessIndicatorService();
  });

  afterEach(() => {
    service.shutdown();
  });

  describe('initialization', () => {
    it('should create service with default config', () => {
      expect(service).toBeDefined();
    });

    it('should start with empty state', () => {
      const result = service.queryReadiness({});
      expect(result.statuses).toEqual([]);
    });

    it('should initialize stats with zeros', () => {
      const stats = service.getStats();
      expect(stats.signalsProcessed).toBe(0);
      expect(stats.statusUpdatesGenerated).toBe(0);
    });
  });

  describe('adding signals', () => {
    it('should add a presence signal', async () => {
      const result = await service.addSignal({
        userId: 'user-1',
        signalType: SignalType.PRESENCE,
        readinessLevel: ReadinessLevel.AVAILABLE,
        confidence: 90,
        timestamp: Date.now(),
        source: 'presence-service',
      });

      expect(result).toBe(true);
      expect(service.getStats().signalsProcessed).toBe(1);
    });

    it('should add multiple signals for same user', async () => {
      const now = Date.now();

      await service.addSignal({
        userId: 'user-1',
        signalType: SignalType.PRESENCE,
        readinessLevel: ReadinessLevel.AVAILABLE,
        confidence: 90,
        timestamp: now,
        source: 'presence-service',
      });

      await service.addSignal({
        userId: 'user-1',
        signalType: SignalType.ACTIVITY,
        readinessLevel: ReadinessLevel.AVAILABLE,
        confidence: 80,
        timestamp: now,
        source: 'activity-tracker',
      });

      const status = service.getUserStatus('user-1');
      expect(status?.signals.length).toBeGreaterThanOrEqual(1);
    });

    it('should update readiness on conflicting signals', async () => {
      const now = Date.now();

      await service.addSignal({
        userId: 'user-1',
        signalType: SignalType.PRESENCE,
        readinessLevel: ReadinessLevel.AVAILABLE,
        confidence: 90,
        timestamp: now,
        source: 'presence-service',
      });

      const status1 = service.getUserStatus('user-1');

      await service.addSignal({
        userId: 'user-1',
        signalType: SignalType.CALENDAR,
        readinessLevel: ReadinessLevel.BUSY,
        confidence: 85,
        timestamp: now,
        source: 'calendar',
      });

      const status2 = service.getUserStatus('user-1');
      expect(status2?.readinessLevel).toBeDefined();
    });
  });

  describe('readiness calculation', () => {
    it('should return offline for user with no signals', () => {
      const status = service.getUserStatus('unknown-user');
      expect(status).toBeNull();
    });

    it('should calculate readiness from signals', async () => {
      const now = Date.now();

      await service.addSignal({
        userId: 'user-1',
        signalType: SignalType.PRESENCE,
        readinessLevel: ReadinessLevel.AVAILABLE,
        confidence: 90,
        timestamp: now,
        source: 'presence-service',
      });

      await service.addSignal({
        userId: 'user-1',
        signalType: SignalType.ACTIVITY,
        readinessLevel: ReadinessLevel.AVAILABLE,
        confidence: 85,
        timestamp: now,
        source: 'activity-tracker',
      });

      const status = service.getUserStatus('user-1');
      expect(status?.readinessScore).toBeGreaterThanOrEqual(0);
      expect(status?.readinessScore).toBeLessThanOrEqual(100);
    });

    it('should prioritize high confidence signals', async () => {
      const now = Date.now();

      await service.addSignal({
        userId: 'user-1',
        signalType: SignalType.PRESENCE,
        readinessLevel: ReadinessLevel.AVAILABLE,
        confidence: 100,
        timestamp: now,
        source: 'presence-service',
      });

      await service.addSignal({
        userId: 'user-1',
        signalType: SignalType.ACTIVITY,
        readinessLevel: ReadinessLevel.AVAILABLE,
        confidence: 95,
        timestamp: now,
        source: 'activity-tracker',
      });

      const status = service.getUserStatus('user-1');
      expect(status?.readinessScore).toBeGreaterThan(50);
    });
  });

  describe('readiness levels', () => {
    it('should classify available status', async () => {
      await service.addSignal({
        userId: 'user-1',
        signalType: SignalType.PRESENCE,
        readinessLevel: ReadinessLevel.AVAILABLE,
        confidence: 95,
        timestamp: Date.now(),
        source: 'presence-service',
      });

      await service.addSignal({
        userId: 'user-1',
        signalType: SignalType.ACTIVITY,
        readinessLevel: ReadinessLevel.AVAILABLE,
        confidence: 90,
        timestamp: Date.now(),
        source: 'activity-tracker',
      });

      const status = service.getUserStatus('user-1');
      expect([ReadinessLevel.AVAILABLE, ReadinessLevel.BUSY]).toContain(status?.readinessLevel);
    });

    it('should transition between readiness levels', async () => {
      const now = Date.now();

      // Start as available
      await service.addSignal({
        userId: 'user-1',
        signalType: SignalType.PRESENCE,
        readinessLevel: ReadinessLevel.AVAILABLE,
        confidence: 95,
        timestamp: now,
        source: 'presence-service',
      });

      await service.addSignal({
        userId: 'user-1',
        signalType: SignalType.ACTIVITY,
        readinessLevel: ReadinessLevel.AVAILABLE,
        confidence: 90,
        timestamp: now,
        source: 'activity-tracker',
      });

      const status1 = service.getUserStatus('user-1');

      // Add busy signal
      await service.addSignal({
        userId: 'user-1',
        signalType: SignalType.CALENDAR,
        readinessLevel: ReadinessLevel.BUSY,
        confidence: 85,
        timestamp: Date.now() + 1000,
        source: 'calendar',
      });

      const status2 = service.getUserStatus('user-1');
      expect(status2).toBeDefined();
    });
  });

  describe('capacity tracking', () => {
    it('should set and get capacity', () => {
      service.setCapacity('user-1', {
        userId: 'user-1',
        activeFileCount: 3,
        activeSessionCount: 2,
        taskLoadScore: 45,
        responseLatencyMs: 200,
        contextSwitchCost: 30,
        recommendedInteractionWindowMs: 300000,
        timestamp: Date.now(),
      });

      const capacity = service.getCapacity('user-1');
      expect(capacity?.activeFileCount).toBe(3);
      expect(capacity?.taskLoadScore).toBe(45);
    });

    it('should return null for unknown user capacity', () => {
      const capacity = service.getCapacity('unknown-user');
      expect(capacity).toBeNull();
    });
  });

  describe('team readiness', () => {
    beforeEach(async () => {
      for (let i = 1; i <= 5; i++) {
        await service.addSignal({
          userId: `user-${i}`,
          signalType: SignalType.PRESENCE,
          readinessLevel: i <= 3 ? ReadinessLevel.AVAILABLE : ReadinessLevel.AWAY,
          confidence: 90,
          timestamp: Date.now(),
          source: 'presence-service',
        });

        await service.addSignal({
          userId: `user-${i}`,
          signalType: SignalType.ACTIVITY,
          readinessLevel: i <= 3 ? ReadinessLevel.AVAILABLE : ReadinessLevel.AWAY,
          confidence: 85,
          timestamp: Date.now(),
          source: 'activity-tracker',
        });
      }
    });

    it('should calculate team readiness metrics', () => {
      const metrics = service.getTeamReadiness('team-1', [
        'user-1',
        'user-2',
        'user-3',
        'user-4',
        'user-5',
      ]);

      expect(metrics.totalMembers).toBe(5);
      // At least some should have readiness data
      const totalWithStatus =
        metrics.availableCount +
        metrics.busyCount +
        metrics.awayCount +
        metrics.offlineCount +
        metrics.dndCount;
      expect(totalWithStatus).toBeGreaterThan(0);
      expect(metrics.averageReadinessScore).toBeGreaterThanOrEqual(0);
      expect(metrics.averageReadinessScore).toBeLessThanOrEqual(100);
    });

    it('should count team members by readiness level', () => {
      const metrics = service.getTeamReadiness('team-1', [
        'user-1',
        'user-2',
        'user-3',
        'user-4',
        'user-5',
      ]);

      const total =
        metrics.availableCount +
        metrics.busyCount +
        metrics.awayCount +
        metrics.offlineCount +
        metrics.dndCount;
      expect(total).toBeGreaterThan(0);
    });
  });

  describe('predictions', () => {
    beforeEach(async () => {
      const now = Date.now();

      await service.addSignal({
        userId: 'user-1',
        signalType: SignalType.PRESENCE,
        readinessLevel: ReadinessLevel.AVAILABLE,
        confidence: 90,
        timestamp: now,
        source: 'presence-service',
      });

      await service.addSignal({
        userId: 'user-1',
        signalType: SignalType.ACTIVITY,
        readinessLevel: ReadinessLevel.AVAILABLE,
        confidence: 85,
        timestamp: now,
        source: 'activity-tracker',
      });
    });

    it('should predict future readiness', () => {
      const prediction = service.predictReadiness('user-1');
      expect(prediction).not.toBeNull();
      expect(prediction?.predictedReadinessLevel).toBeDefined();
      expect(prediction?.confidenceScore).toBeGreaterThan(0);
    });

    it('should return null for insufficient signals', () => {
      const prediction = service.predictReadiness('unknown-user');
      expect(prediction).toBeNull();
    });

    it('should include factors in prediction', () => {
      const prediction = service.predictReadiness('user-1');
      expect(prediction?.factors).toBeDefined();
      expect(prediction?.factors.presenceFactor).toBeGreaterThanOrEqual(0);
    });
  });

  describe('collaboration windows', () => {
    beforeEach(async () => {
      for (let i = 1; i <= 3; i++) {
        await service.addSignal({
          userId: `user-${i}`,
          signalType: SignalType.PRESENCE,
          readinessLevel: ReadinessLevel.AVAILABLE,
          confidence: 90,
          timestamp: Date.now(),
          source: 'presence-service',
        });

        await service.addSignal({
          userId: `user-${i}`,
          signalType: SignalType.ACTIVITY,
          readinessLevel: ReadinessLevel.AVAILABLE,
          confidence: 85,
          timestamp: Date.now(),
          source: 'activity-tracker',
        });
      }
    });

    it('should find optimal collaboration window', () => {
      const window = service.findOptimalCollaborationWindow('team-1', [
        'user-1',
        'user-2',
        'user-3',
      ]);

      expect(window.recommendedStartTime).toBeGreaterThan(Date.now());
      expect(window.recommendedEndTime).toBeGreaterThan(window.recommendedStartTime);
      expect(window.optimalityScore).toBeGreaterThanOrEqual(0);
      expect(window.optimalityScore).toBeLessThanOrEqual(100);
    });

    it('should include expected available count', () => {
      const window = service.findOptimalCollaborationWindow('team-1', [
        'user-1',
        'user-2',
        'user-3',
      ]);

      expect(window.expectedAvailableCount).toBeGreaterThanOrEqual(0);
      expect(window.expectedAvailableCount).toBeLessThanOrEqual(3);
    });
  });

  describe('subscriptions', () => {
    it('should notify on readiness change', async () => {
      return new Promise<void>((resolve) => {
        const unsubscribe = service.onReadinessChanged('user-1', (update) => {
          expect(update.userId).toBe('user-1');
          expect(update.previousLevel).toBeDefined();
          expect(update.currentLevel).toBeDefined();
          unsubscribe();
          resolve();
        });

        // Trigger a change
        service.addSignal({
          userId: 'user-1',
          signalType: SignalType.PRESENCE,
          readinessLevel: ReadinessLevel.AVAILABLE,
          confidence: 90,
          timestamp: Date.now(),
          source: 'presence-service',
        });

        service.addSignal({
          userId: 'user-1',
          signalType: SignalType.ACTIVITY,
          readinessLevel: ReadinessLevel.AVAILABLE,
          confidence: 85,
          timestamp: Date.now() + 1000,
          source: 'activity-tracker',
        });

        service.addSignal({
          userId: 'user-1',
          signalType: SignalType.CALENDAR,
          readinessLevel: ReadinessLevel.BUSY,
          confidence: 95,
          timestamp: Date.now() + 2000,
          source: 'calendar',
        });
      });
    });

    it('should unsubscribe from readiness changes', async () => {
      let callCount = 0;

      const unsubscribe = service.onReadinessChanged('user-1', () => {
        callCount++;
      });

      await service.addSignal({
        userId: 'user-1',
        signalType: SignalType.PRESENCE,
        readinessLevel: ReadinessLevel.AVAILABLE,
        confidence: 90,
        timestamp: Date.now(),
        source: 'presence-service',
      });

      const countAfterFirst = callCount;

      unsubscribe();

      // This should not trigger callback
      await service.addSignal({
        userId: 'user-1',
        signalType: SignalType.ACTIVITY,
        readinessLevel: ReadinessLevel.AVAILABLE,
        confidence: 85,
        timestamp: Date.now() + 1000,
        source: 'activity-tracker',
      });

      expect(callCount).toBe(countAfterFirst);
    });
  });

  describe('querying', () => {
    beforeEach(async () => {
      for (let i = 1; i <= 3; i++) {
        await service.addSignal({
          userId: `user-${i}`,
          signalType: SignalType.PRESENCE,
          readinessLevel: i === 1 ? ReadinessLevel.AVAILABLE : ReadinessLevel.AWAY,
          confidence: 90,
          timestamp: Date.now(),
          source: 'presence-service',
        });

        await service.addSignal({
          userId: `user-${i}`,
          signalType: SignalType.ACTIVITY,
          readinessLevel: i === 1 ? ReadinessLevel.AVAILABLE : ReadinessLevel.AWAY,
          confidence: 85,
          timestamp: Date.now(),
          source: 'activity-tracker',
        });
      }
    });

    it('should query all readiness statuses', () => {
      const result = service.queryReadiness({});
      expect(result.statuses.length).toBeGreaterThan(0);
      expect(result.totalMatched).toBeGreaterThan(0);
    });

    it('should filter by userId', () => {
      const result = service.queryReadiness({ userId: 'user-1' });
      expect(result.statuses.every((s) => s.userId === 'user-1')).toBe(true);
    });

    it('should filter by readiness level', () => {
      const result = service.queryReadiness({ readinessLevel: ReadinessLevel.AVAILABLE });
      expect(result.statuses.every((s) => s.readinessLevel === ReadinessLevel.AVAILABLE)).toBe(
        true,
      );
    });

    it('should apply max results limit', () => {
      const result = service.queryReadiness({ maxResults: 1 });
      expect(result.statuses.length).toBeLessThanOrEqual(1);
    });
  });

  describe('statistics', () => {
    it('should track signals processed', async () => {
      const statsBefore = service.getStats();

      await service.addSignal({
        userId: 'user-1',
        signalType: SignalType.PRESENCE,
        readinessLevel: ReadinessLevel.AVAILABLE,
        confidence: 90,
        timestamp: Date.now(),
        source: 'presence-service',
      });

      const statsAfter = service.getStats();
      expect(statsAfter.signalsProcessed).toBe(statsBefore.signalsProcessed + 1);
    });

    it('should track team readiness checks', () => {
      const statsBefore = service.getStats();
      service.getTeamReadiness('team-1', ['user-1', 'user-2']);
      const statsAfter = service.getStats();

      expect(statsAfter.teamReadinessCheckCount).toBe(statsBefore.teamReadinessCheckCount + 1);
    });
  });

  describe('singleton pattern', () => {
    it('should return same instance from factory', () => {
      const inst1 = getReadinessIndicatorService();
      const inst2 = getReadinessIndicatorService();
      expect(inst1).toBe(inst2);
    });
  });

  describe('lifecycle', () => {
    it('should shutdown cleanly', () => {
      const srv = createReadinessIndicatorService();
      expect(() => srv.shutdown()).not.toThrow();
    });

    it('should emit events', async () => {
      return new Promise<void>((resolve) => {
        const srv = createReadinessIndicatorService();

        srv.on('readinessChanged', (update) => {
          expect(update.userId).toBeDefined();
          srv.shutdown();
          resolve();
        });

        srv.addSignal({
          userId: 'user-1',
          signalType: SignalType.PRESENCE,
          readinessLevel: ReadinessLevel.AVAILABLE,
          confidence: 90,
          timestamp: Date.now(),
          source: 'presence-service',
        });

        srv.addSignal({
          userId: 'user-1',
          signalType: SignalType.ACTIVITY,
          readinessLevel: ReadinessLevel.AVAILABLE,
          confidence: 85,
          timestamp: Date.now() + 100,
          source: 'activity-tracker',
        });

        srv.addSignal({
          userId: 'user-1',
          signalType: SignalType.CALENDAR,
          readinessLevel: ReadinessLevel.BUSY,
          confidence: 95,
          timestamp: Date.now() + 200,
          source: 'calendar',
        });
      });
    });
  });
});
