#!/usr/bin/env node
// @file        apps/backend/src/services/communication-optimization/index.ts
// @module      collaboration/communication-optimization
// @description Exports for CommunicationOptimizationEngine
// @owner       collab-6.3
// @status      active

export { CommunicationOptimizationEngine } from './communication-optimization-engine';

export type {
  CommunicationMetrics,
  MeetingAnalysis,
  ActionItem,
  ChannelMetrics,
  CommunicationRecommendation,
  Decision,
  AsyncBestPractice,
  CommunicationPatternAnalysis,
  TimeZoneImpact,
  MeetingOptimizationResult,
  RemoteCollaborationProfile,
  AnalysisPeriod,
  CommunicationOptimizationConfig,
} from './types';

/**
 * Factory function to create and initialize CommunicationOptimizationEngine
 */
export async function createCommunicationOptimizationEngine(
  config?: Partial<import('./types').CommunicationOptimizationConfig>
): Promise<CommunicationOptimizationEngine> {
  const engine = new CommunicationOptimizationEngine(config);
  await engine.initialize();
  return engine;
}
