#!/usr/bin/env node
// @file        apps/backend/src/services/collaboration-insight-engine/collaboration-insight-engine.ts
// @module      collaboration/collaboration-insight-engine
// @description Service for intelligent collaboration analytics and recommendations
// @owner       collab-services
// @status      active

import { EventEmitter } from 'events';
import type {
  CollaborationMetrics,
  InteractionEdge,
  CodeOwnership,
  Recommendation,
  Prediction,
  TeamDynamics,
  AnalysisPeriod,
  InsightQueryContext,
  InsightQueryResult,
  CollaborationPattern,
  CapacityForecast,
  RecommendationFilter,
  CollaborationInsightEngineConfig,
  CollaborationInsightStats,
} from './types';

/**
 * CollaborationInsightEngine - Intelligent collaboration analytics and recommendations
 * Analyzes team collaboration patterns, generates recommendations, and provides predictions
 */
export class CollaborationInsightEngine extends EventEmitter {
  private config: CollaborationInsightEngineConfig;
  private metrics: Map<string, CollaborationMetrics> = new Map();
  private interactionEdges: Map<string, InteractionEdge[]> = new Map();
  private codeOwnership: Map<string, CodeOwnership[]> = new Map();
  private recommendations: Map<string, Recommendation[]> = new Map();
  private predictions: Map<string, Prediction[]> = new Map();
  private patterns: Map<string, CollaborationPattern[]> = new Map();
  private stats: CollaborationInsightStats;

  constructor(config?: Partial<CollaborationInsightEngineConfig>) {
    super();
    this.config = {
      enablePatternAnalysis: true,
      enableRecommendations: true,
      enablePredictions: true,
      enableKnowledgeManagement: true,
      enableQualityMetrics: true,
      metricsRetentionDays: 90,
      recommendationRefreshIntervalMs: 3600000, // 1 hour
      predictionModelVersion: '1.0',
      confidenceThreshold: 0.6,
      impactScoreThreshold: 40,
      ...config,
    };

    this.stats = {
      metricsCalculated: 0,
      recommendationsGenerated: 0,
      predictionsCreated: 0,
      patternsAnalyzed: 0,
      teamsMonitored: 0,
      averageAnalysisTimeMs: 0,
      totalInsightsDelivered: 0,
      lastUpdateTime: Date.now(),
    };
  }

  /**
   * Initialize service
   */
  async initialize(): Promise<void> {
    this.emit('initialized', { timestamp: Date.now() });
  }

  /**
   * Query collaboration insights for a team
   */
  async queryInsights(context: InsightQueryContext): Promise<InsightQueryResult> {
    const startTime = performance.now();

    const result: InsightQueryResult = {
      teamId: context.teamId,
      queryTime: 0,
      generatedAt: Date.now(),
    };

    if (context.includeMetrics) {
      result.metrics = this.metrics.get(context.teamId) || {
        teamId: context.teamId,
        collaborationScore: 0,
        communicationHealth: 0,
        reviewEffectiveness: 0,
        knowledgeDistribution: 0,
        updatedAt: Date.now(),
      };
    }

    if (context.includeRecommendations) {
      result.recommendations = this.getRecommendations(context.teamId, {
        minConfidence: this.config.confidenceThreshold,
        minImpact: this.config.impactScoreThreshold,
        unresolved: true,
      });
    }

    if (context.includePredictions) {
      result.predictions = this.predictions.get(context.teamId) || [];
    }

    result.queryTime = performance.now() - startTime;
    this.stats.totalInsightsDelivered++;
    this.emit('insightsQueried', result);

    return result;
  }

