#!/usr/bin/env node
// @file        apps/backend/src/services/collaboration-insight/index.ts
// @module      collaboration/insight
// @description Exports for CollaborationInsightEngine
// @owner       collab-6.2
// @status      active

export { CollaborationInsightEngine } from './collaboration-insight-engine';

export type {
  CollaborationMetrics,
  InteractionEdge,
  CodeOwnership,
  Recommendation,
  Prediction,
  KnowledgeGap,
  InteractionGraph,
  SkillMatrix,
  QualityMetricsTrend,
  BottleneckAnalysis,
  AnalysisPeriod,
  CollaborationInsightConfig,
} from './types';

/**
 * Factory function to create and initialize CollaborationInsightEngine
 */
export async function createCollaborationInsightEngine(
  config?: Partial<import('./types').CollaborationInsightConfig>
): Promise<CollaborationInsightEngine> {
  const engine = new CollaborationInsightEngine(config);
  await engine.initialize();
  return engine;
}
