#!/usr/bin/env node
// @file        apps/backend/src/services/activity-stream/index.ts
// @module      collaboration/activity-stream
// @description Exports for ActivityStreamService
// @owner       collab-6.2
// @status      active

export { ActivityStreamService } from './activity-stream-service';

export type {
  Activity,
  ActivityEvent,
  ActivityFilter,
  ActivityStream,
  ActivityStreamConfig,
  ActivityType,
  Subscription,
  TeamActivityMetrics,
  AggregationResult,
  TrendAnalysis,
  RelatedEntity,
} from './types';

export { ActivityType } from './types';

/**
 * Factory function to create and initialize ActivityStreamService
 */
export async function createActivityStreamService(
  config?: Partial<import('./types').ActivityStreamConfig>
): Promise<ActivityStreamService> {
  const service = new ActivityStreamService(config);
  await service.initialize();
  return service;
}