  /**
   * Analyze team dynamics
   */
  async analyzeTeamDynamics(teamId: string, period: AnalysisPeriod): Promise<TeamDynamics> {
    const interactionEdges = this.interactionEdges.get(teamId) || [];
    const codeOwnerships = this.codeOwnership.get(teamId) || [];

    // Calculate metrics
    const memberSet = new Set<string>();
    const interactionMap = new Map<string, number>();

    interactionEdges.forEach((edge) => {
      memberSet.add(edge.sourceUserId);
      memberSet.add(edge.targetUserId);
      const key = `${edge.sourceUserId}-${edge.targetUserId}`;
      interactionMap.set(key, (interactionMap.get(key) || 0) + edge.strength);
    });

    const memberCount = memberSet.size || 1; // Prevent division by zero
    const activeCollaborators = Math.max(1, Math.ceil(memberCount * 0.7)); // Estimate active collaborators
    const communicationDensity = memberCount > 1 ? interactionMap.size / (memberCount * memberCount) : 0;

    // Calculate code ownership concentration
    let totalConcentration = 0;
    codeOwnerships.forEach((ownership) => {
      totalConcentration += ownership.concentration;
    });
    const averageConcentration = codeOwnerships.length > 0 ? totalConcentration / codeOwnerships.length : 0;

    // Determine collaboration score based on metrics
    const collaborationScore = Math.round(
      Math.max(
        0,
        communicationDensity * 50 +
          (1 - averageConcentration) * 40 +
          (activeCollaborators / memberCount) * 10,
      ),
    );

    // Identify risk factors and strengths
    const riskFactors: string[] = [];
    const strengths: string[] = [];
    const developmentAreas: string[] = [];

    if (averageConcentration > 0.8) {
      riskFactors.push('High code ownership concentration');
      developmentAreas.push('Distribute code ownership');
    } else {
      strengths.push('Well-distributed code ownership');
    }

    if (communicationDensity > 0.5) {
      strengths.push('Strong communication density');
    } else {
      riskFactors.push('Low communication density');
      developmentAreas.push('Increase collaboration');
    }

    const teamDynamics: TeamDynamics = {
      teamId,
      memberCount,
      activeCollaborators,
      communicationDensity,
      knowledge: 1 - averageConcentration,
      averageCodeOwnershipConcentration: averageConcentration,
      collaborationScore,
      riskFactors,
      strengths,
      developmentAreas,
    };

    this.stats.patternsAnalyzed++;
    this.emit('teamDynamicsAnalyzed', teamDynamics);

    return teamDynamics;
  }

  /**
   * Generate recommendations for a team
   */
  async generateRecommendations(teamId: string, period: AnalysisPeriod): Promise<Recommendation[]> {
    const recommendations: Recommendation[] = [];
    const dynamics = await this.analyzeTeamDynamics(teamId, period);

    // Recommendation 1: If knowledge is too concentrated, suggest knowledge transfer
    if (dynamics.averageCodeOwnershipConcentration > 0.75) {
      recommendations.push({
        recommendationId: `rec-${Date.now()}-1`,
        teamId,
        recommendationType: 'knowledge_transfer',
        description: 'High code ownership concentration detected. Consider knowledge transfer sessions.',
        confidence: 0.85,
        impactScore: 75,
        createdAt: Date.now(),
        resolved: false,
      });
    }

    // Recommendation 2: If communication is low, suggest pair programming
    if (dynamics.communicationDensity < 0.3) {
      recommendations.push({
        recommendationId: `rec-${Date.now()}-2`,
        teamId,
        recommendationType: 'pair',
        description: 'Low communication density. Recommend pair programming sessions to improve collaboration.',
        confidence: 0.75,
        impactScore: 60,
        createdAt: Date.now(),
        resolved: false,
      });
    }

    // Recommendation 3: If there are silos, suggest restructuring
    const patterns = await this.analyzePatterns(teamId);
    if (patterns.some((p) => p.patternType === 'silos')) {
      recommendations.push({
        recommendationId: `rec-${Date.now()}-3`,
        teamId,
        recommendationType: 'restructure',
        description: 'Team silos detected. Consider restructuring to improve cross-functional collaboration.',
        confidence: 0.8,
        impactScore: 85,
        createdAt: Date.now(),
        resolved: false,
      });
    }

    // Store recommendations
    this.recommendations.set(teamId, recommendations);
    this.stats.recommendationsGenerated += recommendations.length;
    this.emit('recommendationsGenerated', recommendations);

    return recommendations;
  }

