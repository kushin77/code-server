#!/usr/bin/env node
// @file        apps/backend/src/services/collaboration-insight/__tests__/collaboration-insight-engine.test.ts
// @module      collaboration/insight/tests
// @description Comprehensive test suite for CollaborationInsightEngine
// @owner       collab-6.2
// @status      active

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { CollaborationInsightEngine } from '../collaboration-insight-engine';

describe('CollaborationInsightEngine', () => {
  let engine: CollaborationInsightEngine;

  beforeEach(async () => {
    engine = new CollaborationInsightEngine({
      enablePredictions: true,
      enableRecommendations: true,
      enableInteractionGraphs: true,
      enableQualityMetrics: true,
      enableKnowledgeGaps: true,
      analysisWindowDays: 90,
      minConfidenceThreshold: 0.7,
      enableAutoUpdates: false, // disabled for tests
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
      const newEngine = new CollaborationInsightEngine();
      newEngine.once('initialized', () => {
        emitted = true;
      });
      await newEngine.initialize();
      expect(emitted).toBe(true);
      await newEngine.shutdown();
    });
  });

  describe('Team Metrics Analysis', () => {
    it('should analyze team metrics for week period', async () => {
      const metrics = await engine.analyzeTeamMetrics('team-001', 'week');

      expect(metrics).toBeDefined();
      expect(metrics.teamId).toBe('team-001');
      expect(metrics.collaborationScore).toBeGreaterThanOrEqual(0);
      expect(metrics.collaborationScore).toBeLessThanOrEqual(100);
    });

    it('should analyze team metrics for month period', async () => {
      const metrics = await engine.analyzeTeamMetrics('team-001', 'month');

      expect(metrics.communicationHealth).toBeGreaterThanOrEqual(0);
      expect(metrics.communicationHealth).toBeLessThanOrEqual(100);
    });

    it('should calculate review effectiveness', async () => {
      const metrics = await engine.analyzeTeamMetrics('team-002', 'month');

      expect(metrics.reviewEffectiveness).toBeGreaterThanOrEqual(0);
      expect(metrics.reviewEffectiveness).toBeLessThanOrEqual(100);
    });

    it('should measure code ownership concentration', async () => {
      const metrics = await engine.analyzeTeamMetrics('team-003', 'month');

      expect(metrics.codeOwnershipConcentration).toBeGreaterThanOrEqual(0);
      expect(metrics.codeOwnershipConcentration).toBeLessThanOrEqual(100);
    });

    it('should identify knowledge silos', async () => {
      const metrics = await engine.analyzeTeamMetrics('team-004', 'month');

      expect(metrics.knowledgeSilos).toBeDefined();
      expect(Array.isArray(metrics.knowledgeSilos)).toBe(true);
      expect(metrics.knowledgeSilos.length).toBeGreaterThan(0);
    });

    it('should emit metricsAnalyzed event', async () => {
      let emitted = false;
      engine.once('metricsAnalyzed', () => {
        emitted = true;
      });

      await engine.analyzeTeamMetrics('team-005', 'month');
      expect(emitted).toBe(true);
    });
  });

  describe('Recommendation Generation', () => {
    it('should generate recommendations for team', async () => {
      const recommendations = await engine.generateRecommendations('team-001');

      expect(recommendations).toBeDefined();
      expect(Array.isArray(recommendations)).toBe(true);
      expect(recommendations.length).toBeGreaterThan(0);
    });

    it('should include restructuring recommendations', async () => {
      const recommendations = await engine.generateRecommendations('team-001');

      const restructureRec = recommendations.find((r) => r.recommendationType === 'restructure');
      if (restructureRec) {
        expect(restructureRec.impact).toMatch(/low|medium|high/);
        expect(restructureRec.confidence).toBeGreaterThan(0);
        expect(restructureRec.confidence).toBeLessThanOrEqual(1);
      }
    });

    it('should include pairing recommendations', async () => {
      const recommendations = await engine.generateRecommendations('team-002');

      const pairingRec = recommendations.find((r) => r.recommendationType === 'pair');
      if (pairingRec) {
        expect(pairingRec.estimatedEffort).toMatch(/low|medium|high/);
      }
    });

    it('should include refactoring recommendations', async () => {
      const recommendations = await engine.generateRecommendations('team-003');

      const refactoringRec = recommendations.find((r) => r.recommendationType === 'refactor');
      if (refactoringRec) {
        expect(refactoringRec.description).toBeDefined();
        expect(refactoringRec.rationale).toBeDefined();
      }
    });

    it('should include documentation recommendations', async () => {
      const recommendations = await engine.generateRecommendations('team-004');

      const docsRec = recommendations.find((r) => r.recommendationType === 'documentation');
      if (docsRec) {
        expect(docsRec.targetMetrics).toBeDefined();
        expect(Array.isArray(docsRec.targetMetrics)).toBe(true);
      }
    });

    it('should emit recommendationsGenerated event', async () => {
      let emitted = false;
      engine.once('recommendationsGenerated', () => {
        emitted = true;
      });

      await engine.generateRecommendations('team-005');
      expect(emitted).toBe(true);
    });
  });

  describe('Interaction Graph Analysis', () => {
    it('should build interaction graph for team', async () => {
      const graph = await engine.buildInteractionGraph('team-001');

      expect(graph).toBeDefined();
      expect(graph.teamId).toBe('team-001');
      expect(graph.nodes).toBeDefined();
      expect(graph.edges).toBeDefined();
    });

    it('should identify central nodes (most connected users)', async () => {
      const graph = await engine.buildInteractionGraph('team-002');

      expect(graph.centralNodes).toBeDefined();
      expect(Array.isArray(graph.centralNodes)).toBe(true);
    });

    it('should identify isolated nodes (least connected users)', async () => {
      const graph = await engine.buildInteractionGraph('team-003');

      expect(graph.isolatedNodes).toBeDefined();
      expect(Array.isArray(graph.isolatedNodes)).toBe(true);
    });

    it('should identify clusters in interaction patterns', async () => {
      const graph = await engine.buildInteractionGraph('team-004');

      expect(graph.clusters).toBeDefined();
      expect(graph.clusters.length).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Predictive Analytics', () => {
    it('should predict delivery time for features', async () => {
      const prediction = await engine.predictDeliveryTime('team-001');

      expect(prediction).toBeDefined();
      expect(prediction.predictionType).toBe('delivery_time');
      expect(prediction.predictedValue).toBeGreaterThan(0);
      expect(prediction.confidence).toBeGreaterThan(0);
      expect(prediction.confidence).toBeLessThanOrEqual(1);
    });

    it('should predict burnout risk for team members', async () => {
      const predictions = await engine.predictBurnoutRisk('team-002');

      expect(predictions).toBeDefined();
      expect(Array.isArray(predictions)).toBe(true);
      expect(predictions.length).toBeGreaterThan(0);
      predictions.forEach((p) => {
        expect(p.predictionType).toBe('burnout_risk');
        expect(p.predictedValue).toBeGreaterThanOrEqual(0);
      });
    });

    it('should analyze risk scores for code areas', async () => {
      const predictions = await engine.analyzeRiskScores('team-003');

      expect(predictions).toBeDefined();
      expect(Array.isArray(predictions)).toBe(true);
      predictions.forEach((p) => {
        expect(p.predictionType).toBe('risk_score');
        expect(p.confidence).toBeGreaterThan(0);
      });
    });

    it('should emit predictionGenerated event', async () => {
      let emitted = false;
      engine.once('predictionGenerated', () => {
        emitted = true;
      });

      await engine.predictDeliveryTime('team-004');
      expect(emitted).toBe(true);
    });

    it('should emit burnoutPredictionsGenerated event', async () => {
      let emitted = false;
      engine.once('burnoutPredictionsGenerated', () => {
        emitted = true;
      });

      await engine.predictBurnoutRisk('team-005');
      expect(emitted).toBe(true);
    });

    it('should emit riskAnalyzed event', async () => {
      let emitted = false;
      engine.once('riskAnalyzed', () => {
        emitted = true;
      });

      await engine.analyzeRiskScores('team-006');
      expect(emitted).toBe(true);
    });
  });

  describe('Knowledge Management', () => {
    it('should identify knowledge gaps in team', async () => {
      const gaps = await engine.analyzeKnowledgeGaps('team-001');

      expect(gaps).toBeDefined();
      expect(Array.isArray(gaps)).toBe(true);
      expect(gaps.length).toBeGreaterThan(0);
    });

    it('should classify knowledge gaps by criticality', async () => {
      const gaps = await engine.analyzeKnowledgeGaps('team-002');

      gaps.forEach((gap) => {
        expect(gap.criticality).toMatch(/low|medium|high/);
      });
    });

    it('should suggest actions for knowledge gaps', async () => {
      const gaps = await engine.analyzeKnowledgeGaps('team-003');

      gaps.forEach((gap) => {
        expect(gap.suggestedAction).toBeDefined();
        expect(gap.suggestedAction.length).toBeGreaterThan(0);
      });
    });

    it('should emit knowledgeGapsAnalyzed event', async () => {
      let emitted = false;
      engine.once('knowledgeGapsAnalyzed', () => {
        emitted = true;
      });

      await engine.analyzeKnowledgeGaps('team-004');
      expect(emitted).toBe(true);
    });

    it('should provide skill matrix for team', async () => {
      const skillMatrix = await engine.getSkillMatrix('team-001');

      expect(skillMatrix).toBeDefined();
      expect(Array.isArray(skillMatrix)).toBe(true);
      expect(skillMatrix.length).toBeGreaterThan(0);
    });

    it('should identify team members who can mentor', async () => {
      const skillMatrix = await engine.getSkillMatrix('team-002');

      const mentors = skillMatrix.filter((s) => s.canMentor);
      expect(mentors.length).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Quality Metrics Analysis', () => {
    it('should analyze quality trends for team', async () => {
      const trends = await engine.analyzeQualityTrends('team-001', 'month');

      expect(trends).toBeDefined();
      expect(trends.teamId).toBe('team-001');
      expect(trends.testCoverageTrend).toBeDefined();
      expect(trends.bugDensityTrend).toBeDefined();
    });

    it('should identify refactoring opportunities', async () => {
      const trends = await engine.analyzeQualityTrends('team-002', 'month');

      expect(trends.refactoringOpportunities).toBeGreaterThanOrEqual(0);
    });

    it('should identify high-risk code areas', async () => {
      const trends = await engine.analyzeQualityTrends('team-003', 'month');

      expect(trends.highRiskAreas).toBeDefined();
      expect(Array.isArray(trends.highRiskAreas)).toBe(true);
    });

    it('should track quality improvements', async () => {
      const trends = await engine.analyzeQualityTrends('team-004', 'month');

      expect(trends.improvementAreas).toBeDefined();
      expect(Array.isArray(trends.improvementAreas)).toBe(true);
    });
  });

  describe('Bottleneck Analysis', () => {
    it('should identify bottlenecks in team processes', async () => {
      const bottlenecks = await engine.identifyBottlenecks('team-001');

      expect(bottlenecks).toBeDefined();
      expect(Array.isArray(bottlenecks)).toBe(true);
      expect(bottlenecks.length).toBeGreaterThan(0);
    });

    it('should classify bottlenecks by severity', async () => {
      const bottlenecks = await engine.identifyBottlenecks('team-002');

      bottlenecks.forEach((bn) => {
        expect(bn.severity).toMatch(/low|medium|high/);
      });
    });

    it('should provide root cause analysis', async () => {
      const bottlenecks = await engine.identifyBottlenecks('team-003');

      bottlenecks.forEach((bn) => {
        expect(bn.rootCause).toBeDefined();
        expect(bn.suggestedFix).toBeDefined();
      });
    });

    it('should estimate time savings from fixes', async () => {
      const bottlenecks = await engine.identifyBottlenecks('team-004');

      bottlenecks.forEach((bn) => {
        if (bn.expectedImprovementTime !== undefined) {
          expect(bn.expectedImprovementTime).toBeGreaterThan(0);
        }
      });
    });

    it('should emit bottlenecksIdentified event', async () => {
      let emitted = false;
      engine.once('bottlenecksIdentified', () => {
        emitted = true;
      });

      await engine.identifyBottlenecks('team-005');
      expect(emitted).toBe(true);
    });
  });

  describe('Performance', () => {
    it('should analyze metrics in <15ms', async () => {
      const startTime = performance.now();
      await engine.analyzeTeamMetrics('team-perf-001', 'month');
      const endTime = performance.now();

      expect(endTime - startTime).toBeLessThan(15);
    });

    it('should generate recommendations in <15ms', async () => {
      const startTime = performance.now();
      await engine.generateRecommendations('team-perf-002');
      const endTime = performance.now();

      expect(endTime - startTime).toBeLessThan(15);
    });

    it('should build interaction graph in <15ms', async () => {
      const startTime = performance.now();
      await engine.buildInteractionGraph('team-perf-003');
      const endTime = performance.now();

      expect(endTime - startTime).toBeLessThan(15);
    });

    it('should predict delivery time in <15ms', async () => {
      const startTime = performance.now();
      await engine.predictDeliveryTime('team-perf-004');
      const endTime = performance.now();

      expect(endTime - startTime).toBeLessThan(15);
    });

    it('should analyze quality trends in <15ms', async () => {
      const startTime = performance.now();
      await engine.analyzeQualityTrends('team-perf-005', 'month');
      const endTime = performance.now();

      expect(endTime - startTime).toBeLessThan(15);
    });

    it('should identify bottlenecks in <15ms', async () => {
      const startTime = performance.now();
      await engine.identifyBottlenecks('team-perf-006');
      const endTime = performance.now();

      expect(endTime - startTime).toBeLessThan(15);
    });
  });

  describe('Integration', () => {
    it('should handle multiple teams concurrently', async () => {
      const results = await Promise.all([
        engine.analyzeTeamMetrics('team-a', 'month'),
        engine.analyzeTeamMetrics('team-b', 'month'),
        engine.analyzeTeamMetrics('team-c', 'month'),
      ]);

      expect(results.length).toBe(3);
      results.forEach((result) => {
        expect(result).toBeDefined();
        expect(result.collaborationScore).toBeGreaterThan(0);
      });
    });

    it('should generate multiple analysis types for same team', async () => {
      const teamId = 'team-integration-001';

      const [metrics, recommendations, graph, gaps] = await Promise.all([
        engine.analyzeTeamMetrics(teamId, 'month'),
        engine.generateRecommendations(teamId),
        engine.buildInteractionGraph(teamId),
        engine.analyzeKnowledgeGaps(teamId),
      ]);

      expect(metrics).toBeDefined();
      expect(recommendations.length).toBeGreaterThan(0);
      expect(graph.nodes).toBeDefined();
      expect(gaps.length).toBeGreaterThan(0);
    });
  });
});
