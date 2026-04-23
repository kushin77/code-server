#!/usr/bin/env node
// @file        apps/backend/src/services/readiness-indicator/index.ts
// @module      collaboration/readiness-indicator
// @description Exports for ReadinessIndicatorService
// @owner       collab-services
// @status      active

export { ReadinessIndicatorService, createReadinessIndicatorService, getReadinessIndicatorService } from './readiness-indicator-service';

export type {
  AvailabilitySignal,
  UserReadinessStatus,
  AvailabilityWindow,
  CollaborativeCapacity,
  TeamReadinessMetrics,
  ReadinessPrediction,
  ActivitySignal,
  CalendarEvent,
  ReadinessIndicatorConfig,
  ReadinessIndicatorStats,
  ReadinessQueryOptions,
  ReadinessQueryResult,
  ReadinessUpdate,
  CollaborationWindowRecommendation,
} from './types';

export { ReadinessLevel, SignalType } from './types';
