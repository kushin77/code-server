#!/usr/bin/env node
// @file        apps/backend/src/services/collaboration-insight/types.ts
// @module      collaboration/insight/types
// @description Type definitions for CollaborationInsightEngine
// @owner       collab-6.2
// @status      active

/**
 * Collaboration score breakdown
 */
export interface CollaborationMetrics {
  teamId: string;
  collaborationScore: number; // 0-100
  communicationHealth: number; // 0-100
  reviewEffectiveness: number; // 0-100
  knowledgeDistribution: number; // 0-100
  codeQualityTrend: number; // -100 to +100 (improvement)
  teamVelocity: number; // features per sprint
  avgReviewTime: number; // minutes
  codeOwnershipConcentration: number; // 0-100 (0=distributed, 100=concentrated)
  technicalDebtRatio: number; // 0-100
  testCoverageAverage: number; // 0-100
  knowledgeSilos: string[]; // list of knowledge silos identified
  updatedAt: Date;
}

/**
 * Edge in collaboration interaction graph
 */
export interface InteractionEdge {
  edgeId: string;
  sourceUserId: string;
  targetUserId: string;
  teamId: string;
  interactionType:
    | 'mentorship'
    | 'collaboration'
    | 'code_review'
    | 'knowledge_transfer'
    | 'pair_programming'
    | 'communication';
  strength: number; // 0-1, interaction intensity
  interactionCount: number; // number of interactions
  lastInteraction: Date;
  direction: 'uni' | 'bi'; // unidirectional or bidirectional
}

/**
 * Code ownership analysis
 */
export interface CodeOwnership {
  ownershipId: string;
  teamId: string;
  filePath: string;
  primaryOwner: string;
  secondaryOwners: string[];
  concentration: number; // 0-1, how concentrated ownership is
  lastModified: Date;
  modificationCount: number; // total modifications
  lastModifiedBy: string;
  riskLevel: 'low' | 'medium' | 'high'; // risk if primary owner leaves
}

/**
 * Collaboration recommendation
 */
export interface Recommendation {
  recommendationId: string;
  teamId: string;
  userId?: string; // target user for personalized recommendations
  recommendationType:
    | 'restructure'
    | 'pair'
    | 'mentor'
    | 'refactor'
    | 'documentation'
    | 'async_communication'
    | 'code_review'
    | 'testing'
    | 'knowledge_sharing';
  title: string;
  description: string;
  rationale: string;
  impact: 'low' | 'medium' | 'high';
  confidence: number; // 0-1
  impactScore: number; // 0-100
  estimatedEffort: 'low' | 'medium' | 'high';
  targetMetrics: string[]; // which metrics this improves
  createdAt: Date;
  resolved: boolean;
  resolvedAt?: Date;
  actionTaken?: string;
}

/**
 * Predictive model output
 */
export interface Prediction {
  predictionId: string;
  teamId: string;
  userId?: string; // for user-level predictions
  predictionType:
    | 'delivery_time'
    | 'risk_score'
    | 'burnout_risk'
    | 'technical_debt_growth'
    | 'quality_regression'
    | 'collaboration_improvement'
    | 'capacity_constraint';
  predictedValue: number; // varies by type
  predictedUnit: string; // days, percentage, risk level, etc.
  confidence: number; // 0-1
  confidenceInterval?: { lower: number; upper: number };
  basedOnMetrics: string[]; // which metrics contributed
  modelVersion: string; // version of model used
  createdAt: Date;
  actualValue?: number; // filled when actual data available
  errorMargin?: number;
  resolvedAt?: Date;
  isAccurate?: boolean; // prediction correctness
}

/**
 * Knowledge gap
 */
export interface KnowledgeGap {
  gapId: string;
  teamId: string;
  topic: string; // code area, process, tool, etc.
  criticality: 'low' | 'medium' | 'high';
  affectedUsers: string[];
  availableExperts: string[];
  gap: 'documentation' | 'training' | 'mentoring' | 'knowledge_transfer';
  suggestedAction: string;
  estimatedImpactIfUnaddressed: number; // 0-100
}

/**
 * Interaction graph for visualization
 */
export interface InteractionGraph {
  graphId: string;
  teamId: string;
  nodes: {
    userId: string;
    userName: string;
    expertise: string[];
    interactionCount: number;
  }[];
  edges: InteractionEdge[];
  clusters: {
    clusterId: string;
    members: string[];
    cohesion: number; // 0-1
    name: string;
  }[];
  centralNodes: string[]; // most connected users
  isolatedNodes: string[]; // least connected users
}

/**
 * Skill matrix entry
 */
export interface SkillMatrix {
  userId: string;
  teamId: string;
  skillArea: string;
  proficiency: 'novice' | 'intermediate' | 'advanced' | 'expert';
  yearsExperience: number;
  codeAreasOwned: string[];
  canMentor: boolean;
  trainingNeeds: string[];
  updatedAt: Date;
}

/**
 * Quality metrics trends
 */
export interface QualityMetricsTrend {
  teamId: string;
  period: 'day' | 'week' | 'month';
  testCoverageTrend: number; // -100 to +100
  bugDensityTrend: number; // -100 to +100 (negative = more bugs)
  codeComplexityTrend: number; // -100 to +100 (negative = more complex)
  technicalDebtTrend: number; // -100 to +100 (negative = more debt)
  refactoringOpportunities: number; // count
  highRiskAreas: string[]; // file paths
  improvementAreas: string[]; // areas improving
  regressions: string[]; // areas degrading
}

/**
 * Bottleneck analysis
 */
export interface BottleneckAnalysis {
  bottleneckId: string;
  teamId: string;
  bottleneckType:
    | 'code_review'
    | 'merge_wait'
    | 'knowledge_dependency'
    | 'testing'
    | 'deployment'
    | 'communication';
  severity: 'low' | 'medium' | 'high';
  description: string;
  impactedAreas: string[];
  rootCause: string;
  suggestedFix: string;
  expectedImprovementTime?: number; // minutes/hours saved
  affectedUsers: string[];
  createdAt: Date;
  resolution?: string;
  resolvedAt?: Date;
}

/**
 * Analysis period options
 */
export type AnalysisPeriod = 'week' | 'month' | 'quarter' | 'year';

/**
 * Configuration for CollaborationInsightEngine
 */
export interface CollaborationInsightConfig {
  enablePredictions?: boolean;
  enableRecommendations?: boolean;
  enableInteractionGraphs?: boolean;
  enableQualityMetrics?: boolean;
  enableKnowledgeGaps?: boolean;
  analysisWindowDays?: number; // how far back to analyze
  minConfidenceThreshold?: number; // 0-1
  enableAutoUpdates?: boolean;
  updateIntervalMinutes?: number;
}
