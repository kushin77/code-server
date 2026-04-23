#!/usr/bin/env node
// @file        apps/backend/src/services/collaboration-insight-engine/types.ts
// @module      collaboration/collaboration-insight-engine
// @description Type definitions for CollaborationInsightEngine service
// @owner       collab-services
// @status      active

/**
 * Collaboration metrics for team assessment
 */
export interface CollaborationMetrics {
  teamId: string;
  collaborationScore: number; // 0-100
  communicationHealth: number; // 0-100
  reviewEffectiveness: number; // 0-1
  knowledgeDistribution: number; // 0-1
  updatedAt: number;
  metricsJson?: Record<string, unknown>;
}

/**
 * Interaction edge between team members
 */
export interface InteractionEdge {
  interactionId: string;
  sourceUserId: string;
  targetUserId: string;
  teamId: string;
  interactionType: 'mentorship' | 'collaboration' | 'code_review' | 'pairing' | 'assistance';
  strength: number; // 0-1 scale
  lastInteraction: number;
}

/**
 * Code ownership information
 */
export interface CodeOwnership {
  ownershipId: string;
  teamId: string;
  filePath: string;
  primaryOwner: string;
  secondaryOwners: string[];
  concentration: number; // 0-1, how concentrated ownership is
  lastModified: number;
}

/**
 * Recommendation for team optimization
 */
export interface Recommendation {
  recommendationId: string;
  teamId: string;
  userId?: string;
  recommendationType: 'restructure' | 'pair' | 'refactor' | 'document' | 'knowledge_transfer' | 'skill_development';
  description: string;
  confidence: number; // 0-1
  impactScore: number; // 0-100
  createdAt: number;
  resolved: boolean;
  resolvedAt?: number;
}

/**
 * Predictive model output
 */
export interface Prediction {
  predictionId: string;
  teamId: string;
  userId?: string;
  predictionType: 'delivery_time' | 'risk_score' | 'burnout' | 'conflict_likelihood' | 'quality_trend';
  predictedValue: number;
  confidence: number; // 0-1
  actualValue?: number;
  errorMargin?: number;
  createdAt: number;
  resolvedAt?: number;
}

/**
 * Team dynamics summary
 */
export interface TeamDynamics {
  teamId: string;
  memberCount: number;
  activeCollaborators: number;
  communicationDensity: number; // 0-1
  knowledgeConcentration: number; // 0-1 (how centralized knowledge is)
  averageCodeOwnershipConcentration: number; // 0-1
  collaborationScore: number; // 0-100
  riskFactors: string[];
  strengths: string[];
  developmentAreas: string[];
}

/**
 * Analysis period for metrics calculation
 */
export interface AnalysisPeriod {
  startTime: number;
  endTime: number;
  label: 'daily' | 'weekly' | 'monthly' | 'quarterly';
}

/**
 * Insight query context
 */
export interface InsightQueryContext {
  teamId: string;
  userId?: string;
  period: AnalysisPeriod;
  includeMetrics: boolean;
  includeRecommendations: boolean;
  includePredictions: boolean;
}

/**
 * Insight query result
 */
export interface InsightQueryResult {
  teamId: string;
  queryTime: number;
  metrics?: CollaborationMetrics;
  teamDynamics?: TeamDynamics;
  recommendations?: Recommendation[];
  predictions?: Prediction[];
  interactionEdges?: InteractionEdge[];
  codeOwnership?: CodeOwnership[];
  generatedAt: number;
}

/**
 * Collaboration pattern analysis result
 */
export interface CollaborationPattern {
  patternId: string;
  patternType: 'clustering' | 'silos' | 'bottleneck' | 'healthy' | 'dispersed';
  members: string[];
  strength: number; // 0-1
  description: string;
  riskLevel: 'high' | 'medium' | 'low';
  suggestedAction?: string;
}

/**
 * Team capacity forecast
 */
export interface CapacityForecast {
  teamId: string;
  forecastPeriod: AnalysisPeriod;
  estimatedCapacity: number; // 0-100
  burnoutRisk: number; // 0-1
  recommendedActions: string[];
  confidence: number; // 0-1
}

/**
 * Recommendation filtering options
 */
export interface RecommendationFilter {
  types?: string[];
  minConfidence?: number;
  minImpact?: number;
  unresolved?: boolean;
  limit?: number;
}

/**
 * CollaborationInsightEngine configuration
 */
export interface CollaborationInsightEngineConfig {
  enablePatternAnalysis: boolean;
  enableRecommendations: boolean;
  enablePredictions: boolean;
  enableKnowledgeManagement: boolean;
  enableQualityMetrics: boolean;
  metricsRetentionDays: number;
  recommendationRefreshIntervalMs: number;
  predictionModelVersion: string;
  confidenceThreshold: number;
  impactScoreThreshold: number;
}

/**
 * Service statistics
 */
export interface CollaborationInsightStats {
  metricsCalculated: number;
  recommendationsGenerated: number;
  predictionsCreated: number;
  patternsAnalyzed: number;
  teamsMonitored: number;
  averageAnalysisTimeMs: number;
  totalInsightsDelivered: number;
  lastUpdateTime: number;
}