  /**
   * Analyze collaboration patterns in team
   */
  async analyzePatterns(teamId: string): Promise<CollaborationPattern[]> {
    const patterns: CollaborationPattern[] = [];
    const interactionEdges = this.interactionEdges.get(teamId) || [];

    if (interactionEdges.length === 0) {
      return patterns;
    }

    // Detect clustering patterns
    const clusters = this.detectClusters(interactionEdges);
    clusters.forEach((cluster, idx) => {
      patterns.push({
        patternId: `pattern-${Date.now()}-${idx}`,
        patternType: 'clustering',
        members: Array.from(cluster),
        strength: 0.8,
        description: `Collaboration cluster with ${cluster.size} members`,
        riskLevel: 'low',
      });
    });

    // Detect silos (isolated members)
    const allMembers = new Set<string>();
    const connectedMembers = new Set<string>();
    interactionEdges.forEach((edge) => {
      allMembers.add(edge.sourceUserId);
      allMembers.add(edge.targetUserId);
      if (edge.strength > 0.3) {
        connectedMembers.add(edge.sourceUserId);
        connectedMembers.add(edge.targetUserId);
      }
    });

    if (connectedMembers.size < allMembers.size) {
      const isolatedMembers = Array.from(allMembers).filter((m) => !connectedMembers.has(m));
      patterns.push({
        patternId: `pattern-${Date.now()}-silos`,
        patternType: 'silos',
        members: isolatedMembers,
        strength: 0.6,
        description: `${isolatedMembers.length} isolated team members`,
        riskLevel: 'high',
        suggestedAction: 'Facilitate connections and collaboration opportunities',
      });
    }

    // Detect bottlenecks (members with many dependencies)
    const inDegree = new Map<string, number>();
    interactionEdges.forEach((edge) => {
      inDegree.set(edge.targetUserId, (inDegree.get(edge.targetUserId) || 0) + edge.strength);
    });

    const bottlenecks = Array.from(inDegree.entries())
      .filter(([_, degree]) => degree > 2)
      .map(([userId]) => userId);

    if (bottlenecks.length > 0) {
      patterns.push({
        patternId: `pattern-${Date.now()}-bottleneck`,
        patternType: 'bottleneck',
        members: bottlenecks,
        strength: 0.7,
        description: `${bottlenecks.length} team members are bottlenecks`,
        riskLevel: 'high',
        suggestedAction: 'Distribute workload and empower team members',
      });
    }

    this.stats.patternsAnalyzed += patterns.length;
    return patterns;
  }

  /**
   * Create a capacity forecast for the team
   */
  async forecastCapacity(teamId: string, period: AnalysisPeriod): Promise<CapacityForecast> {
    const dynamics = await this.analyzeTeamDynamics(teamId, period);

    // Simple forecasting logic based on current collaboration metrics
    const collaborationHealthRatio = Math.min(1, Math.max(0, dynamics.collaborationScore / 100));
    const estimatedCapacity = Math.round(collaborationHealthRatio * 100);

    // Burnout risk based on collaboration density and concentration
    const burnoutRiskRatio = 1 - (dynamics.communicationDensity * 0.5 + (1 - dynamics.averageCodeOwnershipConcentration) * 0.5);

    const forecast: CapacityForecast = {
      teamId,
      forecastPeriod: period,
      estimatedCapacity: Math.max(0, Math.min(100, estimatedCapacity)),
      burnoutRisk: Math.max(0, Math.min(1, burnoutRiskRatio)),
      recommendedActions: [],
      confidence: 0.75,
    };

    if (forecast.burnoutRisk > 0.7) {
      forecast.recommendedActions.push('Reduce workload and increase support');
    }

    if (forecast.estimatedCapacity < 60) {
      forecast.recommendedActions.push('Improve team collaboration and communication');
    }

    this.stats.predictionsCreated++;
    this.emit('capacityForecasted', forecast);

    return forecast;
  }

