#!/usr/bin/env node
// @file        apps/backend/src/services/communication-optimization/__tests__/communication-optimization-engine.test.ts
// @module      collaboration/communication-optimization/tests
// @description Comprehensive test suite for CommunicationOptimizationEngine
// @owner       collab-6.3
// @status      active

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { CommunicationOptimizationEngine } from '../communication-optimization-engine';

describe('CommunicationOptimizationEngine', () => {
  let engine: CommunicationOptimizationEngine;

  beforeEach(async () => {
    engine = new CommunicationOptimizationEngine({
      enablePatternAnalysis: true,
      enableMeetingOptimization: true,
      enableAsyncRecommendations: true,
      enableRemoteOptimization: true,
      enableDecisionTracking: true,
      analysisWindowDays: 90,
      minConfidenceThreshold: 0.7,
      enableAutoUpdates: false,
    });
    await engine.initialize();
  });

  afterEach(async () => {
    await engine.shutdown();
  });

  describe('Engine Initialization', () => {
    it('should initialize engine successfully', async () => {
      expect(engine).toBeDefined();
    });

    it('should emit initialized event on startup', async () => {
      let emitted = false;
      const newEngine = new CommunicationOptimizationEngine();
      newEngine.once('initialized', () => {
        emitted = true;
      });
      await newEngine.initialize();
      expect(emitted).toBe(true);
      await newEngine.shutdown();
    });
  });

  describe('Communication Pattern Analysis', () => {
    it('should analyze communication patterns for week period', async () => {
      const analysis = await engine.analyzePatterns('team-001', 'week');

      expect(analysis).toBeDefined();
      expect(analysis.teamId).toBe('team-001');
      expect(analysis.period).toBe('week');
      expect(analysis.metrics).toBeDefined();
    });

    it('should analyze communication patterns for month period', async () => {
      const analysis = await engine.analyzePatterns('team-001', 'month');

      expect(analysis.metrics.syncAsyncRatio).toBeGreaterThanOrEqual(0);
      expect(analysis.metrics.syncAsyncRatio).toBeLessThanOrEqual(100);
    });

    it('should identify sync/async balance', async () => {
      const analysis = await engine.analyzePatterns('team-001', 'month');

      expect(analysis.metrics.syncAsyncRatio).toBeDefined();
      expect(typeof analysis.metrics.syncAsyncRatio).toBe('number');
    });

    it('should measure meeting effectiveness', async () => {
      const analysis = await engine.analyzePatterns('team-001', 'month');

      expect(analysis.metrics.meetingEffectiveness).toBeGreaterThanOrEqual(0);
      expect(analysis.metrics.meetingEffectiveness).toBeLessThanOrEqual(100);
    });

    it('should track async adoption rate', async () => {
      const analysis = await engine.analyzePatterns('team-001', 'month');

      expect(analysis.metrics.asyncCommunicationAdoption).toBeGreaterThanOrEqual(0);
      expect(analysis.metrics.asyncCommunicationAdoption).toBeLessThanOrEqual(100);
    });

    it('should emit patternsAnalyzed event', async () => {
      let emitted = false;
      engine.once('patternsAnalyzed', () => {
        emitted = true;
      });

      await engine.analyzePatterns('team-002', 'month');
      expect(emitted).toBe(true);
    });
  });

  describe('Meeting Optimization', () => {
    it('should optimize meetings for team', async () => {
      const result = await engine.optimizeMeetings('team-001');

      expect(result).toBeDefined();
      expect(result.teamId).toBe('team-001');
      expect(result.meetings).toBeDefined();
      expect(Array.isArray(result.meetings)).toBe(true);
    });

    it('should identify unnecessary meetings', async () => {
      const result = await engine.optimizeMeetings('team-001');

      expect(result.unnecessaryMeetings).toBeDefined();
      expect(Array.isArray(result.unnecessaryMeetings)).toBe(true);
    });

    it('should identify async candidates', async () => {
      const result = await engine.optimizeMeetings('team-001');

      expect(result.asyncCandidates).toBeDefined();
      expect(Array.isArray(result.asyncCandidates)).toBe(true);
    });

    it('should calculate meeting time to optimize', async () => {
      const result = await engine.optimizeMeetings('team-001');

      expect(result.meetingTimeToOptimize).toBeGreaterThanOrEqual(0);
      expect(typeof result.meetingTimeToOptimize).toBe('number');
    });

    it('should provide agenda template', async () => {
      const result = await engine.optimizeMeetings('team-001');

      expect(result.recommendedAgendaTemplate).toBeDefined();
      expect(typeof result.recommendedAgendaTemplate).toBe('string');
    });

    it('should estimate productivity gains', async () => {
      const result = await engine.optimizeMeetings('team-001');

      expect(result.estimatedProductivityGain).toBeGreaterThanOrEqual(0);
    });

    it('should emit meetingsOptimized event', async () => {
      let emitted = false;
      engine.once('meetingsOptimized', () => {
        emitted = true;
      });

      await engine.optimizeMeetings('team-002');
      expect(emitted).toBe(true);
    });
  });

  describe('Time Zone Impact Analysis', () => {
    it('should analyze time zone impacts', async () => {
      const impacts = await engine.analyzeTimeZoneImpact('team-001');

      expect(impacts).toBeDefined();
      expect(Array.isArray(impacts)).toBe(true);
      expect(impacts.length).toBeGreaterThan(0);
    });

    it('should identify working hours per zone', async () => {
      const impacts = await engine.analyzeTimeZoneImpact('team-001');

      impacts.forEach((impact) => {
        expect(impact.workingHours).toBeDefined();
        expect(impact.workingHours.start).toBeGreaterThanOrEqual(0);
        expect(impact.workingHours.end).toBeLessThanOrEqual(24);
      });
    });

    it('should track meetings outside working hours', async () => {
      const impacts = await engine.analyzeTimeZoneImpact('team-001');

      impacts.forEach((impact) => {
        expect(impact.meetingsOutsideHours).toBeGreaterThanOrEqual(0);
      });
    });

    it('should calculate overlap time', async () => {
      const impacts = await engine.analyzeTimeZoneImpact('team-001');

      impacts.forEach((impact) => {
        expect(impact.averageOverlapMinutes).toBeGreaterThanOrEqual(0);
      });
    });

    it('should emit timeZoneImpactAnalyzed event', async () => {
      let emitted = false;
      engine.once('timeZoneImpactAnalyzed', () => {
        emitted = true;
      });

      await engine.analyzeTimeZoneImpact('team-002');
      expect(emitted).toBe(true);
    });
  });

  describe('Remote Collaboration Profile', () => {
    it('should get remote collaboration profile', async () => {
      const profile = await engine.getRemoteCollaborationProfile('team-001');

      expect(profile).toBeDefined();
      expect(profile.teamId).toBe('team-001');
      expect(profile.asyncFirstCapability).toBeGreaterThanOrEqual(0);
      expect(profile.asyncFirstCapability).toBeLessThanOrEqual(100);
    });

    it('should measure documentation maturity', async () => {
      const profile = await engine.getRemoteCollaborationProfile('team-001');

      expect(profile.documentationMaturity).toBeGreaterThanOrEqual(0);
      expect(profile.documentationMaturity).toBeLessThanOrEqual(100);
    });

    it('should assess tool stack optimization', async () => {
      const profile = await engine.getRemoteCollaborationProfile('team-001');

      expect(profile.toolStackOptimization).toBeGreaterThanOrEqual(0);
      expect(profile.toolStackOptimization).toBeLessThanOrEqual(100);
    });

    it('should rate timezone complexity', async () => {
      const profile = await engine.getRemoteCollaborationProfile('team-001');

      expect(profile.timezoneComplexity).toBeGreaterThanOrEqual(0);
      expect(profile.timezoneComplexity).toBeLessThanOrEqual(100);
    });

    it('should provide recommendations', async () => {
      const profile = await engine.getRemoteCollaborationProfile('team-001');

      expect(profile.recommendations).toBeDefined();
      expect(Array.isArray(profile.recommendations)).toBe(true);
      expect(profile.recommendations.length).toBeGreaterThan(0);
    });

    it('should emit remoteProfileAnalyzed event', async () => {
      let emitted = false;
      engine.once('remoteProfileAnalyzed', () => {
        emitted = true;
      });

      await engine.getRemoteCollaborationProfile('team-002');
      expect(emitted).toBe(true);
    });
  });

  describe('Notification Overload Assessment', () => {
    it('should assess notification overload', async () => {
      const assessment = await engine.assessNotificationOverload('team-001');

      expect(assessment).toBeDefined();
      expect(assessment.overloadScore).toBeGreaterThanOrEqual(0);
      expect(assessment.overloadScore).toBeLessThanOrEqual(100);
    });

    it('should identify overload sources', async () => {
      const assessment = await engine.assessNotificationOverload('team-001');

      expect(assessment.sourcesOfOverload).toBeDefined();
      expect(Array.isArray(assessment.sourcesOfOverload)).toBe(true);
    });

    it('should generate notification recommendations', async () => {
      const assessment = await engine.assessNotificationOverload('team-001');

      expect(assessment.recommendations).toBeDefined();
      expect(Array.isArray(assessment.recommendations)).toBe(true);
      expect(assessment.recommendations.length).toBeGreaterThan(0);
    });

    it('should emit notificationOverloadAssessed event', async () => {
      let emitted = false;
      engine.once('notificationOverloadAssessed', () => {
        emitted = true;
      });

      await engine.assessNotificationOverload('team-002');
      expect(emitted).toBe(true);
    });
  });

  describe('Decision Velocity Analysis', () => {
    it('should analyze decision velocity', async () => {
      const analysis = await engine.analyzeDecisionVelocity('team-001', 'month');

      expect(analysis).toBeDefined();
      expect(analysis.avgCycleDays).toBeDefined();
      expect(analysis.bottlenecks).toBeDefined();
    });

    it('should identify decision bottlenecks', async () => {
      const analysis = await engine.analyzeDecisionVelocity('team-001', 'month');

      expect(Array.isArray(analysis.bottlenecks)).toBe(true);
      expect(analysis.bottlenecks.length).toBeGreaterThan(0);
    });

    it('should track improved processes', async () => {
      const analysis = await engine.analyzeDecisionVelocity('team-001', 'month');

      expect(analysis.improvedProcesses).toBeDefined();
      expect(Array.isArray(analysis.improvedProcesses)).toBe(true);
    });

    it('should emit decisionVelocityAnalyzed event', async () => {
      let emitted = false;
      engine.once('decisionVelocityAnalyzed', () => {
        emitted = true;
      });

      await engine.analyzeDecisionVelocity('team-002', 'month');
      expect(emitted).toBe(true);
    });
  });

  describe('Async Best Practices', () => {
    it('should generate async best practices', async () => {
      const practices = await engine.generateAsyncBestPractices('team-001');

      expect(practices).toBeDefined();
      expect(Array.isArray(practices)).toBe(true);
      expect(practices.length).toBeGreaterThan(0);
    });

    it('should provide actionable practices', async () => {
      const practices = await engine.generateAsyncBestPractices('team-001');

      practices.forEach((practice) => {
        expect(practice.title).toBeDefined();
        expect(practice.description).toBeDefined();
        expect(practice.benefits).toBeDefined();
        expect(Array.isArray(practice.benefits)).toBe(true);
      });
    });

    it('should emit asyncBestPracticesGenerated event', async () => {
      let emitted = false;
      engine.once('asyncBestPracticesGenerated', () => {
        emitted = true;
      });

      await engine.generateAsyncBestPractices('team-002');
      expect(emitted).toBe(true);
    });
  });

  describe('Communication Health Snapshot', () => {
    it('should generate health snapshot', async () => {
      const snapshot = await engine.getHealthSnapshot('team-001');

      expect(snapshot).toBeDefined();
      expect(snapshot.overallScore).toBeGreaterThanOrEqual(0);
      expect(snapshot.overallScore).toBeLessThanOrEqual(100);
    });

    it('should measure sync/async balance score', async () => {
      const snapshot = await engine.getHealthSnapshot('team-001');

      expect(snapshot.syncAsyncBalance).toBeDefined();
      expect(typeof snapshot.syncAsyncBalance).toBe('number');
    });

    it('should measure meeting effectiveness', async () => {
      const snapshot = await engine.getHealthSnapshot('team-001');

      expect(snapshot.meetingEffectiveness).toBeGreaterThanOrEqual(0);
      expect(snapshot.meetingEffectiveness).toBeLessThanOrEqual(100);
    });

    it('should measure documentation quality', async () => {
      const snapshot = await engine.getHealthSnapshot('team-001');

      expect(snapshot.documentationQuality).toBeGreaterThanOrEqual(0);
      expect(snapshot.documentationQuality).toBeLessThanOrEqual(100);
    });

    it('should measure decision velocity score', async () => {
      const snapshot = await engine.getHealthSnapshot('team-001');

      expect(snapshot.decisionVelocity).toBeGreaterThanOrEqual(0);
      expect(snapshot.decisionVelocity).toBeLessThanOrEqual(100);
    });

    it('should emit healthSnapshotGenerated event', async () => {
      let emitted = false;
      engine.once('healthSnapshotGenerated', () => {
        emitted = true;
      });

      await engine.getHealthSnapshot('team-002');
      expect(emitted).toBe(true);
    });
  });

  describe('Decision Tracking', () => {
    it('should track decisions', async () => {
      const decision = {
        id: 'dec-001',
        teamId: 'team-001',
        title: 'Adopt async-first',
        description: 'Move to async-first communication',
        proposerId: 'user-1',
        decisionMakers: ['user-2', 'user-3'],
        proposedDate: new Date(),
        status: 'pending' as const,
        documented: false,
      };

      let emitted = false;
      engine.once('decisionTracked', () => {
        emitted = true;
      });

      await engine.trackDecision(decision);
      expect(emitted).toBe(true);
    });
  });

  describe('Performance', () => {
    it('should analyze patterns in <100ms', async () => {
      const startTime = performance.now();
      await engine.analyzePatterns('team-perf-001', 'month');
      const endTime = performance.now();

      expect(endTime - startTime).toBeLessThan(100);
    });

    it('should optimize meetings in <100ms', async () => {
      const startTime = performance.now();
      await engine.optimizeMeetings('team-perf-002');
      const endTime = performance.now();

      expect(endTime - startTime).toBeLessThan(100);
    });

    it('should analyze time zones in <100ms', async () => {
      const startTime = performance.now();
      await engine.analyzeTimeZoneImpact('team-perf-003');
      const endTime = performance.now();

      expect(endTime - startTime).toBeLessThan(100);
    });

    it('should get remote profile in <100ms', async () => {
      const startTime = performance.now();
      await engine.getRemoteCollaborationProfile('team-perf-004');
      const endTime = performance.now();

      expect(endTime - startTime).toBeLessThan(100);
    });

    it('should assess notification overload in <100ms', async () => {
      const startTime = performance.now();
      await engine.assessNotificationOverload('team-perf-005');
      const endTime = performance.now();

      expect(endTime - startTime).toBeLessThan(100);
    });

    it('should generate health snapshot in <100ms', async () => {
      const startTime = performance.now();
      await engine.getHealthSnapshot('team-perf-006');
      const endTime = performance.now();

      expect(endTime - startTime).toBeLessThan(100);
    });
  });

  describe('Integration', () => {
    it('should handle multiple teams concurrently', async () => {
      const results = await Promise.all([
        engine.analyzePatterns('team-a', 'month'),
        engine.analyzePatterns('team-b', 'month'),
        engine.analyzePatterns('team-c', 'month'),
      ]);

      expect(results.length).toBe(3);
      results.forEach((result) => {
        expect(result).toBeDefined();
        expect(result.metrics).toBeDefined();
      });
    });

    it('should perform multiple analysis types for same team', async () => {
      const teamId = 'team-integration-001';

      const [analysis, optimization, profile, snapshot] = await Promise.all([
        engine.analyzePatterns(teamId, 'month'),
        engine.optimizeMeetings(teamId),
        engine.getRemoteCollaborationProfile(teamId),
        engine.getHealthSnapshot(teamId),
      ]);

      expect(analysis).toBeDefined();
      expect(optimization).toBeDefined();
      expect(profile).toBeDefined();
      expect(snapshot).toBeDefined();
    });
  });
});
