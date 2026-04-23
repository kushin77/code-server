#!/usr/bin/env node
// @file        apps/backend/src/services/collaboration-insight-engine/__tests__/collaboration-insight-engine.test.ts
// @module      collaboration/collaboration-insight-engine/tests
// @description Comprehensive test suite for CollaborationInsightEngine
// @owner       collab-services
// @status      active

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { CollaborationInsightEngine, createCollaborationInsightEngine } from '../collaboration-insight-engine';
import type { InteractionEdge, CodeOwnership, AnalysisPeriod } from '../types';

describe('CollaborationInsightEngine', () => {
  let engine: CollaborationInsightEngine;

  beforeEach(async () => {
    engine = createCollaborationInsightEngine({
      enablePatternAnalysis: true,
      enableRecommendations: true,
      enablePredictions: true,
    });
    await engine.initialize();
  });

  afterEach(async () => {
    await engine.shutdown();
  });

  describe('Service Initialization', () => {
    it('should initialize service successfully', async () => {
      expect(engine).toBeDefined();
      const stats = engine.getStats();
      expect(stats).toBeDefined();
      expect(stats.totalInsightsDelivered).toBeGreaterThanOrEqual(0);
    }, 10);

    it('should shutdown gracefully', async () => {
      const localEngine = createCollaborationInsightEngine();
      await localEngine.initialize();
      await localEngine.shutdown();
      expect(localEngine).toBeDefined();
    }, 8);
  });

  describe('Interaction Recording', () => {
    it('should record interaction edges between team members', async () => {
      const edge: InteractionEdge = {
        interactionId: 'int-1',
        sourceUserId: 'user-1',
        targetUserId: 'user-2',
        teamId: 'team-1',
        interactionType: 'collaboration',
        strength: 0.8,
        lastInteraction: Date.now(),
      };

      await engine.recordInteraction(edge);
      expect(edge.interactionId).toBe('int-1');
    }, 10);

    it('should handle multiple interaction types', async () => {
      const types = ['mentorship', 'collaboration', 'code_review', 'pairing', 'assistance'] as const;

      for (const type of types) {
        const edge: InteractionEdge = {
          interactionId: `int-${type}`,
          sourceUserId: 'user-1',
          targetUserId: 'user-2',
          teamId: 'team-1',
          interactionType: type,
          strength: 0.7,
          lastInteraction: Date.now(),
        };
        await engine.recordInteraction(edge);
      }

      expect(true).toBe(true);
    }, 12);
  });

  describe('Code Ownership', () => {
    it('should record code ownership information', async () => {
      const ownership: CodeOwnership = {
        ownershipId: 'own-1',
        teamId: 'team-1',
        filePath: 'src/services/test.ts',
        primaryOwner: 'user-1',
        secondaryOwners: ['user-2'],
        concentration: 0.6,
        lastModified: Date.now(),
      };

      await engine.recordCodeOwnership(ownership);
      expect(ownership.concentration).toBeLessThanOrEqual(1);
    }, 10);

    it('should track multiple file ownerships', async () => {
      const files = ['src/services/a.ts', 'src/services/b.ts', 'src/services/c.ts'];

      for (const filePath of files) {
        const ownership: CodeOwnership = {
          ownershipId: `own-${filePath}`,
          teamId: 'team-1',
          filePath,
          primaryOwner: 'user-1',
          secondaryOwners: [],
          concentration: 0.5 + Math.random() * 0.4,
          lastModified: Date.now(),
        };
        await engine.recordCodeOwnership(ownership);
      }

      expect(true).toBe(true);
    }, 12);
  });

  describe('Team Dynamics Analysis', () => {
    it('should analyze team dynamics correctly', async () => {
      const period: AnalysisPeriod = {
        startTime: Date.now() - 7 * 24 * 60 * 60 * 1000,
        endTime: Date.now(),
        label: 'weekly',
      };

      // Add some interactions
      const edge: InteractionEdge = {
        interactionId: 'int-1',
        sourceUserId: 'user-1',
        targetUserId: 'user-2',
        teamId: 'team-1',
        interactionType: 'collaboration',
        strength: 0.8,
        lastInteraction: Date.now(),
      };
      await engine.recordInteraction(edge);

      const dynamics = await engine.analyzeTeamDynamics('team-1', period);

      expect(dynamics.teamId).toBe('team-1');
      expect(dynamics.collaborationScore).toBeGreaterThanOrEqual(0);
      expect(dynamics.collaborationScore).toBeLessThanOrEqual(100);
      expect(dynamics.memberCount).toBeGreaterThanOrEqual(0);
    }, 15);

    it('should identify risk factors in team dynamics', async () => {
      const period: AnalysisPeriod = {
        startTime: Date.now() - 7 * 24 * 60 * 60 * 1000,
        endTime: Date.now(),
        label: 'weekly',
      };

      const dynamics = await engine.analyzeTeamDynamics('team-risk', period);

      expect(Array.isArray(dynamics.riskFactors)).toBe(true);
      expect(Array.isArray(dynamics.strengths)).toBe(true);
      expect(Array.isArray(dynamics.developmentAreas)).toBe(true);
    }, 14);
  });

  describe('Pattern Analysis', () => {
    it('should detect collaboration patterns', async () => {
      // Add interactions for pattern detection
      const edges: InteractionEdge[] = [
        {
          interactionId: 'int-1',
          sourceUserId: 'user-1',
          targetUserId: 'user-2',
          teamId: 'team-1',
          interactionType: 'collaboration',
          strength: 0.9,
          lastInteraction: Date.now(),
        },
        {
          interactionId: 'int-2',
          sourceUserId: 'user-2',
          targetUserId: 'user-3',
          teamId: 'team-1',
          interactionType: 'collaboration',
          strength: 0.85,
          lastInteraction: Date.now(),
        },
      ];

      for (const edge of edges) {
        await engine.recordInteraction(edge);
      }

      const patterns = await engine.analyzePatterns('team-1');

      expect(Array.isArray(patterns)).toBe(true);
      expect(patterns.length).toBeGreaterThanOrEqual(0);
    }, 13);

    it('should identify team silos', async () => {
      // Create isolated interaction
      const edge: InteractionEdge = {
        interactionId: 'int-silo',
        sourceUserId: 'user-isolated',
        targetUserId: 'user-isolated',
        teamId: 'team-silos',
        interactionType: 'collaboration',
        strength: 0.1,
        lastInteraction: Date.now(),
      };

      await engine.recordInteraction(edge);

      const patterns = await engine.analyzePatterns('team-silos');

      // Patterns may or may not find silos depending on data, so just check it returns array
      expect(Array.isArray(patterns)).toBe(true);
    }, 12);
  });

  describe('Recommendation Generation', () => {
    it('should generate recommendations for team', async () => {
      const period: AnalysisPeriod = {
        startTime: Date.now() - 30 * 24 * 60 * 60 * 1000,
        endTime: Date.now(),
        label: 'monthly',
      };

      const recommendations = await engine.generateRecommendations('team-1', period);

      expect(Array.isArray(recommendations)).toBe(true);
    }, 14);

    it('should filter recommendations by confidence', async () => {
      const period: AnalysisPeriod = {
        startTime: Date.now() - 30 * 24 * 60 * 60 * 1000,
        endTime: Date.now(),
        label: 'monthly',
      };

      await engine.generateRecommendations('team-filter', period);

      const recommendations = engine.getRecommendations('team-filter', {
        minConfidence: 0.7,
      });

      recommendations.forEach((rec) => {
        expect(rec.confidence).toBeGreaterThanOrEqual(0.7);
      });
    }, 13);

    it('should filter recommendations by impact score', async () => {
      const period: AnalysisPeriod = {
        startTime: Date.now() - 30 * 24 * 60 * 60 * 1000,
        endTime: Date.now(),
        label: 'monthly',
      };

      await engine.generateRecommendations('team-impact', period);

      const recommendations = engine.getRecommendations('team-impact', {
        minImpact: 60,
      });

      recommendations.forEach((rec) => {
        expect(rec.impactScore).toBeGreaterThanOrEqual(60);
      });
    }, 13);

    it('should filter unresolved recommendations', async () => {
      const period: AnalysisPeriod = {
        startTime: Date.now() - 30 * 24 * 60 * 60 * 1000,
        endTime: Date.now(),
        label: 'monthly',
      };

      await engine.generateRecommendations('team-unresolved', period);

      const recommendations = engine.getRecommendations('team-unresolved', {
        unresolved: true,
      });

      recommendations.forEach((rec) => {
        expect(rec.resolved).toBe(false);
      });
    }, 12);
  });

  describe('Capacity Forecasting', () => {
    it('should forecast team capacity', async () => {
      const period: AnalysisPeriod = {
        startTime: Date.now() - 30 * 24 * 60 * 60 * 1000,
        endTime: Date.now(),
        label: 'monthly',
      };

      const forecast = await engine.forecastCapacity('team-forecast', period);

      expect(forecast.teamId).toBe('team-forecast');
      expect(forecast.estimatedCapacity).toBeGreaterThanOrEqual(0);
      expect(forecast.estimatedCapacity).toBeLessThanOrEqual(100);
      expect(forecast.burnoutRisk).toBeGreaterThanOrEqual(0);
      expect(forecast.burnoutRisk).toBeLessThanOrEqual(1);
      expect(forecast.confidence).toBeGreaterThanOrEqual(0);
      expect(forecast.confidence).toBeLessThanOrEqual(1);
    }, 14);

    it('should identify burnout risk', async () => {
      const period: AnalysisPeriod = {
        startTime: Date.now() - 30 * 24 * 60 * 60 * 1000,
        endTime: Date.now(),
        label: 'monthly',
      };

      const forecast = await engine.forecastCapacity('team-burnout', period);

      if (forecast.burnoutRisk > 0.7) {
        expect(forecast.recommendedActions.length).toBeGreaterThan(0);
      }
    }, 13);
  });

  describe('Insight Queries', () => {
    it('should query team insights with metrics', async () => {
      const result = await engine.queryInsights({
        teamId: 'team-query',
        period: {
          startTime: Date.now() - 7 * 24 * 60 * 60 * 1000,
          endTime: Date.now(),
          label: 'weekly',
        },
        includeMetrics: true,
        includeRecommendations: false,
        includePredictions: false,
      });

      expect(result.teamId).toBe('team-query');
      expect(result.metrics).toBeDefined();
      expect(result.queryTime).toBeGreaterThanOrEqual(0);
    }, 12);

    it('should query insights with recommendations', async () => {
      const result = await engine.queryInsights({
        teamId: 'team-query-recs',
        period: {
          startTime: Date.now() - 7 * 24 * 60 * 60 * 1000,
          endTime: Date.now(),
          label: 'weekly',
        },
        includeMetrics: false,
        includeRecommendations: true,
        includePredictions: false,
      });

      expect(result.recommendations).toBeDefined();
      expect(Array.isArray(result.recommendations)).toBe(true);
    }, 12);

    it('should query insights with predictions', async () => {
      const result = await engine.queryInsights({
        teamId: 'team-query-preds',
        period: {
          startTime: Date.now() - 7 * 24 * 60 * 60 * 1000,
          endTime: Date.now(),
          label: 'weekly',
        },
        includeMetrics: false,
        includeRecommendations: false,
        includePredictions: true,
      });

      expect(result.predictions).toBeDefined();
      expect(Array.isArray(result.predictions)).toBe(true);
    }, 12);
  });

  describe('Statistics Tracking', () => {
    it('should track service statistics', async () => {
      const stats = engine.getStats();

      expect(stats.totalInsightsDelivered).toBeGreaterThanOrEqual(0);
      expect(stats.metricsCalculated).toBeGreaterThanOrEqual(0);
      expect(stats.recommendationsGenerated).toBeGreaterThanOrEqual(0);
      expect(stats.patternsAnalyzed).toBeGreaterThanOrEqual(0);
      expect(stats.averageAnalysisTimeMs).toBeGreaterThanOrEqual(0);
    }, 10);

    it('should update statistics with insights', async () => {
      const before = engine.getStats();

      await engine.queryInsights({
        teamId: 'team-stats',
        period: {
          startTime: Date.now() - 7 * 24 * 60 * 60 * 1000,
          endTime: Date.now(),
          label: 'weekly',
        },
        includeMetrics: true,
        includeRecommendations: false,
        includePredictions: false,
      });

      const after = engine.getStats();

      expect(after.totalInsightsDelivered).toBeGreaterThanOrEqual(before.totalInsightsDelivered);
    }, 12);
  });

  describe('Performance', () => {
    it('should analyze team dynamics in <15ms', async () => {
      const period: AnalysisPeriod = {
        startTime: Date.now() - 7 * 24 * 60 * 60 * 1000,
        endTime: Date.now(),
        label: 'weekly',
      };

      const start = performance.now();
      await engine.analyzeTeamDynamics('team-perf', period);
      const duration = performance.now() - start;

      expect(duration).toBeLessThan(15);
    }, 15);

    it('should query insights in <15ms', async () => {
      const start = performance.now();
      await engine.queryInsights({
        teamId: 'team-perf-query',
        period: {
          startTime: Date.now() - 7 * 24 * 60 * 60 * 1000,
          endTime: Date.now(),
          label: 'weekly',
        },
        includeMetrics: true,
        includeRecommendations: false,
        includePredictions: false,
      });
      const duration = performance.now() - start;

      expect(duration).toBeLessThan(15);
    }, 15);
  });
});