  /**
   * Record an interaction edge between team members
   */
  async recordInteraction(edge: InteractionEdge): Promise<void> {
    const edges = this.interactionEdges.get(edge.teamId) || [];
    edges.push(edge);
    this.interactionEdges.set(edge.teamId, edges);
    this.emit('interactionRecorded', edge);
  }

  /**
   * Record code ownership information
   */
  async recordCodeOwnership(ownership: CodeOwnership): Promise<void> {
    const ownerships = this.codeOwnership.get(ownership.teamId) || [];
    ownerships.push(ownership);
    this.codeOwnership.set(ownership.teamId, ownerships);
    this.emit('codeOwnershipRecorded', ownership);
  }

  /**
   * Get recommendations for a team
   */
  getRecommendations(teamId: string, filter?: RecommendationFilter): Recommendation[] {
    let recommendations = this.recommendations.get(teamId) || [];

    if (filter?.types) {
      recommendations = recommendations.filter((r) => filter.types!.includes(r.recommendationType));
    }

    if (filter?.minConfidence) {
      recommendations = recommendations.filter((r) => r.confidence >= filter.minConfidence!);
    }

    if (filter?.minImpact) {
      recommendations = recommendations.filter((r) => r.impactScore >= filter.minImpact!);
    }

    if (filter?.unresolved) {
      recommendations = recommendations.filter((r) => !r.resolved);
    }

    if (filter?.limit) {
      recommendations = recommendations.slice(0, filter.limit);
    }

    return recommendations;
  }

  /**
   * Get service statistics
   */
  getStats(): CollaborationInsightStats {
    return { ...this.stats };
  }

  /**
   * Detect clustering in interaction edges using simple algorithm
   */
  private detectClusters(edges: InteractionEdge[]): Set<string>[] {
    const clusters: Set<string>[] = [];
    const visited = new Set<string>();
    const adjacency = new Map<string, string[]>();

    // Build adjacency map
    edges.forEach((edge) => {
      if (!adjacency.has(edge.sourceUserId)) {
        adjacency.set(edge.sourceUserId, []);
      }
      if (!adjacency.has(edge.targetUserId)) {
        adjacency.set(edge.targetUserId, []);
      }
      if (edge.strength > 0.5) {
        adjacency.get(edge.sourceUserId)!.push(edge.targetUserId);
        adjacency.get(edge.targetUserId)!.push(edge.sourceUserId);
      }
    });

    // Find clusters using DFS
    const dfs = (node: string, cluster: Set<string>) => {
      visited.add(node);
      cluster.add(node);
      const neighbors = adjacency.get(node) || [];
      neighbors.forEach((neighbor) => {
        if (!visited.has(neighbor)) {
          dfs(neighbor, cluster);
        }
      });
    };

    adjacency.forEach((_, node) => {
      if (!visited.has(node)) {
        const cluster = new Set<string>();
        dfs(node, cluster);
        if (cluster.size > 1) {
          clusters.push(cluster);
        }
      }
    });

    return clusters;
  }

  /**
   * Shutdown service
   */
  async shutdown(): Promise<void> {
    this.removeAllListeners();
    this.metrics.clear();
    this.interactionEdges.clear();
    this.codeOwnership.clear();
    this.recommendations.clear();
    this.predictions.clear();
    this.patterns.clear();
    this.emit('shutdown', { timestamp: Date.now() });
  }
}

/**
 * Factory function to create service instance
 */
export function createCollaborationInsightEngine(
  config?: Partial<CollaborationInsightEngineConfig>,
): CollaborationInsightEngine {
  return new CollaborationInsightEngine(config);
}

export * from './types';
