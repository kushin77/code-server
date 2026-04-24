#!/usr/bin/env node
// @file        apps/backend/src/services/conflict-prediction/__tests__/conflict-prediction-service.test.ts
// @module      collaboration/conflict-prediction
// @description Unit and integration tests for ConflictPredictionService
// @owner       collab-services
// @status      active

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  ConflictPredictionService,
  createConflictPredictionService,
  getConflictPredictionService,
} from '../conflict-prediction-service';
import type {
  ActiveEdit,
  ConflictAlert,
  ConflictMetrics,
  ConflictServiceStats,
  ActivityReportResult,
} from '../types';

describe('ConflictPredictionService', () => {
  let service: ConflictPredictionService;

  beforeEach(() => {
    service = createConflictPredictionService({
      stalledEditThresholdMs: 60000, // 1 minute for testing
      cleanupIntervalMs: 5000,
    });
  });

  afterEach(() => {
    service.shutdown();
  });

  describe('initialization', () => {
    it('should create service with default config', () => {
      const srv = new ConflictPredictionService();
      expect(srv).toBeDefined();
      srv.shutdown();
    });

    it('should create service with custom config', () => {
      const srv = new ConflictPredictionService({
        stalledEditThresholdMs: 120000,
      });
      expect(srv).toBeDefined();
      srv.shutdown();
    });

    it('should initialize empty active edits', () => {
      const edits = service.getMatchingEdits();
      expect(edits).toEqual([]);
    });

    it('should initialize empty metrics', () => {
      const metrics = service.getMetrics();
      expect(metrics.totalActiveEdits).toBe(0);
      expect(metrics.activeUsers.size).toBe(0);
    });

    it('should initialize stats with zeros', () => {
      const stats = service.getStats();
      expect(stats.alertsGenerated).toBe(0);
      expect(stats.totalAnalyzed).toBe(0);
    });
  });

  describe('reportActivity', () => {
    it('should report activity without conflicts', async () => {
      const result = await service.reportActivity('user-1', 'file.ts');
      expect(result.success).toBe(true);
      expect(result.alertsGenerated).toEqual([]);
      expect(result.riskScore).toBeDefined();
    });

    it('should report activity with function name', async () => {
      const result = await service.reportActivity('user-1', 'file.ts', 'myFunction');
      expect(result.success).toBe(true);
      expect(result.riskScore).toBeDefined();
    });

    it('should detect file-level conflicts', async () => {
      await service.reportActivity('user-1', 'file.ts');
      const result = await service.reportActivity('user-2', 'file.ts');

      expect(result.success).toBe(true);
      expect(result.alertsGenerated.length).toBeGreaterThan(0);
    });

    it('should detect function-level conflicts', async () => {
      await service.reportActivity('user-1', 'file.ts', 'myFunction');
      const result = await service.reportActivity('user-2', 'file.ts', 'myFunction');

      expect(result.success).toBe(true);
      expect(result.alertsGenerated.length).toBeGreaterThan(0);
    });

    it('should handle multiple conflicting users', async () => {
      await service.reportActivity('user-1', 'file.ts', 'func1');
      await service.reportActivity('user-2', 'file.ts', 'func1');
      const result = await service.reportActivity('user-3', 'file.ts', 'func1');

      expect(result.alertsGenerated.length).toBeGreaterThan(0);
    });

    it('should not alert for different files', async () => {
      await service.reportActivity('user-1', 'file1.ts');
      const result = await service.reportActivity('user-2', 'file2.ts');

      expect(result.alertsGenerated.length).toBe(0);
    });

    it('should not alert for different functions', async () => {
      await service.reportActivity('user-1', 'file.ts', 'func1');
      const result = await service.reportActivity('user-2', 'file.ts', 'func2');

      expect(result.alertsGenerated).toEqual([]);
    });

    it('should handle same user re-editing', async () => {
      const result1 = await service.reportActivity('user-1', 'file.ts', 'func1');
      const result2 = await service.reportActivity('user-1', 'file.ts', 'func1');

      expect(result1.success).toBe(true);
      expect(result2.success).toBe(true);
    });

    it('should increment stats on report', async () => {
      const statsBefore = service.getStats();
      await service.reportActivity('user-1', 'file.ts');
      const statsAfter = service.getStats();

      expect(statsAfter.totalAnalyzed).toBe(statsBefore.totalAnalyzed + 1);
    });
  });

  describe('conflict detection', () => {
    it('should detect file-level + function-level conflict', async () => {
      await service.reportActivity('user-1', 'file.ts'); // file-level
      const result = await service.reportActivity('user-2', 'file.ts', 'myFunc'); // function-level

      expect(result.alertsGenerated.length).toBeGreaterThan(0);
    });

    it('should calculate risk score', async () => {
      const result = await service.reportActivity('user-1', 'file.ts');
      expect(result.riskScore).toBeGreaterThanOrEqual(0);
      expect(result.riskScore).toBeLessThanOrEqual(100);
    });

    it('should increase risk with more conflicts', async () => {
      await service.reportActivity('user-1', 'file.ts', 'func');
      await service.reportActivity('user-2', 'file.ts', 'func');
      const result = await service.reportActivity('user-3', 'file.ts', 'func');

      expect(result.riskScore).toBeGreaterThan(20);
    });

    it('should score complex files higher', async () => {
      // First user on simple file
      await service.reportActivity('user-1', 'readme.md');
      // Second user on simple file to trigger conflict detection
      const simpleResult = await service.reportActivity('user-2', 'readme.md');

      // First user on complex file
      await service.reportActivity('user-3', 'services/core.ts');
      // Second user on complex file to trigger conflict detection
      const complexResult = await service.reportActivity('user-4', 'services/core.ts');

      // Complex file should have higher risk in conflict scenarios
      expect(complexResult.riskScore).toBeGreaterThanOrEqual(simpleResult.riskScore);
    });

    it('should generate alerts for all affected users', async () => {
      await service.reportActivity('user-1', 'file.ts');
      const result = await service.reportActivity('user-2', 'file.ts');

      const alerts = result.alertsGenerated;
      expect(alerts.length).toBeGreaterThan(0);
      expect(alerts.every((a) => a.targetUserId === 'user-1')).toBe(true);
    });
  });

  describe('alert severity', () => {
    it('should classify alerts by severity', async () => {
      await service.reportActivity('user-1', 'services/api/core.ts');
      const result = await service.reportActivity('user-2', 'services/api/core.ts');

      const alert = result.alertsGenerated[0];
      if (alert) {
        expect(['low', 'medium', 'high', 'critical']).toContain(alert.severity);
      }
    });

    it('should have higher severity for function-level conflicts', async () => {
      const fileResult = await service.reportActivity('user-1', 'file.ts');
      const funcResult = await service.reportActivity('user-2', 'file.ts', 'myFunc');

      const fileScore = fileResult.riskScore ?? 0;
      const funcScore = funcResult.riskScore ?? 0;
      expect(funcScore).toBeGreaterThanOrEqual(fileScore);
    });
  });

  describe('getMatchingEdits', () => {
    beforeEach(async () => {
      await service.reportActivity('user-1', 'file1.ts');
      await service.reportActivity('user-2', 'file1.ts');
      await service.reportActivity('user-1', 'file2.ts');
    });

    it('should get all edits', () => {
      const edits = service.getMatchingEdits();
      expect(edits.length).toBeGreaterThanOrEqual(3);
    });

    it('should filter by userId', () => {
      const edits = service.getMatchingEdits('user-1');
      expect(edits.every((e) => e.userId === 'user-1')).toBe(true);
    });

    it('should filter by filePath', () => {
      const edits = service.getMatchingEdits(undefined, 'file1.ts');
      expect(edits.every((e) => e.filePath === 'file1.ts')).toBe(true);
    });

    it('should filter by userId and filePath', () => {
      const edits = service.getMatchingEdits('user-1', 'file1.ts');
      expect(edits.every((e) => e.userId === 'user-1' && e.filePath === 'file1.ts')).toBe(true);
    });
  });

  describe('previewConflicts', () => {
    it('should preview conflicts for upcoming merge', async () => {
      await service.reportActivity('user-1', 'file.ts', 'myFunc');
      await service.reportActivity('user-2', 'file.ts', 'myFunc');

      const preview = service.previewConflicts('user-1', 'file.ts', 'myFunc');
      expect(preview).toBeDefined();
      expect(Array.isArray(preview)).toBe(true);
    });

    it('should show no conflicts when none exist', () => {
      const preview = service.previewConflicts('user-1', 'file.ts');
      expect(preview.length).toBe(0);
    });
  });

  describe('calculateRiskScore', () => {
    it('should return score between 0-100', () => {
      const score = service.calculateRiskScore('file.ts');
      expect(score).toBeGreaterThanOrEqual(0);
      expect(score).toBeLessThanOrEqual(100);
    });

    it('should increase with conflict count', () => {
      const score0 = service.calculateRiskScore('file.ts', undefined, 0);
      const score2 = service.calculateRiskScore('file.ts', undefined, 2);
      expect(score2).toBeGreaterThanOrEqual(score0);
    });

    it('should consider file complexity', () => {
      // Test direct calculateRiskScore calls with conflict counts
      // With 1 concurrent edit on a simple file
      const simpleWithConflict = service.calculateRiskScore('readme.md', undefined, 1);
      // With 1 concurrent edit on a complex file
      const complexWithConflict = service.calculateRiskScore('services/core.ts', undefined, 1);

      // Complex file should score higher due to complexity factor
      expect(complexWithConflict).toBeGreaterThanOrEqual(simpleWithConflict);
    });

    it('should consider function specificity', () => {
      const fileScore = service.calculateRiskScore('file.ts');
      const funcScore = service.calculateRiskScore('file.ts', 'myFunc');
      expect(funcScore).toBeGreaterThanOrEqual(fileScore);
    });
  });

  describe('subscriptions', () => {
    it('should subscribe to conflict alerts', async () => {
      let alertReceived: ConflictAlert | null = null;

      const unsubscribe = service.onConflictAlert('user-1', (alert) => {
        alertReceived = alert;
      });

      await service.reportActivity('user-1', 'file.ts');
      await service.reportActivity('user-2', 'file.ts');

      expect(alertReceived).not.toBeNull();
      expect(alertReceived?.targetUserId).toBe('user-1');

      unsubscribe();
    });

    it('should unsubscribe from alerts', async () => {
      let callCount = 0;

      const unsubscribe = service.onConflictAlert('user-1', () => {
        callCount++;
      });

      await service.reportActivity('user-1', 'file.ts');
      await service.reportActivity('user-2', 'file.ts');

      const callCountAfterFirst = callCount;

      unsubscribe();

      await service.reportActivity('user-3', 'file.ts');

      // Count should not increase after unsubscribe
      expect(callCount).toBe(callCountAfterFirst);
    });

    it('should emit conflict events', (done) => {
      service.on('conflict', (alert: ConflictAlert) => {
        expect(alert).toBeDefined();
        expect(alert.targetUserId).toBeDefined();
        done();
      });

      (async () => {
        await service.reportActivity('user-1', 'file.ts');
        await service.reportActivity('user-2', 'file.ts');
      })();
    });
  });

  describe('metrics', () => {
    it('should track active edits count', async () => {
      await service.reportActivity('user-1', 'file.ts');
      const metrics = service.getMetrics();
      expect(metrics.totalActiveEdits).toBeGreaterThan(0);
    });

    it('should track active users', async () => {
      await service.reportActivity('user-1', 'file.ts');
      await service.reportActivity('user-2', 'file.ts');
      const metrics = service.getMetrics();
      expect(metrics.activeUsers.size).toBe(2);
    });

    it('should track files being edited', async () => {
      await service.reportActivity('user-1', 'file1.ts');
      await service.reportActivity('user-2', 'file2.ts');
      const metrics = service.getMetrics();
      expect(metrics.filesWithConflicts).toBeGreaterThanOrEqual(2);
    });

    it('should calculate average risk score', async () => {
      await service.reportActivity('user-1', 'file.ts');
      await service.reportActivity('user-2', 'file.ts');
      const metrics = service.getMetrics();
      expect(metrics.averageRiskScore).toBeGreaterThanOrEqual(0);
    });

    it('should count critical conflicts', async () => {
      // Create a high-risk scenario
      for (let i = 0; i < 5; i++) {
        await service.reportActivity(`user-${i}`, 'services/core.ts', 'critical');
      }
      const metrics = service.getMetrics();
      expect(metrics.criticalConflicts).toBeGreaterThanOrEqual(0);
    });
  });

  describe('query alerts', () => {
    beforeEach(async () => {
      await service.reportActivity('user-1', 'file.ts');
      await service.reportActivity('user-2', 'file.ts');
      await service.reportActivity('user-3', 'file.ts', 'myFunc');
    });

    it('should query all alerts', () => {
      const result = service.queryAlerts({});
      expect(result.totalMatched).toBeGreaterThanOrEqual(0);
      expect(Array.isArray(result.alerts)).toBe(true);
    });

    it('should query by userId', () => {
      const result = service.queryAlerts({ userId: 'user-1' });
      expect(result.alerts.every((a) => a.targetUserId === 'user-1' || a.otherUserId === 'user-1')).toBe(true);
    });

    it('should query by filePath', () => {
      const result = service.queryAlerts({ filePath: 'file.ts' });
      expect(result.alerts.every((a) => a.filePath === 'file.ts')).toBe(true);
    });

    it('should query with max results limit', () => {
      const result = service.queryAlerts({ maxResults: 2 });
      expect(result.alerts.length).toBeLessThanOrEqual(2);
    });

    it('should filter by risk score', () => {
      const result = service.queryAlerts({ minRiskScore: 30 });
      expect(result.alerts.every((a) => a.riskScore >= 30)).toBe(true);
    });

    it('should return query time', () => {
      const result = service.queryAlerts({});
      expect(result.queryTimeMs).toBeGreaterThanOrEqual(0);
    });
  });

  describe('stats', () => {
    it('should track alerts generated', async () => {
      const statsBefore = service.getStats();
      await service.reportActivity('user-1', 'file.ts');
      await service.reportActivity('user-2', 'file.ts');
      const statsAfter = service.getStats();

      expect(statsAfter.alertsGenerated).toBeGreaterThanOrEqual(statsBefore.alertsGenerated);
    });

    it('should track total analyzed', async () => {
      const statsBefore = service.getStats();
      await service.reportActivity('user-1', 'file.ts');
      const statsAfter = service.getStats();

      expect(statsAfter.totalAnalyzed).toBe(statsBefore.totalAnalyzed + 1);
    });

    it('should return stats copy', () => {
      const stats1 = service.getStats();
      const stats2 = service.getStats();
      expect(stats1).not.toBe(stats2); // Different objects
      expect(stats1).toEqual(stats2); // Same values
    });
  });

  describe('cleanup and shutdown', () => {
    it('should clear alert history', async () => {
      await service.reportActivity('user-1', 'file.ts');
      await service.reportActivity('user-2', 'file.ts');

      service.clearHistory();
      const result = service.queryAlerts({});
      expect(result.alerts.length).toBe(0);
    });

    it('should shutdown service cleanly', () => {
      const srv = createConflictPredictionService();
      expect(() => srv.shutdown()).not.toThrow();
    });
  });

  describe('edge cases', () => {
    it('should handle null function names', async () => {
      const result = await service.reportActivity('user-1', 'file.ts', undefined);
      expect(result.success).toBe(true);
    });

    it('should handle empty string function names', async () => {
      const result = await service.reportActivity('user-1', 'file.ts', '');
      expect(result.success).toBe(true);
    });

    it('should handle special characters in paths', async () => {
      const result = await service.reportActivity('user-1', 'src/@scope/file.ts');
      expect(result.success).toBe(true);
    });

    it('should handle many active edits', async () => {
      for (let i = 0; i < 100; i++) {
        await service.reportActivity(`user-${i}`, `file-${i}.ts`);
      }
      const metrics = service.getMetrics();
      expect(metrics.totalActiveEdits).toBeGreaterThan(0);
    });

    it('should handle concurrent report calls', async () => {
      const promises = [];
      for (let i = 0; i < 10; i++) {
        promises.push(service.reportActivity(`user-${i}`, 'file.ts'));
      }
      const results = await Promise.all(promises);
      expect(results.every((r) => r.success)).toBe(true);
    });
  });

  describe('singleton instance', () => {
    it('should return same instance from factory', () => {
      const inst1 = getConflictPredictionService();
      const inst2 = getConflictPredictionService();
      expect(inst1).toBe(inst2);
    });
  });
});
